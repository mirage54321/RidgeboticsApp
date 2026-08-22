import 'dart:async';

/// Runs [action] and automatically retries it with exponential backoff if
/// it throws an error that [isRetryable] accepts (defaults to retrying on
/// any error). Gives up and rethrows the final error after [maxAttempts]
/// total tries.
///
/// [onRetry] fires right before each wait, so a caller can update UI text
/// like "High demand — retrying (2/3)...".
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
      delay *= 2; // 3s, 6s, 12s...
    }
  }
}

/// Matches the "experiencing high demand" exception thrown by
/// AiService/AiRulesService when Gemini returns a quota/rate-limit error.
bool isHighDemandError(Object error) =>
    error.toString().contains('experiencing high demand');