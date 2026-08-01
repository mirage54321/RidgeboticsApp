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

  static Future<bool> requestMotionAccess() async {
    final deviceMotionCtor = web.window.getProperty<JSAny?>('DeviceMotionEvent'.toJS);
    if (deviceMotionCtor == null) return true;
    if (deviceMotionCtor is! JSObject) return true;
    final ctorObj = deviceMotionCtor;
    if (!ctorObj.has('requestPermission')) return true;
    try {
      final resultPromise = ctorObj.callMethod<JSPromise?>('requestPermission'.toJS);
      if (resultPromise == null) return true;
      final result = await resultPromise.toDart;
      final resultStr = (result as JSString).toDart;
      return resultStr == 'granted';
    } catch (_) {
      return true;
    }
  }

  static void watchTilt(void Function(double pitchDeg) onTilt) {
    stopTilt();
    void handler(web.Event event) {
      final motion = event as web.DeviceMotionEvent;
      final gravity = motion.accelerationIncludingGravity;
      if (gravity == null) return;
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
  }

  static void stopTilt() {
    final handler = motionHandler;
    if (handler != null) {
      web.window.removeEventListener('devicemotion', handler);
      motionHandler = null;
    }
  }

  static void watchFrame(void Function(double brightness, double sharpness) onFrame) {
    stopFrame();
    try {
      final videoElement = web.document.querySelector('video');
      if (videoElement == null) {
        print('WebProbe: no <video> element found yet');
        return;
      }
      final video = videoElement as web.HTMLVideoElement;

      const sampleWidth = 160;
      const sampleHeight = 120;
      final sampleCanvas = web.HTMLCanvasElement()
        ..width = sampleWidth
        ..height = sampleHeight;
      canvas = sampleCanvas;

      final rawCtx = sampleCanvas.getContext('2d');
      if (rawCtx == null) {
        print('WebProbe: getContext(2d) returned null');
        return;
      }
      final ctx = rawCtx as web.CanvasRenderingContext2D;

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
          onFrame(brightness, sharpness);
        } catch (e) {
          // ignore: avoid_print
          print('WebProbe frame sample failed: $e');
        }
      });
    } catch (e) {
      // ignore: avoid_print
      print('WebProbe.watchFrame setup failed: $e');
    }
  }

  static void stopFrame() {
    frameTimer?.cancel();
    frameTimer = null;
    canvas = null;
  }
}