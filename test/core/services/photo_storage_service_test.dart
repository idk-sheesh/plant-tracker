import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:garden_journal/core/services/photo_storage_service.dart';

void main() {
  late Directory temp;
  late Directory root;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gardenjournal-photos-');
    root = Directory('${temp.path}/managed');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('copie, vérifie puis finalise une migration héritée', () async {
    final source = File('${temp.path}/legacy.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);

    final migrated = await PhotoStorageService.migrateLegacyImage(
      source.path,
      bucket: 'plants',
      rootDirectory: root,
    );

    expect(await source.exists(), isTrue);
    expect(await File(migrated).readAsBytes(), [1, 2, 3, 4]);
    expect(
      await PhotoStorageService.isManagedPath(
        migrated,
        rootDirectory: root,
      ),
      isTrue,
    );
    await PhotoStorageService.finalizeLegacyMigration(
      source.path,
      documentsDirectory: temp,
      temporaryDirectory: temp,
    );
    expect(await source.exists(), isFalse);
  });

  test('refuse toute suppression hors du répertoire géré', () async {
    final outside = File('${temp.path}/outside.jpg');
    await outside.writeAsBytes([1]);

    expect(
      () => PhotoStorageService.deleteManagedFile(
        outside.path,
        rootDirectory: root,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await outside.exists(), isTrue);
  });

  test('écrit directement une image mémoire dans le stockage géré', () async {
    final bytes = Uint8List.fromList([0xff, 0xd8, 1, 2, 0xff, 0xd9]);

    final stored = await PhotoStorageService.persistImageBytes(
      bytes,
      bucket: 'camera_snapshots',
      rootDirectory: root,
    );

    expect(await File(stored).readAsBytes(), bytes);
    expect(
      await PhotoStorageService.isManagedPath(
        stored,
        rootDirectory: root,
      ),
      isTrue,
    );
    await expectLater(
      PhotoStorageService.persistImageBytes(
        Uint8List(0),
        bucket: 'camera_snapshots',
        rootDirectory: root,
      ),
      throwsFormatException,
    );
  });

  test('suppression idempotente et nettoyage orphelin avec simulation',
      () async {
    final sourceA = File('${temp.path}/a.jpg')..writeAsBytesSync([1]);
    final sourceB = File('${temp.path}/b.jpg')..writeAsBytesSync([2]);
    final referenced = await PhotoStorageService.persistImage(
      sourceA.path,
      bucket: 'actions',
      rootDirectory: root,
    );
    final orphan = await PhotoStorageService.persistImage(
      sourceB.path,
      bucket: 'actions',
      rootDirectory: root,
    );

    final dryRun = await PhotoStorageService.cleanupOrphans(
      [referenced],
      rootDirectory: root,
    );
    expect(dryRun.dryRun, isTrue);
    expect(dryRun.orphanPaths.map(p.normalize), [p.normalize(orphan)]);
    expect(await File(orphan).exists(), isTrue);

    final deleted = await PhotoStorageService.cleanupOrphans(
      [referenced],
      dryRun: false,
      rootDirectory: root,
    );
    expect(deleted.orphanPaths.map(p.normalize), [p.normalize(orphan)]);
    expect(await File(orphan).exists(), isFalse);
    expect(
      await PhotoStorageService.deleteManagedFile(
        orphan,
        rootDirectory: root,
      ),
      isFalse,
    );
  });
}
