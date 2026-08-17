import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:web/web.dart' as web;

class WebProbe {
  static JSFunction? motionHandler;
  static Timer? frameTimer;
  static web.HTMLCanvasElement? canvas;
  static final List<String> debugLog = [];

  static void log(String msg) {
    debugLog.add(msg);
    if (debugLog.length > 5) debugLog.removeAt(0);
  }

  static Future<bool> requestMotionAccess() async {
    final deviceMotionCtor =
        web.window.getProperty<JSObject?>('DeviceMotionEvent'.toJS);
    if (deviceMotionCtor == null) {
      log('no DeviceMotionEvent');
      return true;
    }
    if (!deviceMotionCtor.has('requestPermission')) {
      log('no requestPermission fn (non-iOS)');
      return true;
    }
    try {
      final resultPromise = deviceMotionCtor
          .callMethod<JSPromise<JSString>?>('requestPermission'.toJS);
      if (resultPromise == null) {
        log('requestPermission returned null');
        return true;
      }
      final result = await resultPromise.toDart;
      final resultStr = result.toDart;
      log('motion permission: $resultStr');
      return resultStr == 'granted';
    } catch (e) {
      log('motion permission threw: $e');
      return true;
    }
  }

  static void watchTilt(void Function(double pitchDeg) onTilt) {
    stopTilt();
    bool loggedFirst = false;
    void handler(web.Event event) {
      if (!loggedFirst) {
        log('devicemotion fired');
        loggedFirst = true;
      }
      final motion = event as web.DeviceMotionEvent;
      final gravity = motion.accelerationIncludingGravity;
      if (gravity == null) {
        log('accelerationIncludingGravity null');
        return;
      }
      final x = gravity.x ?? 0;
      final y = gravity.y ?? 0;
      final z = gravity.z ?? 0;
      if (x == 0 && y == 0 && z == 0) return;
      final pitchRad = math.atan2(-x, math.sqrt(y * y + z * z));
      onTilt(pitchRad * 180 / math.pi);
    }

    final jsHandler = handler.toJS;
    motionHandler = jsHandler;
    web.window.addEventListener('devicemotion', jsHandler);
    log('devicemotion listener attached');
  }

  static void stopTilt() {
    final handler = motionHandler;
    if (handler != null) {
      web.window.removeEventListener('devicemotion', handler);
      motionHandler = null;
    }
  }

  static Timer? findVideoTimer;

  static void watchFrame(void Function(double brightness, double sharpness) onFrame) {
    stopFrame();
    int attempts = 0;
    const maxAttempts = 20;
    findVideoTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      attempts++;
      final videoElement = web.document.querySelector('video');
      if (videoElement == null) {
        if (attempts >= maxAttempts) {
          log('gave up finding <video> after $attempts tries');
          timer.cancel();
        }
        return;
      }
      timer.cancel();
      log('video found after $attempts tries');
      setUpSampling(videoElement as web.HTMLVideoElement, onFrame);
    });
  }

  static void setUpSampling(
    web.HTMLVideoElement video,
    void Function(double brightness, double sharpness) onFrame,
  ) {
    try {
      const sampleWidth = 160;
      const sampleHeight = 120;
      final sampleCanvas = web.HTMLCanvasElement()
        ..width = sampleWidth
        ..height = sampleHeight;
      canvas = sampleCanvas;

      final rawCtx = sampleCanvas.getContext('2d');
      if (rawCtx == null) {
        log('getContext(2d) returned null');
        return;
      }
      final ctx = rawCtx as web.CanvasRenderingContext2D;
      log('canvas+context ready');

      bool loggedFirstSample = false;
      frameTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (video.videoWidth == 0) return;
        try {
          ctx.drawImage(video, 0, 0, sampleWidth, sampleHeight);
          final imageData = ctx.getImageData(0, 0, sampleWidth, sampleHeight);
          final Uint8ClampedList data = imageData.data.toDart;

          int sum = 0;
          int count = 0;
          int sharpSum = 0;
          int sharpCount = 0;
          const stride = 16;

          for (int i = 0; i + 2 < data.length; i += stride) {
            final gray = (data[i] + data[i + 1] + data[i + 2]) ~/ 3;
            sum += gray;
            count++;

            final nextIdx = i + stride;
            if (nextIdx + 2 < data.length) {
              final grayNext = (data[nextIdx] + data[nextIdx + 1] + data[nextIdx + 2]) ~/ 3;
              sharpSum += (gray - grayNext).abs();
              sharpCount++;
            }
          }

          if (count == 0) return;
          final brightness = sum / count;
          final sharpness = sharpCount == 0 ? 0.0 : sharpSum / sharpCount;
          if (!loggedFirstSample) {
            log('first sample ok, count=$count');
            loggedFirstSample = true;
          }
          onFrame(brightness, sharpness);
        } catch (e) {
          log('sample loop threw: $e');
        }
      });
    } catch (e) {
      log('setUpSampling threw: $e');
    }
  }

  static void stopFrame() {
    findVideoTimer?.cancel();
    findVideoTimer = null;
    frameTimer?.cancel();
    frameTimer = null;
    canvas = null;
  }
}
