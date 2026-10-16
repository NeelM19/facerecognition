import 'dart:convert';

class EmployeeProfile {
  const EmployeeProfile({
    this.id = 1,
    required this.displayName,
    this.photoPath,
    this.embedding,
    this.maskedEmbedding,
    this.appearanceEmbeddings = const [],
    this.updatedAt,
    this.remoteSyncedAt,
  });

  final int id;
  final String displayName;
  final String? photoPath;

  /// Clear-face MobileFaceNet embedding (primary template).
  final List<double>? embedding;

  /// Optional masked-face template (enrolled only if user opts in).
  final List<double>? maskedEmbedding;

  /// Extra clear-face looks (beard / glasses / lighting) for 1:N match.
  final List<List<double>> appearanceEmbeddings;

  final DateTime? updatedAt;
  final DateTime? remoteSyncedAt;

  bool get isEnrolled =>
      embedding != null && embedding!.isNotEmpty && photoPath != null;

  bool get hasMaskedModel =>
      maskedEmbedding != null && maskedEmbedding!.isNotEmpty;

  EmployeeProfile copyWith({
    int? id,
    String? displayName,
    String? photoPath,
    List<double>? embedding,
    List<double>? maskedEmbedding,
    List<List<double>>? appearanceEmbeddings,
    DateTime? updatedAt,
    DateTime? remoteSyncedAt,
    bool clearRemoteSyncedAt = false,
    bool clearMaskedEmbedding = false,
  }) {
    return EmployeeProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      photoPath: photoPath ?? this.photoPath,
      embedding: embedding ?? this.embedding,
      maskedEmbedding: clearMaskedEmbedding
          ? null
          : (maskedEmbedding ?? this.maskedEmbedding),
      appearanceEmbeddings:
          appearanceEmbeddings ?? this.appearanceEmbeddings,
      updatedAt: updatedAt ?? this.updatedAt,
      remoteSyncedAt:
          clearRemoteSyncedAt ? null : (remoteSyncedAt ?? this.remoteSyncedAt),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'photo_path': photoPath,
      'embedding': embedding == null ? null : jsonEncode(embedding),
      'masked_embedding':
          maskedEmbedding == null ? null : jsonEncode(maskedEmbedding),
      'appearance_embeddings': appearanceEmbeddings.isEmpty
          ? null
          : jsonEncode(appearanceEmbeddings),
      'updated_at': updatedAt?.toIso8601String(),
      'remote_synced_at': remoteSyncedAt?.toIso8601String(),
    };
  }

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) {
    return EmployeeProfile(
      id: json['id'] as int? ?? 1,
      displayName: json['display_name'] as String? ?? 'Me',
      photoPath: json['photo_path'] as String?,
      embedding: _parseEmbedding(json['embedding']),
      maskedEmbedding: _parseEmbedding(json['masked_embedding']),
      appearanceEmbeddings:
          _parseAppearanceList(json['appearance_embeddings']),
      updatedAt: _parseDate(json['updated_at']),
      remoteSyncedAt: _parseDate(json['remote_synced_at']),
    );
  }

  static List<double>? _parseEmbedding(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList();
    }
    if (raw is List) {
      return raw.map((e) => (e as num).toDouble()).toList();
    }
    return null;
  }

  static List<List<double>> _parseAppearanceList(Object? raw) {
    if (raw == null) return const [];
    Object? decoded = raw;
    if (raw is String && raw.isNotEmpty) {
      decoded = jsonDecode(raw);
    }
    if (decoded is! List) return const [];
    final out = <List<double>>[];
    for (final item in decoded) {
      if (item is List) {
        out.add(item.map((e) => (e as num).toDouble()).toList());
      }
    }
    return out;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
