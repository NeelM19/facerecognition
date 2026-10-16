import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static void enroll(String message) => _log('ENROLL', message);

  static void match(String message) => _log('MATCH', message);

  static void punch(String message) => _log('PUNCH', message);

  static void update(String message) => _log('UPDATE', message);

  static void sync(String message) => _log('SYNC', message);

  static void info(String message) => _log('INFO', message);

  static void error(String message, [Object? error, StackTrace? stack]) {
    _log('ERROR', message);
    if (error != null) {
      debugPrint('[ERROR] $error');
    }
    if (stack != null) {
      debugPrint('$stack');
    }
  }

  static void _log(String tag, String message) {
    debugPrint('[$tag] $message');
  }
}
