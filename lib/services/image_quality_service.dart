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
  });

  /// 0–255 average luminance.
  final double meanLuma;

  /// Higher = sharper (gradient magnitude proxy).
  final double sharpness;

  final bool tooDark;
  final bool tooBright;
  final bool tooBlurry;

  bool get isAcceptable => !tooDark && !tooBright && !tooBlurry;

  String? get rejectionReason {
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
  /// Downscale still and score brightness + sharpness.
  Future<ImageQualityReport> assess(
    Uint8List jpegBytes, {
    double minLuma = 45,
    double maxLuma = 210,
    double minSharpness = 12,
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

    return ImageQualityReport(
      meanLuma: mean,
      sharpness: sharpness,
      tooDark: mean < minLuma,
      tooBright: mean > maxLuma,
      tooBlurry: sharpness < minSharpness,
    );
  }
}
