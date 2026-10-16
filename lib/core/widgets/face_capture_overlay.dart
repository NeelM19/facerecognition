import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Modern biometric-style face guide (Face ID / banking FR look).
class FaceCaptureOverlay extends StatefulWidget {
  const FaceCaptureOverlay({
    super.key,
    required this.accentColor,
    this.faceDetected = false,
    this.isCapturing = false,
    this.isProcessing = false,
    this.progress,
    this.ovalCenterYFactor = 0.42,
  });

  final Color accentColor;
  final bool faceDetected;
  final bool isCapturing;
  final bool isProcessing;

  /// Optional 0..1 recognition / enroll progress.
  final double? progress;

  final double ovalCenterYFactor;

  @override
  State<FaceCaptureOverlay> createState() => _FaceCaptureOverlayState();
}

class _FaceCaptureOverlayState extends State<FaceCaptureOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _breathe;
  late final AnimationController _orbit;
  late final AnimationController _scan;
  late final AnimationController _lock;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    )..repeat();

    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _lock = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didUpdateWidget(covariant FaceCaptureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCapturing && !oldWidget.isCapturing) {
      _lock.forward(from: 0);
    }
    if (widget.faceDetected && !oldWidget.faceDetected) {
      // Soft confirm pulse when face enters frame.
      _lock.forward(from: 0.35);
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _orbit.dispose();
    _scan.dispose();
    _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanning = widget.isProcessing || widget.isCapturing;
    final active = widget.faceDetected || scanning;
    final color = active
        ? const Color(0xFF5CE1C5)
        : Color.lerp(widget.accentColor, const Color(0xFF7AD7FF), 0.55)!;

    return AnimatedBuilder(
      animation: Listenable.merge([_breathe, _orbit, _scan, _lock]),
      builder: (context, _) {
        return CustomPaint(
          painter: _ModernFacePainter(
            color: color,
            breathe: Curves.easeInOut.transform(_breathe.value),
            orbit: _orbit.value,
            scan: Curves.easeInOut.transform(_scan.value),
            lock: Curves.easeOutCubic.transform(_lock.value),
            faceDetected: widget.faceDetected,
            scanning: scanning,
            progress: widget.progress,
            centerYFactor: widget.ovalCenterYFactor,
          ),
        );
      },
    );
  }
}

Rect _faceRect(Size size, double centerYFactor) {
  final w = size.width * 0.58;
  final h = w * 1.28;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * centerYFactor),
    width: w,
    height: h,
  );
}

class _ModernFacePainter extends CustomPainter {
  _ModernFacePainter({
    required this.color,
    required this.breathe,
    required this.orbit,
    required this.scan,
    required this.lock,
    required this.faceDetected,
    required this.scanning,
    required this.progress,
    required this.centerYFactor,
  });

  final Color color;
  final double breathe;
  final double orbit;
  final double scan;
  final double lock;
  final bool faceDetected;
  final bool scanning;
  final double? progress;
  final double centerYFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final face = _faceRect(size, centerYFactor);
    final scale = 1.0 + (breathe * 0.012) + (lock * 0.018);
    final oval = Rect.fromCenter(
      center: face.center,
      width: face.width * scale,
      height: face.height * scale,
    );

    _paintVignette(canvas, size, oval);
    _paintGlowRings(canvas, oval);
    _paintOrbitTicks(canvas, oval);
    _paintMainRing(canvas, oval);
    _paintScanBeam(canvas, oval);
    _paintLandmarkDots(canvas, oval);
    _paintProgress(canvas, oval);

    if (lock > 0.05 && lock < 0.98) {
      _paintLockRipple(canvas, oval);
    }
  }

  void _paintVignette(Canvas canvas, Size size, Rect oval) {
    final hole = Path()
      ..addRect(Offset.zero & size)
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      hole,
      Paint()..color = const Color(0xCC0A1210),
    );

    // Soft edge feather around the cutout.
    final feather = Paint()
      ..shader = ui.Gradient.radial(
        oval.center,
        oval.longestSide * 0.62,
        [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.18),
        ],
        [0.72, 1.0],
      );
    canvas.save();
    canvas.clipPath(Path()..addOval(oval));
    canvas.drawRect(oval.inflate(40), feather);
    canvas.restore();
  }

  void _paintGlowRings(Canvas canvas, Rect oval) {
    final outer = oval.inflate(18 + breathe * 6);
    final mid = oval.inflate(8);

    canvas.drawOval(
      outer,
      Paint()
        ..color = color.withValues(alpha: 0.10 + breathe * 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawOval(
      mid,
      Paint()
        ..color = color.withValues(alpha: faceDetected ? 0.35 : 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _paintOrbitTicks(Canvas canvas, Rect oval) {
    final ring = oval.inflate(22);
    final cx = ring.center.dx;
    final cy = ring.center.dy;
    final rx = ring.width / 2;
    final ry = ring.height / 2;
    const tickCount = 48;

    for (var i = 0; i < tickCount; i++) {
      final t = i / tickCount;
      final angle = t * math.pi * 2 + orbit * math.pi * 2;
      // Longer ticks in a traveling highlight band.
      final band = ((t + orbit) % 1.0);
      final highlight = band < 0.18
          ? 1.0 - (band / 0.18)
          : (band > 0.92 ? (band - 0.92) / 0.08 : 0.0);
      final len = 3.0 + highlight * 7.0;
      final alpha = 0.18 + highlight * 0.75;

      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final x0 = cx + cosA * rx;
      final y0 = cy + sinA * ry;
      // Normal approx for ellipse.
      final nx = cosA / rx;
      final ny = sinA / ry;
      final nLen = math.sqrt(nx * nx + ny * ny);
      final ux = nx / nLen;
      final uy = ny / nLen;

      canvas.drawLine(
        Offset(x0, y0),
        Offset(x0 + ux * len, y0 + uy * len),
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = highlight > 0.4 ? 2.0 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintMainRing(Canvas canvas, Rect oval) {
    final base = Paint()
      ..color = color.withValues(alpha: faceDetected ? 0.95 : 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = faceDetected ? 2.4 : 1.8
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(oval, base);

    // Rotating dashed accent arc.
    final dash = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      oval.inflate(1),
      orbit * math.pi * 2 - math.pi / 2,
      math.pi * 0.55,
      false,
      dash,
    );

    // Opposite shorter arc for balance.
    canvas.drawArc(
      oval.inflate(1),
      orbit * math.pi * 2 + math.pi * 0.7,
      math.pi * 0.22,
      false,
      dash..strokeWidth = 2.0,
    );
  }

  void _paintScanBeam(Canvas canvas, Rect oval) {
    if (!scanning && !faceDetected) {
      // Idle: very soft hint beam.
      _drawBeam(canvas, oval, scan, color.withValues(alpha: 0.22), height: 1.2);
      return;
    }

    final strength = scanning ? 0.85 : 0.55;
    _drawBeam(canvas, oval, scan, color.withValues(alpha: strength), height: 2.0);

    // Soft trailing gradient band.
    final y = oval.top + oval.height * scan;
    final band = Rect.fromLTRB(
      oval.left + 6,
      y - 28,
      oval.right - 6,
      y + 4,
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(oval));
    canvas.drawRect(
      band,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(band.center.dx, band.top),
          Offset(band.center.dx, band.bottom),
          [
            color.withValues(alpha: 0),
            color.withValues(alpha: scanning ? 0.22 : 0.10),
          ],
        ),
    );
    canvas.restore();
  }

  void _drawBeam(
    Canvas canvas,
    Rect oval,
    double t,
    Color c, {
    required double height,
  }) {
    final y = oval.top + oval.height * t;
    canvas.save();
    canvas.clipPath(Path()..addOval(oval));
    canvas.drawLine(
      Offset(oval.left + 10, y),
      Offset(oval.right - 10, y),
      Paint()
        ..color = c
        ..strokeWidth = height
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawLine(
      Offset(oval.left + 18, y),
      Offset(oval.right - 18, y),
      Paint()
        ..color = Colors.white.withValues(alpha: c.a * 0.7)
        ..strokeWidth = height * 0.45
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _paintLandmarkDots(Canvas canvas, Rect oval) {
    if (!faceDetected && !scanning) return;

    // Stylized facial landmark constellation (not real detection points).
    final points = <Offset>[
      Offset(oval.center.dx - oval.width * 0.18, oval.center.dy - oval.height * 0.12),
      Offset(oval.center.dx + oval.width * 0.18, oval.center.dy - oval.height * 0.12),
      Offset(oval.center.dx, oval.center.dy + oval.height * 0.02),
      Offset(oval.center.dx - oval.width * 0.12, oval.center.dy + oval.height * 0.22),
      Offset(oval.center.dx + oval.width * 0.12, oval.center.dy + oval.height * 0.22),
      Offset(oval.center.dx, oval.center.dy + oval.height * 0.28),
    ];

    final alpha = 0.35 + breathe * 0.35;
    for (final p in points) {
      canvas.drawCircle(
        p,
        2.2,
        Paint()..color = color.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        p,
        5.5,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    // Light connection lines between landmarks.
    final line = Paint()
      ..color = color.withValues(alpha: 0.22 + breathe * 0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..lineTo(points[5].dx, points[5].dy)
      ..lineTo(points[4].dx, points[4].dy)
      ..lineTo(points[1].dx, points[1].dy);
    canvas.drawPath(path, line);
  }

  void _paintProgress(Canvas canvas, Rect oval) {
    final p = progress;
    if (p == null || p <= 0) return;

    final track = oval.inflate(28);
    canvas.drawOval(
      track,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    canvas.drawArc(
      track,
      -math.pi / 2,
      p.clamp(0.0, 1.0) * math.pi * 2,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  void _paintLockRipple(Canvas canvas, Rect oval) {
    final t = lock;
    final ripple = oval.inflate(12 + t * 36);
    canvas.drawOval(
      ripple,
      Paint()
        ..color = color.withValues(alpha: (1 - t) * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ModernFacePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.breathe != breathe ||
        oldDelegate.orbit != orbit ||
        oldDelegate.scan != scan ||
        oldDelegate.lock != lock ||
        oldDelegate.faceDetected != faceDetected ||
        oldDelegate.scanning != scanning ||
        oldDelegate.progress != progress ||
        oldDelegate.centerYFactor != centerYFactor;
  }
}
