import 'package:flutter/material.dart';

const kBrand      = Color(0xFF00B3AC);
const kBrandLight = Color(0xFFE0F7F6);
const kBrandDark  = Color(0xFF008C86);
const kBrandText  = Color(0xFF005C59);

// ─────────────────────────────────────────
// SCAN STATUS
// ─────────────────────────────────────────

enum ScanStatus { ok, warning, critical }

class StatusColors {
  final Color background;
  final Color text;
  const StatusColors(this.background, this.text);
}

StatusColors statusColors(ScanStatus status) {
  switch (status) {
    case ScanStatus.ok:
      return const StatusColors(kBrandLight, kBrandText);
    case ScanStatus.warning:
      return const StatusColors(Color(0xFFFFF3E0), Color(0xFF7B4500));
    case ScanStatus.critical:
      return const StatusColors(Color(0xFFFFEBEE), Color(0xFF7B1010));
  }
}

// ─────────────────────────────────────────
// FINDING MODEL
// ─────────────────────────────────────────

class Finding {
  final String title;
  final String description;
  final ScanStatus severity;

  Finding({
    required this.title,
    required this.description,
    required this.severity,
  });

  factory Finding.fromJson(Map<String, dynamic> json) {
    ScanStatus severity;
    switch ((json['severity'] as String).toLowerCase().trim()) {
      case 'critical':
        severity = ScanStatus.critical;
        break;
      case 'warning':
        severity = ScanStatus.warning;
        break;
      default:
        severity = ScanStatus.ok;
    }
    return Finding(
      title: json['title'] as String? ?? 'Unknown',
      description: json['description'] as String? ?? '',
      severity: severity,
    );
  }
}