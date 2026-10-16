import 'package:facerecognition/data/models/attendance_record.dart';
import 'package:facerecognition/modules/attendance/controllers/history_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class AttendanceHistoryView extends GetView<HistoryController> {
  const AttendanceHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance history')),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = controller.records;
        if (items.isEmpty) {
          return Center(
            child: Text(
              'No attendance records yet',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final record = items[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: record.matched
                        ? (record.type == AttendanceType.clockIn
                            ? Colors.green.shade100
                            : Colors.orange.shade100)
                        : Colors.red.shade100,
                    child: Icon(
                      record.matched
                          ? (record.type == AttendanceType.clockIn
                              ? Icons.login
                              : Icons.logout)
                          : Icons.warning_amber_rounded,
                      color: record.matched
                          ? (record.type == AttendanceType.clockIn
                              ? Colors.green.shade800
                              : Colors.orange.shade800)
                          : Colors.red.shade800,
                    ),
                  ),
                  title: Text(
                    record.matched
                        ? 'Punch ${record.type.label}'
                        : 'Failed recognition',
                  ),
                  subtitle: Text(
                    DateFormat.yMMMd().add_jm().format(record.timestamp.toLocal()),
                  ),
                  trailing: Text(
                    record.similarity.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              );
            },
          ),
        );
      }),
    );
  }
}
