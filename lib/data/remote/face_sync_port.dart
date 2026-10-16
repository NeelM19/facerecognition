import 'package:facerecognition/data/models/attendance_record.dart';
import 'package:facerecognition/data/models/face_sync_payload.dart';

/// Contract for uploading face / attendance data to project storage later.
abstract class FaceSyncPort {
  Future<void> uploadFace(FaceSyncPayload payload);

  Future<void> uploadAttendance(AttendanceRecord record);
}
