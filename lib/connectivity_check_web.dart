import 'package:web/web.dart' as web;


class ConnectivityCheck {
  static bool get isOnline => web.window.navigator.onLine;
}