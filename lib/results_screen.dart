import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'constants.dart';
import 'scan_screen.dart';

class ResultsScreen extends StatelessWidget {
  final Uint8List imageBytes;
  final List<Finding> findings;

  const ResultsScreen({
    super.key,
    required this.imageBytes,
    required this.findings,
  });

  int get _criticalCount =>
      findings.where((f) => f.severity == ScanStatus.critical).length;
  int get _warningCount =>
      findings.where((f) => f.severity == ScanStatus.warning).length;
  int get _okCount =>
      findings.where((f) => f.severity == ScanStatus.ok).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FFFE),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPhoto(),
                    _buildVerdict(),
                    _buildSectionLabel('What the AI found'),
                    ...findings.asMap().entries.map(
                          (e) => _buildFinding(
                            number: '${e.key + 1}',
                            finding: e.value,
                          ),
                        ),
                    _buildActions(context),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: kBrandLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back, color: kBrand, size: 17),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Scan results',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          Text(
            _formattedTime(),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoto() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF1C2B2B),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.memory(imageBytes,
            fit: BoxFit.cover, width: double.infinity),
      ),
    );
  }

  Widget _buildVerdict() {
    final hasIssues = _criticalCount + _warningCount > 0;
    final total = _criticalCount + _warningCount;
    final iconColor = _criticalCount > 0
        ? const Color(0xFFD93025)
        : _warningCount > 0
            ? const Color(0xFFE8A000)
            : kBrand;
    final bgColor = _criticalCount > 0
        ? const Color(0xFFFFEBEE)
        : _warningCount > 0
            ? const Color(0xFFFFF3E0)
            : kBrandLight;
    final icon = _criticalCount > 0
        ? Icons.warning_amber_rounded
        : _warningCount > 0
            ? Icons.info_outline
            : Icons.check_circle_outline;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.black.withValues(alpha: 0.07), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasIssues
                    ? '$total issue${total > 1 ? 's' : ''} found'
                    : 'All clear!',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                '$_criticalCount critical · $_warningCount warning · $_okCount ok',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildFinding({required String number, required Finding finding}) {
    final colors = statusColors(finding.severity);
    final badgeLabel = finding.severity == ScanStatus.critical
        ? 'Critical'
        : finding.severity == ScanStatus.warning
            ? 'Warning'
            : 'All clear';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.black.withValues(alpha: 0.07), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: colors.background,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(number,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.text)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(finding.title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(finding.description,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        height: 1.5)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(badgeLabel,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: colors.text)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: kBrand,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined,
                        color: Colors.white, size: 16),
                    SizedBox(width: 7),
                    Text('Scan again',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.black.withValues(alpha: 0.1), width: 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.ios_share_outlined,
                      color: Colors.grey[700], size: 16),
                  const SizedBox(width: 7),
                  Text('Export',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formattedTime() {
    final now = DateTime.now();
    return '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }
}