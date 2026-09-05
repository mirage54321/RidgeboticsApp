import 'dart:async';


Future<T> withBackoffRetry<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 3),
  bool Function(Object error)? isRetryable,
  void Function(int attempt, int maxAttempts, Duration nextDelay)? onRetry,
}) async {
  var attempt = 0;
  var delay = initialDelay;

  while (true) {
    attempt++;
    try {
      return await action();
    } catch (e) {
      final shouldRetry = isRetryable?.call(e) ?? true;
      if (!shouldRetry || attempt >= maxAttempts) {
        rethrow;
      }
      onRetry?.call(attempt, maxAttempts, delay);
      await Future.delayed(delay);
      delay *= 2;
    }
  }
}


bool isHighDemandError(Object error) =>
    error.toString().contains('experiencing high demand');