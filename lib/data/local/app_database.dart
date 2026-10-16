import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, AppConstants.dbName);

    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE employee_profile (
            id INTEGER PRIMARY KEY,
            display_name TEXT NOT NULL,
            photo_path TEXT,
            embedding TEXT,
            masked_embedding TEXT,
            appearance_embeddings TEXT,
            updated_at TEXT,
            remote_synced_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE attendance_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            similarity REAL NOT NULL,
            matched INTEGER NOT NULL,
            remote_synced_at TEXT
          )
        ''');

        await _createMatchSamples(db);

        await db.insert('employee_profile', {
          'id': 1,
          'display_name': AppConstants.defaultDisplayName,
          'photo_path': null,
          'embedding': null,
          'masked_embedding': null,
          'appearance_embeddings': null,
          'updated_at': null,
          'remote_synced_at': null,
        });
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE employee_profile ADD COLUMN masked_embedding TEXT',
          );
        }
        if (oldVersion < 3) {
          await _createMatchSamples(db);
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE employee_profile ADD COLUMN appearance_embeddings TEXT',
          );
        }
      },
    );
  }

  Future<void> _createMatchSamples(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS match_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        similarity REAL NOT NULL,
        distance REAL NOT NULL,
        matched INTEGER NOT NULL,
        face_score REAL NOT NULL,
        template_kind TEXT,
        label TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
