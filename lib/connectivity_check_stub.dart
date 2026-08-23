/// Native platforms have no equivalent to the browser's navigator.onLine
/// without adding a plugin (e.g. connectivity_plus). Rather than pull in a
/// new dependency for this, this always reports online — on native, an
/// actual offline device still gets caught by the AI request's own
/// timeout/retry handling, just without the instant fail-fast this gives
/// on web.
class ConnectivityCheck {
  static bool get isOnline => true;
}