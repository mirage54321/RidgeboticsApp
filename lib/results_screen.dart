import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'constants.dart';
import 'scan_screen.dart';

class ResultsScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final List<Finding> findings;

  const ResultsScreen({
    super.key,
    required this.imageBytes,
    required this.findings,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int? _highlightedIndex;

  late final Future<ui.Image> _decodedImage;

  @override
  void initState() {
    super.initState();
    _decodedImage = _decodeImage(widget.imageBytes);
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  List<Finding> get findings => widget.findings;

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
                    photor(),
                    answers(),
                    thingsFound('What the AI found'),
                    ...findings.asMap().entries.map(
                          (e) => _buildFinding(
                            index: e.key,
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
                color: Color.fromARGB(255, 161, 161, 161),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back,
                  color: Color.fromARGB(255, 255, 255, 255), size: 17),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Scan results',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          Text(
            _formattedTime(),
            style: TextStyle(
                fontSize: 12, color: Color.fromARGB(255, 161, 161, 161)),
          ),
        ],
      ),
    );
  }

  Widget photor() {
    return GestureDetector(
      onTap: () => setState(() => _highlightedIndex = null),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF1C2B2B),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: FutureBuilder<ui.Image>(
            future: _decodedImage,
            builder: (context, snapshot) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final containerSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        widget.imageBytes,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                      if (snapshot.hasData)
                        CustomPaint(
                          size: containerSize,
                          painter: _BoxPainter(
                            findings: findings,
                            highlightedIndex: _highlightedIndex,
                            imageSize: Size(
                              snapshot.data!.width.toDouble(),
                              snapshot.data!.height.toDouble(),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget answers() {
    final hasIssues = _criticalCount + _warningCount > 0;
    final total = _criticalCount + _warningCount;
    final iconColor = _criticalCount > 0
        ? const Color(0xFFD93025)
        : _warningCount > 0
            ? const Color(0xFFE8A000)
            : Color.fromARGB(255, 161, 161, 161);
    final bgColor = _criticalCount > 0
        ? const Color(0xFFFFEBEE)
        : _warningCount > 0
            ? const Color(0xFFFFF3E0)
            : Color.fromARGB(255, 199, 205, 205);
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

  Widget thingsFound(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildFinding({
    required int index,
    required String number,
    required Finding finding,
  }) {
    final colors = statusColors(finding.severity);
    final badgeLabel = finding.severity == ScanStatus.critical
        ? 'Critical'
        : finding.severity == ScanStatus.warning
            ? 'Warning'
            : 'All clear';
    final isHighlighted = _highlightedIndex == index;

    return GestureDetector(
      onTap: finding.box == null
          ? null
          : () => setState(() {
                _highlightedIndex = isHighlighted ? null : index;
              }),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHighlighted
                ? colors.text.withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.07),
            width: isHighlighted ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                              color: Color.fromARGB(255, 161, 161, 161),
                              height: 1.5)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
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
                          if (finding.box != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.my_location,
                                      size: 11, color: Colors.grey[600]),
                                  const SizedBox(width: 3),
                                  Text(
                                    isHighlighted ? 'Showing on photo' : 'Show on photo',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: finding.isReported
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text('Reported',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[500])),
                      ],
                    )
                  : GestureDetector(
                      onTap: () => _reportFinding(index, finding),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_outlined,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text('Report an error',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[500])),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _reportFinding(int index, Finding finding) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report this finding?'),
        content: Text(
          'Let us know "${finding.title}" looks wrong. This helps improve future scans.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() => finding.isReported = true);
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Thanks — this finding was reported.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Report'),
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
                  color: Color.fromARGB(255, 161, 161, 161),
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
        ],
      ),
    );
  }

  String _formattedTime() {
    final now = DateTime.now();
    return '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class _BoxPainter extends CustomPainter {
  final List<Finding> findings;
  final int? highlightedIndex;
  final Size imageSize;

  _BoxPainter({
    required this.findings,
    required this.highlightedIndex,
    required this.imageSize,
  });

  Rect _containedImageRect(Size containerSize) {
    final imageAspect = imageSize.width / imageSize.height;
    final containerAspect = containerSize.width / containerSize.height;

    double renderWidth, renderHeight;
    if (imageAspect > containerAspect) {
      renderWidth = containerSize.width;
      renderHeight = renderWidth / imageAspect;
    } else {
      renderHeight = containerSize.height;
      renderWidth = renderHeight * imageAspect;
    }

    final left = (containerSize.width - renderWidth) / 2;
    final top = (containerSize.height - renderHeight) / 2;
    return Rect.fromLTWH(left, top, renderWidth, renderHeight);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final imageRect = _containedImageRect(size);

    for (var i = 0; i < findings.length; i++) {
      final finding = findings[i];
      final box = finding.box;
      if (box == null) continue;

      final isDimmed = highlightedIndex != null && highlightedIndex != i;
      final color = finding.severity == ScanStatus.critical
          ? const Color(0xFFD93025)
          : finding.severity == ScanStatus.warning
              ? const Color(0xFFE8A000)
              : const Color(0xFF00B3AC);

      final rect = Rect.fromLTWH(
        imageRect.left + box.x * imageRect.width,
        imageRect.top + box.y * imageRect.height,
        box.width * imageRect.width,
        box.height * imageRect.height,
      );

      final paint = Paint()
        ..color = isDimmed ? color.withValues(alpha: 0.25) : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDimmed ? 1.5 : 2.5;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, paint);

      if (!isDimmed) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelTop =
            (rect.top - 18) < imageRect.top ? rect.top : rect.top - 18;

        final labelBgRect = Rect.fromLTWH(
          rect.left,
          labelTop,
          labelPainter.width + 10,
          18,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(labelBgRect,
              topLeft: const Radius.circular(4),
              topRight: const Radius.circular(4),
              bottomRight: const Radius.circular(4)),
          Paint()..color = color,
        );
        labelPainter.paint(
          canvas,
          Offset(labelBgRect.left + 5, labelBgRect.top + 3),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter oldDelegate) {
    return oldDelegate.highlightedIndex != highlightedIndex ||
        oldDelegate.findings != findings ||
        oldDelegate.imageSize != imageSize;
  }
}