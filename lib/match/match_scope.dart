import 'package:flutter/widgets.dart';

import 'match_data_controller.dart';


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