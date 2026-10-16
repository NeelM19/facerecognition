import 'package:facerecognition/modules/settings/controllers/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final profile = controller.profile.value;
        final enrolled = profile?.isEnrolled == true;
        final photoPath = profile?.photoPath;
        final bytes = controller.photoBytes.value;
        final photoVersion = controller.photoVersion.value;
        final showPhoto = enrolled && bytes != null && bytes.isNotEmpty;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Enrolled face',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 260,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: showPhoto
                  ? Image.memory(
                      bytes,
                      key: ValueKey(
                        'enrolled_${photoPath}_'
                        '${profile?.updatedAt?.millisecondsSinceEpoch}_'
                        '${photoVersion}_${bytes.length}',
                      ),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      gaplessPlayback: false,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 48,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_off_outlined,
                            size: 48,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No face enrolled yet',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            if (enrolled && profile?.updatedAt != null)
              Text(
                'Updated ${DateFormat.yMMMd().add_jm().format(profile!.updatedAt!.toLocal())}'
                '${profile.hasMaskedModel ? ' · clear + masked' : ' · clear only'}'
                '${profile.appearanceEmbeddings.isEmpty ? '' : ' · ${profile.appearanceEmbeddings.length} appearance looks'}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: controller.updateFace,
              icon: Icon(enrolled ? Icons.camera_front : Icons.person_add_alt),
              label: Text(
                enrolled ? 'Update face' : 'Enroll face',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.openHistory,
              icon: const Icon(Icons.history),
              label: const Text('Attendance history'),
            ),
          ],
        );
      }),
    );
  }
}
