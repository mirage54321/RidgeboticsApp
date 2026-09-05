import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'retry_helper.dart';
import 'connectivity_check.dart';
import 'ai_scan.dart'
    show
        gridRegionNames,
        CropRegion,
        CroppedImage,
        cropToRegion,
        findingFromRegionJson,
        RetryCallback;

class AiRulesService {
  static const String _base = 'https://ridgeboticsapp.onrender.com';

  static const Map<String, String> _manualAssetPaths = {
    '2026': 'assets/rules/frc_2026_manual.pdf',
    '2025': 'assets/rules/frc_2025_manual.pdf',
    '2024': 'assets/rules/frc_2024_manual.pdf',
  };


  static Future<List<Finding>> analyzeImage(
    Uint8List imageBytes,
    String year, {
    int maxAttempts = 3,
    RetryCallback? onRetry,
  }) async {
    if (!ConnectivityCheck.isOnline) {
      throw Exception('offline');
    }

    final manualPath = _manualAssetPaths[year];
    if (manualPath == null) {
      throw Exception('No game manual available for $year');
    }

    final manualData = await rootBundle.load(manualPath);
    final base64Manual = base64Encode(manualData.buffer.asUint8List(
      manualData.offsetInBytes,
      manualData.lengthInBytes,
    ));

    final crops = {
      for (final name in gridRegionNames)
        name: cropToRegion(imageBytes, CropRegion.fromRegionName(name)),
    };

    return withBackoffRetry<List<Finding>>(
      () => _analyzeOnce(crops, base64Manual, year),
      maxAttempts: maxAttempts,
      initialDelay: const Duration(seconds: 3),
      isRetryable: isHighDemandError,
      onRetry: onRetry,
    );
  }

  static Future<List<Finding>> _analyzeOnce(
    Map<String, CroppedImage> crops,
    String base64Manual,
    String year,
  ) async {
    final parts = <Map<String, dynamic>>[
      {'text': _promptText(year)},
      {
        'inline_data': {
          'mime_type': 'application/pdf',
          'data': base64Manual,
        }
      },
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
        .timeout(const Duration(seconds: 75));

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

  static String _promptText(String year) =>
      'You are a strict FRC (FIRST Robotics Competition) robot inspector '
      'checking a photo against the attached $year FRC game manual. Use '
      'ONLY that manual as the source of truth because rules change each '
      'season. Your job is to identify visible possible violations, not '
      'to reassure the user. Do not say a robot is compliant merely '
      'because it looks assembled.\n\n'
      'The photo is split into 9 overlapping crops. Each crop has a '
      '"Region:" label immediately before its image (top-left, top-center, '
      'top-right, middle-left, center, middle-right, bottom-left, '
      'bottom-center, bottom-right). Inspect every visible area for '
      'evidence of rule violations, especially bumpers, frame perimeter, '
      'wiring/electrical safety, exposed battery terminals, sharp edges, '
      'extension beyond allowed boundaries, and other requirements that '
      'can actually be seen in the photo. Cite the specific rule number '
      'when the manual supports it. Do not invent violations that cannot '
      'be seen or measured from a photo.\n\n'
      'Return an empty findings list ONLY if the image is clear enough to '
      'inspect and you find no visible evidence of a violation. If the '
      'image is too dark, blurry, obstructed, or too distant to inspect '
      'the relevant robot features, return one warning titled "Photo '
      'quality prevents rule inspection" rather than an empty list. '
      'Because crops overlap, report each distinct visible violation only '
      'once, using its clearest crop and setting "region" to that crop\'s '
      'label. For box_2d, use Gemini\'s standard format: [ymin, xmin, '
      'ymax, xmax], each 0–1000, relative to THAT CROP (not the full '
      'photo). Respond only with JSON in this exact format:\n\n'
      '{"findings":[{"region":"top-left","title":"short issue name",'
      '"description":"one or two sentence explanation, cite rule number '
      'if applicable","severity":"critical|warning|ok",'
      '"box_2d":[0,0,0,0]}]}\n\n'
      'Omit "box_2d" entirely if you cannot localize the issue within its '
      'crop. If nothing looks like a violation, return {"findings":[]}.';

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

  static List<Finding> _dedupeFindings(List<Finding> findings) {
    final seenTitles = <String>{};
    final result = <Finding>[];
    for (final f in findings) {
      final key = f.title.trim().toLowerCase();
      if (seenTitles.add(key)) result.add(f);
    }
    return result;
  }
}