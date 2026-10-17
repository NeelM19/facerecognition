import 'package:facerecognition/app.dart';
import 'package:facerecognition/bindings/initial_binding.dart';
import 'package:facerecognition/core/config/match_threshold_config.dart';
import 'package:facerecognition/core/logging/app_logger.dart';
import 'package:facerecognition/services/face_pad_service.dart';
import 'package:facerecognition/services/face_recognition_service.dart';
import 'package:facerecognition/services/image_quality_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  AppLogger.info('Bootstrapping face services…');
  final prefs = await SharedPreferences.getInstance();
  final thresholdStore = MatchThresholdStore(prefs);
  final imageQuality = ImageQualityService();
  final facePad = FacePadService();
  await facePad.init();
  final faceService = FaceRecognitionService(
    thresholdStore: thresholdStore,
    imageQualityService: imageQuality,
    facePadService: facePad,
  );
  await faceService.init();
  AppLogger.info('FaceRecognitionService + PAD initialized');

  runApp(
    FaceAttendanceApp(
      initialBinding: InitialBinding(
        faceRecognitionService: faceService,
        thresholdStore: thresholdStore,
        imageQualityService: imageQuality,
        facePadService: facePad,
      ),
    ),
  );
}
