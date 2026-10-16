import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:facerecognition/core/theme/app_theme.dart';
import 'package:facerecognition/routes/app_pages.dart';
import 'package:facerecognition/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FaceAttendanceApp extends StatelessWidget {
  const FaceAttendanceApp({super.key, required this.initialBinding});

  final Bindings initialBinding;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialBinding: initialBinding,
      initialRoute: AppRoutes.dashboard,
      getPages: AppPages.pages,
    );
  }
}
