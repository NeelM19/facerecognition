import 'package:facerecognition/core/config/match_threshold_config.dart';
import 'package:facerecognition/core/network/api_client.dart';
import 'package:facerecognition/data/local/app_database.dart';
import 'package:facerecognition/data/local/attendance_local_datasource.dart';
import 'package:facerecognition/data/local/profile_local_datasource.dart';
import 'package:facerecognition/data/remote/face_sync_port.dart';
import 'package:facerecognition/data/remote/noop_face_sync_client.dart';
import 'package:facerecognition/data/repositories/attendance_repository.dart';
import 'package:facerecognition/data/repositories/profile_repository.dart';
import 'package:facerecognition/services/face_recognition_service.dart';
import 'package:facerecognition/services/image_quality_service.dart';
import 'package:get/get.dart';

/// Sync GetX registration. Async services are created in [main] and passed in
/// so [GetMaterialApp.initialBinding] does not wipe them.
class InitialBinding extends Bindings {
  InitialBinding({
    required this.faceRecognitionService,
    required this.thresholdStore,
    required this.imageQualityService,
  });

  final FaceRecognitionService faceRecognitionService;
  final MatchThresholdStore thresholdStore;
  final ImageQualityService imageQualityService;

  @override
  void dependencies() {
    Get.put(ApiClient(), permanent: true);
    Get.put<FaceSyncPort>(NoopFaceSyncClient(), permanent: true);
    Get.put(AppDatabase(), permanent: true);
    Get.put(ProfileLocalDatasource(Get.find()), permanent: true);
    Get.put(AttendanceLocalDatasource(Get.find()), permanent: true);
    Get.put(imageQualityService, permanent: true);
    Get.put(thresholdStore, permanent: true);
    // Face service before ProfileRepository (gallery merge uses it).
    Get.put<FaceRecognitionService>(faceRecognitionService, permanent: true);
    Get.put(
      ProfileRepository(
        localDatasource: Get.find(),
        faceSyncPort: Get.find(),
        faceRecognitionService: faceRecognitionService,
      ),
      permanent: true,
    );
    Get.put(
      AttendanceRepository(
        localDatasource: Get.find(),
        faceSyncPort: Get.find(),
      ),
      permanent: true,
    );
  }
}
