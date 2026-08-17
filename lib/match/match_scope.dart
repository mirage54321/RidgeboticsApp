import 'package:flutter/widgets.dart';

import 'match_data_controller.dart';

/// Makes a single [MatchDataController] available to the shell and every
/// tab beneath it, without adding a state-management package as a
/// dependency. Access it anywhere below with `MatchScope.of(context)`.
class MatchScope extends InheritedNotifier<MatchDataController> {
  const MatchScope({
    super.key,
    required MatchDataController controller,
    required super.child,
  }) : super(notifier: controller);

  static MatchDataController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MatchScope>();
    assert(scope != null, 'MatchScope.of() called with no MatchScope ancestor');
    return scope!.notifier!;
  }
}