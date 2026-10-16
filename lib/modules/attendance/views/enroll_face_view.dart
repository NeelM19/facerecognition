import 'package:camera/camera.dart';
import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:facerecognition/core/widgets/face_capture_overlay.dart';
import 'package:facerecognition/modules/attendance/controllers/enroll_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EnrollFaceView extends GetView<EnrollController> {
  const EnrollFaceView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final base =
              controller.fromSettings ? 'Update face' : 'Enroll face';
          if (controller.enrollStep.value == 0) {
            return Text('$base (clear)');
          }
          return Text('$base (mask)');
        }),
      ),
      body: Obx(() {
        if (controller.permissionDenied.value) {
          return _PermissionDenied(
            onOpenSettings: controller.openAppSettingsPage,
          );
        }

        final ready = controller.isCameraReady.value;
        final cam = controller.cameraController;
        final processing = controller.isProcessing.value;
        final capturing = controller.isCapturing.value;
        final frameIndex = controller.clearFrameIndex.value;
        final progress = processing && frameIndex > 0
            ? frameIndex / AppConstants.clearEnrollFrameCount
            : null;

        return Column(
          children: [
            Expanded(
              child: Padding(
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
                        faceDetected: capturing || (processing && frameIndex > 0),
                        isCapturing: capturing,
                        isProcessing: processing,
                        progress: progress,
                      ),
                      if (processing && frameIndex > 0)
                        Positioned(
                          top: 20,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _GlassLabel(
                              label: controller.enrollStep.value == 0
                                  ? 'Scanning  $frameIndex / ${AppConstants.clearEnrollFrameCount}'
                                  : 'Scanning masked face',
                            ),
                          ),
                        ),
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 20,
                        child: _GlassLabel(
                          label: controller.statusMessage.value,
                          multiline: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: FilledButton.icon(
                onPressed: processing ? null : controller.captureAndEnroll,
                icon: processing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(
                  processing
                      ? 'Capturing…'
                      : controller.enrollStep.value == 0
                          ? 'Capture clear face'
                          : 'Capture with mask',
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _GlassLabel extends StatelessWidget {
  const _GlassLabel({required this.label, this.multiline = false});

  final String label;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x990A1210),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: multiline ? 16 : 14,
          vertical: multiline ? 12 : 8,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            height: multiline ? 1.35 : 1.2,
            fontSize: multiline ? 13.5 : 12.5,
          ),
        ),
      ),
    );
  }
}

class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.onOpenSettings});

  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Camera permission is required for face enrollment.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}
