import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:facerecognition/core/logging/app_logger.dart';
import 'package:facerecognition/data/repositories/profile_repository.dart';
import 'package:facerecognition/routes/app_routes.dart';
import 'package:facerecognition/services/face_recognition_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

/// Clear multi-frame enrollment, then optional masked template.
class EnrollController extends GetxController {
  EnrollController({
    required ProfileRepository profileRepository,
    required FaceRecognitionService faceRecognitionService,
  })  : _profileRepository = profileRepository,
        _faceService = faceRecognitionService;

  final ProfileRepository _profileRepository;
  final FaceRecognitionService _faceService;

  final isCameraReady = false.obs;
  final isProcessing = false.obs;
  final isCapturing = false.obs;
  final statusMessage = 'Face the camera without a mask'.obs;
  final permissionDenied = false.obs;

  /// 0 = clear template, 1 = masked template (only if user opts in).
  final enrollStep = 0.obs;

  /// Clear frames captured so far (1..[AppConstants.clearEnrollFrameCount]).
  final clearFrameIndex = 0.obs;

  CameraController? cameraController;

  late final bool fromSettings;

  List<double>? _clearEmbedding;
  Uint8List? _clearPhotoBytes;
  final List<List<double>> _clearFrameEmbeddings = [];

  @override
  void onInit() {
    super.onInit();
    fromSettings =
        Get.arguments is Map && (Get.arguments as Map)['fromSettings'] == true;
  }

  @override
  void onReady() {
    super.onReady();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      permissionDenied.value = true;
      statusMessage.value = 'Camera permission is required';
      return;
    }

    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      cameraController = controller;
      isCameraReady.value = true;
      statusMessage.value =
          'No mask — hold still; we capture '
          '${AppConstants.clearEnrollFrameCount} frames';
    } catch (e, st) {
      AppLogger.error('Camera init failed', e, st);
      statusMessage.value = 'Unable to start camera';
      Get.snackbar('Camera error', e.toString());
    }
  }

  Future<void> captureAndEnroll() async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (isProcessing.value) return;

    isProcessing.value = true;
    try {
      if (enrollStep.value == 0) {
        await _captureClearFrames(controller);
      } else {
        await _captureMaskedAndSave(controller);
      }
    } catch (e, st) {
      AppLogger.error('Enrollment failed', e, st);
      statusMessage.value = e.toString().replaceFirst('Bad state: ', '');
      Get.snackbar('Enrollment failed', statusMessage.value);
    } finally {
      isCapturing.value = false;
      isProcessing.value = false;
    }
  }

  Future<void> _captureClearFrames(CameraController controller) async {
    _clearFrameEmbeddings.clear();
    _clearEmbedding = null;
    _clearPhotoBytes = null;
    clearFrameIndex.value = 0;

    final frameCount = AppConstants.clearEnrollFrameCount;
    for (var i = 0; i < frameCount; i++) {
      clearFrameIndex.value = i + 1;
      statusMessage.value = 'Capturing clear face ${i + 1}/$frameCount…';
      await _shutterCapture();
      final file = await controller.takePicture();
      isCapturing.value = false;
      final bytes = await File(file.path).readAsBytes();

      final result = await _faceService.enrollFromBytes(
        bytes,
        templateKind: FaceTemplateKind.clear,
      );
      _clearFrameEmbeddings.add(result.embedding);
      if (i == 0) {
        _clearEmbedding = result.embedding;
        _clearPhotoBytes = result.photoBytes;
      }
      if (i < frameCount - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }

    final primary = _clearEmbedding;
    final photo = _clearPhotoBytes;
    if (primary == null || photo == null) {
      throw StateError('Clear-face capture failed. Try again.');
    }

    final wantMask = await _askForMaskedEnrollment();
    if (wantMask == true) {
      enrollStep.value = 1;
      statusMessage.value =
          'Put on your mask, keep eyes visible, then capture';
      Get.snackbar(
        'Clear face saved',
        'Optional: capture once with your mask on',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    await _finishEnrollment(
      clearEmbedding: primary,
      clearPhoto: photo,
      maskedEmbedding: null,
    );
  }

  Future<void> _captureMaskedAndSave(CameraController controller) async {
    final clearEmbedding = _clearEmbedding;
    final clearPhoto = _clearPhotoBytes;
    if (clearEmbedding == null || clearPhoto == null) {
      throw StateError('Clear-face step missing. Restart enrollment.');
    }

    statusMessage.value = 'Capturing masked face…';
    clearFrameIndex.value = AppConstants.clearEnrollFrameCount;
    await _shutterCapture();
    final file = await controller.takePicture();
    isCapturing.value = false;
    final bytes = await File(file.path).readAsBytes();
    final result = await _faceService.enrollFromBytes(
      bytes,
      templateKind: FaceTemplateKind.masked,
    );

    await _finishEnrollment(
      clearEmbedding: clearEmbedding,
      clearPhoto: clearPhoto,
      maskedEmbedding: result.embedding,
    );
  }

  Future<void> _shutterCapture() async {
    isCapturing.value = true;
    // Let the flash/shutter animation paint before takePicture freezes preview.
    await Future<void>.delayed(const Duration(milliseconds: 90));
  }

  Future<bool?> _askForMaskedEnrollment() {
    return Get.dialog<bool>(
      AlertDialog(
        title: const Text('Also enroll with mask?'),
        content: const Text(
          'Optional. If you sometimes punch with a face mask, '
          'capture a masked photo now. Otherwise save clear face only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('No — clear only'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Yes — add mask'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _finishEnrollment({
    required List<double> clearEmbedding,
    required Uint8List clearPhoto,
    required List<double>? maskedEmbedding,
  }) async {
    final appearance = _faceService.appearanceFromEnrollFrames(
      primary: clearEmbedding,
      frames: _clearFrameEmbeddings,
    );

    final hasMask = maskedEmbedding != null && maskedEmbedding.isNotEmpty;
    statusMessage.value = hasMask
        ? 'Saving clear + masked models…'
        : 'Saving clear face…';

    final saved = await _profileRepository.saveEnrollment(
      embedding: clearEmbedding,
      maskedEmbedding: maskedEmbedding,
      appearanceEmbeddings: appearance,
      photoBytes: clearPhoto,
      isUpdate: fromSettings,
    );

    statusMessage.value =
        hasMask ? 'Clear + masked face enrolled' : 'Clear face enrolled';

    if (fromSettings) {
      Get.back(result: saved);
    } else {
      Get.snackbar(
        'Success',
        statusMessage.value,
        snackPosition: SnackPosition.BOTTOM,
      );
      Get.offNamed(AppRoutes.punch);
    }
  }

  Future<void> openAppSettingsPage() => openAppSettings();

  @override
  void onClose() {
    cameraController?.dispose();
    cameraController = null;
    super.onClose();
  }
}
