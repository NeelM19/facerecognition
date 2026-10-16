import 'package:facerecognition/data/models/attendance_record.dart';
import 'package:facerecognition/data/repositories/attendance_repository.dart';
import 'package:get/get.dart';

class HistoryController extends GetxController {
  HistoryController(this._attendanceRepository);

  final AttendanceRepository _attendanceRepository;

  final isLoading = true.obs;
  final records = <AttendanceRecord>[].obs;

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      records.assignAll(await _attendanceRepository.getHistory());
    } finally {
      isLoading.value = false;
    }
  }
}
