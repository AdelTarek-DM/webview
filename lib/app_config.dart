import 'package:flutter/foundation.dart';

/// Runtime config injected at build time via `--dart-define`.
///
/// This keeps secrets out of source control (but note: `--dart-define` values
/// are still recoverable from the APK by a motivated attacker).
class AppConfig {
  static const String tokenApiUrl = String.fromEnvironment('TOKEN_API_URL');
  static const String tokenApiAuthHeader =
      String.fromEnvironment('TOKEN_API_AUTH_HEADER');
  static const String clientId = String.fromEnvironment('CLIENT_ID');
  static const String clientSecret = String.fromEnvironment('CLIENT_SECRET');

  static const String webBaseUrl = String.fromEnvironment('WEB_BASE_URL');

  static void validate() {
    final missing = <String>[];
    if (tokenApiUrl.isEmpty) missing.add('TOKEN_API_URL');
    if (tokenApiAuthHeader.isEmpty) missing.add('TOKEN_API_AUTH_HEADER');
    if (clientId.isEmpty) missing.add('CLIENT_ID');
    if (clientSecret.isEmpty) missing.add('CLIENT_SECRET');
    if (webBaseUrl.isEmpty) missing.add('WEB_BASE_URL');

    if (missing.isNotEmpty) {
      // Fail fast in debug; in release we keep running but will error later.
      if (kDebugMode) {
        throw StateError('Missing dart-defines: ${missing.join(', ')}');
      }
    }
  }
}

