import 'package:facerecognition/core/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime match gates. Defaults mirror [AppConstants].
class MatchThresholdConfig {
  const MatchThresholdConfig({
    required this.clearMinSimilarity,
    required this.clearMaxDistance,
    required this.maskedMinSimilarity,
    required this.maskedMaxDistance,
    required this.occludedMinSimilarity,
    required this.occludedMaxDistance,
  });

  final double clearMinSimilarity;
  final double clearMaxDistance;
  final double maskedMinSimilarity;
  final double maskedMaxDistance;
  final double occludedMinSimilarity;
  final double occludedMaxDistance;

  static const defaults = MatchThresholdConfig(
    clearMinSimilarity: AppConstants.punchMatchThreshold,
    clearMaxDistance: AppConstants.punchMaxDistance,
    maskedMinSimilarity: AppConstants.punchMaskedMatchThreshold,
    maskedMaxDistance: AppConstants.punchMaskedMaxDistance,
    occludedMinSimilarity: AppConstants.punchOccludedMatchThreshold,
    occludedMaxDistance: AppConstants.punchOccludedMaxDistance,
  );

  MatchThresholdConfig copyWith({
    double? clearMinSimilarity,
    double? clearMaxDistance,
    double? maskedMinSimilarity,
    double? maskedMaxDistance,
    double? occludedMinSimilarity,
    double? occludedMaxDistance,
  }) {
    return MatchThresholdConfig(
      clearMinSimilarity: clearMinSimilarity ?? this.clearMinSimilarity,
      clearMaxDistance: clearMaxDistance ?? this.clearMaxDistance,
      maskedMinSimilarity: maskedMinSimilarity ?? this.maskedMinSimilarity,
      maskedMaxDistance: maskedMaxDistance ?? this.maskedMaxDistance,
      occludedMinSimilarity:
          occludedMinSimilarity ?? this.occludedMinSimilarity,
      occludedMaxDistance: occludedMaxDistance ?? this.occludedMaxDistance,
    );
  }

  Map<String, double> toMap() => {
        'clearMinSimilarity': clearMinSimilarity,
        'clearMaxDistance': clearMaxDistance,
        'maskedMinSimilarity': maskedMinSimilarity,
        'maskedMaxDistance': maskedMaxDistance,
        'occludedMinSimilarity': occludedMinSimilarity,
        'occludedMaxDistance': occludedMaxDistance,
      };
}

class MatchThresholdStore {
  MatchThresholdStore(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'match_threshold_';

  MatchThresholdConfig load() {
    double read(String key, double fallback) =>
        _prefs.getDouble('$_prefix$key') ?? fallback;

    final d = MatchThresholdConfig.defaults;
    return MatchThresholdConfig(
      clearMinSimilarity: read('clearMinSimilarity', d.clearMinSimilarity),
      clearMaxDistance: read('clearMaxDistance', d.clearMaxDistance),
      maskedMinSimilarity: read('maskedMinSimilarity', d.maskedMinSimilarity),
      maskedMaxDistance: read('maskedMaxDistance', d.maskedMaxDistance),
      occludedMinSimilarity:
          read('occludedMinSimilarity', d.occludedMinSimilarity),
      occludedMaxDistance: read('occludedMaxDistance', d.occludedMaxDistance),
    );
  }

  Future<void> save(MatchThresholdConfig config) async {
    for (final entry in config.toMap().entries) {
      await _prefs.setDouble('$_prefix${entry.key}', entry.value);
    }
  }

  Future<void> reset() async => save(MatchThresholdConfig.defaults);
}
