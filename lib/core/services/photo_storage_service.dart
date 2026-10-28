import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class PhotoStorageService {
  PhotoStorageService._();

  static const _uuid = Uuid();
  static const _rootFolder = 'gardenjournal_photos';

  static Future<Directory> managedRoot({Directory? rootOverride}) async {
    if (rootOverride != null) return rootOverride;
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDir.path, _rootFolder));
  }

  static Future<String> persistImage(
    String sourcePath, {
    required String bucket,
    Directory? rootDirectory,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Photo introuvable', path.basename(sourcePath));
    }
    if (await source.length() <= 0) {
      throw FileSystemException('Photo vide', path.basename(sourcePath));
    }

    final root = await managedRoot(rootOverride: rootDirectory);
    final safeBucket = _safeBucket(bucket);
    final photosDir = Directory(path.join(root.path, safeBucket));
    await photosDir.create(recursive: true);

    final sourceAbsolute = source.absolute.path;
    if (_isInsideDirectory(sourceAbsolute, root.absolute.path)) {
      return sourceAbsolute;
    }

    final extension = _safeExtension(sourcePath);
    final fileName =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}_${_uuid.v4()}$extension';
    final destinationPath = path.join(photosDir.path, fileName);
    final copied = await source.copy(destinationPath);
    if (!await copied.exists() ||
        await copied.length() != await source.length()) {
      if (await copied.exists()) await copied.delete();
      throw FileSystemException('Copie de photo incomplète', fileName);
    }
    return copied.absolute.path;
  }

  static Future<String> persistImageBytes(
    Uint8List bytes, {
    required String bucket,
    String extension = '.jpg',
    Directory? rootDirectory,
  }) async {
    if (bytes.isEmpty) throw const FormatException('Photo vide');
    final root = await managedRoot(rootOverride: rootDirectory);
    final photosDir = Directory(path.join(root.path, _safeBucket(bucket)));
    await photosDir.create(recursive: true);
    final safeExtension = _safeExtension('photo$extension');
    final fileName =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}_${_uuid.v4()}$safeExtension';
    final destination = File(path.join(photosDir.path, fileName));
    final temporary = File('${destination.path}.partial');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (!await temporary.exists() ||
          await temporary.length() != bytes.length) {
        throw FileSystemException('Écriture de photo incomplète', fileName);
      }
      return (await temporary.rename(destination.path)).absolute.path;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<String> migrateLegacyImage(
    String sourcePath, {
    required String bucket,
    Directory? rootDirectory,
  }) async {
    if (await isManagedPath(sourcePath, rootDirectory: rootDirectory)) {
      return File(sourcePath).absolute.path;
    }
    final migrated = await persistImage(
      sourcePath,
      bucket: bucket,
      rootDirectory: rootDirectory,
    );
    if (!await File(migrated).exists()) {
      throw FileSystemException(
          'Photo migrée introuvable', path.basename(migrated));
    }
    debugPrint('Photo héritée migrée: ${path.basename(sourcePath)}');
    return migrated;
  }

  static Future<void> finalizeLegacyMigration(
    String sourcePath, {
    Directory? documentsDirectory,
    Directory? temporaryDirectory,
  }) async {
    if (!await _isSafeLegacyPath(
      sourcePath,
      documentsDirectory: documentsDirectory,
      temporaryDirectory: temporaryDirectory,
    )) {
      return;
    }
    final source = File(sourcePath);
    if (await source.exists()) await source.delete();
  }

  static Future<bool> isManagedPath(
    String filePath, {
    Directory? rootDirectory,
  }) async {
    final root = await managedRoot(rootOverride: rootDirectory);
    return _isInsideDirectory(File(filePath).absolute.path, root.absolute.path);
  }

  static Future<bool> deleteManagedFile(
    String filePath, {
    Directory? rootDirectory,
  }) async {
    if (!await isManagedPath(filePath, rootDirectory: rootDirectory)) {
      throw FileSystemException(
        'Suppression refusée hors du stockage photo géré',
        path.basename(filePath),
      );
    }
    final file = File(filePath);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  static Future<int> deleteManagedFiles(
    Iterable<String> filePaths, {
    Directory? rootDirectory,
  }) async {
    var deleted = 0;
    final failures = <String>[];
    for (final filePath in filePaths.toSet()) {
      try {
        if (await deleteManagedFile(
          filePath,
          rootDirectory: rootDirectory,
        )) {
          deleted++;
        }
      } on FileSystemException catch (error, stackTrace) {
        failures.add(path.basename(filePath));
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'gardenjournal photos',
            context: ErrorDescription('suppression d’une photo gérée'),
          ),
        );
      }
    }
    if (failures.isNotEmpty) throw PhotoCleanupException(failures);
    return deleted;
  }

  static Future<PhotoCleanupReport> cleanupOrphans(
    Iterable<String> referencedPaths, {
    bool dryRun = true,
    Directory? rootDirectory,
  }) async {
    final root = await managedRoot(rootOverride: rootDirectory);
    if (!await root.exists()) {
      return PhotoCleanupReport(dryRun: dryRun, orphanPaths: const []);
    }
    final referenced = referencedPaths
        .map((value) => path.normalize(File(value).absolute.path))
        .toSet();
    final orphans = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final normalized = path.normalize(entity.absolute.path);
      if (referenced.contains(normalized)) continue;
      orphans.add(normalized);
      if (!dryRun) await entity.delete();
    }
    return PhotoCleanupReport(dryRun: dryRun, orphanPaths: orphans);
  }

  static Future<bool> _isSafeLegacyPath(
    String filePath, {
    Directory? documentsDirectory,
    Directory? temporaryDirectory,
  }) async {
    final absolute = File(filePath).absolute.path;
    final documents =
        documentsDirectory ?? await getApplicationDocumentsDirectory();
    final temporary = temporaryDirectory ?? await getTemporaryDirectory();
    return _isInsideDirectory(absolute, documents.absolute.path) ||
        _isInsideDirectory(absolute, temporary.absolute.path);
  }

  static bool _isInsideDirectory(String filePath, String directoryPath) {
    final normalizedFile = path.normalize(filePath);
    final normalizedDirectory = path.normalize(directoryPath);
    if (Platform.isWindows) {
      final lowerFile = normalizedFile.toLowerCase();
      final lowerDirectory = normalizedDirectory.toLowerCase();
      return lowerFile == lowerDirectory ||
          lowerFile.startsWith('$lowerDirectory${Platform.pathSeparator}');
    }
    return normalizedFile == normalizedDirectory ||
        normalizedFile.startsWith(
          '$normalizedDirectory${Platform.pathSeparator}',
        );
  }

  static String _safeBucket(String bucket) {
    final normalized = bucket.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(normalized)) {
      throw const FormatException('Identifiant de dossier photo invalide');
    }
    return normalized;
  }

  static String _safeExtension(String sourcePath) {
    final extension = path.extension(sourcePath).toLowerCase();
    if (RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) {
      return extension;
    }
    return '.jpg';
  }
}

class PhotoCleanupReport {
  final bool dryRun;
  final List<String> orphanPaths;

  const PhotoCleanupReport({
    required this.dryRun,
    required this.orphanPaths,
  });
}

class PhotoCleanupException implements Exception {
  final List<String> fileNames;

  const PhotoCleanupException(this.fileNames);

  @override
  String toString() =>
      'Nettoyage photo incomplet (${fileNames.length} fichier(s))';
}
