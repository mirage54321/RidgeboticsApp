import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'constants.dart';
import 'retry_helper.dart';
import 'connectivity_check.dart';

const List<String> gridRegionNames = [
  'top-left',
  'top-center',
  'top-right',
  'middle-left',
  'center',
  'middle-right',
  'bottom-left',
  'bottom-center',
  'bottom-right',
];

class CropRegion {
  final double x;
  final double y;
  final double width;
  final double height;

  const CropRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory CropRegion.fromRegionName(String region) {
    switch (region) {
      case 'top-left':
        return const CropRegion(x: 0.0, y: 0.0, width: 0.55, height: 0.55);
      case 'top-center':
        return const CropRegion(x: 0.25, y: 0.0, width: 0.5, height: 0.5);
      case 'top-right':
        return const CropRegion(x: 0.45, y: 0.0, width: 0.55, height: 0.55);
      case 'middle-left':
        return const CropRegion(x: 0.0, y: 0.25, width: 0.55, height: 0.5);
      case 'center':
        return const CropRegion(x: 0.2, y: 0.2, width: 0.6, height: 0.6);
      case 'middle-right':
        return const CropRegion(x: 0.45, y: 0.25, width: 0.55, height: 0.5);
      case 'bottom-left':
        return const CropRegion(x: 0.0, y: 0.45, width: 0.55, height: 0.55);
      case 'bottom-center':
        return const CropRegion(x: 0.25, y: 0.5, width: 0.5, height: 0.5);
      case 'bottom-right':
        return const CropRegion(x: 0.45, y: 0.45, width: 0.55, height: 0.55);
      default:
        return const CropRegion(x: 0.0, y: 0.0, width: 1.0, height: 1.0);
    }
  }
}

class CroppedImage {
  final String base64Jpeg;
  final CropRegion region;

  const CroppedImage({required this.base64Jpeg, required this.region});
}

CroppedImage cropToRegion(Uint8List originalBytes, CropRegion region) {
  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) {
    return CroppedImage(
      base64Jpeg: base64Encode(originalBytes),
      region: const CropRegion(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
    );
  }

  final cropX = (region.x * decoded.width).round().clamp(0, decoded.width - 1);
  final cropY =
      (region.y * decoded.height).round().clamp(0, decoded.height - 1);
  final cropW =
      (region.width * decoded.width).round().clamp(1, decoded.width - cropX);
  final cropH = (region.height * decoded.height)
      .round()
      .clamp(1, decoded.height - cropY);

  final cropped = img.copyCrop(
    decoded,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );

  final jpegBytes = img.encodeJpg(cropped, quality: 85);

  return CroppedImage(
    base64Jpeg: base64Encode(jpegBytes),
    region: region,
  );
}

BoundingBox? mapBoxFromCropToFull(
  List<dynamic>? box2dInCrop,
  CropRegion region,
) {
  if (box2dInCrop == null || box2dInCrop.length != 4) return null;

  final cropBox = BoundingBox.fromBox2D(box2dInCrop);

  return BoundingBox(
    x: region.x + cropBox.x * region.width,
    y: region.y + cropBox.y * region.height,
    width: cropBox.width * region.width,
    height: cropBox.height * region.height,
  );
}

/// Called before each automatic retry so the UI can show progress,
/// e.g. "High demand — retrying (2/3)...".
typedef RetryCallback = void Function(
    int attempt, int maxAttempts, Duration nextDelay);

class AiService {
  static const String _base = 'https://ridgeboticsapp.onrender.com';

  static Future<void> reportFinding({
    required String scanId,
    required String findingId,
    required Finding finding,
    required String errorType,
    required String scanMode,
    String userComment = '',
  }) async {
    final response = await http
        .post(
          Uri.parse('$_base/reportFinding'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'scanId': scanId,
            'findingId': findingId,
            'scanMode': scanMode,
            'errorType': errorType,
            'title': finding.title,
            'description': finding.description,
            'severity': finding.severity.name,
            'userComment': userComment,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode >= 200 && response.statusCode < 300) return;

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error']?.toString() ?? 'Could not submit report');
    } catch (error) {
      if (error is Exception) rethrow;
      throw Exception('Could not submit report');
    }
  }

  /// Analyzes [imageBytes] for safety issues.
  ///
  /// If Gemini is under heavy load, this automatically retries with
  /// exponential backoff (up to [maxAttempts] total tries) instead of
  /// immediately surfacing an error. [onRetry], if provided, is called
  /// before each wait so the caller can update status text.
  static Future<List<Finding>> analyzeImage(
    Uint8List imageBytes, {
    int maxAttempts = 3,
    RetryCallback? onRetry,
  }) async {
    if (!ConnectivityCheck.isOnline) {
      throw Exception('offline');
    }

    // Crop once up front and reuse across retries — no need to redo the
    // (relatively expensive) image cropping on every attempt.
    final crops = {
      for (final name in gridRegionNames)
        name: cropToRegion(imageBytes, CropRegion.fromRegionName(name)),
    };

    return withBackoffRetry<List<Finding>>(
      () => _analyzeOnce(crops),
      maxAttempts: maxAttempts,
      initialDelay: const Duration(seconds: 3),
      isRetryable: isHighDemandError,
      onRetry: onRetry,
    );
  }

  static Future<List<Finding>> _analyzeOnce(
      Map<String, CroppedImage> crops) async {
    final parts = <Map<String, dynamic>>[
      {'text': _promptText},
    ];
    for (final name in gridRegionNames) {
      parts.add({'text': 'Region: $name'});
      parts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': crops[name]!.base64Jpeg,
        }
      });
    }

    final body = {
      'contents': [
        {'parts': parts}
      ],
      'generationConfig': {
        'temperature': 0,
        'maxOutputTokens': 3000,
        'responseMimeType': 'application/json',
      },
    };

    final response = await http
        .post(
          Uri.parse('$_base/analyzeImage'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final errMsg = data['error']?.toString() ?? 'Unknown error';
      if (_looksLikeQuotaError(errMsg)) {
        throw Exception('experiencing high demand');
      }
      throw Exception(errMsg);
    }

    final rawText = _extractText(data);
    if (rawText == null || rawText.isEmpty) {
      throw Exception('experiencing high demand');
    }

    try {
      final parsed = jsonDecode(rawText) as Map<String, dynamic>;
      final findingsJson = parsed['findings'] as List<dynamic>? ?? [];
      return _dedupeFindings(
        findingsJson
            .map((f) => findingFromRegionJson(f as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      throw Exception("Could not read the AI's response, please try again.");
    }
  }

  static const String _promptText =
      'You are a safety-first FRC (FIRST Robotics Competition) robot pit '
      'inspector. Your job is to FIND visible risks, not to reassure the '
      'user. Inspect every visible robot area carefully before deciding '
      'whether it is safe. The photo is split into 9 overlapping crops, '
      'each labeled with a "Region:" tag immediately before its image '
      '(top-left, top-center, top-right, middle-left, center, '
      'middle-right, bottom-left, bottom-center, bottom-right).\n\n'
      'Look specifically for exposed conductors or damaged insulation, '
      'loose/unsecured wiring, loose connectors, unprotected battery '
      'terminals, loose/missing fasteners, cracked/bent frame members, '
      'corrosion, loose/misaligned belts or chains, sharp edges, visibly '
      'unsafe mechanisms, and parts likely to fail in a match. Do not '
      'assume a robot is safe just because it looks assembled. A plausible '
      'visible issue should be reported as a warning rather than omitted. '
      'Do not invent defects: ordinary screws, mounting holes, zip ties, '
      'and normal wires are not problems by themselves.\n\n'
      'Return an empty findings list ONLY when the photo is clear enough '
      'to inspect and every visible robot area looks safe. If the image is '
      'too dark, blurry, obstructed, or too distant for a meaningful '
      'inspection, return one warning titled "Photo quality prevents '
      'inspection" instead of returning an empty list. Since crops '
      'overlap, report a real issue only once, using the clearest crop and '
      'setting "region" to that crop\'s label. For box_2d, use Gemini\'s '
      'standard format: [ymin, xmin, ymax, xmax], each 0–1000, relative '
      'to THAT CROP (not the full photo). Respond only with JSON in this '
      'exact format:\n\n'
      '{"findings":[{"region":"top-left","title":"short issue name",'
      '"description":"one or two sentence explanation",'
      '"severity":"critical|warning|ok",'
      '"box_2d":[0,0,0,0]}]}\n\n'
      'Omit "box_2d" entirely if you cannot localize the issue within its '
      'crop. If nothing looks wrong, return {"findings":[]}.';

  static bool _looksLikeQuotaError(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('quota') ||
        lower.contains('429') ||
        lower.contains('rate limit') ||
        lower.contains('resource_exhausted');
  }

  static String? _extractText(Map<String, dynamic> data) {
    try {
      final candidates = data['candidates'] as List<dynamic>?;
      final text = candidates?[0]['content']['parts'][0]['text'] as String?;
      return text?.replaceAll('```json', '').replaceAll('```', '').trim();
    } catch (e) {
      return null;
    }
  }
}

Finding findingFromRegionJson(Map<String, dynamic> json) {
  final regionName = json['region'] as String?;
  final region = CropRegion.fromRegionName(regionName ?? '');
  final box2d = json['box_2d'] as List<dynamic>?;

  return Finding(
    title: json['title'] as String? ?? 'Issue found',
    description: json['description'] as String? ?? '',
    severity: parseSeverity(json['severity']),
    box: mapBoxFromCropToFull(box2d, region),
    isReported: false,
  );
}

ScanStatus parseSeverity(dynamic value) {
  final s = (value as String? ?? '').toLowerCase();
  if (s.contains('critical') || s == 'high') return ScanStatus.critical;
  if (s.contains('warn') || s == 'medium') return ScanStatus.warning;
  return ScanStatus.ok;
}

List<Finding> _dedupeFindings(List<Finding> findings) {
  final seenTitles = <String>{};
  final result = <Finding>[];
  for (final f in findings) {
    final key = f.title.trim().toLowerCase();
    if (seenTitles.add(key)) result.add(f);
  }
  return result;
}