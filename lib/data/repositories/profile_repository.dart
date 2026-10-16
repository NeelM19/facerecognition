import 'dart:io';

import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:facerecognition/core/logging/app_logger.dart';
import 'package:facerecognition/data/local/profile_local_datasource.dart';
import 'package:facerecognition/data/models/employee_profile.dart';
import 'package:facerecognition/data/models/face_sync_payload.dart';
import 'package:facerecognition/data/remote/face_sync_port.dart';
import 'package:facerecognition/services/face_recognition_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProfileRepository {
  ProfileRepository({
    required ProfileLocalDatasource localDatasource,
    required FaceSyncPort faceSyncPort,
    FaceRecognitionService? faceRecognitionService,
  })  : _local = localDatasource,
        _faceSyncPort = faceSyncPort,
        _faceService = faceRecognitionService;

  final ProfileLocalDatasource _local;
  final FaceSyncPort _faceSyncPort;
  final FaceRecognitionService? _faceService;

  Future<EmployeeProfile> getProfile() => _local.getProfile();

  Future<bool> isEnrolled() async {
    final profile = await getProfile();
    return profile.isEnrolled;
  }

  /// Saves clear (+ optional masked) templates and appearance gallery, then syncs.
  Future<EmployeeProfile> saveEnrollment({
    required List<double> embedding,
    List<double>? maskedEmbedding,
    List<List<double>> appearanceEmbeddings = const [],
    required List<int> photoBytes,
    String displayName = AppConstants.defaultDisplayName,
    bool isUpdate = false,
  }) async {
    final previous = await getProfile();
    final docs = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final photoPath = p.join(
      docs.path,
      '${AppConstants.enrolledPhotoFilePrefix}${now.millisecondsSinceEpoch}.jpg',
    );
    final file = File(photoPath);
    await file.writeAsBytes(photoBytes, flush: true);

    final hasMask = maskedEmbedding != null && maskedEmbedding.isNotEmpty;
    final profile = EmployeeProfile(
      displayName: displayName,
      photoPath: photoPath,
      embedding: embedding,
      maskedEmbedding: hasMask ? maskedEmbedding : null,
      appearanceEmbeddings: appearanceEmbeddings,
      updatedAt: now,
    );

    await _local.upsertProfile(profile);
    await _deletePhotoIfExists(previous.photoPath, keepPath: photoPath);
    await _deletePhotoIfExists(
      p.join(docs.path, AppConstants.enrolledPhotoFileName),
      keepPath: photoPath,
    );

    if (isUpdate) {
      AppLogger.update(
        'face re-enrolled clear'
        '${hasMask ? '+masked' : '-only'} '
        'appearance=${appearanceEmbeddings.length} '
        'at=${now.toIso8601String()}',
      );
    } else {
      AppLogger.enroll(
        'saved clearDim=${embedding.length} '
        'masked=${hasMask ? maskedEmbedding.length : 0} '
        'appearance=${appearanceEmbeddings.length} path=$photoPath '
        'at=${now.toIso8601String()}',
      );
    }

    try {
      await _faceSyncPort.uploadFace(
        FaceSyncPayload(
          employeeId: AppConstants.defaultEmployeeId,
          displayName: displayName,
          embedding: embedding,
          maskedEmbedding: hasMask ? maskedEmbedding : null,
          photoFilePath: photoPath,
          updatedAt: now,
        ),
      );
    } catch (e, st) {
      AppLogger.error('face sync failed', e, st);
    }

    return profile;
  }

  /// Adds or refreshes an appearance vector after a high-confidence punch.
  Future<EmployeeProfile> upsertAppearanceEmbedding(
    List<double> liveEmbedding,
  ) async {
    final current = await getProfile();
    if (!current.isEnrolled || current.embedding == null) return current;

    final face = _faceService;
    final nextGallery = face == null
        ? _appendCapped(current.appearanceEmbeddings, liveEmbedding)
        : face.upsertAppearanceGallery(
            gallery: current.appearanceEmbeddings,
            candidate: liveEmbedding,
            primary: current.embedding,
          );

    final updated = current.copyWith(
      appearanceEmbeddings: nextGallery,
      updatedAt: DateTime.now(),
    );
    await _local.upsertProfile(updated);
    AppLogger.update(
      'appearance gallery size=${nextGallery.length}',
    );
    return updated;
  }

  List<List<double>> _appendCapped(
    List<List<double>> gallery,
    List<double> live,
  ) {
    final next = [...gallery, live];
    if (next.length <= AppConstants.appearanceGalleryMax) return next;
    return next.sublist(next.length - AppConstants.appearanceGalleryMax);
  }

  Future<void> _deletePhotoIfExists(
    String? path, {
    required String keepPath,
  }) async {
    if (path == null || path.isEmpty || path == keepPath) return;
    try {
      final old = File(path);
      if (await old.exists()) {
        await old.delete();
      }
    } catch (e, st) {
      AppLogger.error('failed to delete old enrolled photo', e, st);
    }
  }
}
