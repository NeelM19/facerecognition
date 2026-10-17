import 'dart:math' as math;

/// How the user completed liveness (for logging / UI).
enum LivenessPassMethod { blinkAndHeadTurn }

enum _LivenessStep { blink, turnLeft, turnRight }

/// Challenge-response anti-spoofing.
///
/// A still photo / gallery image held to the camera previously passed because:
/// - blink used nearly identical open/closed gates (noise looked like a blink)
/// - OR a tiny ~12° phone tilt counted as a head turn
///
/// This tracker requires **both** a real blink **and** a directed head turn
/// (random left/right), with stricter thresholds and a return-to-center.
class LivenessTracker {
  LivenessTracker({math.Random? random}) : _random = random ?? math.Random() {
    _buildChallengeOrder();
  }

  final math.Random _random;

  bool completed = false;
  LivenessPassMethod? passMethod;

  /// Current user-facing instruction for the active challenge.
  String prompt = 'Look at the camera';

  /// Latest eye-open average for UI/debug (null if unavailable).
  double? lastEyeOpen;

  /// Human-readable blink progress for the status line.
  String blinkHint = 'Look at the camera with eyes open';

  /// True once the user has made progress on any challenge (or finished).
  bool get hasProgress =>
      completed ||
      _stepIndex > 0 ||
      _blinkSawOpen ||
      _blinkSawClosed ||
      _turnSawFrontal ||
      _turnSawTarget;

  late List<_LivenessStep> _steps;
  int _stepIndex = 0;

  // --- Blink state ---
  bool _blinkSawOpen = false;
  bool _blinkSawClosed = false;
  int _openFrames = 0;
  int _closedFrames = 0;
  double _peakOpen = 0;
  double _troughOpen = 1;
  DateTime? _closedAt;

  // --- Head turn state ---
  bool _turnSawFrontal = false;
  bool _turnSawTarget = false;
  int _frontalFrames = 0;
  int _targetFrames = 0;

  // --- Motion / static spoof heuristic ---
  double? _prevYaw;
  double? _prevFaceCx;
  double? _prevFaceCy;
  double _motionBudget = 0;
  int _staticFrames = 0;

  // Glasses-friendly gates: absolute levels are softer; a relative drop from
  // the user's own open baseline is what confirms a blink (specs often never
  // reach "textbook" closed scores).
  static const _openGate = 0.40;
  static const _closedGate = 0.36;
  static const _dropGate = 0.18;
  static const _recoverGate = 0.06;
  static const _minOpenFrames = 1;
  static const _minClosedFrames = 1;
  static const _minClosedMs = 35;

  static const _frontalYaw = 8.0;
  static const _targetYaw = 22.0;
  static const _minFrontalFrames = 2;
  static const _minTargetFrames = 3;

  /// Reject if face pose barely changes while a motion challenge is active.
  static const _staticFrameLimit = 45;
  static const _minMotionForTurn = 6.0;

  void _buildChallengeOrder() {
    final turn =
        _random.nextBool() ? _LivenessStep.turnLeft : _LivenessStep.turnRight;
    // Randomize order so a replayed video / scripted tilt is harder.
    if (_random.nextBool()) {
      _steps = [_LivenessStep.blink, turn];
    } else {
      _steps = [turn, _LivenessStep.blink];
    }
    _stepIndex = 0;
    _syncPrompt();
  }

  void resetProgress() {
    completed = false;
    passMethod = null;
    _blinkSawOpen = false;
    _blinkSawClosed = false;
    _openFrames = 0;
    _closedFrames = 0;
    _peakOpen = 0;
    _troughOpen = 1;
    _closedAt = null;
    _turnSawFrontal = false;
    _turnSawTarget = false;
    _frontalFrames = 0;
    _targetFrames = 0;
    _prevYaw = null;
    _prevFaceCx = null;
    _prevFaceCy = null;
    _motionBudget = 0;
    _staticFrames = 0;
    lastEyeOpen = null;
    blinkHint = 'Look at the camera with eyes open';
    _buildChallengeOrder();
  }

  _LivenessStep get _currentStep => _steps[_stepIndex];

  void _syncPrompt() {
    switch (_currentStep) {
      case _LivenessStep.blink:
        prompt = 'Blink both eyes (glasses OK)';
        blinkHint = 'Eyes open — now blink';
      case _LivenessStep.turnLeft:
        prompt = 'Turn your head LEFT, then face the camera';
        blinkHint = prompt;
      case _LivenessStep.turnRight:
        prompt = 'Turn your head RIGHT, then face the camera';
        blinkHint = prompt;
    }
  }

  void _advanceStep() {
    _stepIndex++;
    if (_stepIndex >= _steps.length) {
      completed = true;
      passMethod = LivenessPassMethod.blinkAndHeadTurn;
      prompt = 'Liveness OK';
      blinkHint = 'Liveness OK';
      return;
    }
    // Reset per-challenge counters when moving to the next challenge.
    _blinkSawOpen = false;
    _blinkSawClosed = false;
    _openFrames = 0;
    _closedFrames = 0;
    _peakOpen = 0;
    _troughOpen = 1;
    _closedAt = null;
    _turnSawFrontal = false;
    _turnSawTarget = false;
    _frontalFrames = 0;
    _targetFrames = 0;
    _staticFrames = 0;
    _motionBudget = 0;
    _syncPrompt();
  }

  /// Feed one face observation. Returns true when liveness just completed.
  ///
  /// Optional [faceCenterX]/[faceCenterY] (normalized 0..1) improve the
  /// static-photo heuristic when available.
  bool observe({
    required double? leftEyeOpen,
    required double? rightEyeOpen,
    required double? yawDegrees,
    double? faceCenterX,
    double? faceCenterY,
  }) {
    if (completed) return false;

    _trackMotion(
      yawDegrees: yawDegrees,
      faceCenterX: faceCenterX,
      faceCenterY: faceCenterY,
    );

    final step = _currentStep;
    final done = switch (step) {
      _LivenessStep.blink => _observeBlink(leftEyeOpen, rightEyeOpen),
      _LivenessStep.turnLeft =>
        _observeDirectedTurn(yawDegrees, targetSign: -1),
      _LivenessStep.turnRight =>
        _observeDirectedTurn(yawDegrees, targetSign: 1),
    };

    if (!done) {
      // During a turn challenge, a perfectly still photo rarely accumulates
      // enough motion; after enough static frames, soft-reset the turn step.
      if (step != _LivenessStep.blink &&
          _staticFrames >= _staticFrameLimit &&
          _motionBudget < _minMotionForTurn) {
        _resetTurnOnly();
        blinkHint = 'Move naturally — static image rejected';
        prompt = blinkHint;
      }
      return false;
    }

    _advanceStep();
    return completed;
  }

  void _resetTurnOnly() {
    _turnSawFrontal = false;
    _turnSawTarget = false;
    _frontalFrames = 0;
    _targetFrames = 0;
    _staticFrames = 0;
    _motionBudget = 0;
    _syncPrompt();
  }

  void _trackMotion({
    required double? yawDegrees,
    double? faceCenterX,
    double? faceCenterY,
  }) {
    var delta = 0.0;
    if (yawDegrees != null && _prevYaw != null) {
      delta += (yawDegrees - _prevYaw!).abs();
    }
    if (faceCenterX != null && _prevFaceCx != null) {
      delta += (faceCenterX - _prevFaceCx!).abs() * 80;
    }
    if (faceCenterY != null && _prevFaceCy != null) {
      delta += (faceCenterY - _prevFaceCy!).abs() * 80;
    }

    if (yawDegrees != null) _prevYaw = yawDegrees;
    if (faceCenterX != null) _prevFaceCx = faceCenterX;
    if (faceCenterY != null) _prevFaceCy = faceCenterY;

    if (delta < 0.35) {
      _staticFrames++;
    } else {
      _staticFrames = 0;
      _motionBudget += delta;
    }
  }

  bool _observeBlink(double? left, double? right) {
    if (left == null && right == null) {
      blinkHint = 'Move closer — eyes not tracked yet';
      lastEyeOpen = null;
      return false;
    }

    final opens = <double>[?left, ?right];
    final avg = opens.reduce((a, b) => a + b) / opens.length;
    // Prefer the more-closed eye so partial / glasses-occluded blinks still
    // register (one lens often tracks worse than the other).
    final minOpen = opens.reduce((a, b) => a < b ? a : b);
    final maxOpen = opens.reduce((a, b) => a > b ? a : b);
    lastEyeOpen = avg;

    if (!_blinkSawClosed && avg > _peakOpen) _peakOpen = avg;

    // Phase 3: eyes were closed — only wait for re-open (do NOT keep matching
    // "closed" via relativeDrop, or recovery never finishes and punch stalls).
    if (_blinkSawClosed) {
      final riseFromTrough = avg - _troughOpen;
      final strongRise = maxOpen - _troughOpen;
      final recovered = riseFromTrough >= _recoverGate ||
          strongRise >= _recoverGate ||
          avg >= _openGate ||
          maxOpen >= _openGate ||
          (_peakOpen > 0 && avg >= _peakOpen - _recoverGate);

      if (!recovered) {
        blinkHint = 'Blink seen — open eyes again';
        return false;
      }

      _openFrames++;
      if (_openFrames < _minOpenFrames) {
        blinkHint = 'Open your eyes again…';
        return false;
      }

      final closedMs = _closedAt == null
          ? _minClosedMs
          : DateTime.now().difference(_closedAt!).inMilliseconds;
      if (closedMs < _minClosedMs) {
        blinkHint = 'Open your eyes again…';
        return false;
      }
      // Very long "closed" is fine with glasses lag — still accept reopen.
      blinkHint = 'Blink OK';
      return true;
    }

    // Phase 1: establish open eyes.
    final looksOpen = avg >= _openGate || maxOpen >= (_openGate + 0.05);
    if (!_blinkSawOpen) {
      if (looksOpen) {
        _openFrames++;
        if (_openFrames >= _minOpenFrames) {
          _blinkSawOpen = true;
          blinkHint = 'Eyes open — now blink';
        } else {
          blinkHint = 'Hold eyes open…';
        }
      } else {
        blinkHint = 'Open your eyes, then blink (glasses OK)';
      }
      return false;
    }

    // Phase 2: look for a close / relative drop (only before closed is locked).
    final relativeDrop = _peakOpen > 0 ? (_peakOpen - minOpen) : 0.0;
    final looksClosed = minOpen <= _closedGate ||
        relativeDrop >= _dropGate ||
        avg <= _peakOpen - _dropGate;

    if (looksClosed) {
      _closedFrames++;
      _openFrames = 0;
      if (minOpen < _troughOpen) _troughOpen = minOpen;
      if (_closedFrames >= _minClosedFrames) {
        _blinkSawClosed = true;
        _closedAt = DateTime.now();
        blinkHint = 'Blink seen — open eyes again';
      } else {
        blinkHint = 'Keep blinking…';
      }
      return false;
    }

    blinkHint = 'Blink now';
    return false;
  }

  /// Require frontal → clear yaw in [targetSign] direction → frontal again.
  bool _observeDirectedTurn(double? yaw, {required int targetSign}) {
    if (yaw == null) {
      blinkHint = 'Face the camera so head pose can be tracked';
      return false;
    }

    final dirLabel = targetSign < 0 ? 'LEFT' : 'RIGHT';

    if (!_turnSawFrontal) {
      if (yaw.abs() < _frontalYaw) {
        _frontalFrames++;
        if (_frontalFrames >= _minFrontalFrames) {
          _turnSawFrontal = true;
          blinkHint = 'Now turn your head $dirLabel';
        } else {
          blinkHint = 'Face the camera straight';
        }
      } else {
        _frontalFrames = 0;
        blinkHint = 'Face the camera straight first';
      }
      return false;
    }

    if (!_turnSawTarget) {
      final towardTarget = targetSign < 0 ? yaw < -_targetYaw : yaw > _targetYaw;
      if (towardTarget) {
        _targetFrames++;
        if (_targetFrames >= _minTargetFrames) {
          _turnSawTarget = true;
          blinkHint = 'Good — face the camera again';
        } else {
          blinkHint = 'Keep turning $dirLabel…';
        }
      } else {
        _targetFrames = 0;
        // Wrong direction does not count.
        if (targetSign < 0 && yaw > _targetYaw) {
          blinkHint = 'Wrong way — turn LEFT';
        } else if (targetSign > 0 && yaw < -_targetYaw) {
          blinkHint = 'Wrong way — turn RIGHT';
        } else {
          blinkHint = 'Turn your head $dirLabel';
        }
      }
      return false;
    }

    // Return to center to complete the turn challenge.
    if (yaw.abs() < _frontalYaw) {
      _frontalFrames++;
      if (_frontalFrames >= _minFrontalFrames) {
        blinkHint = 'Head turn OK';
        return true;
      }
      blinkHint = 'Hold facing the camera…';
    } else {
      _frontalFrames = 0;
      blinkHint = 'Face the camera again';
    }
    return false;
  }
}
