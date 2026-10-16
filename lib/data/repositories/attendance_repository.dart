import 'package:facerecognition/core/logging/app_logger.dart';
import 'package:facerecognition/data/local/attendance_local_datasource.dart';
import 'package:facerecognition/data/models/attendance_record.dart';
import 'package:facerecognition/data/remote/face_sync_port.dart';

class AttendanceRepository {
  AttendanceRepository({
    required AttendanceLocalDatasource localDatasource,
    required FaceSyncPort faceSyncPort,
  })  : _local = localDatasource,
        _faceSyncPort = faceSyncPort;

  final AttendanceLocalDatasource _local;
  final FaceSyncPort _faceSyncPort;

  Future<List<AttendanceRecord>> getHistory({int limit = 100}) {
    return _local.getAll(limit: limit);
  }

  Future<AttendanceRecord?> getLatestMatched() => _local.getLatestMatched();

  Future<AttendanceType> nextPunchType() async {
    final latest = await getLatestMatched();
    if (latest == null || latest.type == AttendanceType.clockOut) {
      return AttendanceType.clockIn;
    }
    return AttendanceType.clockOut;
  }

  Future<AttendanceRecord> recordPunch({
    required AttendanceType type,
    required double similarity,
    required bool matched,
    double? distance,
    List<double>? embedding,
  }) async {
    final record = AttendanceRecord(
      type: type,
      timestamp: DateTime.now(),
      similarity: similarity,
      matched: matched,
      distance: distance,
      embedding: embedding,
    );

    final id = await _local.insert(record);
    final saved = AttendanceRecord(
      id: id,
      type: record.type,
      timestamp: record.timestamp,
      similarity: record.similarity,
      matched: record.matched,
      distance: record.distance,
      embedding: record.embedding,
    );

    AppLogger.punch(
      'type=${type.label} matched=$matched similarity='
      '${similarity.toStringAsFixed(3)}'
      '${distance != null ? ' distance=${distance.toStringAsFixed(3)}' : ''} '
      'at=${record.timestamp.toIso8601String()}',
    );

    try {
      await _faceSyncPort.uploadAttendance(saved);
    } catch (e, st) {
      AppLogger.error('attendance sync failed', e, st);
    }

    return saved;
  }
}
