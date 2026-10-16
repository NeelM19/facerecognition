class FaceSyncPayload {
  const FaceSyncPayload({
    required this.displayName,
    required this.embedding,
    required this.photoFilePath,
    required this.updatedAt,
    this.maskedEmbedding,
    this.employeeId,
    this.deviceId,
  });

  final String displayName;
  final List<double> embedding;
  final List<double>? maskedEmbedding;
  final String photoFilePath;
  final DateTime updatedAt;
  final String? employeeId;
  final String? deviceId;

  /// Local / print-oriented map (includes file path, not bytes).
  Map<String, dynamic> toJson() {
    return {
      'employee_id': employeeId,
      'display_name': displayName,
      'embedding': embedding,
      if (maskedEmbedding != null) 'masked_embedding': maskedEmbedding,
      'photo_file_path': photoFilePath,
      'enrolled_at': updatedAt.toIso8601String(),
      if (deviceId != null) 'device_id': deviceId,
    };
  }
}
