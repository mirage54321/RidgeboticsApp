import 'dart:js_interop';

/// Thin Dart wrapper around window.matchPush (see web/push.js), using
/// dart:js_interop static bindings — no extra pub package needed, and no
/// avoid_web_libraries_in_flutter lint, unlike dart:html/dart:js_util.
///
/// IMPORTANT: this only works if web/push.js is actually loaded on the
/// page. Add this to web/index.html, before the Flutter bootstrap script:
///   <script src="push.js"></script>

@JS('matchPush.isSupported')
external JSPromise<JSBoolean> _isSupportedJS();

@JS('matchPush.subscriptionState')
external JSPromise<JSString> _subscriptionStateJS();

@JS('matchPush.subscribe')
external JSPromise<JSBoolean> _subscribeJS(
  JSString vapidKey,
  JSString teamNumber,
  JSString eventKey,
  JSString backendBase,
);

@JS('matchPush.unsubscribe')
external JSPromise<JSBoolean> _unsubscribeJS(JSString backendBase);

class PushNotifications {
  // Replace with the public key printed by `npx web-push generate-vapid-keys`.
  static const String vapidPublicKey = 'YOUR_VAPID_PUBLIC_KEY_HERE';
  static const String backendBase = 'https://ridgeboticsapp.onrender.com';

  static Future<bool> isSupported() async {
    try {
      final result = await _isSupportedJS().toDart;
      return result.toDart;
    } catch (_) {
      // window.matchPush isn't loaded yet, or this browser doesn't support it
      return false;
    }
  }

  /// Returns 'subscribed', 'unsubscribed', or 'unsupported'.
  static Future<String> subscriptionState() async {
    try {
      final result = await _subscriptionStateJS().toDart;
      return result.toDart;
    } catch (_) {
      return 'unsupported';
    }
  }

  static Future<bool> subscribe(String teamNumber, String eventKey) async {
    try {
      final result = await _subscribeJS(
        vapidPublicKey.toJS,
        teamNumber.toJS,
        eventKey.toJS,
        backendBase.toJS,
      ).toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> unsubscribe() async {
    try {
      final result = await _unsubscribeJS(backendBase.toJS).toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }
}