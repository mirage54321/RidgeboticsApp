class PushNotifications {
  static Future<bool> isSupported() async => false;
  static Future<String> subscriptionState() async => 'unsupported';
  static Future<String> subscribe(String teamNumber, String eventKey) async => 'unsupported';
  static Future<bool> unsubscribe() async => false;
}
