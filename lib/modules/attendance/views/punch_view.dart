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
        final showProgress = faceInView &&
            controller.livenessPassed.value &&
            (progress > 0 || processing);

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
                Positioned(
                  left: 20,
                  right: 20,
                  top: 20,
                  child: Column(
                    children: [
                      _GlassBadge(
                        label: 'Next · ${controller.nextType.value.label}',
                        accent: scheme.primary,
                      ),
                      const SizedBox(height: 8),
                      _GlassBadge(
                        label: controller.livenessPassed.value
                            ? (processing
                                ? 'Verifying identity…'
                                : 'Liveness verified')
                            : (controller.livenessPrompt.value.isEmpty
                                ? 'Complete blink + head turn'
                                : controller.livenessPrompt.value),
                        accent: controller.livenessPassed.value
                            ? const Color(0xFF5CE1C5)
                            : const Color(0xFFFFB74D),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 20,
                  child: _GlassBadge(
                    label: controller.statusMessage.value,
                    accent: Colors.white24,
                    multiline: true,
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

class _GlassBadge extends StatelessWidget {
  const _GlassBadge({
    required this.label,
    required this.accent,
    this.multiline = false,
  });

  final String label;
  final Color accent;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x990A1210),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: multiline ? 16 : 14,
          vertical: multiline ? 12 : 9,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.94),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.25,
            height: multiline ? 1.35 : 1.2,
            fontSize: multiline ? 13.5 : 12.5,
          ),
        ),
      ),
    );
  }
}
