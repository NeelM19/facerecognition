import 'package:facerecognition/data/repositories/profile_repository.dart';
import 'package:facerecognition/routes/app_routes.dart';
import 'package:get/get.dart';

class AttendanceGateController extends GetxController {
  AttendanceGateController(this._profileRepository);

  final ProfileRepository _profileRepository;

  final statusMessage = 'Checking enrollment…'.obs;

  @override
  void onReady() {
    super.onReady();
    _route();
  }

  Future<void> _route() async {
    try {
      final enrolled = await _profileRepository.isEnrolled();
      if (enrolled) {
        statusMessage.value = 'Face found — opening punch…';
        Get.offNamed(AppRoutes.punch);
      } else {
        statusMessage.value = 'No face enrolled — opening enrollment…';
        Get.offNamed(AppRoutes.enroll);
      }
    } catch (e) {
      statusMessage.value = 'Unable to check enrollment';
      Get.snackbar('Error', e.toString());
    }
  }
}
