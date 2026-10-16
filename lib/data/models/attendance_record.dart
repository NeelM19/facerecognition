enum AttendanceType { clockIn, clockOut }

extension AttendanceTypeX on AttendanceType {
  String get dbValue => this == AttendanceType.clockIn ? 'in' : 'out';

  String get label => this == AttendanceType.clockIn ? 'IN' : 'OUT';

  static AttendanceType fromDb(String value) {
    return value == 'out' ? AttendanceType.clockOut : AttendanceType.clockIn;
  }
}

class AttendanceRecord {
  const AttendanceRecord({
    this.id,
    required this.type,
    required this.timestamp,
    required this.similarity,
    required this.matched,
    this.distance,
    this.embedding,
    this.remoteSyncedAt,
  });

  final int? id;
  final AttendanceType type;
  final DateTime timestamp;
  final double similarity;
  final bool matched;

  /// Optional match distance from on-device recognition; not persisted to SQLite.
  final double? distance;

  /// Live L2-normalized face embedding from punch match; API-only, not persisted.
  final List<double>? embedding;
  final DateTime? remoteSyncedAt;

  /// SQLite row map (`matched` as 0/1). Does not include [distance] or [embedding].
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'type': type.dbValue,
      'timestamp': timestamp.toIso8601String(),
      'similarity': similarity,
      'matched': matched ? 1 : 0,
      'remote_synced_at': remoteSyncedAt?.toIso8601String(),
    };
  }

  /// Future POST /api/attendance/punch body (`matched` as JSON bool).
  Map<String, dynamic> toApiRequestBody({
    required String employeeId,
    String? deviceId,
  }) {
    return {
      'employee_id': employeeId,
      'type': type.dbValue,
      'timestamp': timestamp.toIso8601String(),
      'similarity': similarity,
      'matched': matched,
      if (distance != null) 'distance': distance,
      if (embedding != null) 'embedding': embedding,
      if (deviceId != null) 'device_id': deviceId,
    };
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'] as int?,
      type: AttendanceTypeX.fromDb(json['type'] as String? ?? 'in'),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
      matched: (json['matched'] as int? ?? 0) == 1,
      distance: (json['distance'] as num?)?.toDouble(),
      remoteSyncedAt: json['remote_synced_at'] is String
          ? DateTime.tryParse(json['remote_synced_at'] as String)
          : null,
    );
  }
}
