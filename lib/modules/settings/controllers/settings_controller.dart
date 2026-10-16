import 'dart:io';
import 'dart:typed_data';

import 'package:facerecognition/data/models/employee_profile.dart';
import 'package:facerecognition/data/repositories/profile_repository.dart';
import 'package:facerecognition/routes/app_routes.dart';
import 'package:flutter/painting.dart';
import 'package:get/get.dart';

class SettingsController extends GetxController {
  SettingsController(this._profileRepository);

  final ProfileRepository _profileRepository;

  final isLoading = true.obs;
  final profile = Rxn<EmployeeProfile>();

  /// Decoded enrolled photo bytes for [Image.memory] (avoids FileImage cache).
  final photoBytes = Rxn<Uint8List>();

  /// Bumps whenever the displayed photo must be force-rebuilt.
  final photoVersion = 0.obs;

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) isLoading.value = true;
    try {
      final current = await _profileRepository.getProfile();
      await _applyProfile(current);
    } finally {
      if (showLoading) isLoading.value = false;
    }
  }

  /// Applies [current] to Rx state and loads photo bytes for display.
  Future<void> _applyProfile(EmployeeProfile current) async {
    final previousPath = profile.value?.photoPath;
    final path = current.photoPath;

    if (previousPath != null && previousPath != path) {
      await _evictPhotoCache(previousPath);
    }
    if (path != null) {
      await _evictPhotoCache(path);
    }

    Uint8List? bytes;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        bytes = await file.readAsBytes();
      }
    }

    photoVersion.value++;
    photoBytes.value = bytes;
    profile.value = current;
  }

  Future<void> _evictPhotoCache(String path) async {
    await FileImage(File(path)).evict();
  }

  Future<void> updateFace() async {
    final result = await Get.toNamed(
      AppRoutes.enroll,
      arguments: {'fromSettings': true},
    );

    // Prefer the profile returned by enroll (authoritative, no race with DB).
    if (result is EmployeeProfile) {
      await _applyProfile(result);
      isLoading.value = false;
      Get.snackbar(
        'Success',
        'Face updated',
        snackPosition: SnackPosition.BOTTOM,
      );
      // Quiet DB re-read keeps Rx aligned without blanking the photo Obx tree.
      await load(showLoading: false);
      return;
    }

    // Cancelled / system back — still refresh in case enrollment finished.
    await load(showLoading: false);
  }

  void openHistory() => Get.toNamed(AppRoutes.history);
}
