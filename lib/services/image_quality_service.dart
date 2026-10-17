import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Simple on-device still quality checks for enroll / punch photos.
class ImageQualityReport {
  const ImageQualityReport({
    required this.meanLuma,
    required this.sharpness,
    required this.tooDark,
    required this.tooBright,
    required this.tooBlurry,
    this.screenStripeScore = 0,
    this.moireScore = 0,
    this.likelyScreenOrPrint = false,
  });

  /// 0–255 average luminance.
  final double meanLuma;

  /// Higher = sharper (gradient magnitude proxy).
  final double sharpness;

  final bool tooDark;
  final bool tooBright;
  final bool tooBlurry;

  /// Alternate-pixel luma oscillation (LCD/subpixel / moiré proxy).
  final double screenStripeScore;

  /// Row-autocorrelation peak (periodic screen refresh / pixel grid).
  final double moireScore;

  /// True when heuristics suggest a phone screen or printed photo replay.
  final bool likelyScreenOrPrint;

  bool get isAcceptable =>
      !tooDark && !tooBright && !tooBlurry && !likelyScreenOrPrint;

  String? get rejectionReason {
    if (likelyScreenOrPrint) {
      return 'Live face required — screen/photo detected. '
          'Do not show a picture or phone display.';
    }
    if (tooDark) {
      return 'Image too dark (${meanLuma.toStringAsFixed(0)}). '
          'Move to better light.';
    }
    if (tooBright) {
      return 'Image too bright / washed out (${meanLuma.toStringAsFixed(0)}). '
          'Avoid strong backlight.';
    }
    if (tooBlurry) {
      return 'Image too blurry (sharpness ${sharpness.toStringAsFixed(1)}). '
          'Hold still and try again.';
    }
    return null;
  }
}

class ImageQualityService {
  /// Downscale still and score brightness, sharpness, and screen/print cues.
  Future<ImageQualityReport> assess(
    Uint8List jpegBytes, {
    double minLuma = 45,
    double maxLuma = 210,
    double minSharpness = 12,
    bool checkScreenOrPrint = false,
    double screenStripeGate = 22,
    double moireGate = 0.42,
  }) async {
    final codec = await ui.instantiateImageCodec(
      jpegBytes,
      targetWidth: 160,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    if (byteData == null) {
      return const ImageQualityReport(
        meanLuma: 0,
        sharpness: 0,
        tooDark: true,
        tooBright: false,
        tooBlurry: true,
        likelyScreenOrPrint: false,
      );
    }

    final bytes = byteData.buffer.asUint8List();
    final width = 160;
    final height = bytes.length ~/ (width * 4);
    if (height < 3) {
      return const ImageQualityReport(
        meanLuma: 0,
        sharpness: 0,
        tooDark: true,
        tooBright: false,
        tooBlurry: true,
        likelyScreenOrPrint: false,
      );
    }

    var lumaSum = 0.0;
    var count = 0;
    final luma = List<double>.filled(width * height, 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final r = bytes[i].toDouble();
        final g = bytes[i + 1].toDouble();
        final b = bytes[i + 2].toDouble();
        final yLuma = 0.299 * r + 0.587 * g + 0.114 * b;
        luma[y * width + x] = yLuma;
        lumaSum += yLuma;
        count++;
      }
    }
    final mean = count == 0 ? 0.0 : lumaSum / count;

    // Mean absolute gradient — cheap blur proxy.
    var gradSum = 0.0;
    var gradCount = 0;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final dx = luma[y * width + x + 1] - luma[y * width + x - 1];
        final dy = luma[(y + 1) * width + x] - luma[(y - 1) * width + x];
        gradSum += dx.abs() + dy.abs();
        gradCount++;
      }
    }
    final sharpness = gradCount == 0 ? 0.0 : gradSum / gradCount;

    var screenStripeScore = 0.0;
    var moireScore = 0.0;
    var likelyScreenOrPrint = false;

    if (checkScreenOrPrint) {
      // Center ROI — face usually fills middle of punch still.
      final x0 = width ~/ 4;
      final x1 = width - width ~/ 4;
      final y0 = height ~/ 5;
      final y1 = height - height ~/ 5;

      var stripeSum = 0.0;
      var stripeCount = 0;
      var colorOsc = 0.0;
      var colorCount = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1 - 1; x++) {
          final i = (y * width + x) * 4;
          final a = luma[y * width + x];
          final bL = luma[y * width + x + 1];
          stripeSum += (a - bL).abs();
          stripeCount++;
          // Subpixel RGB flicker common on phone screens.
          final r0 = bytes[i].toDouble();
          final g0 = bytes[i + 1].toDouble();
          final b0 = bytes[i + 2].toDouble();
          final r1 = bytes[i + 4].toDouble();
          final g1 = bytes[i + 5].toDouble();
          final b1 = bytes[i + 6].toDouble();
          colorOsc += (r0 - r1).abs() + (g0 - g1).abs() + (b0 - b1).abs();
          colorCount++;
        }
      }
      screenStripeScore =
          stripeCount == 0 ? 0.0 : stripeSum / stripeCount;

      // Row-mean autocorrelation: periodic vertical banding from pixel grids.
      final rowMeans = List<double>.filled(y1 - y0, 0);
      for (var y = y0; y < y1; y++) {
        var rowSum = 0.0;
        var rowN = 0;
        for (var x = x0; x < x1; x++) {
          rowSum += luma[y * width + x];
          rowN++;
        }
        rowMeans[y - y0] = rowN == 0 ? 0.0 : rowSum / rowN;
      }
      moireScore = _bestAutocorrPeak(rowMeans);

      final colorStripe =
          colorCount == 0 ? 0.0 : colorOsc / (colorCount * 3);

      // Sharp + strong alternate-pixel / periodic energy ⇒ screen.
      // Soft grain with moderate stripe can still be a print held to camera.
      likelyScreenOrPrint = (screenStripeScore >= screenStripeGate &&
              sharpness >= minSharpness * 1.15) ||
          (moireScore >= moireGate && screenStripeScore >= screenStripeGate * 0.65) ||
          (colorStripe >= 14 && screenStripeScore >= screenStripeGate * 0.75);
    }

    return ImageQualityReport(
      meanLuma: mean,
      sharpness: sharpness,
      tooDark: mean < minLuma,
      tooBright: mean > maxLuma,
      tooBlurry: sharpness < minSharpness,
      screenStripeScore: screenStripeScore,
      moireScore: moireScore,
      likelyScreenOrPrint: likelyScreenOrPrint,
    );
  }

  /// Peak normalized autocorrelation for small lags (2..8).
  double _bestAutocorrPeak(List<double> series) {
    if (series.length < 16) return 0;
    var mean = 0.0;
    for (final v in series) {
      mean += v;
    }
    mean /= series.length;
    var varSum = 0.0;
    for (final v in series) {
      final d = v - mean;
      varSum += d * d;
    }
    if (varSum < 1e-6) return 0;

    var best = 0.0;
    for (var lag = 2; lag <= 8; lag++) {
      var cov = 0.0;
      final n = series.length - lag;
      for (var i = 0; i < n; i++) {
        cov += (series[i] - mean) * (series[i + lag] - mean);
      }
      final corr = (cov / n) / (varSum / series.length);
      best = math.max(best, corr.abs());
    }
    return best;
  }
}
