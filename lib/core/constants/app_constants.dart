class AppConstants {
  AppConstants._();

  static const String appName = 'Face Attendance';
  static const String dbName = 'face_attendance.db';
  static const int dbVersion = 4;

  /// Max extra appearance vectors (beard/glasses variants) per profile.
  static const int appearanceGalleryMax = 8;

  /// Clear enroll captures this many frames to seed the gallery.
  static const int clearEnrollFrameCount = 3;

  /// Only adapt gallery after a punch stronger than the accept gate.
  static const double appearanceAdaptMinSimilarity = 0.78;
  static const double appearanceAdaptMaxDistance = 0.80;

  /// Cosine similarity for MobileFaceNet embeddings (-1..1).
  /// Package guide: > 0.6 likely same person. We stay stricter to avoid
  /// false accepts between different people.
  static const double faceMatchThreshold = 0.72;

  /// Euclidean distance for the same embeddings. Lower = more alike.
  /// Package guide: < 0.6 very likely same; > 1.0 different.
  static const double faceMaxDistance = 0.85;

  /// Clear↔clear punch gate (strict — prevents impostor punches).
  static const double punchMatchThreshold = 0.72;
  static const double punchMaxDistance = 0.85;

  /// Masked↔masked punch gate (same person with mask enrolled).
  /// Slightly softer than clear, still far above impostor scores.
  static const double punchMaskedMatchThreshold = 0.70;
  static const double punchMaskedMaxDistance = 0.88;

  /// Clear template vs masked live ONLY when no masked template was enrolled.
  /// Kept close to the clear gate — the old 0.55 value caused false accepts.
  static const double punchOccludedMatchThreshold = 0.68;
  static const double punchOccludedMaxDistance = 0.92;

  /// Detector create() floor so masked faces are not dropped before app logic.
  static const double detectorMinScore = 0.5;

  /// Mesh presence gate at create(); lower so mask/occlusion still pass.
  static const double detectorMinFacePresence = 0.25;

  /// Enroll clear-face step still requires a high-quality face.
  static const double minFaceScore = 0.85;

  /// Masked enroll + punch stills accept weaker detector scores.
  static const double punchMinFaceScore = 0.55;

  /// Face must cover at least this fraction of image width (clear enroll).
  static const double minFaceWidthFraction = 0.22;

  /// Punch / masked enroll allows a slightly smaller face in frame.
  static const double punchMinFaceWidthFraction = 0.16;

  static const String defaultDisplayName = 'Me';

  /// Placeholder until a real employee id exists in the app / backend.
  static const String defaultEmployeeId = 'EMP001';

  /// Legacy fixed filename (pre unique-path enrollments).
  static const String enrolledPhotoFileName = 'enrolled_face.jpg';

  /// Prefix for unique enrolled photo files: enrolled_face_TIMESTAMP.jpg
  static const String enrolledPhotoFilePrefix = 'enrolled_face_';

  /// MiniFASNetV2 silent-face PAD asset (LiteRT / TFLite).
  static const String padModelAsset = 'assets/models/silentface.tflite';

  /// Face crop scale relative to detector box (Silent-Face MiniFASNetV2 = 2.7).
  static const double padCropScale = 2.7;

  /// Softmax class-1 (live) score required to accept a punch / enroll still.
  /// Dual-scale ensemble (2.7+4.0) usually lands live faces well above this.
  /// Raise toward 0.85 for stricter anti-replay; lower if genuine rejects rise.
  static const double padMinLiveScore = 0.70;
}
