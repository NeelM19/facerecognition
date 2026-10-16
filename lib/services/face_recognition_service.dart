import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_detection_tflite/face_detection_tflite_native.dart';
import 'package:facerecognition/core/config/match_threshold_config.dart';
import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:facerecognition/core/logging/app_logger.dart';
import 'package:facerecognition/services/image_quality_service.dart';
import 'package:get/get.dart';

enum FaceTemplateKind { clear, masked, appearance }

class FaceMatchResult {
  const FaceMatchResult({
    required this.similarity,
    required this.distance,
    required this.matched,
    required this.faceScore,
    required this.embedding,
    this.occlusionTolerant = false,
    this.matchedTemplate,
  });

  final double similarity;
  final double distance;
  final bool matched;
  final double faceScore;
  final List<double> embedding;
  final bool occlusionTolerant;
  final FaceTemplateKind? matchedTemplate;
}

class FaceEnrollmentResult {
  const FaceEnrollmentResult({
    required this.embedding,
    required this.faceScore,
    required this.photoBytes,
    required this.templateKind,
  });

  final List<double> embedding;
  final double faceScore;
  final Uint8List photoBytes;
  final FaceTemplateKind templateKind;
}

class FaceRecognitionService extends GetxService {
  FaceRecognitionService({
    MatchThresholdStore? thresholdStore,
    ImageQualityService? imageQualityService,
  })  : _thresholdStore = thresholdStore,
        _quality = imageQualityService ?? ImageQualityService();

  FaceDetector? _detector;
  MatchThresholdStore? _thresholdStore;
  final ImageQualityService _quality;

  MatchThresholdConfig get thresholds =>
      _thresholdStore?.load() ?? MatchThresholdConfig.defaults;

  void bindThresholdStore(MatchThresholdStore store) {
    _thresholdStore = store;
  }

  Future<FaceRecognitionService> init() async {
    _detector = await FaceDetector.create(
      model: FaceDetectionModel.frontCamera,
      minScore: AppConstants.detectorMinScore,
      minFaceSize: AppConstants.punchMinFaceWidthFraction,
      minFacePresenceConfidence: AppConstants.detectorMinFacePresence,
    );
    AppLogger.info('FaceRecognitionService ready');
    return this;
  }

  FaceDetector get _fd {
    final detector = _detector;
    if (detector == null) {
      throw StateError('FaceRecognitionService not initialized');
    }
    return detector;
  }

  Future<List<Face>> detectFromBytes(
    Uint8List bytes, {
    FaceDetectionMode mode = FaceDetectionMode.full,
  }) {
    return _fd.detectFacesFromBytes(bytes, mode: mode);
  }

  Future<List<Face>> detectFromCameraImage(
    CameraImage image, {
    CameraFrameRotation? rotation,
    FaceDetectionMode mode = FaceDetectionMode.fast,
  }) {
    return _fd.detectFacesFromCameraImage(
      image,
      rotation: rotation,
      mode: mode,
      maxDim: mode == FaceDetectionMode.fast ? 640 : 480,
    );
  }

  Future<FaceEnrollmentResult> enrollFromBytes(
    Uint8List photoBytes, {
    FaceTemplateKind templateKind = FaceTemplateKind.clear,
  }) async {
    final quality = await _quality.assess(photoBytes);
    AppLogger.enroll(
      'quality luma=${quality.meanLuma.toStringAsFixed(1)} '
      'sharpness=${quality.sharpness.toStringAsFixed(1)} '
      'ok=${quality.isAcceptable}',
    );
    if (!quality.isAcceptable) {
      throw StateError(quality.rejectionReason ?? 'Image quality too low');
    }

    final masked = templateKind == FaceTemplateKind.masked;
    final faces = await detectFromBytes(photoBytes);
    if (faces.length > 1) {
      throw StateError(
        'Multiple faces detected (${faces.length}). '
        'Only one person should be in frame for enrollment.',
      );
    }
    final face = _selectBestFace(
      faces,
      requireSingleFace: true,
      minScore: masked
          ? AppConstants.punchMinFaceScore
          : AppConstants.minFaceScore,
      minWidthFraction: masked
          ? AppConstants.punchMinFaceWidthFraction
          : AppConstants.minFaceWidthFraction,
    );
    final embedding = _l2Normalize(
      await _fd.getFaceEmbedding(face, photoBytes),
    );
    final asList = embedding.toList(growable: false);

    AppLogger.enroll(
      'template=${templateKind.name} '
      'faceScore=${face.score.toStringAsFixed(3)} '
      'widthFraction=${face.widthFraction.toStringAsFixed(3)} '
      'embeddingDim=${asList.length}',
    );

    return FaceEnrollmentResult(
      embedding: asList,
      faceScore: face.score,
      photoBytes: photoBytes,
      templateKind: templateKind,
    );
  }

  Future<FaceMatchResult> matchFromBytes({
    required Uint8List photoBytes,
    required List<double> referenceEmbedding,
    List<double>? maskedReferenceEmbedding,
    List<List<double>> appearanceEmbeddings = const [],
  }) async {
    final quality = await _quality.assess(photoBytes);
    if (quality.tooDark || quality.tooBlurry) {
      throw StateError(
        quality.rejectionReason ??
            'Punch photo quality too low. Hold still in good light.',
      );
    }

    final face = _selectBestFace(
      await detectFromBytes(photoBytes),
      requireSingleFace: true,
      minScore: AppConstants.punchMinFaceScore,
      minWidthFraction: AppConstants.punchMinFaceWidthFraction,
    );
    final live = _l2Normalize(
      await _fd.getFaceEmbedding(face, photoBytes),
    );
    final occluded = _looksOccludedOrCovered(face);
    final asList = live.toList(growable: false);
    final hasMaskedTemplate = maskedReferenceEmbedding != null &&
        maskedReferenceEmbedding.isNotEmpty;
    final gatesConfig = thresholds;

    final candidates = <({FaceTemplateKind kind, Float32List vector})>[
      (
        kind: FaceTemplateKind.clear,
        vector: _l2Normalize(Float32List.fromList(referenceEmbedding)),
      ),
      for (final appearance in appearanceEmbeddings)
        if (appearance.isNotEmpty)
          (
            kind: FaceTemplateKind.appearance,
            vector: _l2Normalize(Float32List.fromList(appearance)),
          ),
      if (hasMaskedTemplate)
        (
          kind: FaceTemplateKind.masked,
          vector: _l2Normalize(Float32List.fromList(maskedReferenceEmbedding)),
        ),
    ];

    var bestSim = -2.0;
    var bestDist = 999.0;
    var bestMatched = false;
    FaceTemplateKind? bestKind;
    var bestOcclusionTolerant = false;

    for (final candidate in candidates) {
      final similarity = FaceDetector.compareFaces(candidate.vector, live);
      final distance = FaceDetector.faceDistance(candidate.vector, live);

      final gates = _gatesFor(
        template: candidate.kind,
        liveOccluded: occluded,
        hasMaskedTemplate: hasMaskedTemplate,
        config: gatesConfig,
      );
      final passes =
          similarity >= gates.minSim && distance <= gates.maxDist;

      AppLogger.match(
        'template=${candidate.kind.name} '
        'similarity=${similarity.toStringAsFixed(3)} '
        '(min=${gates.minSim.toStringAsFixed(2)}) '
        'distance=${distance.toStringAsFixed(3)} '
        '(max=${gates.maxDist.toStringAsFixed(2)}) '
        'passes=$passes occluded=$occluded',
      );

      final betterThanBest = !bestMatched
          ? (passes ||
              similarity > bestSim ||
              (similarity == bestSim && distance < bestDist))
          : (passes &&
              (similarity > bestSim ||
                  (similarity == bestSim && distance < bestDist)));

      if (!betterThanBest) continue;
      if (bestMatched && !passes) continue;

      bestSim = similarity;
      bestDist = distance;
      bestMatched = passes;
      bestKind = passes ? candidate.kind : null;
      bestOcclusionTolerant = passes && gates.occlusionTolerant;
    }

    return FaceMatchResult(
      similarity: bestSim < -1 ? 0 : bestSim,
      distance: bestDist > 100 ? 0 : bestDist,
      matched: bestMatched,
      faceScore: face.score,
      embedding: asList,
      occlusionTolerant: bestOcclusionTolerant,
      matchedTemplate: bestKind,
    );
  }

  /// Adds [candidate] to the appearance gallery, replacing a near-duplicate
  /// when found; caps at [AppConstants.appearanceGalleryMax].
  List<List<double>> upsertAppearanceGallery({
    required List<List<double>> gallery,
    required List<double> candidate,
    List<double>? primary,
  }) {
    final live = _l2Normalize(Float32List.fromList(candidate));
    final liveList = live.toList(growable: false);

    // Skip if almost identical to the primary clear template.
    if (primary != null && primary.isNotEmpty) {
      final primaryVec = _l2Normalize(Float32List.fromList(primary));
      final toPrimary = FaceDetector.compareFaces(primaryVec, live);
      if (toPrimary >= 0.97) {
        return List<List<double>>.from(gallery);
      }
    }

    var bestIndex = -1;
    var bestSim = -2.0;
    for (var i = 0; i < gallery.length; i++) {
      final vec = _l2Normalize(Float32List.fromList(gallery[i]));
      final sim = FaceDetector.compareFaces(vec, live);
      if (sim > bestSim) {
        bestSim = sim;
        bestIndex = i;
      }
    }

    final next = gallery.map((e) => List<double>.from(e)).toList();
    if (bestIndex >= 0 && bestSim >= 0.92) {
      next[bestIndex] = liveList;
    } else {
      next.add(liveList);
    }

    while (next.length > AppConstants.appearanceGalleryMax) {
      next.removeAt(0);
    }
    return next;
  }

  /// Builds initial appearance slots from multi-frame clear enroll captures
  /// (excludes the primary embedding).
  List<List<double>> appearanceFromEnrollFrames({
    required List<double> primary,
    required List<List<double>> frames,
  }) {
    var gallery = <List<double>>[];
    for (final frame in frames) {
      if (_sameVector(frame, primary)) continue;
      gallery = upsertAppearanceGallery(
        gallery: gallery,
        candidate: frame,
        primary: primary,
      );
    }
    return gallery;
  }

  bool _sameVector(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-9) return false;
    }
    return true;
  }

  ({double minSim, double maxDist, bool occlusionTolerant}) _gatesFor({
    required FaceTemplateKind template,
    required bool liveOccluded,
    required bool hasMaskedTemplate,
    required MatchThresholdConfig config,
  }) {
    if (template == FaceTemplateKind.masked) {
      if (liveOccluded) {
        return (
          minSim: config.maskedMinSimilarity,
          maxDist: config.maskedMaxDistance,
          occlusionTolerant: false,
        );
      }
      return (
        minSim: config.clearMinSimilarity,
        maxDist: config.clearMaxDistance,
        occlusionTolerant: false,
      );
    }

    // Clear + appearance prototypes share clear gates (strict).
    if (liveOccluded && !hasMaskedTemplate) {
      return (
        minSim: config.occludedMinSimilarity,
        maxDist: config.occludedMaxDistance,
        occlusionTolerant: true,
      );
    }
    return (
      minSim: config.clearMinSimilarity,
      maxDist: config.clearMaxDistance,
      occlusionTolerant: false,
    );
  }

  bool _looksOccludedOrCovered(Face face) {
    final lm = face.landmarks;
    final leftEye = lm.leftEye;
    final rightEye = lm.rightEye;
    final nose = lm.noseTip;
    final mouth = lm.mouth;
    if (leftEye == null || rightEye == null || nose == null || mouth == null) {
      return false;
    }

    final eyeDist = _distance(leftEye, rightEye);
    if (eyeDist < 1e-3) return false;

    final eyeMidY = (leftEye.y + rightEye.y) / 2.0;
    final mouthGap = (mouth.y - eyeMidY).abs();
    final noseGap = (nose.y - eyeMidY).abs();
    final mouthRatio = mouthGap / eyeDist;
    final noseRatio = noseGap / eyeDist;

    if (mouthRatio < 0.70) return true;
    if (noseRatio < 0.22) return true;

    final mesh = face.meshScore;
    if (mesh != null && mesh < 0.55 && mouthRatio < 0.90) return true;
    return false;
  }

  double _distance(Point a, Point b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  Face _selectBestFace(
    List<Face> faces, {
    required bool requireSingleFace,
    required double minScore,
    required double minWidthFraction,
  }) {
    if (faces.isEmpty) {
      throw StateError(
        'No face detected. Keep eyes visible (mask OK) and try again.',
      );
    }
    if (requireSingleFace && faces.length > 1) {
      throw StateError(
        'Multiple faces detected. Ensure only you are in frame.',
      );
    }

    faces = [...faces]
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return b.widthFraction.compareTo(a.widthFraction);
      });

    final face = faces.first;
    if (face.score < minScore) {
      throw StateError(
        'Face quality too low (${face.score.toStringAsFixed(2)}). '
        'Move closer, face the camera, keep eyes visible.',
      );
    }
    if (face.widthFraction < minWidthFraction) {
      throw StateError(
        'Face too small in frame. Move closer to the camera.',
      );
    }
    return face;
  }

  Float32List _l2Normalize(Float32List input) {
    var sumSquares = 0.0;
    for (final v in input) {
      sumSquares += v * v;
    }
    final norm = math.sqrt(sumSquares);
    if (norm <= 1e-10) return input;

    final out = Float32List(input.length);
    for (var i = 0; i < input.length; i++) {
      out[i] = input[i] / norm;
    }
    return out;
  }

  @override
  void onClose() {
    _detector?.dispose();
    _detector = null;
    super.onClose();
  }
}
