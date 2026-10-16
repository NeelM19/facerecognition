import 'package:facerecognition/data/local/app_database.dart';
import 'package:facerecognition/data/models/employee_profile.dart';
import 'package:sqflite/sqflite.dart';

class ProfileLocalDatasource {
  ProfileLocalDatasource(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<EmployeeProfile> getProfile() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'employee_profile',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const EmployeeProfile(displayName: 'Me');
    }
    return EmployeeProfile.fromJson(rows.first);
  }

  Future<void> upsertProfile(EmployeeProfile profile) async {
    final db = await _appDatabase.database;
    await db.insert(
      'employee_profile',
      profile.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
