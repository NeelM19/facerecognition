import 'package:facerecognition/data/repositories/attendance_repository.dart';
import 'package:facerecognition/data/repositories/profile_repository.dart';
import 'package:facerecognition/modules/attendance/controllers/attendance_gate_controller.dart';
import 'package:facerecognition/modules/attendance/controllers/enroll_controller.dart';
import 'package:facerecognition/modules/attendance/controllers/history_controller.dart';
import 'package:facerecognition/modules/attendance/controllers/punch_controller.dart';
import 'package:facerecognition/services/face_recognition_service.dart';
import 'package:get/get.dart';

class AttendanceGateBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => AttendanceGateController(Get.find<ProfileRepository>()),
    );
  }
}

class EnrollBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => EnrollController(
        profileRepository: Get.find(),
        faceRecognitionService: Get.find<FaceRecognitionService>(),
      ),
    );
  }
}

class PunchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => PunchController(
        profileRepository: Get.find(),
        attendanceRepository: Get.find(),
        faceRecognitionService: Get.find<FaceRecognitionService>(),
      ),
    );
  }
}

class HistoryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => HistoryController(Get.find<AttendanceRepository>()),
    );
  }
}
