import 'package:facerecognition/modules/attendance/controllers/attendance_gate_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AttendanceGateView extends GetView<AttendanceGateController> {
  const AttendanceGateView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: Center(
        child: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(controller.statusMessage.value),
            ],
          ),
        ),
      ),
    );
  }
}
