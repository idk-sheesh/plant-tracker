import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/services/form_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late FormDraftStore store;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('gardenjournal_drafts_');
    store = FormDraftStore(
      directoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('restaure le dernier brouillon sauvegardé', () async {
    await store.save('action-add-plant-1', {
      'version': 1,
      'notes': 'première version',
    });
    await store.save('action-add-plant-1', {
      'version': 1,
      'notes': 'version après verrouillage',
    });

    expect(
      await store.load('action-add-plant-1'),
      {
        'version': 1,
        'notes': 'version après verrouillage',
      },
    );
  });

  test('retombe sur la copie précédente si la plus récente est corrompue',
      () async {
    await store.save('action-add-plant-1', {
      'version': 1,
      'notes': 'copie valide',
    });
    await store.save('action-add-plant-1', {
      'version': 1,
      'notes': 'copie récente',
    });
    final latest = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}drafts'
      '${Platform.pathSeparator}action-add-plant-1.1.json',
    );
    await latest.writeAsString('{écriture interrompue');

    expect(
      await store.load('action-add-plant-1'),
      {
        'version': 1,
        'notes': 'copie valide',
      },
    );
  });

  test('supprime toutes les copies après validation', () async {
    await store.save('action-add-plant-1', {'version': 1, 'notes': 'test'});

    await store.delete('action-add-plant-1');

    expect(await store.load('action-add-plant-1'), isNull);
  });

  test('la session écrit les changements puis les efface au checkpoint',
      () async {
    final values = <String, dynamic>{
      'version': 1,
      'notes': '',
    };
    final session = FormDraftSession(
      key: 'action-add-plant-1',
      snapshot: () => Map<String, dynamic>.from(values),
      store: store,
      interval: const Duration(hours: 1),
    );

    expect(await session.restore(), isNull);
    session.start();
    values['notes'] = 'saisie protégée';
    await session.flush();
    expect(
      await store.load('action-add-plant-1'),
      {'version': 1, 'notes': 'saisie protégée'},
    );

    await session.checkpoint();
    expect(await store.load('action-add-plant-1'), isNull);

    values['notes'] = 'saisie au verrouillage';
    session.didChangeAppLifecycleState(AppLifecycleState.paused);
    await session.flush();
    expect(
      await store.load('action-add-plant-1'),
      {'version': 1, 'notes': 'saisie au verrouillage'},
    );

    await session.clear();
  });
}
