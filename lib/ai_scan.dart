import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'constants.dart';

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

class AiService {
  static const String _base = 'https://ridgeboticsapp.onrender.com';

  static Future<List<Finding>> analyzeImage(Uint8List imageBytes) async {
    final crops = {
      for (final name in gridRegionNames)
        name: cropToRegion(imageBytes, CropRegion.fromRegionName(name)),
    };

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
      'generationConfig': {'temperature': 0, 'maxOutputTokens': 2000},
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
      'You are inspecting a photo of an FRC (FIRST Robotics Competition) '
      'robot during a pit-stop check. The photo has been split into 9 '
      'overlapping crops, each labeled with a "Region:" tag right before '
      'the image (top-left, top-center, top-right, middle-left, center, '
      'middle-right, bottom-left, bottom-center, bottom-right). Look at '
      'every crop for physical issues: frayed or exposed wiring, loose or '
      'missing screws/bolts, cracked or bent frame members, corrosion, '
      'loose belts/chains, or anything else that looks unsafe or likely '
      'to fail mid-match. Since the crops overlap, the same physical '
      'issue may appear in more than one crop — only report each distinct '
      'issue ONCE, using whichever crop shows it most clearly, and set '
      '"region" to that crop\'s label. For box_2d, use Gemini\'s standard '
      'format: [ymin, xmin, ymax, xmax], each 0–1000, relative to THAT '
      'CROP (not the full photo). Respond ONLY with valid JSON, no '
      'markdown, in this exact format:\n\n'
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