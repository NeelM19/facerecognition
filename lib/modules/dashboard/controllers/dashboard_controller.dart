import 'package:facerecognition/data/models/employee_profile.dart';
import 'package:facerecognition/data/repositories/profile_repository.dart';
import 'package:facerecognition/routes/app_routes.dart';
import 'package:get/get.dart';

class DashboardController extends GetxController {
  DashboardController(this._profileRepository);

  final ProfileRepository _profileRepository;

  final isLoading = true.obs;
  final isEnrolled = false.obs;
  final profile = Rxn<EmployeeProfile>();

  @override
  void onReady() {
    super.onReady();
    refreshStatus();
  }

  Future<void> refreshStatus() async {
    isLoading.value = true;
    try {
      final current = await _profileRepository.getProfile();
      profile.value = current;
      isEnrolled.value = current.isEnrolled;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> openAttendance() async {
    await Get.toNamed(AppRoutes.attendanceGate);
    await refreshStatus();
  }

  Future<void> openSettings() async {
    await Get.toNamed(AppRoutes.settings);
    await refreshStatus();
  }
}
