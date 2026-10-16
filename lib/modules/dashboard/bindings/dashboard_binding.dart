import 'package:facerecognition/data/repositories/profile_repository.dart';
import 'package:facerecognition/modules/dashboard/controllers/dashboard_controller.dart';
import 'package:get/get.dart';

class DashboardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DashboardController(Get.find<ProfileRepository>()),
    );
  }
}
