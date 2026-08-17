/// No-op fallback used on non-web builds (dart.library.io present) so the
/// app still compiles if you ever target mobile/desktop too.
class PushNotifications {
  static Future<bool> isSupported() async => false;
  static Future<String> subscriptionState() async => 'unsupported';
  static Future<String> subscribe(String teamNumber, String eventKey) async => 'unsupported';
  static Future<bool> unsubscribe() async => false;
}
