import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

typedef DraftDirectoryProvider = Future<Directory> Function();

/// Persiste les saisies incomplètes hors de la base métier.
///
/// Deux fichiers alternés sont conservés par brouillon. Si Android arrête
/// l'application pendant une écriture, la version précédente reste lisible.
class FormDraftStore {
  FormDraftStore({DraftDirectoryProvider? directoryProvider})
      : _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory;

  static final FormDraftStore instance = FormDraftStore();

  static const _schemaVersion = 1;
  final DraftDirectoryProvider _directoryProvider;

  Future<Map<String, dynamic>?> load(String key) async {
    final candidates = await _readCandidates(key);
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Map<String, dynamic>.from(candidates.first.data);
  }

  Future<void> save(String key, Map<String, dynamic> data) async {
    final files = await _filesFor(key);
    final candidates = await _readCandidatesFrom(files);
    final latestSlot = candidates.isEmpty
        ? -1
        : candidates.reduce((a, b) => a.updatedAt >= b.updatedAt ? a : b).slot;
    final targetSlot = latestSlot == 0 ? 1 : 0;
    final payload = <String, Object?>{
      'schemaVersion': _schemaVersion,
      'updatedAt': DateTime.now().toUtc().microsecondsSinceEpoch,
      'data': data,
    };
    await files[targetSlot].writeAsString(
      jsonEncode(payload),
      flush: true,
    );
  }

  Future<void> delete(String key) async {
    final files = await _filesFor(key);
    for (final file in files) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<List<_DraftCandidate>> _readCandidates(String key) async =>
      _readCandidatesFrom(await _filesFor(key));

  Future<List<_DraftCandidate>> _readCandidatesFrom(List<File> files) async {
    final candidates = <_DraftCandidate>[];
    for (var slot = 0; slot < files.length; slot++) {
      final file = files[slot];
      if (!await file.exists()) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic> ||
            decoded['schemaVersion'] != _schemaVersion ||
            decoded['updatedAt'] is! int ||
            decoded['data'] is! Map) {
          continue;
        }
        candidates.add(_DraftCandidate(
          slot: slot,
          updatedAt: decoded['updatedAt'] as int,
          data: Map<String, dynamic>.from(decoded['data'] as Map),
        ));
      } on FormatException {
        // L'autre slot peut encore contenir le dernier brouillon valide.
      } on FileSystemException {
        // Une lecture concurrente ne doit jamais bloquer le formulaire.
      }
    }
    return candidates;
  }

  Future<List<File>> _filesFor(String key) async {
    final fileStem = RegExp(r'^[a-zA-Z0-9._-]{1,120}$').hasMatch(key)
        ? key
        : 'draft-${sha256.convert(utf8.encode(key))}';
    final root = await _directoryProvider();
    final directory = Directory('${root.path}${Platform.pathSeparator}drafts');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return [
      File('${directory.path}${Platform.pathSeparator}$fileStem.0.json'),
      File('${directory.path}${Platform.pathSeparator}$fileStem.1.json'),
    ];
  }
}

class _DraftCandidate {
  final int slot;
  final int updatedAt;
  final Map<String, dynamic> data;

  const _DraftCandidate({
    required this.slot,
    required this.updatedAt,
    required this.data,
  });
}

/// Sauvegarde régulièrement un instantané et force une écriture lorsque
/// l'application devient inactive (verrouillage, changement d'app, arrêt).
class FormDraftSession with WidgetsBindingObserver {
  FormDraftSession({
    required this.key,
    required this.snapshot,
    FormDraftStore? store,
    this.interval = const Duration(milliseconds: 700),
  }) : _store = store ?? FormDraftStore.instance {
    _initialFingerprint = _fingerprint(snapshot());
  }

  final String key;
  final Map<String, dynamic> Function() snapshot;
  final Duration interval;
  final FormDraftStore _store;

  Timer? _timer;
  Future<void> _writeChain = Future<void>.value();
  String? _lastFingerprint;
  bool _started = false;
  bool _closed = false;
  bool _restoredExisting = false;
  String? _initialFingerprint;

  Future<Map<String, dynamic>?> restore() async {
    try {
      final restored = await _store.load(key);
      _restoredExisting = restored != null;
      return restored;
    } catch (error) {
      debugPrint('Brouillon $key illisible: $error');
      return null;
    }
  }

  void start() {
    if (_started || _closed) return;
    _started = true;
    _lastFingerprint = _restoredExisting
        ? _fingerprint(snapshot())
        : _initialFingerprint ?? _fingerprint(snapshot());
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) => unawaited(flush()));
  }

  Future<void> flush() async {
    if (!_started || _closed) return;
    final data = snapshot();
    final fingerprint = _fingerprint(data);
    if (fingerprint == _lastFingerprint) {
      await _writeChain;
      return;
    }
    _lastFingerprint = fingerprint;
    _writeChain = _writeChain.then((_) => _store.save(key, data)).catchError(
      (Object error, StackTrace stackTrace) {
        _lastFingerprint = null;
        debugPrint('Brouillon $key non sauvegardé: $error');
      },
    );
    await _writeChain;
  }

  /// Supprime le brouillon après validation ou abandon explicite.
  Future<void> clear() async {
    _stop();
    try {
      await _writeChain;
      await _store.delete(key);
    } catch (error) {
      debugPrint('Brouillon $key non supprimé: $error');
    }
  }

  /// Marque l'état courant comme enregistré tout en gardant l'autosauvegarde
  /// active pour les modifications suivantes du même écran.
  Future<void> checkpoint() async {
    if (!_started || _closed) return;
    try {
      await _writeChain;
      await _store.delete(key);
      _lastFingerprint = _fingerprint(snapshot());
    } catch (error) {
      debugPrint('Brouillon $key non réinitialisé: $error');
    }
  }

  void dispose() {
    if (_closed) return;
    final data = _started ? snapshot() : null;
    final fingerprint = data == null ? null : _fingerprint(data);
    final shouldSave =
        data != null && fingerprint != null && fingerprint != _lastFingerprint;
    _stop();
    if (shouldSave) {
      _writeChain = _writeChain.then((_) => _store.save(key, data)).catchError(
        (Object error, StackTrace stackTrace) {
          debugPrint('Brouillon $key non sauvegardé à la fermeture: $error');
        },
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  void _stop() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }

  String _fingerprint(Map<String, dynamic> data) => jsonEncode(data);
}
