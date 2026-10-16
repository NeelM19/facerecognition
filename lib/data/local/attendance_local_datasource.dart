import 'package:facerecognition/data/local/app_database.dart';
import 'package:facerecognition/data/models/attendance_record.dart';

class AttendanceLocalDatasource {
  AttendanceLocalDatasource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<int> insert(AttendanceRecord record) async {
    final db = await _appDatabase.database;
    return db.insert('attendance_records', record.toJson());
  }

  Future<List<AttendanceRecord>> getAll({int limit = 100}) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'attendance_records',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(AttendanceRecord.fromJson).toList();
  }

  Future<AttendanceRecord?> getLatestMatched() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'attendance_records',
      where: 'matched = ?',
      whereArgs: [1],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceRecord.fromJson(rows.first);
  }
}
