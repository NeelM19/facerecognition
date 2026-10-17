import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_detection_tflite/face_detection_tflite_native.dart';
import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:facerecognition/core/logging/app_logger.dart';
import 'package:facerecognition/data/models/attendance_record.dart';
import 'package:facerecognition/data/repositories/attendance_repository.dart';
import 'package:facerecognition/data/repositories/profile_repository.dart';
import 'package:facerecognition/routes/app_routes.dart';
import 'package:facerecognition/services/face_recognition_service.dart';
import 'package:facerecognition/services/liveness_tracker.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class PunchController extends GetxController {
  PunchController({
    required ProfileRepository profileRepository,
    required AttendanceRepository attendanceRepository,
    required FaceRecognitionService faceRecognitionService,
  })  : _profileRepository = profileRepository,
        _attendanceRepository = attendanceRepository,
        _faceService = faceRecognitionService;

  final ProfileRepository _profileRepository;
  final AttendanceRepository _attendanceRepository;
  final FaceRecognitionService _faceService;

  static const _stableFaceHitsRequired = 2;
  static const _cooldown = Duration(seconds: 4);
  /// Faster sampling during liveness so short blinks (esp. with glasses) are caught.
  static const _livenessFrameGap = Duration(milliseconds: 55);
  static const _matchFrameGap = Duration(milliseconds: 280);
  /// Lose the face this many frames → restart liveness (blocks photo swap).
  static const _faceLostResetFrames = 4;
  /// After liveness passes, punch must happen quickly or challenges restart.
  static const _livenessFreshFor = Duration(seconds: 4);

  final isCameraReady = false.obs;
  final isProcessing = false.obs;
  final isCapturing = false.obs;
  final permissionDenied = false.obs;
  final faceInView = false.obs;
  final livenessPassed = false.obs;
  final livenessPrompt = ''.obs;
  /// Short, user-facing instruction shown on the punch screen.
  final userPrompt = 'Center your face in the circle'.obs;
  final statusMessage = 'Look at the camera to punch'.obs;
  final lastResult = Rxn<AttendanceRecord>();
  final nextType = AttendanceType.clockIn.obs;
  final lastSimilarity = RxnDouble();

  /// Stable-face progress toward auto punch (0..1).
  final stableProgress = 0.0.obs;

  CameraController? cameraController;
  List<double>? _referenceEmbedding;
  List<double>? _maskedReferenceEmbedding;
  List<List<double>> _appearanceEmbeddings = const [];

  bool _streamActive = false;
  bool _frameBusy = false;
  int _stableHits = 0;
  int _faceLostFrames = 0;
  DateTime? _cooldownUntil;
  DateTime? _lastFrameAt;
  DateTime? _livenessPassedAt;
  bool _closed = false;

  LivenessTracker _liveness = LivenessTracker();

  @override
  void onReady() {
    super.onReady();
    _bootstrap();
  }

  void _resetLiveness({String? reason}) {
    _liveness = LivenessTracker();
    livenessPassed.value = false;
    livenessPrompt.value = _liveness.prompt;
    _livenessPassedAt = null;
    _stableHits = 0;
    stableProgress.value = 0;
    _faceLostFrames = 0;
    final msg = reason ?? _friendlyLivenessHint(_liveness.prompt);
    statusMessage.value = msg;
    userPrompt.value = msg;
  }

  /// Maps internal liveness hints to short UI copy (no debug / jargon).
  String _friendlyLivenessHint(String raw) {
    final t = raw.toLowerCase();
    if (t.contains('timed out') || t.contains('expired')) {
      return 'Let’s try again — follow the next step';
    }
    if (t.contains('static') || t.contains('flat') || t.contains('spoof')) {
      return 'Use your live face, not a photo';
    }
    if (t.contains('blink')) {
      if (t.contains('seen') || t.contains('open your eyes again')) {
        return 'Nice — open your eyes again';
      }
      if (t.contains('ok')) return 'Blink done — next step';
      return 'Blink naturally';
    }
    if (t.contains('left')) {
      if (t.contains('wrong')) return 'Turn left';
      if (t.contains('face the camera again') || t.contains('good')) {
        return 'Good — face the camera again';
      }
      return 'Turn your head left, then look at the camera';
    }
    if (t.contains('right')) {
      if (t.contains('wrong')) return 'Turn right';
      if (t.contains('face the camera again') || t.contains('good')) {
        return 'Good — face the camera again';
      }
      return 'Turn your head right, then look at the camera';
    }
    if (t.contains('face lost') || t.contains('keep your face')) {
      return 'Keep your face in the circle';
    }
    if (t.contains('closer')) return 'Move a little closer';
    if (t.contains('straight') || t.contains('face the camera')) {
      return 'Look straight at the camera';
    }
    if (raw.trim().isEmpty) return 'Center your face in the circle';
    // Fall back to raw prompt when already short/clear.
    if (raw.length <= 48 && !raw.contains('·') && !raw.contains('eyes')) {
      return raw;
    }
    return 'Follow the on-screen step';
  }

  Future<void> _bootstrap() async {
    try {
      final profile = await _profileRepository.getProfile();
      if (!profile.isEnrolled || profile.embedding == null) {
        statusMessage.value = 'No enrolled face found';
        Get.snackbar('Missing face', 'Please enroll your face first');
        return;
      }
      _referenceEmbedding = profile.embedding;
      _maskedReferenceEmbedding = profile.maskedEmbedding;
      _appearanceEmbeddings = profile.appearanceEmbeddings;
      nextType.value = await _attendanceRepository.nextPunchType();
      _resetLiveness();
      userPrompt.value = _friendlyLivenessHint(_liveness.prompt);
      statusMessage.value = userPrompt.value;
      await _initCamera();
    } catch (e, st) {
      AppLogger.error('Punch bootstrap failed', e, st);
      statusMessage.value = 'Unable to prepare punch screen';
      userPrompt.value = 'Something went wrong — go back and try again';
    }
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      permissionDenied.value = true;
      statusMessage.value = 'Camera permission is required';
      return;
    }

    const maxAttempts = 3;
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_closed) return;

      CameraController? controller;
      try {
        final cameras = await availableCameras();
        final front = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );

        controller = CameraController(
          front,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await controller.initialize();
        if (_closed) {
          await controller.dispose();
          return;
        }
        cameraController = controller;
        isCameraReady.value = true;
        await _startAutoDetection();
        return;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        AppLogger.error(
          'Punch camera init failed (attempt $attempt/$maxAttempts)',
          e,
          st,
        );
        try {
          await controller?.dispose();
        } catch (_) {}
        if (attempt < maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }

    AppLogger.error('Punch camera init failed', lastError, lastStack);
    statusMessage.value = 'Unable to start camera';
    Get.snackbar('Camera error', lastError.toString());
  }

  Future<void> _startAutoDetection() async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (_streamActive || controller.value.isStreamingImages) return;

    await controller.startImageStream(_onCameraFrame);
    _streamActive = true;
    userPrompt.value = livenessPassed.value
        ? 'Hold still…'
        : _friendlyLivenessHint(_liveness.prompt);
    statusMessage.value = userPrompt.value;
  }

  Future<void> _stopAutoDetection() async {
    final controller = cameraController;
    if (controller == null) return;
    if (!_streamActive && !controller.value.isStreamingImages) return;

    try {
      await controller.stopImageStream();
    } catch (_) {}
    _streamActive = false;
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_closed || _frameBusy || isProcessing.value) return;

    final now = DateTime.now();
    final minGap =
        livenessPassed.value ? _matchFrameGap : _livenessFrameGap;
    if (_lastFrameAt != null && now.difference(_lastFrameAt!) < minGap) {
      return;
    }
    _lastFrameAt = now;

    if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) {
      faceInView.value = false;
      return;
    }

    _frameBusy = true;
    try {
      final controller = cameraController;
      if (controller == null) return;

      final rotation = rotationForFrame(
        width: image.width,
        height: image.height,
        sensorOrientation: controller.description.sensorOrientation,
        isFrontCamera:
            controller.description.lensDirection == CameraLensDirection.front,
        deviceOrientation: controller.value.deviceOrientation,
      );

      // Full mode: eye open probs (blink) + head yaw (turn) + mesh depth.
      final faces = await _faceService.detectFromCameraImage(
        image,
        rotation: rotation,
        mode: FaceDetectionMode.full,
      );

      if (_closed || isProcessing.value) return;

      Face? face;
      for (final f in faces) {
        if (f.score >= AppConstants.punchMinFaceScore &&
            f.widthFraction >=
                AppConstants.punchMinFaceWidthFraction * 0.9) {
          face = f;
          break;
        }
      }
      faceInView.value = face != null;

      if (face == null) {
        _stableHits = 0;
        stableProgress.value = 0;
        _faceLostFrames++;
        // Dropping the face mid-challenge (or after pass) forces a full
        // liveness restart so a photo cannot be swapped in after a live pass.
        if (_faceLostFrames >= _faceLostResetFrames &&
            (livenessPassed.value || _liveness.hasProgress)) {
          _resetLiveness(reason: 'Keep your face in the circle');
        } else if (!isProcessing.value &&
            (_cooldownUntil == null || now.isAfter(_cooldownUntil!))) {
          userPrompt.value = livenessPassed.value
              ? 'Keep your face in the circle'
              : _friendlyLivenessHint(_liveness.prompt);
          statusMessage.value = userPrompt.value;
        }
        return;
      }

      _faceLostFrames = 0;

      // Freshness: must capture soon after challenges pass.
      if (livenessPassed.value &&
          _livenessPassedAt != null &&
          now.difference(_livenessPassedAt!) > _livenessFreshFor) {
        _resetLiveness(reason: 'Let’s try again — follow the next step');
        return;
      }

      if (!livenessPassed.value) {
        final box = face.detectionData.boundingBox;
        final faceWidthPx =
            (box.xmax - box.xmin).abs() * face.originalSize.width;
        final depthSpread = face.mesh == null
            ? null
            : LivenessTracker.meshDepthSpread(
                zs: face.mesh!.points.map((p) => p.z),
                faceWidthPx: faceWidthPx,
              );

        final done = _liveness.observe(
          leftEyeOpen: face.leftEyeOpenProbability,
          rightEyeOpen: face.rightEyeOpenProbability,
          yawDegrees: face.headEulerAngleY,
          faceCenterX: (box.xmin + box.xmax) * 0.5,
          faceCenterY: (box.ymin + box.ymax) * 0.5,
          meshDepthSpread: depthSpread,
        );
        livenessPrompt.value = _liveness.prompt;
        userPrompt.value = _friendlyLivenessHint(_liveness.blinkHint);
        statusMessage.value = userPrompt.value;

        if (_liveness.timedOut) {
          _resetLiveness(reason: 'Let’s try again — follow the next step');
          _startCooldown();
          return;
        }

        if (done) {
          livenessPassed.value = true;
          _livenessPassedAt = now;
          userPrompt.value = 'Hold still…';
          statusMessage.value = userPrompt.value;
          // Start stable-face countdown on the same frame so punch is not delayed.
          _stableHits = 1;
          stableProgress.value = _stableHits / _stableFaceHitsRequired;
          return;
        }
        _stableHits = 0;
        stableProgress.value = 0;
        return;
      }

      _stableHits++;
      stableProgress.value = _stableHits / _stableFaceHitsRequired;
      userPrompt.value = 'Hold still…';
      statusMessage.value = userPrompt.value;

      if (_stableHits >= _stableFaceHitsRequired) {
        _stableHits = 0;
        await _autoPunch();
      }
    } catch (e, st) {
      AppLogger.error('Auto detect frame failed', e, st);
    } finally {
      _frameBusy = false;
    }
  }

  Future<void> _autoPunch() async {
    final controller = cameraController;
    final reference = _referenceEmbedding;
    if (controller == null || !controller.value.isInitialized) return;
    if (reference == null || isProcessing.value) return;
    // Hard gate: never punch without a completed live challenge session.
    if (!livenessPassed.value || !_liveness.completed) {
      _resetLiveness(reason: _friendlyLivenessHint(_liveness.prompt));
      return;
    }

    final passedAt = _livenessPassedAt;
    if (passedAt == null ||
        DateTime.now().difference(passedAt) > _livenessFreshFor) {
      _resetLiveness(reason: 'Let’s try again — follow the next step');
      return;
    }

    isProcessing.value = true;
    stableProgress.value = 1;
    userPrompt.value = 'Almost done…';
    statusMessage.value = userPrompt.value;

    try {
      await _stopAutoDetection();
      isCapturing.value = true;
      await Future<void>.delayed(const Duration(milliseconds: 140));

      final file = await controller.takePicture();
      isCapturing.value = false;
      userPrompt.value = 'Verifying…';
      statusMessage.value = userPrompt.value;
      final bytes = await File(file.path).readAsBytes();

      final match = await _faceService.matchFromBytes(
        photoBytes: bytes,
        referenceEmbedding: reference,
        maskedReferenceEmbedding: _maskedReferenceEmbedding,
        appearanceEmbeddings: _appearanceEmbeddings,
      );
      lastSimilarity.value = match.similarity;

      print(
        '[AUTO_PUNCH] match => matched=${match.matched} '
        'sim=${match.similarity} dist=${match.distance} '
        'template=${match.matchedTemplate?.name}',
      );

      if (!match.matched) {
        userPrompt.value = 'Face not recognized — try again';
        statusMessage.value = userPrompt.value;
        Get.snackbar(
          'Not recognized',
          'Make sure you are enrolled and look at the camera',
          snackPosition: SnackPosition.BOTTOM,
        );
        _resetLiveness();
        _startCooldown();
        return;
      }

      if (match.similarity >= AppConstants.appearanceAdaptMinSimilarity &&
          match.distance <= AppConstants.appearanceAdaptMaxDistance) {
        try {
          final updated =
              await _profileRepository.upsertAppearanceEmbedding(
            match.embedding,
          );
          _appearanceEmbeddings = updated.appearanceEmbeddings;
        } catch (e, st) {
          AppLogger.error('Appearance gallery adapt failed', e, st);
        }
      }

      final type = await _attendanceRepository.nextPunchType();
      final record = await _attendanceRepository.recordPunch(
        type: type,
        similarity: match.similarity,
        matched: true,
        distance: match.distance,
        embedding: match.embedding,
      );

      lastResult.value = record;
      nextType.value = await _attendanceRepository.nextPunchType();
      final successMsg = record.type == AttendanceType.clockIn
          ? 'Checked in successfully'
          : 'Checked out successfully';
      userPrompt.value = successMsg;
      statusMessage.value = successMsg;

      _closed = true;
      await _stopAutoDetection();
      Get.offAllNamed(AppRoutes.dashboard);
      Get.snackbar(
        'Attendance marked',
        successMsg,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e, st) {
      print('[AUTO_PUNCH] error => $e');
      AppLogger.error('Auto punch failed', e, st);
      final raw = e.toString().replaceFirst('Bad state: ', '');
      final friendly = raw.toLowerCase().contains('spoof') ||
              raw.toLowerCase().contains('pad')
          ? 'Use your live face — photos and videos are blocked'
          : (raw.length > 80 ? 'Couldn’t verify — try again' : raw);
      userPrompt.value = friendly;
      statusMessage.value = friendly;
      Get.snackbar('Couldn’t punch', friendly, snackPosition: SnackPosition.BOTTOM);
      _resetLiveness();
      _startCooldown();
    } finally {
      isProcessing.value = false;
      isCapturing.value = false;
      faceInView.value = false;
      if (!_closed) {
        stableProgress.value = 0;
        await _startAutoDetection();
      }
    }
  }

  void _startCooldown() {
    _cooldownUntil = DateTime.now().add(_cooldown);
    userPrompt.value =
        'Wait ${_cooldown.inSeconds}s, then try again';
    statusMessage.value = userPrompt.value;
  }

  Future<void> openAppSettingsPage() => openAppSettings();

  @override
  void onClose() {
    _closed = true;
    final controller = cameraController;
    cameraController = null;
    if (controller != null) {
      unawaited(() async {
        try {
          if (controller.value.isStreamingImages) {
            await controller.stopImageStream();
          }
        } catch (_) {}
        await controller.dispose();
      }());
    }
    super.onClose();
  }
}
