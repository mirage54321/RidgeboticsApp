import 'dart:js_interop';


@JS('matchPush.isSupported')
external JSPromise<JSBoolean> _isSupportedJS();

@JS('matchPush.subscriptionState')
external JSPromise<JSString> _subscriptionStateJS();

@JS('matchPush.subscribe')
external JSPromise<JSString> _subscribeJS(
  JSString vapidKey,
  JSString teamNumber,
  JSString eventKey,
  JSString backendBase,
);

@JS('matchPush.unsubscribe')
external JSPromise<JSBoolean> _unsubscribeJS(JSString backendBase);

class PushNotifications {
  static const String vapidPublicKey = 'BHD8saPsXKCcRNcCPbgzX3VXoN0gLDnCIScORRG2RBUPASfKHNF7cCD0HRF3dyd0z2CTlz5n3lM2GUpyJSLEXKs';
  static const String backendBase = 'https://ridgeboticsapp.onrender.com';

  static Future<bool> isSupported() async {
    try {
      final result = await _isSupportedJS().toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<String> subscriptionState() async {
    try {
      final result = await _subscriptionStateJS().toDart;
      return result.toDart;
    } catch (_) {
      return 'unsupported';
    }
  }

  static Future<String> subscribe(String teamNumber, String eventKey) async {
    try {
      final result = await _subscribeJS(
        vapidPublicKey.toJS,
        teamNumber.toJS,
        eventKey.toJS,
        backendBase.toJS,
      ).toDart;
      return result.toDart;
    } catch (_) {
      return 'subscription-failed';
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
