import 'package:camera/camera.dart';
import 'package:facerecognition/core/widgets/face_capture_overlay.dart';
import 'package:facerecognition/data/models/attendance_record.dart';
import 'package:facerecognition/modules/attendance/controllers/punch_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PunchView extends GetView<PunchController> {
  const PunchView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Punch in / out')),
      body: Obx(() {
        if (controller.permissionDenied.value) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.no_photography_outlined, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Camera permission is required to mark attendance.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: controller.openAppSettingsPage,
                    child: const Text('Open settings'),
                  ),
                ],
              ),
            ),
          );
        }

        final ready = controller.isCameraReady.value;
        final cam = controller.cameraController;
        final processing = controller.isProcessing.value;
        final capturing = controller.isCapturing.value;
        final faceInView = controller.faceInView.value;
        final progress = controller.stableProgress.value;
        final livenessOk = controller.livenessPassed.value;
        final showProgress =
            faceInView && livenessOk && (progress > 0 || processing);
        final nextLabel = controller.nextType.value == AttendanceType.clockIn
            ? 'Checking in'
            : 'Checking out';

        return Padding(
          padding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ready && cam != null)
                  CameraPreview(cam)
                else
                  const ColoredBox(
                    color: Colors.black12,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                FaceCaptureOverlay(
                  accentColor: scheme.primary,
                  faceDetected: faceInView,
                  isCapturing: capturing,
                  isProcessing: processing,
                  progress: showProgress ? progress.clamp(0.0, 1.0) : null,
                  ovalCenterYFactor: 0.45,
                ),
                // Single status chip — punch type only.
                Positioned(
                  left: 20,
                  right: 20,
                  top: 20,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _StatusChip(
                      label: nextLabel,
                      accent: scheme.primary,
                    ),
                  ),
                ),
                // One clear instruction at the bottom (no duplicates / jargon).
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 24,
                  child: _InstructionCard(
                    title: controller.userPrompt.value,
                    subtitle: livenessOk
                        ? 'Keep your face in the circle'
                        : 'Use your live face — photos won’t work',
                    accent: livenessOk
                        ? const Color(0xFF5CE1C5)
                        : const Color(0xFFFFB74D),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC0A1210),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE60A1210),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w400,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
