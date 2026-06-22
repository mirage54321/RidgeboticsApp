import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'constants.dart';
import 'ai_scan.dart';
import 'results_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  Uint8List? _imageBytes;
  bool _isAnalyzing = false;
  String _analyzingStatus = 'Analyzing...';
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickFromGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _imageBytes = bytes);
    }
  }

  Future<void> _analyze() async {
    if (_imageBytes == null) return;
    setState(() {
      _isAnalyzing = true;
      _analyzingStatus = 'Sending to AI...';
    });

    try {
      setState(() => _analyzingStatus = 'Scanning for issues...');
      final findings = await AiService.analyzeImage(_imageBytes!);

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            imageBytes: _imageBytes!,
            findings: findings,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scan Failed: \n${e.toString()}',
          ),
          backgroundColor: const Color(0xFFD93025),
          duration: const Duration(seconds: 20),
        ),
      );
    }
  }

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
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildImageArea(),
                    const SizedBox(height: 16),
                    if (_imageBytes == null) _buildPickerButton(),
                    if (_imageBytes != null) _buildRetakeButton(),
                    const SizedBox(height: 20),
                    _buildAnalyzeButton(),
                    const SizedBox(height: 20),
                    _buildHintText(),
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
          const Text('New scan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildImageArea() {
    return Container(
      width: double.infinity,
      height: 280,
      decoration: BoxDecoration(
        color: _imageBytes == null ? kBrandLight : null,
        border: _imageBytes == null
            ? Border.all(
                color: kBrand,
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside)
            : null,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: _imageBytes == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: kBrand.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_outlined,
                      color: kBrand, size: 30),
                ),
                const SizedBox(height: 14),
                const Text('No photo selected',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: kBrandText)),
                const SizedBox(height: 4),
                Text('Tap the button below to upload one',
                    style: TextStyle(
                        fontSize: 12,
                        color: kBrandText.withValues(alpha: 0.6))),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(_imageBytes!, fit: BoxFit.cover),
                if (_isAnalyzing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: kBrand),
                        const SizedBox(height: 14),
                        Text(
                          _analyzingStatus,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildPickerButton() {
    return SizedBox(
      width: double.infinity,
      child: _outlineButton(
        icon: Icons.photo_library_outlined,
        label: 'Upload photo',
        onTap: _pickFromGallery,
      ),
    );
  }

  Widget _buildRetakeButton() {
    return SizedBox(
      width: double.infinity,
      child: _outlineButton(
        icon: Icons.photo_library_outlined,
        label: 'Choose a different photo',
        onTap: _pickFromGallery,
      ),
    );
  }

  Widget _outlineButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
            Icon(icon, color: kBrand, size: 18),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: kBrandText)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    final ready = _imageBytes != null && !_isAnalyzing;
    return GestureDetector(
      onTap: ready ? _analyze : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: ready ? kBrand : kBrand.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: _isAnalyzing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text(_analyzingStatus,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                  ],
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Analyze photo',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHintText() {
    return Text(
      'The AI will scan for wiring issues, cracks, misalignment, and more.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.5),
    );
  }
}