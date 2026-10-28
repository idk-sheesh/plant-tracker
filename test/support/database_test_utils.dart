import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openMemoryDatabase() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys = ON');
  return db;
}

Future<void> createLegacySchema(
  Database db,
  int version, {
  bool withData = true,
  bool allowDuplicateSensorTimestamp = false,
}) async {
  if (version < 1 || version > 8) throw ArgumentError.value(version);
  await db.execute('''CREATE TABLE groups (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
    color INTEGER NOT NULL DEFAULT 4280391411, created_at TEXT NOT NULL
    ${version >= 2 ? ', parent_group_id TEXT' : ''})''');
  await db.execute('''CREATE TABLE plants (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, variety TEXT,
    potting_date TEXT NOT NULL, culture_type TEXT NOT NULL, pot_size TEXT,
    photo_path TEXT, notes TEXT, group_id TEXT, qr_code TEXT NOT NULL,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    ${version >= 3 ? ", location TEXT NOT NULL DEFAULT 'indoor', container_type TEXT NOT NULL DEFAULT 'pot'" : ''}
    ${version >= 6 ? ", origin TEXT NOT NULL DEFAULT 'unknown', is_pinned INTEGER NOT NULL DEFAULT 0, is_harvested INTEGER NOT NULL DEFAULT 0" : ''},
    FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE SET NULL)''');
  await db.execute('''CREATE TABLE actions (
    id TEXT PRIMARY KEY, plant_id TEXT NOT NULL, action_type TEXT NOT NULL,
    timestamp TEXT NOT NULL, quantity REAL, quantity_unit TEXT, ph REAL,
    tds REAL, product_used TEXT, pruning_type TEXT, notes TEXT,
    created_at TEXT NOT NULL
    ${version >= 2 ? ', ph_na INTEGER NOT NULL DEFAULT 0, tds_na INTEGER NOT NULL DEFAULT 0, parent_plant_id TEXT, cutting_notes TEXT' : ''}
    ${version >= 4 ? ', is_watering_combined INTEGER NOT NULL DEFAULT 0' : ''}
    ${version >= 6 ? ', harvest_weight_stored REAL, harvest_weight_waste REAL' : ''}
    ${version >= 7 ? ", status TEXT NOT NULL DEFAULT 'done', completed_at TEXT" : ''},
    FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE)''');
  if (version >= 4) {
    await db.execute('''CREATE TABLE action_photos (
      id TEXT PRIMARY KEY, action_id TEXT NOT NULL, plant_id TEXT NOT NULL,
      photo_path TEXT NOT NULL, created_at TEXT NOT NULL,
      FOREIGN KEY (action_id) REFERENCES actions(id) ON DELETE CASCADE)''');
  }
  if (version >= 8) {
    await db.execute('''CREATE TABLE devices (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, zone_id TEXT,
      ip_address TEXT NOT NULL, last_seen_at INTEGER,
      FOREIGN KEY (zone_id) REFERENCES groups(id) ON DELETE SET NULL)''');
    await db.execute('''CREATE TABLE sensor_readings (
      id TEXT PRIMARY KEY, device_id TEXT NOT NULL, measured_at INTEGER NOT NULL,
      temperature REAL NOT NULL, humidity REAL NOT NULL, vpd REAL NOT NULL,
      mist_on INTEGER NOT NULL DEFAULT 0, fan_percent REAL,
      FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
      ${allowDuplicateSensorTimestamp ? '' : ', UNIQUE (device_id, measured_at)'})''');
  }
  if (!withData) return;

  await db.insert('groups', {
    'id': 'group-parent',
    'name': 'Parent',
    'color': 1,
    'created_at': '2026-01-01T00:00:00Z',
  });
  await db.insert('groups', {
    'id': 'group-child',
    'name': 'Enfant',
    'color': 2,
    'created_at': '2026-01-02T00:00:00Z',
    if (version >= 2) 'parent_group_id': 'group-parent',
  });
  await db.insert('plants', {
    'id': 'plant-1',
    'name': 'Plante migration',
    'potting_date': '2026-01-01T00:00:00Z',
    'culture_type': 'indoor',
    'group_id': 'group-child',
    'qr_code': 'plant:plant-1',
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  });
  await db.insert('actions', {
    'id': 'action-1',
    'plant_id': 'plant-1',
    'action_type': 'recolte',
    'timestamp': '2026-02-01T00:00:00Z',
    'created_at': '2026-02-01T00:00:00Z',
    if (version >= 6) 'harvest_weight_stored': 42.5,
    if (version >= 6) 'harvest_weight_waste': 8.0,
  });
  if (version >= 4) {
    await db.insert('action_photos', {
      'id': 'photo-1',
      'action_id': 'action-1',
      'plant_id': 'plant-1',
      'photo_path': '/legacy/photo.jpg',
      'created_at': '2026-02-01T00:00:00Z',
    });
  }
  if (version >= 8) {
    await db.insert('devices', {
      'id': 'sensor-1',
      'name': 'Capteur v8',
      'zone_id': 'group-parent',
      'ip_address': '192.168.1.20',
    });
    await db.insert('sensor_readings', {
      'id': 'reading-1',
      'device_id': 'sensor-1',
      'measured_at': 1783947600,
      'temperature': 24.0,
      'humidity': 55.0,
      'vpd': 1.2,
    });
  }
}
