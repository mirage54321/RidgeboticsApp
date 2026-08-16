import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'ai_scan.dart'
    show
        gridRegionNames,
        CropRegion,
        cropToRegion,
        findingFromRegionJson;

class AiRulesService {
  static const String _base = 'https://ridgeboticsapp.onrender.com';

  static const Map<String, String> _manualAssetPaths = {
    '2026': 'assets/rules/frc_2026_manual.pdf',
    '2025': 'assets/rules/frc_2025_manual.pdf',
    '2024': 'assets/rules/frc_2024_manual.pdf',
  };

  static Future<List<Finding>> analyzeImage(
      Uint8List imageBytes, String year) async {
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
      'generationConfig': {'temperature': 0, 'maxOutputTokens': 2000},
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
      'You are inspecting a photo of an FRC (FIRST Robotics Competition) '
      'robot for compliance with the attached $year FRC game manual. Use '
      'ONLY the attached rulebook as your source of truth, not general '
      'knowledge, since rules change year to year. The photo has been '
      'split into 9 overlapping crops, each labeled with a "Region:" tag '
      'right before the image (top-left, top-center, top-right, '
      'middle-left, center, middle-right, bottom-left, bottom-center, '
      'bottom-right). Look at every crop for anything that may violate a '
      'specific rule (frame perimeter, height, weight, bumpers, '
      'wiring/electrical rules, etc.), and cite the rule number when '
      'possible. Since the crops overlap, the same violation may appear '
      'in more than one crop — only report each distinct issue ONCE, '
      'using whichever crop shows it most clearly, and set "region" to '
      'that crop\'s label. For box_2d, use Gemini\'s standard format: '
      '[ymin, xmin, ymax, xmax], each 0–1000, relative to THAT CROP (not '
      'the full photo). Respond ONLY with valid JSON, no markdown, in '
      'this exact format:\n\n'
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