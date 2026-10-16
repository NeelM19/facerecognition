/// How the user completed liveness (for logging / UI).
enum LivenessPassMethod { blink, headTurn }

/// Anti-spoof tracker: passes when the user **blinks** OR **turns their head
/// left/right** (any direction).
class LivenessTracker {
  bool completed = false;
  LivenessPassMethod? passMethod;

  static const instruction =
      'Blink both eyes, or turn your head left/right';

  /// Blink: open → closed → open (lenient thresholds; blinks are short).
  bool _blinkSawOpen = false;
  bool _blinkSawClosed = false;
  double _peakOpen = 0;

  /// Head turn: near-frontal, then clear yaw either way.
  bool _turnSawFrontal = false;

  /// Latest eye-open average for UI/debug (null if unavailable).
  double? lastEyeOpen;

  /// Human-readable blink progress for the status line.
  String blinkHint = 'Look at the camera with eyes open';

  void resetProgress() {
    completed = false;
    passMethod = null;
    _blinkSawOpen = false;
    _blinkSawClosed = false;
    _peakOpen = 0;
    _turnSawFrontal = false;
    lastEyeOpen = null;
    blinkHint = 'Look at the camera with eyes open';
  }

  /// Feed one face observation. Returns true when liveness just completed.
  bool observe({
    required double? leftEyeOpen,
    required double? rightEyeOpen,
    required double? yawDegrees,
  }) {
    if (completed) return false;

    if (_observeBlink(leftEyeOpen, rightEyeOpen)) {
      completed = true;
      passMethod = LivenessPassMethod.blink;
      blinkHint = 'Blink OK';
      return true;
    }
    if (_observeTurnAnyDirection(yawDegrees)) {
      completed = true;
      passMethod = LivenessPassMethod.headTurn;
      return true;
    }
    return false;
  }

  bool _observeBlink(double? left, double? right) {
    if (left == null && right == null) {
      blinkHint = 'Move closer — eyes not tracked yet';
      lastEyeOpen = null;
      return false;
    }

    // Prefer the more-closed eye so a partial blink still registers.
    final opens = <double>[
      if (left != null) left,
      if (right != null) right,
    ];
    final avg = opens.reduce((a, b) => a + b) / opens.length;
    final minOpen = opens.reduce((a, b) => a < b ? a : b);
    lastEyeOpen = avg;

    // Track peak while looking open.
    if (avg > _peakOpen) _peakOpen = avg;

    // Lenient gates: natural blinks are ~100–300ms and often miss harsh cutoffs.
    const openGate = 0.48;
    const closedGate = 0.45;
    const dropGate = 0.18;

    final looksOpen = avg >= openGate && minOpen >= 0.40;
    final looksClosed = minOpen <= closedGate ||
        (_peakOpen - minOpen) >= dropGate ||
        avg <= closedGate;

    if (looksOpen) {
      if (_blinkSawClosed && _blinkSawOpen) {
        return true;
      }
      _blinkSawOpen = true;
      blinkHint = _blinkSawClosed
          ? 'Open your eyes again…'
          : 'Eyes open — now blink';
      return false;
    }

    if (looksClosed && _blinkSawOpen) {
      _blinkSawClosed = true;
      blinkHint = 'Blink seen — open eyes again';
      return false;
    }

    if (!_blinkSawOpen) {
      blinkHint = 'Open your eyes clearly, then blink';
    }
    return false;
  }

  /// Accept a meaningful turn left **or** right after a frontal pose.
  bool _observeTurnAnyDirection(double? yaw) {
    if (yaw == null) return false;

    if (yaw.abs() < 10) {
      _turnSawFrontal = true;
      return false;
    }
    if (!_turnSawFrontal) return false;

    // Slightly easier turn (~12°) either direction.
    return yaw.abs() > 12;
  }
}
