/// No-op fallback used on non-web builds (dart.library.io present) so the
/// app still compiles if you ever target mobile/desktop too.
class PushNotifications {
  static Future<bool> isSupported() async => false;
  static Future<String> subscriptionState() async => 'unsupported';
  static Future<bool> subscribe(String teamNumber, String eventKey) async => false;
  static Future<bool> unsubscribe() async => false;
}