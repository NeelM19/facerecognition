import 'package:facerecognition/data/repositories/profile_repository.dart';
import 'package:facerecognition/modules/settings/controllers/settings_controller.dart';
import 'package:get/get.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => SettingsController(Get.find<ProfileRepository>()),
      fenix: true,
    );
  }
}
