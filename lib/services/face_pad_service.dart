import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:facerecognition/core/logging/app_logger.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:get/get.dart';

/// Result of MiniFASNetV2 silent-face PAD (presentation attack detection).
class FacePadResult {
  const FacePadResult({
    required this.liveScore,
    required this.argmax,
    required this.probs,
    required this.isLive,
  });

  /// Softmax probability of the live class (index 1).
  final double liveScore;

  /// Argmax over [fake_print, live, fake_replay]-style logits.
  final int argmax;

  final List<double> probs;

  /// True when [argmax] is live and [liveScore] meets [AppConstants.padMinLiveScore].
  final bool isLive;

  String get rejectionReason =>
      'Spoof detected (PAD live ${liveScore.toStringAsFixed(2)}, '
      'class $argmax). Use a live face — photos/videos/screens rejected.';
}

/// On-device face anti-spoofing via Silent-Face MiniFASNetV2 TFLite.
///
/// Input must match the original MiniFASNet training path:
/// face crop (scales 2.7 and 4.0 ensembled), **BGR**, NCHW `[1,3,80,80]`,
/// values in **0..255** (Silent-Face `ToTensor` does **not** divide by 255).
///
/// Output: 3-class probabilities (model graph includes softmax);
/// class 1 = live, 0/2 = spoof.
class FacePadService extends GetxService {
  Interpreter? _interpreter;
  bool _nchw = true;
  int _inH = 80;
  int _inW = 80;

  /// Same scales the original Silent-Face APK ensembles.
  static const _cropScales = <double>[2.7, 4.0];

  bool get isReady => _interpreter != null;

  Future<FacePadService> init() async {
    try {
      final interpreter = await Interpreter.fromAsset(
        AppConstants.padModelAsset,
      );
      final shape = interpreter.getInputTensor(0).shape;
      // Expected [1, 3, 80, 80] (NCHW) or [1, 80, 80, 3] (NHWC).
      if (shape.length == 4 && shape[1] == 3) {
        _nchw = true;
        _inH = shape[2];
        _inW = shape[3];
      } else if (shape.length == 4 && shape[3] == 3) {
        _nchw = false;
        _inH = shape[1];
        _inW = shape[2];
      } else {
        AppLogger.error('Unexpected PAD input shape: $shape');
      }
      _interpreter = interpreter;
      AppLogger.info(
        'FacePadService ready shape=$shape nchw=$_nchw '
        'size=${_inW}x$_inH range=0..255',
      );
    } catch (e, st) {
      AppLogger.error('FacePadService init failed', e, st);
      rethrow;
    }
    return this;
  }

  /// Scores a still. [box] is normalized `xmin,ymin,xmax,ymax` in `[0,1]`.
  Future<FacePadResult> assessBytes({
    required Uint8List photoBytes,
    required double xmin,
    required double ymin,
    required double xmax,
    required double ymax,
    double minLiveScore = AppConstants.padMinLiveScore,
  }) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('FacePadService not initialized');
    }

    final codec = await ui.instantiateImageCodec(photoBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    try {
      final srcW = image.width;
      final srcH = image.height;
      final x = xmin.clamp(0.0, 1.0) * srcW;
      final y = ymin.clamp(0.0, 1.0) * srcH;
      final boxW = math.max(1.0, (xmax - xmin).abs() * srcW);
      final boxH = math.max(1.0, (ymax - ymin).abs() * srcH);

      // Ensemble crop scales like the original Silent-Face pipeline.
      final fused = Float32List(3);
      for (final scale in _cropScales) {
        final input = await _prepareInputFromImage(
          image: image,
          x: x,
          y: y,
          boxW: boxW,
          boxH: boxH,
          scale: scale,
        );
        final output = Float32List(3);
        interpreter.run(input, output);
        final probs = _asProbabilities(output);
        for (var i = 0; i < 3; i++) {
          fused[i] += probs[i];
        }
      }
      for (var i = 0; i < 3; i++) {
        fused[i] /= _cropScales.length;
      }

      var argmax = 0;
      for (var i = 1; i < fused.length; i++) {
        if (fused[i] > fused[argmax]) argmax = i;
      }
      final liveScore = fused[1];
      final isLive = argmax == 1 && liveScore >= minLiveScore;

      AppLogger.punch(
        'PAD live=${liveScore.toStringAsFixed(3)} '
        'argmax=$argmax '
        'probs=${fused.map((p) => p.toStringAsFixed(2)).join(',')} '
        'box=${boxW.toStringAsFixed(0)}x${boxH.toStringAsFixed(0)} '
        'img=${srcW}x$srcH isLive=$isLive',
      );

      return FacePadResult(
        liveScore: liveScore,
        argmax: argmax,
        probs: fused.toList(growable: false),
        isLive: isLive,
      );
    } finally {
      image.dispose();
    }
  }

  Future<Float32List> _prepareInputFromImage({
    required ui.Image image,
    required double x,
    required double y,
    required double boxW,
    required double boxH,
    required double scale,
  }) async {
    final srcW = image.width;
    final srcH = image.height;
    final crop = _expandBox(
      srcW: srcW,
      srcH: srcH,
      x: x,
      y: y,
      boxW: boxW,
      boxH: boxH,
      scale: scale,
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // FilterQuality.medium ≈ cv2.INTER_LINEAR used by Silent-Face resize.
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    final src = ui.Rect.fromLTRB(
      crop.$1.toDouble(),
      crop.$2.toDouble(),
      (crop.$3 + 1).toDouble(),
      (crop.$4 + 1).toDouble(),
    );
    final dst = ui.Rect.fromLTWH(0, 0, _inW.toDouble(), _inH.toDouble());
    canvas.drawImageRect(image, src, dst, paint);
    final picture = recorder.endRecording();
    final resized = await picture.toImage(_inW, _inH);

    final bytes = await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
    resized.dispose();
    if (bytes == null) {
      throw StateError('PAD crop encode failed');
    }

    final rgba = bytes.buffer.asUint8List();
    final plane = _inH * _inW;
    final out = Float32List(3 * plane);

    // Keep 0..255 floats — matches Silent-Face numpy ToTensor (no /255).
    for (var yy = 0; yy < _inH; yy++) {
      for (var xx = 0; xx < _inW; xx++) {
        final i = (yy * _inW + xx) * 4;
        final r = rgba[i].toDouble();
        final g = rgba[i + 1].toDouble();
        final b = rgba[i + 2].toDouble();
        final idx = yy * _inW + xx;
        if (_nchw) {
          out[0 * plane + idx] = b;
          out[1 * plane + idx] = g;
          out[2 * plane + idx] = r;
        } else {
          final o = idx * 3;
          out[o] = b;
          out[o + 1] = g;
          out[o + 2] = r;
        }
      }
    }
    return out;
  }

  /// Silent-Face `CropImage._get_new_box` — bbox is `[x,y,w,h]` in pixels.
  (int, int, int, int) _expandBox({
    required int srcW,
    required int srcH,
    required double x,
    required double y,
    required double boxW,
    required double boxH,
    required double scale,
  }) {
    var s = scale;
    s = math.min((srcH - 1) / boxH, math.min((srcW - 1) / boxW, s));

    final newWidth = boxW * s;
    final newHeight = boxH * s;
    final centerX = boxW / 2 + x;
    final centerY = boxH / 2 + y;

    var left = centerX - newWidth / 2;
    var top = centerY - newHeight / 2;
    var right = centerX + newWidth / 2;
    var bottom = centerY + newHeight / 2;

    if (left < 0) {
      right -= left;
      left = 0;
    }
    if (top < 0) {
      bottom -= top;
      top = 0;
    }
    if (right > srcW - 1) {
      left -= right - srcW + 1;
      right = (srcW - 1).toDouble();
    }
    if (bottom > srcH - 1) {
      top -= bottom - srcH + 1;
      bottom = (srcH - 1).toDouble();
    }

    return (
      left.round().clamp(0, srcW - 1),
      top.round().clamp(0, srcH - 1),
      right.round().clamp(0, srcW - 1),
      bottom.round().clamp(0, srcH - 1),
    );
  }

  /// Model may already emit softmax; avoid distorting valid probabilities.
  List<double> _asProbabilities(Float32List raw) {
    var sum = 0.0;
    var minV = raw[0];
    var maxV = raw[0];
    for (final v in raw) {
      sum += v;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final alreadyProb =
        minV >= -1e-3 && maxV <= 1.0 + 1e-3 && (sum - 1.0).abs() < 0.08;
    if (alreadyProb) {
      return [for (final v in raw) v.clamp(0.0, 1.0)];
    }

    var peak = raw[0];
    for (var i = 1; i < raw.length; i++) {
      if (raw[i] > peak) peak = raw[i];
    }
    final exps = List<double>.filled(raw.length, 0);
    var eSum = 0.0;
    for (var i = 0; i < raw.length; i++) {
      exps[i] = math.exp(raw[i] - peak);
      eSum += exps[i];
    }
    if (eSum <= 0) return List<double>.filled(raw.length, 0);
    return [for (final e in exps) e / eSum];
  }

  @override
  void onClose() {
    _interpreter?.close();
    _interpreter = null;
    super.onClose();
  }
}
