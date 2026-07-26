import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'constants.dart';


class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({super.key});

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  StreamSubscription<AccelerometerEvent>? _accelSub;

  double _pitchDegrees = 0;
  static const double _levelToleranceDeg = 8;
  bool get _isLevel => _pitchDegrees.abs() <= _levelToleranceDeg;

  double _brightness = 0;
  bool get _isWellLit => _brightness >= 60 && _brightness <= 220;

  double _sharpness = 0;
  static const double _sharpnessThreshold = 8.0;
  bool get _isSharpEnough => _sharpness >= _sharpnessThreshold;

  bool get _allGood => _isLevel && _isWellLit && _isSharpEnough;

  bool _isStreamBusy = false;
  bool _isCapturing = false;
  bool _initError = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;

  DateTime? _goodSince;
  double _goodConditionProgress = 0;
  static const Duration _requiredGoodDuration = Duration(milliseconds: 1400);

  String get _statusMessage {
    if (_isCapturing) return 'Capturing...';
    if (!_isLevel) {
      return _pitchDegrees > 0 ? 'Tilt the phone down a bit' : 'Tilt the phone up a bit';
    }
    if (!_isWellLit) {
      return _brightness < 60 ? 'Find better lighting' : 'Too much glare — reduce light';
    }
    if (!_isSharpEnough) return 'Hold steady / adjust distance';
    return 'Hold still...';
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() {
        _initError = true;
        _permissionDenied = true;
        _permissionPermanentlyDenied = status.isPermanentlyDenied;
      });
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _initError = true);
        return;
      }
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() => _controller = controller);
      await controller.startImageStream(_onFrame);

      _accelSub = accelerometerEventStream().listen(_onAccel);
    } catch (_) {
      if (mounted) setState(() => _initError = true);
    }
  }

  void _onAccel(AccelerometerEvent event) {

    final pitchRad =
        math.atan2(-event.x, math.sqrt(event.y * event.y + event.z * event.z));
    final pitchDeg = pitchRad * 180 / math.pi;
    if (!mounted) return;
    setState(() => _pitchDegrees = pitchDeg);
    _evaluateGoodCondition();
  }

  void _onFrame(CameraImage image) {
    if (_isStreamBusy || _isCapturing) return;
    _isStreamBusy = true;
    try {
      final yPlane = image.planes[0];
      final bytes = yPlane.bytes;
      final width = image.width;
      final height = image.height;
      final bytesPerRow = yPlane.bytesPerRow;

      const step = 12;
      int sum = 0;
      int count = 0;
      int sharpnessSum = 0;
      int sharpnessCount = 0;

      for (int y = step; y < height - step; y += step) {
        final rowStart = y * bytesPerRow;
        for (int x = step; x < width - step; x += step) {
          final idx = rowStart + x;
          if (idx >= bytes.length) continue;
          final val = bytes[idx];
          sum += val;
          count++;

          final rightIdx = idx + step;
          if (rightIdx < bytes.length) {
            sharpnessSum += (val - bytes[rightIdx]).abs();
            sharpnessCount++;
          }
        }
      }

      final avgBrightness = count == 0 ? 0.0 : sum / count;
      final avgSharpness = sharpnessCount == 0 ? 0.0 : sharpnessSum / sharpnessCount;

      if (mounted) {
        setState(() {
          _brightness = avgBrightness;
          _sharpness = avgSharpness;
        });
        _evaluateGoodCondition();
      }
    } catch (_) {
    } finally {
      _isStreamBusy = false;
    }
  }

  void _evaluateGoodCondition() {
    if (_isCapturing) return;
    if (_allGood) {
      _goodSince ??= DateTime.now();
      final elapsed = DateTime.now().difference(_goodSince!);
      final progress =
          (elapsed.inMilliseconds / _requiredGoodDuration.inMilliseconds).clamp(0.0, 1.0);
      if (progress != _goodConditionProgress) {
        setState(() => _goodConditionProgress = progress);
      }
      if (progress >= 1.0) {
        _captureNow();
      }
    } else {
      _goodSince = null;
      if (_goodConditionProgress != 0) {
        setState(() => _goodConditionProgress = 0);
      }
    }
  }

  Future<void> _captureNow() async {
    if (_isCapturing || _controller == null) return;
    setState(() => _isCapturing = true);
    try {
      await _controller!.stopImageStream();
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.pop(context, bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCapturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $e')),
      );
      try {
        await _controller?.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  Future<void> _captureManually() async {
    _goodSince = null;
    await _captureNow();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_initError)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        _permissionDenied
                            ? 'Camera access is needed to take a guided photo.'
                            : 'Could not access the camera.',
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                      if (_permissionPermanentlyDenied) ...[
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: () => openAppSettings(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TealScan,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Open Settings'),
                        ),
                      ] else if (_permissionDenied) ...[
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _initError = false;
                              _permissionDenied = false;
                            });
                            _init();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TealScan,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Try again'),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else if (controller != null && controller.value.isInitialized)
              Positioned.fill(child: CameraPreview(controller))
            else
              const Center(child: CircularProgressIndicator(color: TealScan)),
            Positioned(
              top: 10,
              left: 10,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
            if (!_initError) ...[
              _buildGuideOverlay(),
              _buildStatusBar(),
              _buildManualButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGuideOverlay() {
    return Center(
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _allGood ? const Color(0xFF00B3AC) : Colors.white.withValues(alpha: 0.6),
                width: _allGood ? 3 : 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _statusMessage,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          if (_allGood && !_isCapturing) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _goodConditionProgress,
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                  color: const Color(0xFF00B3AC),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManualButton() {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _isCapturing ? null : _captureManually,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.white54, width: 4),
            ),
            child: _isCapturing
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: TealScan, strokeWidth: 3),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}