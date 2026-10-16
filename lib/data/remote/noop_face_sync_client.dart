import 'dart:convert';
import 'dart:io';

import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:facerecognition/core/logging/app_logger.dart';
import 'package:facerecognition/data/models/attendance_record.dart';
import 'package:facerecognition/data/models/face_sync_payload.dart';
import 'package:facerecognition/data/remote/face_sync_port.dart';

/// v1 implementation — no network calls. Builds and prints full API request
/// bodies so future HttpFaceSyncClient wiring has a clear contract.
class NoopFaceSyncClient implements FaceSyncPort {
  static final _prettyJson = JsonEncoder.withIndent('  ');

  @override
  Future<void> uploadFace(FaceSyncPayload payload) async {
    final body = await _buildEnrollBody(payload);
    _printRequestBody(
      method: 'POST',
      path: '/api/faces/enroll',
      body: body,
    );
  }

  @override
  Future<void> uploadAttendance(AttendanceRecord record) async {
    final body = record.toApiRequestBody(
      employeeId: AppConstants.defaultEmployeeId,
    );
    _printRequestBody(
      method: 'POST',
      path: '/api/attendance/punch',
      body: body,
    );
  }

  Future<Map<String, dynamic>> _buildEnrollBody(FaceSyncPayload payload) async {
    final body = <String, dynamic>{
      'employee_id':
          payload.employeeId ?? AppConstants.defaultEmployeeId,
      'display_name': payload.displayName,
      'embedding': payload.embedding,
      if (payload.maskedEmbedding != null)
        'masked_embedding': payload.maskedEmbedding,
      'enrolled_at': payload.updatedAt.toIso8601String(),
      if (payload.deviceId != null) 'device_id': payload.deviceId,
    };

    final photoBase64 = await _readPhotoBase64(payload.photoFilePath);
    if (photoBase64 != null) {
      body['photo_base64'] = photoBase64;
    } else {
      body['photo_file_path'] = payload.photoFilePath;
      body['photo_base64_note'] =
          'photo file missing or unreadable; photo_base64 omitted';
    }

    return body;
  }

  Future<String?> _readPhotoBase64(String path) async {
    if (path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) {
        AppLogger.sync('enroll photo missing at path=$path');
        return null;
      }
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e, st) {
      AppLogger.error('failed to base64-encode enroll photo', e, st);
      return null;
    }
  }

  void _printRequestBody({
    required String method,
    required String path,
    required Map<String, dynamic> body,
  }) {
    final encoded = _prettyJson.convert(body);
    AppLogger.sync(
      'no API configured — would $method $path '
      '(printing full request body below)',
    );
    // Use print() so the full embedding / base64 is not truncated in console.
    print('========== FACE SYNC REQUEST $method $path ==========');
    print(encoded);
    print('========== END FACE SYNC REQUEST ==========');
  }
}
