import 'package:facerecognition/modules/attendance/bindings/attendance_binding.dart';
import 'package:facerecognition/modules/attendance/views/attendance_gate_view.dart';
import 'package:facerecognition/modules/attendance/views/attendance_history_view.dart';
import 'package:facerecognition/modules/attendance/views/enroll_face_view.dart';
import 'package:facerecognition/modules/attendance/views/punch_view.dart';
import 'package:facerecognition/modules/dashboard/bindings/dashboard_binding.dart';
import 'package:facerecognition/modules/dashboard/views/dashboard_view.dart';
import 'package:facerecognition/modules/settings/bindings/settings_binding.dart';
import 'package:facerecognition/modules/settings/views/settings_view.dart';
import 'package:facerecognition/routes/app_routes.dart';
import 'package:get/get.dart';

class AppPages {
  AppPages._();

  static final pages = <GetPage<dynamic>>[
    GetPage(
      name: AppRoutes.dashboard,
      page: () => const DashboardView(),
      binding: DashboardBinding(),
    ),
    GetPage(
      name: AppRoutes.settings,
      page: () => const SettingsView(),
      binding: SettingsBinding(),
    ),
    GetPage(
      name: AppRoutes.attendanceGate,
      page: () => const AttendanceGateView(),
      binding: AttendanceGateBinding(),
    ),
    GetPage(
      name: AppRoutes.enroll,
      page: () => const EnrollFaceView(),
      binding: EnrollBinding(),
    ),
    GetPage(
      name: AppRoutes.punch,
      page: () => const PunchView(),
      binding: PunchBinding(),
    ),
    GetPage(
      name: AppRoutes.history,
      page: () => const AttendanceHistoryView(),
      binding: HistoryBinding(),
    ),
  ];
}
