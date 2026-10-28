import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const currentVersion = 25;
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;
  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'garden_journal.db');
    return await openDatabase(
      path,
      version: currentVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE groups (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
      color INTEGER NOT NULL DEFAULT 4280391411, created_at TEXT NOT NULL,
      parent_group_id TEXT,
      FOREIGN KEY (parent_group_id) REFERENCES groups(id) ON DELETE SET NULL,
      CHECK (parent_group_id IS NULL OR parent_group_id != id))''');
    await db.execute('''CREATE TABLE plants (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, variety TEXT,
      potting_date TEXT NOT NULL, culture_type TEXT NOT NULL, pot_size TEXT,
      photo_path TEXT, notes TEXT, group_id TEXT, qr_code TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      location TEXT NOT NULL DEFAULT 'indoor',
      container_type TEXT NOT NULL DEFAULT 'pot',
      origin TEXT NOT NULL DEFAULT 'unknown',
      is_pinned INTEGER NOT NULL DEFAULT 0,
      is_harvested INTEGER NOT NULL DEFAULT 0,
      is_dead INTEGER NOT NULL DEFAULT 0,
      watering_reminder INTEGER CHECK (watering_reminder IN (0, 1)),
      observation_code TEXT,
      FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE SET NULL)''');
    await db.execute('''CREATE TABLE actions (
      id TEXT PRIMARY KEY, plant_id TEXT NOT NULL, action_type TEXT NOT NULL,
      timestamp TEXT NOT NULL, quantity REAL, quantity_unit TEXT,
      ph REAL, ph_na INTEGER NOT NULL DEFAULT 0, tds REAL, tds_na INTEGER NOT NULL DEFAULT 0,
      product_used TEXT, pruning_type TEXT, notes TEXT, created_at TEXT NOT NULL,
      parent_plant_id TEXT, cutting_notes TEXT, repot_container_type TEXT,
      is_watering_combined INTEGER NOT NULL DEFAULT 0,
      harvest_weight_fresh REAL,
      harvest_weight_stored REAL,
      harvest_weight_waste REAL,
      status TEXT NOT NULL DEFAULT 'done',
      completed_at TEXT,
      FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE,
      FOREIGN KEY (parent_plant_id) REFERENCES plants(id) ON DELETE SET NULL,
      CHECK (harvest_weight_fresh IS NULL OR harvest_weight_fresh BETWEEN 0 AND 1000000),
      CHECK (harvest_weight_stored IS NULL OR harvest_weight_stored BETWEEN 0 AND 1000000),
      CHECK (harvest_weight_waste IS NULL OR harvest_weight_waste BETWEEN 0 AND 1000000))''');
    await db.execute('''CREATE TABLE action_photos (
      id TEXT PRIMARY KEY, action_id TEXT NOT NULL, plant_id TEXT NOT NULL,
      photo_path TEXT NOT NULL, created_at TEXT NOT NULL,
      FOREIGN KEY (action_id) REFERENCES actions(id) ON DELETE CASCADE,
      FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE)''');
    await _createCoreIndexes(db);
    await _createLegacyDevicesTable(db);
    await _createCultivationTables(db);
    await _createGenericSensorTables(db);
    await _createDeviceHealthTables(db);
    await _createCalibrationAndAlertTables(db);
    await _createSafeControlTables(db);
    await _createGatewayTables(db);
    await _createLoRaTables(db);
    await _createOtaTables(db);
    await _createAutomationTables(db);
    await _createCycleExportTables(db);
    await _createCameraTables(db);
    await _createZonePhotoTable(db);
    await _createObservationAssessmentsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'ph_na',
          definition: 'ph_na INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'tds_na',
          definition: 'tds_na INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'parent_plant_id',
          definition: 'parent_plant_id TEXT');
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'cutting_notes',
          definition: 'cutting_notes TEXT');
      await _addColumnIfMissing(db,
          table: 'groups',
          column: 'parent_group_id',
          definition: 'parent_group_id TEXT');
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(db,
          table: 'plants',
          column: 'location',
          definition: "location TEXT NOT NULL DEFAULT 'indoor'");
      await _addColumnIfMissing(db,
          table: 'plants',
          column: 'container_type',
          definition: "container_type TEXT NOT NULL DEFAULT 'pot'");
    }
    if (oldVersion < 4) {
      await _createActionPhotosTable(db);
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'is_watering_combined',
          definition: 'is_watering_combined INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 5) {
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'is_watering_combined',
          definition: 'is_watering_combined INTEGER NOT NULL DEFAULT 0');
      await _createActionPhotosTable(db);
      await _addColumnIfMissing(db,
          table: 'plants',
          column: 'location',
          definition: "location TEXT NOT NULL DEFAULT 'indoor'");
      await _addColumnIfMissing(db,
          table: 'plants',
          column: 'container_type',
          definition: "container_type TEXT NOT NULL DEFAULT 'pot'");
    }
    if (oldVersion < 6) {
      // Nouveaux champs plante : origine, épinglage, récolte
      await _addColumnIfMissing(db,
          table: 'plants',
          column: 'origin',
          definition: "origin TEXT NOT NULL DEFAULT 'unknown'");
      await _addColumnIfMissing(db,
          table: 'plants',
          column: 'is_pinned',
          definition: 'is_pinned INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db,
          table: 'plants',
          column: 'is_harvested',
          definition: 'is_harvested INTEGER NOT NULL DEFAULT 0');
      // Nouveaux champs action : poids récolte
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'harvest_weight_stored',
          definition: 'harvest_weight_stored REAL');
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'harvest_weight_waste',
          definition: 'harvest_weight_waste REAL');
    }
    if (oldVersion < 7) {
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'status',
          definition: "status TEXT NOT NULL DEFAULT 'done'");
      await _addColumnIfMissing(db,
          table: 'actions',
          column: 'completed_at',
          definition: 'completed_at TEXT');
    }
    if (oldVersion < 8) {
      await _createLegacySensorTables(db);
    }
    if (oldVersion < 9) {
      await _migrateToVersion9(db);
    }
    if (oldVersion < 10) {
      await _migrateToVersion10(db);
    }
    if (oldVersion < 11) {
      await _createGenericSensorTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 12) {
      await _addColumnIfMissing(
        db,
        table: 'sensor_devices',
        column: 'device_kind',
        definition: "device_kind TEXT NOT NULL DEFAULT 'sensor'",
      );
      await _addColumnIfMissing(
        db,
        table: 'sensor_devices',
        column: 'transport',
        definition: "transport TEXT NOT NULL DEFAULT 'http'",
      );
      await _addColumnIfMissing(
        db,
        table: 'sensor_devices',
        column: 'model',
        definition: 'model TEXT',
      );
      await _addColumnIfMissing(
        db,
        table: 'sensor_devices',
        column: 'hardware_version',
        definition: 'hardware_version TEXT',
      );
      await _addColumnIfMissing(
        db,
        table: 'sensor_devices',
        column: 'ble_device_id',
        definition: 'ble_device_id TEXT',
      );
      await _createDeviceHealthTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 13) {
      await _createCalibrationAndAlertTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 14) {
      await _createSafeControlTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 15) {
      await _createGatewayTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 16) {
      await _createLoRaTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 17) {
      await _createOtaTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 18) {
      await _createAutomationTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 19) {
      await _addColumnIfMissing(
        db,
        table: 'device_commands',
        column: 'zone_id',
        definition: 'zone_id TEXT',
      );
      await _createCycleExportTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 20) {
      if (await _tableExists(db, 'sensor_devices')) {
        await _addColumnIfMissing(
          db,
          table: 'sensor_devices',
          column: 'cloud_device_id',
          definition: 'cloud_device_id TEXT',
        );
        await _addColumnIfMissing(
          db,
          table: 'sensor_devices',
          column: 'cloud_cursor',
          definition: 'cloud_cursor TEXT',
        );
        await _addColumnIfMissing(
          db,
          table: 'sensor_devices',
          column: 'cloud_last_sync_at',
          definition: 'cloud_last_sync_at INTEGER',
        );
        await _addColumnIfMissing(
          db,
          table: 'sensor_devices',
          column: 'cloud_last_error',
          definition: 'cloud_last_error TEXT',
        );
        await _addColumnIfMissing(
          db,
          table: 'sensor_devices',
          column: 'cloud_last_error_at',
          definition: 'cloud_last_error_at INTEGER',
        );
        await _addColumnIfMissing(
          db,
          table: 'sensor_devices',
          column: 'cloud_last_contact_at',
          definition: 'cloud_last_contact_at INTEGER',
        );
      }
      if (await _tableExists(db, 'sensor_readings')) {
        await _addColumnIfMissing(
          db,
          table: 'sensor_readings',
          column: 'remote_event_id',
          definition: 'remote_event_id TEXT',
        );
        await _addColumnIfMissing(
          db,
          table: 'sensor_readings',
          column: 'source_sequence',
          definition: 'source_sequence INTEGER',
        );
        await db.execute('''CREATE INDEX IF NOT EXISTS
          idx_sensor_readings_remote_event
          ON sensor_readings(device_id, remote_event_id)''');
      }
      await _assertForeignKeys(db);
    }
    if (oldVersion < 21) {
      if (await _tableExists(db, 'plants')) {
        await _addColumnIfMissing(
          db,
          table: 'plants',
          column: 'is_dead',
          definition: 'is_dead INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
    if (oldVersion < 22) {
      await _createCameraTables(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 23) {
      await _createCameraTables(db);
      if (await _tableExists(db, 'camera_snapshots')) {
        await _addColumnIfMissing(
          db,
          table: 'camera_snapshots',
          column: 'photo_path',
          definition: 'photo_path TEXT',
        );
      }
      await _assertForeignKeys(db);
    }
    if (oldVersion < 24) {
      await _createZonePhotoTable(db);
      await _assertForeignKeys(db);
    }
    if (oldVersion < 25) {
      if (await _tableExists(db, 'plants')) {
        await _addColumnIfMissing(db,
            table: 'plants',
            column: 'watering_reminder',
            definition:
                'watering_reminder INTEGER CHECK (watering_reminder IN (0, 1))');
        await _addColumnIfMissing(db,
            table: 'plants',
            column: 'observation_code',
            definition: 'observation_code TEXT');
        await _createObservationAssessmentsTable(db);
      }
      await _assertForeignKeys(db);
    }
  }

  Future<void> _createObservationAssessmentsTable(Database db) async {
    if (!await _tableExists(db, 'plants')) return;
    await db.execute('''CREATE TABLE IF NOT EXISTS observation_assessments (
      id TEXT PRIMARY KEY,
      plant_id TEXT NOT NULL,
      observed_at TEXT NOT NULL,
      stage TEXT NOT NULL,
      scores_json TEXT NOT NULL DEFAULT '{}',
      measurements_json TEXT NOT NULL DEFAULT '{}',
      aromas TEXT,
      notes TEXT,
      decision TEXT NOT NULL DEFAULT 'undecided',
      created_at TEXT NOT NULL,
      FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_observation_plant_date
      ON observation_assessments(plant_id, observed_at DESC)''');
  }

  Future<void> _createZonePhotoTable(Database db) async {
    if (!await _tableExists(db, 'cultivation_zones')) return;
    await db.execute('''CREATE TABLE IF NOT EXISTS zone_photos (
      id TEXT PRIMARY KEY,
      zone_id TEXT NOT NULL,
      photo_path TEXT NOT NULL,
      captured_at INTEGER NOT NULL,
      caption TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (zone_id) REFERENCES cultivation_zones(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_zone_photos_zone_captured
      ON zone_photos(zone_id, captured_at DESC)''');
  }

  Future<void> _createCoreIndexes(Database db) async {
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_plants_group_id
      ON plants(group_id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_actions_plant_timestamp
      ON actions(plant_id, timestamp DESC)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_actions_parent_plant_id
      ON actions(parent_plant_id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_action_photos_action_id
      ON action_photos(action_id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_action_photos_plant_id
      ON action_photos(plant_id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_groups_parent_group_id
      ON groups(parent_group_id)''');
  }

  Future<void> _migrateToVersion10(Database db) async {
    const requiredTables = <String>[
      'groups',
      'plants',
      'actions',
      'action_photos',
      'devices',
      'zone_placements',
    ];
    for (final table in requiredTables) {
      if (!await _tableExists(db, table)) {
        throw StateError('Migration v10 impossible: table $table absente');
      }
    }

    await _assertNoRows(
      db,
      '''SELECT actions.id FROM actions
         LEFT JOIN plants ON plants.id = actions.plant_id
         WHERE plants.id IS NULL LIMIT 1''',
      'une action référence une plante inexistante',
    );
    await _assertNoRows(
      db,
      '''SELECT action_photos.id FROM action_photos
         LEFT JOIN actions ON actions.id = action_photos.action_id
         WHERE actions.id IS NULL LIMIT 1''',
      'une photo référence une action inexistante',
    );

    for (final table in const [
      'action_photos_v10',
      'actions_v10',
      'zone_placements_v10',
      'plants_v10',
      'devices_v10',
      'groups_v10',
    ]) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }

    await db.execute('''CREATE TABLE groups_v10 (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
      color INTEGER NOT NULL DEFAULT 4280391411, created_at TEXT NOT NULL,
      parent_group_id TEXT,
      FOREIGN KEY (parent_group_id) REFERENCES groups_v10(id)
        ON DELETE SET NULL,
      CHECK (parent_group_id IS NULL OR parent_group_id != id))''');
    await db.execute('''CREATE TABLE plants_v10 (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, variety TEXT,
      potting_date TEXT NOT NULL, culture_type TEXT NOT NULL, pot_size TEXT,
      photo_path TEXT, notes TEXT, group_id TEXT, qr_code TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      location TEXT NOT NULL DEFAULT 'indoor',
      container_type TEXT NOT NULL DEFAULT 'pot',
      origin TEXT NOT NULL DEFAULT 'unknown',
      is_pinned INTEGER NOT NULL DEFAULT 0,
      is_harvested INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (group_id) REFERENCES groups_v10(id) ON DELETE SET NULL)''');
    await db.execute('''CREATE TABLE actions_v10 (
      id TEXT PRIMARY KEY, plant_id TEXT NOT NULL, action_type TEXT NOT NULL,
      timestamp TEXT NOT NULL, quantity REAL, quantity_unit TEXT, ph REAL,
      ph_na INTEGER NOT NULL DEFAULT 0, tds REAL,
      tds_na INTEGER NOT NULL DEFAULT 0, product_used TEXT, pruning_type TEXT,
      notes TEXT, created_at TEXT NOT NULL, parent_plant_id TEXT,
      cutting_notes TEXT, repot_container_type TEXT,
      is_watering_combined INTEGER NOT NULL DEFAULT 0,
      harvest_weight_fresh REAL, harvest_weight_stored REAL,
      harvest_weight_waste REAL, status TEXT NOT NULL DEFAULT 'done',
      completed_at TEXT,
      FOREIGN KEY (plant_id) REFERENCES plants_v10(id) ON DELETE CASCADE,
      FOREIGN KEY (parent_plant_id) REFERENCES plants_v10(id)
        ON DELETE SET NULL,
      CHECK (harvest_weight_fresh IS NULL OR harvest_weight_fresh BETWEEN 0 AND 1000000),
      CHECK (harvest_weight_stored IS NULL OR harvest_weight_stored BETWEEN 0 AND 1000000),
      CHECK (harvest_weight_waste IS NULL OR harvest_weight_waste BETWEEN 0 AND 1000000))''');
    await db.execute('''CREATE TABLE action_photos_v10 (
      id TEXT PRIMARY KEY, action_id TEXT NOT NULL, plant_id TEXT NOT NULL,
      photo_path TEXT NOT NULL, created_at TEXT NOT NULL,
      FOREIGN KEY (action_id) REFERENCES actions_v10(id) ON DELETE CASCADE,
      FOREIGN KEY (plant_id) REFERENCES plants_v10(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE devices_v10 (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, zone_id TEXT,
      ip_address TEXT NOT NULL, last_seen_at INTEGER,
      FOREIGN KEY (zone_id) REFERENCES groups_v10(id) ON DELETE SET NULL)''');
    await db.execute('''CREATE TABLE zone_placements_v10 (
      id TEXT PRIMARY KEY, zone_id TEXT NOT NULL, plant_id TEXT, group_id TEXT,
      entity_name TEXT NOT NULL, entered_at INTEGER NOT NULL, exited_at INTEGER,
      note TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY (zone_id) REFERENCES cultivation_zones(id)
        ON DELETE RESTRICT,
      FOREIGN KEY (plant_id) REFERENCES plants_v10(id) ON DELETE SET NULL,
      FOREIGN KEY (group_id) REFERENCES groups_v10(id) ON DELETE SET NULL,
      CHECK (plant_id IS NULL OR group_id IS NULL))''');

    await db.execute('''INSERT INTO groups_v10
      (id, name, description, color, created_at, parent_group_id)
      SELECT g.id, g.name, g.description, g.color, g.created_at,
        CASE WHEN g.parent_group_id IS NOT NULL
          AND g.parent_group_id != g.id
          AND EXISTS (SELECT 1 FROM groups parent
            WHERE parent.id = g.parent_group_id)
        THEN g.parent_group_id ELSE NULL END
      FROM groups g''');
    await db.execute('''INSERT INTO plants_v10
      (id, name, variety, potting_date, culture_type, pot_size, photo_path,
       notes, group_id, qr_code, created_at, updated_at, location,
       container_type, origin, is_pinned, is_harvested)
      SELECT p.id, p.name, p.variety, p.potting_date, p.culture_type,
       p.pot_size, p.photo_path, p.notes,
       CASE WHEN EXISTS (SELECT 1 FROM groups g WHERE g.id = p.group_id)
         THEN p.group_id ELSE NULL END,
       p.qr_code, p.created_at, p.updated_at, p.location, p.container_type,
       p.origin, p.is_pinned, p.is_harvested
      FROM plants p''');

    final actionColumns = await db.rawQuery('PRAGMA table_info(actions)');
    final hasWetWeight =
        actionColumns.any((column) => column['name'] == 'harvest_weight_fresh');
    final wetWeightExpression =
        hasWetWeight ? 'a.harvest_weight_fresh' : 'NULL';
    final hasRepotContainer =
        actionColumns.any((column) => column['name'] == 'repot_container_type');
    final repotContainerExpression =
        hasRepotContainer ? 'a.repot_container_type' : 'NULL';
    await db.execute('''INSERT INTO actions_v10
      (id, plant_id, action_type, timestamp, quantity, quantity_unit, ph,
       ph_na, tds, tds_na, product_used, pruning_type, notes, created_at,
       parent_plant_id, cutting_notes, repot_container_type,
       is_watering_combined,
       harvest_weight_fresh, harvest_weight_stored, harvest_weight_waste, status,
       completed_at)
      SELECT a.id, a.plant_id, a.action_type, a.timestamp, a.quantity,
       a.quantity_unit, a.ph, a.ph_na, a.tds, a.tds_na, a.product_used,
       a.pruning_type, a.notes, a.created_at,
       CASE WHEN EXISTS (SELECT 1 FROM plants p
         WHERE p.id = a.parent_plant_id) THEN a.parent_plant_id ELSE NULL END,
       a.cutting_notes, $repotContainerExpression, a.is_watering_combined,
       $wetWeightExpression,
       a.harvest_weight_stored, a.harvest_weight_waste, a.status, a.completed_at
      FROM actions a''');
    await db.execute('''INSERT INTO action_photos_v10
      (id, action_id, plant_id, photo_path, created_at)
      SELECT photo.id, photo.action_id, action.plant_id,
       photo.photo_path, photo.created_at
      FROM action_photos photo
      JOIN actions action ON action.id = photo.action_id''');
    await db.execute('''INSERT INTO devices_v10
      (id, name, zone_id, ip_address, last_seen_at)
      SELECT d.id, d.name,
       CASE WHEN EXISTS (SELECT 1 FROM groups g WHERE g.id = d.zone_id)
         THEN d.zone_id ELSE NULL END,
       d.ip_address, d.last_seen_at
      FROM devices d''');
    await db.execute('''INSERT INTO zone_placements_v10
      (id, zone_id, plant_id, group_id, entity_name, entered_at, exited_at,
       note, created_at, updated_at)
      SELECT placement.id, placement.zone_id,
       CASE WHEN EXISTS (SELECT 1 FROM plants p
         WHERE p.id = placement.plant_id) THEN placement.plant_id ELSE NULL END,
       CASE WHEN EXISTS (SELECT 1 FROM groups g
         WHERE g.id = placement.group_id) THEN placement.group_id ELSE NULL END,
       placement.entity_name, placement.entered_at, placement.exited_at,
       placement.note, placement.created_at, placement.updated_at
      FROM zone_placements placement''');

    for (final pair in const [
      ('groups', 'groups_v10'),
      ('plants', 'plants_v10'),
      ('actions', 'actions_v10'),
      ('action_photos', 'action_photos_v10'),
      ('devices', 'devices_v10'),
      ('zone_placements', 'zone_placements_v10'),
    ]) {
      await _assertSameRowCount(db, pair.$1, pair.$2);
      await _assertForeignKeys(db, pair.$2);
    }

    await db.execute('DROP TABLE action_photos');
    await db.execute('DROP TABLE actions');
    await db.execute('DROP TABLE zone_placements');
    await db.execute('DROP TABLE plants');
    await db.execute('DROP TABLE devices');
    await db.execute('DROP TABLE groups');

    await db.execute('ALTER TABLE groups_v10 RENAME TO groups');
    await db.execute('ALTER TABLE plants_v10 RENAME TO plants');
    await db.execute('ALTER TABLE actions_v10 RENAME TO actions');
    await db.execute('ALTER TABLE action_photos_v10 RENAME TO action_photos');
    await db.execute('ALTER TABLE devices_v10 RENAME TO devices');
    await db.execute(
      'ALTER TABLE zone_placements_v10 RENAME TO zone_placements',
    );

    await db.execute('''UPDATE plants
      SET is_harvested = CASE WHEN EXISTS (
        SELECT 1 FROM actions
        WHERE actions.plant_id = plants.id
          AND actions.action_type = 'recolte'
          AND actions.status != 'planned'
      ) THEN 1 ELSE 0 END''');
    await _createCoreIndexes(db);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_devices_zone_id ON devices(zone_id)',
    );
    await _createCultivationIndexes(db);
    await _assertForeignKeys(db);
  }

  Future<void> _assertNoRows(
    Database db,
    String query,
    String message,
  ) async {
    if ((await db.rawQuery(query)).isNotEmpty) {
      throw StateError('Migration interrompue: $message');
    }
  }

  Future<void> _assertSameRowCount(
    Database db,
    String source,
    String destination,
  ) async {
    final sourceCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $source'),
        ) ??
        0;
    final destinationCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $destination'),
        ) ??
        0;
    if (sourceCount != destinationCount) {
      throw StateError(
        'Migration interrompue: $source=$sourceCount, '
        '$destination=$destinationCount',
      );
    }
  }

  Future<void> _assertForeignKeys(Database db, [String? table]) async {
    final suffix = table == null ? '' : '($table)';
    final failures = await db.rawQuery('PRAGMA foreign_key_check$suffix');
    if (failures.isNotEmpty) {
      throw StateError(
        'Migration interrompue: violation de clé étrangère '
        '${table ?? 'globale'}',
      );
    }
  }

  Future<void> _createLegacySensorTables(Database db) async {
    await _createLegacyDevicesTable(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS sensor_readings (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      measured_at INTEGER NOT NULL,
      temperature REAL NOT NULL,
      humidity REAL NOT NULL,
      vpd REAL NOT NULL,
      mist_on INTEGER NOT NULL DEFAULT 0,
      fan_percent REAL,
      FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE,
      UNIQUE (device_id, measured_at))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_sensor_readings_device_measured_at
      ON sensor_readings(device_id, measured_at)''');
  }

  Future<void> _createLegacyDevicesTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS devices (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      zone_id TEXT,
      ip_address TEXT NOT NULL,
      last_seen_at INTEGER,
      FOREIGN KEY (zone_id) REFERENCES groups(id) ON DELETE SET NULL)''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_devices_zone_id ON devices(zone_id)');
  }

  Future<void> _createCultivationTables(Database db) async {
    await _createCultivationZonesTable(db);
    await _createSensorDevicesTable(db);
    await _createSensorReadingsV9Table(db, table: 'sensor_readings');
    await _createZonePlacementsTable(db);
    await _createCultivationIndexes(db);
    await _seedDefaultCultivationZones(db);
  }

  Future<void> _createGenericSensorTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sensor_device_capabilities (
      device_id TEXT NOT NULL,
      capability_key TEXT NOT NULL,
      display_name TEXT NOT NULL,
      value_type TEXT NOT NULL,
      unit TEXT,
      minimum_value REAL,
      maximum_value REAL,
      is_writable INTEGER NOT NULL DEFAULT 0,
      metadata_json TEXT NOT NULL DEFAULT '{}',
      updated_at TEXT NOT NULL,
      PRIMARY KEY (device_id, capability_key),
      UNIQUE (device_id, capability_key, value_type),
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id)
        ON DELETE CASCADE,
      CHECK (value_type IN ('number', 'boolean', 'text')),
      CHECK (is_writable IN (0, 1)),
      CHECK (minimum_value IS NULL OR maximum_value IS NULL
        OR minimum_value <= maximum_value))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS sensor_measurements (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      zone_id TEXT,
      capability_key TEXT NOT NULL,
      measured_at INTEGER NOT NULL,
      value_type TEXT NOT NULL,
      numeric_value REAL,
      text_value TEXT,
      boolean_value INTEGER,
      unit TEXT,
      quality TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (device_id, capability_key, value_type)
        REFERENCES sensor_device_capabilities(
          device_id, capability_key, value_type)
        ON DELETE CASCADE,
      FOREIGN KEY (zone_id) REFERENCES cultivation_zones(id)
        ON DELETE SET NULL,
      UNIQUE (device_id, capability_key, measured_at),
      CHECK (value_type IN ('number', 'boolean', 'text')),
      CHECK (boolean_value IS NULL OR boolean_value IN (0, 1)),
      CHECK ((numeric_value IS NOT NULL) + (text_value IS NOT NULL)
        + (boolean_value IS NOT NULL) = 1),
      CHECK ((value_type = 'number' AND numeric_value IS NOT NULL)
        OR (value_type = 'text' AND text_value IS NOT NULL)
        OR (value_type = 'boolean' AND boolean_value IS NOT NULL)))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_sensor_capabilities_device
      ON sensor_device_capabilities(device_id, capability_key)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_sensor_measurements_device_measured
      ON sensor_measurements(device_id, measured_at DESC)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_sensor_measurements_zone_measured
      ON sensor_measurements(zone_id, measured_at DESC)''');
  }

  Future<void> _migrateToVersion9(Database db) async {
    await _createCultivationZonesTable(db);
    await _createSensorDevicesTable(db);
    await _createZonePlacementsTable(db);
    await _seedDefaultCultivationZones(db);
    await _migrateLegacyDevices(db);
    await _migrateLegacySensorReadings(db);
    await _createCultivationIndexes(db);
  }

  Future<void> _createDeviceHealthTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS device_health_snapshots (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      observed_at INTEGER NOT NULL,
      is_online INTEGER NOT NULL,
      battery_percent REAL,
      battery_voltage REAL,
      rssi_dbm INTEGER,
      snr_db REAL,
      uptime_seconds INTEGER,
      free_heap_bytes INTEGER,
      missing_readings INTEGER NOT NULL DEFAULT 0,
      firmware_version TEXT,
      last_error TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id)
        ON DELETE CASCADE,
      UNIQUE (device_id, observed_at),
      CHECK (is_online IN (0, 1)),
      CHECK (battery_percent IS NULL OR battery_percent BETWEEN 0 AND 100),
      CHECK (battery_voltage IS NULL OR battery_voltage BETWEEN 0 AND 100),
      CHECK (missing_readings >= 0),
      CHECK (uptime_seconds IS NULL OR uptime_seconds >= 0),
      CHECK (free_heap_bytes IS NULL OR free_heap_bytes >= 0))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_device_health_device_observed
      ON device_health_snapshots(device_id, observed_at DESC)''');
  }

  Future<void> _createCalibrationAndAlertTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS calibration_records (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      capability_key TEXT NOT NULL,
      calibration_type TEXT NOT NULL,
      calibrated_at INTEGER NOT NULL,
      reference_values_json TEXT NOT NULL,
      coefficients_json TEXT NOT NULL,
      temperature_c REAL,
      operator_name TEXT,
      solution_lot TEXT,
      expires_at INTEGER,
      node_ack_at INTEGER NOT NULL,
      node_config_hash TEXT NOT NULL,
      notes TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id)
        ON DELETE RESTRICT,
      CHECK (calibration_type IN ('single_point', 'two_point', 'three_point')),
      CHECK (expires_at IS NULL OR expires_at > calibrated_at),
      CHECK (node_ack_at >= calibrated_at))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_calibrations_device_capability_date
      ON calibration_records(device_id, capability_key, calibrated_at DESC)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS alert_rules (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      zone_id TEXT,
      device_id TEXT,
      metric_key TEXT NOT NULL,
      comparison TEXT NOT NULL,
      threshold_min REAL,
      threshold_max REAL,
      duration_seconds INTEGER NOT NULL DEFAULT 0,
      hysteresis REAL NOT NULL DEFAULT 0,
      cooldown_seconds INTEGER NOT NULL DEFAULT 900,
      severity TEXT NOT NULL DEFAULT 'warning',
      is_enabled INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (zone_id) REFERENCES cultivation_zones(id)
        ON DELETE CASCADE,
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id)
        ON DELETE CASCADE,
      CHECK (zone_id IS NOT NULL OR device_id IS NOT NULL),
      CHECK (comparison IN ('gt', 'lt', 'outside', 'stale')),
      CHECK (duration_seconds >= 0),
      CHECK (hysteresis >= 0),
      CHECK (cooldown_seconds >= 0),
      CHECK (severity IN ('info', 'warning', 'critical')),
      CHECK (is_enabled IN (0, 1)))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_alert_rules_targets ON alert_rules(zone_id, device_id, is_enabled)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS alert_evaluation_states (
      rule_id TEXT PRIMARY KEY,
      first_violation_at INTEGER,
      last_evaluated_at INTEGER NOT NULL,
      last_value REAL,
      is_violating INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (rule_id) REFERENCES alert_rules(id) ON DELETE CASCADE,
      CHECK (is_violating IN (0, 1)))''');

    await db.execute('''CREATE TABLE IF NOT EXISTS alert_events (
      id TEXT PRIMARY KEY,
      rule_id TEXT NOT NULL,
      device_id TEXT,
      zone_id TEXT,
      metric_key TEXT NOT NULL,
      severity TEXT NOT NULL,
      message TEXT NOT NULL,
      observed_value REAL,
      started_at INTEGER NOT NULL,
      last_observed_at INTEGER NOT NULL,
      resolved_at INTEGER,
      acknowledged_at INTEGER,
      notification_sent_at INTEGER,
      created_at TEXT NOT NULL,
      CHECK (severity IN ('info', 'warning', 'critical')),
      CHECK (resolved_at IS NULL OR resolved_at >= started_at),
      CHECK (acknowledged_at IS NULL OR acknowledged_at >= started_at))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_alert_events_active
      ON alert_events(resolved_at, started_at DESC)''');
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
      idx_alert_events_one_active_rule
      ON alert_events(rule_id) WHERE resolved_at IS NULL''');
  }

  Future<void> _createSafeControlTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS device_commands (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      zone_id TEXT,
      command_type TEXT NOT NULL,
      params_json TEXT NOT NULL,
      idempotency_key TEXT NOT NULL UNIQUE,
      safety_class TEXT NOT NULL,
      requested_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      status TEXT NOT NULL,
      node_ack_at INTEGER,
      node_response_json TEXT,
      error_code TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (command_type IN (
        'mist.set', 'fan.set', 'light.set', 'irrigation.pulse')),
      CHECK (safety_class IN ('standard', 'critical')),
      CHECK (expires_at > requested_at),
      CHECK (status IN (
        'pending', 'acknowledged', 'rejected', 'failed', 'expired')),
      CHECK (node_ack_at IS NULL OR node_ack_at >= requested_at))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_device_commands_device_requested
      ON device_commands(device_id, requested_at DESC)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS node_schedules (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      name TEXT NOT NULL,
      command_type TEXT NOT NULL,
      timezone TEXT NOT NULL,
      days_mask INTEGER NOT NULL,
      start_minute INTEGER NOT NULL,
      params_json TEXT NOT NULL,
      revision INTEGER NOT NULL,
      schedule_hash TEXT NOT NULL,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL,
      node_ack_at INTEGER,
      node_ack_hash TEXT,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id) ON DELETE CASCADE,
      CHECK (command_type IN (
        'mist.set', 'fan.set', 'light.set', 'irrigation.pulse')),
      CHECK (days_mask BETWEEN 1 AND 127),
      CHECK (start_minute BETWEEN 0 AND 1439),
      CHECK (revision >= 1),
      CHECK (is_enabled IN (0, 1)),
      CHECK (status IN (
        'pending', 'active', 'rejected', 'failed', 'disabled')),
      CHECK (node_ack_at IS NULL OR node_ack_hash IS NOT NULL))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_node_schedules_device_enabled
      ON node_schedules(device_id, is_enabled, start_minute)''');
  }

  Future<void> _createGatewayTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS gateway_configs (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL UNIQUE,
      transport_mode TEXT NOT NULL,
      http_base_url TEXT,
      mqtt_host TEXT,
      mqtt_port INTEGER,
      mqtt_use_tls INTEGER NOT NULL DEFAULT 1,
      mqtt_topic_prefix TEXT NOT NULL DEFAULT 'gardenjournal',
      mqtt_username TEXT,
      last_http_cursor INTEGER NOT NULL DEFAULT 0,
      last_mqtt_at INTEGER,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id) ON DELETE CASCADE,
      CHECK (transport_mode IN ('http', 'mqtt', 'hybrid')),
      CHECK (mqtt_port IS NULL OR mqtt_port BETWEEN 1 AND 65535),
      CHECK (mqtt_use_tls IN (0, 1)),
      CHECK (transport_mode = 'mqtt' OR http_base_url IS NOT NULL),
      CHECK (transport_mode = 'http' OR mqtt_host IS NOT NULL))''');

    await db.execute('''CREATE TABLE IF NOT EXISTS gateway_messages (
      id TEXT PRIMARY KEY,
      gateway_id TEXT NOT NULL,
      transport TEXT NOT NULL,
      topic TEXT,
      message_id TEXT NOT NULL,
      payload_hash TEXT NOT NULL,
      sent_at INTEGER NOT NULL,
      received_at INTEGER NOT NULL,
      status TEXT NOT NULL,
      error_code TEXT,
      payload_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (gateway_id) REFERENCES gateway_configs(id) ON DELETE CASCADE,
      UNIQUE (gateway_id, message_id),
      CHECK (transport IN ('http', 'mqtt')),
      CHECK (status IN ('processing', 'accepted', 'rejected')),
      CHECK (received_at >= sent_at - 86400))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_gateway_messages_received
      ON gateway_messages(gateway_id, received_at DESC)''');
  }

  Future<void> _createLoRaTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS gateway_nodes (
      gateway_id TEXT NOT NULL,
      node_device_id TEXT NOT NULL UNIQUE,
      lora_address TEXT NOT NULL,
      protocol_version INTEGER NOT NULL DEFAULT 1,
      last_session_id TEXT,
      last_frame_counter INTEGER NOT NULL DEFAULT -1,
      joined_at INTEGER NOT NULL,
      last_seen_at INTEGER,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (gateway_id, lora_address),
      FOREIGN KEY (gateway_id) REFERENCES gateway_configs(id) ON DELETE CASCADE,
      FOREIGN KEY (node_device_id) REFERENCES sensor_devices(id) ON DELETE CASCADE,
      CHECK (protocol_version = 1),
      CHECK (last_frame_counter >= -1),
      CHECK (status IN ('active', 'disabled')) )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS lora_packets (
      id TEXT PRIMARY KEY,
      gateway_id TEXT NOT NULL,
      node_device_id TEXT,
      node_uid TEXT NOT NULL,
      session_id TEXT NOT NULL,
      frame_counter INTEGER NOT NULL,
      sent_at INTEGER NOT NULL,
      received_at INTEGER NOT NULL,
      rssi INTEGER,
      snr REAL,
      payload_hash TEXT NOT NULL,
      status TEXT NOT NULL,
      error_code TEXT,
      raw_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (gateway_id) REFERENCES gateway_configs(id) ON DELETE CASCADE,
      FOREIGN KEY (node_device_id) REFERENCES sensor_devices(id) ON DELETE SET NULL,
      CHECK (frame_counter >= 0),
      CHECK (rssi IS NULL OR rssi BETWEEN -200 AND 0),
      CHECK (snr IS NULL OR snr BETWEEN -50 AND 50),
      CHECK (status IN (
        'processing', 'accepted', 'rejected', 'replay', 'unknown_node')) )''');
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
      idx_lora_packets_once
      ON lora_packets(gateway_id, node_uid, session_id, frame_counter)
      WHERE status IN ('processing', 'accepted')''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_lora_packets_received
      ON lora_packets(gateway_id, received_at DESC)''');
  }

  Future<void> _createOtaTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS ota_trusted_keys (
      key_id TEXT PRIMARY KEY,
      algorithm TEXT NOT NULL,
      public_key_base64 TEXT NOT NULL,
      valid_from INTEGER NOT NULL,
      revoked_at INTEGER,
      source TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK (algorithm = 'ed25519'),
      CHECK (source = 'app_build'),
      CHECK (revoked_at IS NULL OR revoked_at >= valid_from))''');

    await db.execute('''CREATE TABLE IF NOT EXISTS ota_device_states (
      device_id TEXT PRIMARY KEY,
      current_version TEXT,
      current_build INTEGER NOT NULL DEFAULT 0,
      highest_accepted_build INTEGER NOT NULL DEFAULT 0,
      last_known_good_build INTEGER NOT NULL DEFAULT 0,
      hardware_model TEXT,
      bootloader_version TEXT,
      rollback_supported INTEGER NOT NULL DEFAULT 0,
      last_update_at INTEGER,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id) ON DELETE CASCADE,
      CHECK (current_build >= 0),
      CHECK (highest_accepted_build >= current_build),
      CHECK (last_known_good_build BETWEEN 0 AND highest_accepted_build),
      CHECK (rollback_supported IN (0, 1)))''');

    await db.execute('''CREATE TABLE IF NOT EXISTS ota_updates (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      manifest_id TEXT NOT NULL UNIQUE,
      version TEXT NOT NULL,
      build_number INTEGER NOT NULL,
      firmware_url TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      firmware_sha256 TEXT NOT NULL,
      signature_base64 TEXT NOT NULL,
      key_id TEXT NOT NULL,
      status TEXT NOT NULL,
      verified_at INTEGER,
      requested_at INTEGER,
      node_ack_at INTEGER,
      error_code TEXT,
      manifest_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (build_number > 0),
      CHECK (size_bytes BETWEEN 1 AND 33554432),
      CHECK (status IN (
        'verified', 'requested', 'downloading', 'installing',
        'succeeded', 'failed', 'rejected')),
      CHECK (requested_at IS NULL OR verified_at IS NOT NULL),
      CHECK (node_ack_at IS NULL OR requested_at IS NOT NULL))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_ota_updates_device_created
      ON ota_updates(device_id, created_at DESC)''');
  }

  Future<void> _createAutomationTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS automation_rules (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      name TEXT NOT NULL,
      condition_json TEXT NOT NULL,
      action_type TEXT NOT NULL,
      action_params_json TEXT NOT NULL,
      duration_seconds INTEGER NOT NULL DEFAULT 0,
      cooldown_seconds INTEGER NOT NULL DEFAULT 900,
      max_runs_per_day INTEGER NOT NULL DEFAULT 10,
      revision INTEGER NOT NULL,
      rule_hash TEXT NOT NULL,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL,
      node_ack_at INTEGER,
      node_ack_hash TEXT,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id) ON DELETE CASCADE,
      CHECK (action_type IN ('mist.set', 'fan.set', 'light.set')),
      CHECK (duration_seconds BETWEEN 0 AND 86400),
      CHECK (cooldown_seconds BETWEEN 0 AND 604800),
      CHECK (max_runs_per_day BETWEEN 1 AND 100),
      CHECK (revision >= 1),
      CHECK (is_enabled IN (0, 1)),
      CHECK (status IN ('pending', 'active', 'disabled', 'failed')),
      CHECK (node_ack_at IS NULL OR node_ack_hash IS NOT NULL))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_automation_rules_device_enabled
      ON automation_rules(device_id, is_enabled, name)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS automation_executions (
      id TEXT PRIMARY KEY,
      rule_id TEXT NOT NULL,
      device_id TEXT NOT NULL,
      executed_at INTEGER NOT NULL,
      command_id TEXT,
      observed_values_json TEXT NOT NULL,
      status TEXT NOT NULL,
      error_code TEXT,
      created_at TEXT NOT NULL,
      CHECK (status IN ('acknowledged', 'rejected', 'failed')) )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_automation_executions_rule_date
      ON automation_executions(rule_id, executed_at DESC)''');
  }

  Future<void> _createCycleExportTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS cycle_exports (
      id TEXT PRIMARY KEY,
      plant_id TEXT NOT NULL,
      period_start INTEGER NOT NULL,
      period_end INTEGER NOT NULL,
      schema_version INTEGER NOT NULL,
      content_sha256 TEXT NOT NULL,
      counts_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK (period_end > period_start),
      CHECK (schema_version = 1),
      CHECK (length(content_sha256) = 64))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_cycle_exports_plant_created
      ON cycle_exports(plant_id, created_at DESC)''');
  }

  Future<void> _createCameraTables(Database db) async {
    if (!await _tableExists(db, 'sensor_devices') ||
        !await _tableExists(db, 'cultivation_zones')) {
      return;
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS camera_snapshots (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      zone_id TEXT,
      captured_at INTEGER NOT NULL,
      sha256 TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      photo_path TEXT,
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id)
        ON DELETE CASCADE,
      FOREIGN KEY (zone_id) REFERENCES cultivation_zones(id)
        ON DELETE SET NULL,
      CHECK (captured_at > 0),
      CHECK (size_bytes > 0 AND size_bytes <= 16777216),
      CHECK (length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*'))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_camera_snapshots_device_captured
      ON camera_snapshots(device_id, captured_at DESC)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_camera_snapshots_zone_captured
      ON camera_snapshots(zone_id, captured_at DESC)''');
  }

  Future<void> _createCultivationZonesTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS cultivation_zones (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      width_cm REAL,
      depth_cm REAL,
      height_cm REAL,
      description TEXT,
      target_profile TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');
  }

  Future<void> _createSensorDevicesTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sensor_devices (
      id TEXT PRIMARY KEY,
      uid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      zone_id TEXT,
      base_url TEXT NOT NULL,
      firmware_version TEXT,
      last_seen_at INTEGER,
      last_sync_at INTEGER,
      cloud_device_id TEXT,
      cloud_cursor TEXT,
      cloud_last_sync_at INTEGER,
      cloud_last_error TEXT,
      cloud_last_error_at INTEGER,
      cloud_last_contact_at INTEGER,
      status TEXT NOT NULL DEFAULT 'unknown',
      device_kind TEXT NOT NULL DEFAULT 'sensor',
      transport TEXT NOT NULL DEFAULT 'http',
      model TEXT,
      hardware_version TEXT,
      ble_device_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (zone_id) REFERENCES cultivation_zones(id)
        ON DELETE SET NULL)''');
  }

  Future<void> _createSensorReadingsV9Table(
    Database db, {
    required String table,
  }) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $table (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      zone_id TEXT,
      measured_at INTEGER NOT NULL,
      temperature_c REAL NOT NULL,
      humidity_percent REAL NOT NULL,
      vpd_kpa REAL NOT NULL,
      dew_point_c REAL,
      mist_on INTEGER NOT NULL DEFAULT 0,
      fan_percent REAL,
      light_on INTEGER,
      water_low INTEGER,
      rssi INTEGER,
      remote_event_id TEXT,
      source_sequence INTEGER,
      created_at TEXT NOT NULL,
      FOREIGN KEY (device_id) REFERENCES sensor_devices(id)
        ON DELETE CASCADE,
      FOREIGN KEY (zone_id) REFERENCES cultivation_zones(id)
        ON DELETE SET NULL,
      UNIQUE (device_id, measured_at))''');
  }

  Future<void> _createZonePlacementsTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS zone_placements (
      id TEXT PRIMARY KEY,
      zone_id TEXT NOT NULL,
      plant_id TEXT,
      group_id TEXT,
      entity_name TEXT NOT NULL,
      entered_at INTEGER NOT NULL,
      exited_at INTEGER,
      note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (zone_id) REFERENCES cultivation_zones(id)
        ON DELETE RESTRICT,
      FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE SET NULL,
      FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE SET NULL,
      CHECK (plant_id IS NULL OR group_id IS NULL))''');
  }

  Future<void> _createCultivationIndexes(Database db) async {
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_sensor_devices_zone_id ON sensor_devices(zone_id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_sensor_readings_zone_measured_at
      ON sensor_readings(zone_id, measured_at)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_sensor_readings_device_measured_at_v9
      ON sensor_readings(device_id, measured_at)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS
      idx_zone_placements_zone_entered
      ON zone_placements(zone_id, entered_at)''');
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
      idx_zone_placements_active_plant
      ON zone_placements(plant_id)
      WHERE exited_at IS NULL AND plant_id IS NOT NULL''');
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
      idx_zone_placements_active_group
      ON zone_placements(group_id)
      WHERE exited_at IS NULL AND group_id IS NOT NULL''');
  }

  Future<void> _seedDefaultCultivationZones(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final zones = <Map<String, Object?>>[
      {
        'id': 'zone-collection',
        'name': 'COLLECTION_ORCHIDEES',
        'type': 'collection',
        'width_cm': null,
        'depth_cm': null,
        'height_cm': null,
        'description': 'Collection d’orchidées en pots',
        'target_profile':
            '{"temperatureMin":20,"temperatureMax":28,"humidityMin":50,"humidityMax":75,"vpdMin":0.8,"vpdMax":1.2}',
      },
      {
        'id': 'zone-cutting',
        'name': 'BOUTURES',
        'type': 'cutting',
        'width_cm': null,
        'depth_cm': null,
        'height_cm': null,
        'description': 'Bouturage et enracinement',
        'target_profile':
            '{"temperatureMin":21,"temperatureMax":27,"humidityMin":65,"humidityMax":85,"vpdMin":0.4,"vpdMax":0.8}',
      },
      {
        'id': 'zone-nursery',
        'name': 'PEPINIERE',
        'type': 'nursery',
        'width_cm': null,
        'depth_cm': null,
        'height_cm': null,
        'description': 'Jeunes plantes enracinées et préparation',
        'target_profile':
            '{"temperatureMin":20,"temperatureMax":28,"humidityMin":55,"humidityMax":75,"vpdMin":0.7,"vpdMax":1.2}',
      },
      {
        'id': 'zone-main',
        'name': 'SERRE_TOMATES',
        'type': 'main',
        'width_cm': null,
        'depth_cm': null,
        'height_cm': null,
        'description': 'Cycle principal',
        'target_profile':
            '{"temperatureMin":18,"temperatureMax":29,"humidityMin":40,"humidityMax":70,"vpdMin":0.8,"vpdMax":1.5}',
      },
      {
        'id': 'zone-storage',
        'name': 'CONSERVATION',
        'type': 'storage',
        'width_cm': null,
        'depth_cm': null,
        'height_cm': null,
        'description': 'Suivi des semences conservées',
        'target_profile':
            '{"temperatureMin":16,"temperatureMax":22,"humidityMin":55,"humidityMax":65,"vpdMin":0.3,"vpdMax":1.2}',
      },
    ];
    for (final zone in zones) {
      final existing = await db.query(
        'cultivation_zones',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [zone['id']],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert(
          'cultivation_zones',
          {...zone, 'created_at': now, 'updated_at': now},
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    }
  }

  Future<void> _migrateLegacyDevices(Database db) async {
    if (!await _tableExists(db, 'devices')) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final legacyDevices = await db.rawQuery('''SELECT devices.*,
      groups.name AS group_name
      FROM devices
      LEFT JOIN groups ON groups.id = devices.zone_id''');
    for (final device in legacyDevices) {
      final legacyGroupId = device['zone_id'] as String?;
      String? migratedZoneId;
      if (legacyGroupId != null) {
        migratedZoneId = 'legacy-group-$legacyGroupId';
        final existingZone = await db.query(
          'cultivation_zones',
          columns: const ['id'],
          where: 'id = ?',
          whereArgs: [migratedZoneId],
          limit: 1,
        );
        if (existingZone.isEmpty) {
          await db.insert(
            'cultivation_zones',
            {
              'id': migratedZoneId,
              'name': device['group_name'] as String? ?? 'Zone importée',
              'type': 'custom',
              'description': 'Zone créée depuis une association groupe v8',
              'target_profile': '{}',
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }
      final ipAddress = device['ip_address'] as String? ?? '127.0.0.1';
      final existing = await db.query(
        'sensor_devices',
        where: 'id = ?',
        whereArgs: [device['id']],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert(
          'sensor_devices',
          {
            'id': device['id'],
            'uid': device['id'],
            'name': device['name'],
            'zone_id': migratedZoneId,
            'base_url': 'http://$ipAddress',
            'last_seen_at': device['last_seen_at'],
            'last_sync_at': device['last_seen_at'],
            'status': 'unknown',
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else if (existing.single['uid'] != device['id']) {
        throw StateError(
          'Migration v9 interrompue: identifiant capteur incohérent',
        );
      }
    }
  }

  Future<void> _migrateLegacySensorReadings(Database db) async {
    if (!await _tableExists(db, 'sensor_readings')) {
      await _createSensorReadingsV9Table(db, table: 'sensor_readings');
      return;
    }
    final columns = await db.rawQuery('PRAGMA table_info(sensor_readings)');
    if (columns.any((column) => column['name'] == 'temperature_c')) {
      await db.execute('DROP TABLE IF EXISTS sensor_readings_v9');
      return;
    }

    await db.execute('DROP TABLE IF EXISTS sensor_readings_v9');
    await _createSensorReadingsV9Table(db, table: 'sensor_readings_v9');
    final readings = await db.query('sensor_readings');
    final now = DateTime.now().toUtc().toIso8601String();
    for (final reading in readings) {
      final deviceId = reading['device_id'] as String;
      var devices = await db.query(
        'sensor_devices',
        where: 'id = ?',
        whereArgs: [deviceId],
        limit: 1,
      );
      if (devices.isEmpty) {
        await db.insert(
          'sensor_devices',
          {
            'id': deviceId,
            'uid': deviceId,
            'name': 'Capteur importé',
            'base_url': 'http://127.0.0.1',
            'status': 'unknown',
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        devices = await db.query(
          'sensor_devices',
          where: 'id = ?',
          whereArgs: [deviceId],
          limit: 1,
        );
      }
      await db.insert(
        'sensor_readings_v9',
        {
          'id': reading['id'],
          'device_id': deviceId,
          'zone_id': devices.first['zone_id'],
          'measured_at': reading['measured_at'],
          'temperature_c': reading['temperature'],
          'humidity_percent': reading['humidity'],
          'vpd_kpa': reading['vpd'],
          'mist_on': reading['mist_on'],
          'fan_percent': reading['fan_percent'],
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
    await _assertSameRowCount(db, 'sensor_readings', 'sensor_readings_v9');
    await _assertForeignKeys(db, 'sensor_readings_v9');
    await db.execute('DROP TABLE sensor_readings');
    await db
        .execute('ALTER TABLE sensor_readings_v9 RENAME TO sensor_readings');
  }

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', table],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> createSchemaForTesting(Database db) =>
      _onCreate(db, currentVersion);

  Future<void> upgradeSchemaForTesting(
    Database db,
    int oldVersion,
  ) =>
      _onUpgrade(db, oldVersion, currentVersion);

  Future<void> _createActionPhotosTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS action_photos (
      id TEXT PRIMARY KEY, action_id TEXT NOT NULL, plant_id TEXT NOT NULL,
      photo_path TEXT NOT NULL, created_at TEXT NOT NULL,
      FOREIGN KEY (action_id) REFERENCES actions(id) ON DELETE CASCADE,
      FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE)''');
  }

  Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $definition');
  }

  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> queryAll(String table) async {
    final db = await database;
    return await db.query(table, orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> queryWhere(
      String table, String where, List<dynamic> whereArgs,
      {String? orderBy}) async {
    final db = await database;
    return await db.query(table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy ?? 'created_at DESC');
  }

  Future<Map<String, dynamic>?> queryById(String table, String id) async {
    final db = await database;
    final r = await db.query(table, where: 'id = ?', whereArgs: [id]);
    return r.isNotEmpty ? r.first : null;
  }

  Future<int> update(String table, Map<String, dynamic> data, String id) async {
    final db = await database;
    return await db.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String table, String id) async {
    final db = await database;
    return await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}
