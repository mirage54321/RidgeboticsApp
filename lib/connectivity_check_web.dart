import 'package:web/web.dart' as web;

/// Instant, no-network-call check for whether the browser thinks it has a
/// connection. This is what lets the AI screens fail immediately with
/// "can't use when offline" instead of waiting out a full request timeout
/// first — navigator.onLine is a free, synchronous read, not a probe.
///
/// Note: this reflects "does the device have a network interface up"
/// (e.g. off in airplane mode / no wifi), not "is there actually working
/// internet on that network." A wifi network with no real internet behind
/// it will still report online=true here — that case still gets caught,
/// just by the AI request's own timeout/retry handling instead of this
/// instant check.
class ConnectivityCheck {
  static bool get isOnline => web.window.navigator.onLine;
}