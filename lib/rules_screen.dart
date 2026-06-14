import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'constants.dart';
import 'ai_rules.dart';
import 'results_screen.dart';

const kPink = Color(0xFFCF2879);
const kPinkLight = Color(0xFFFFE4F0);

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  Uint8List? _imageBytes;
  bool _isAnalyzing = false;
  String _analyzingStatus = 'Analyzing...';
  String _selectedYear = '2025';
  final ImagePicker _picker = ImagePicker();

  final List<String> _years = ['2026', '2025', '2024'];

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
      setState(() => _analyzingStatus = 'Checking $_selectedYear rules...');
      final findings =
          await AiRulesService.analyzeImage(_imageBytes!, _selectedYear);

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
          content: Text('Scan failed: ${e.toString()}'),
          backgroundColor: const Color(0xFFD93025),
          duration: const Duration(seconds: 5),
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
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildYearSelector(),
                    const SizedBox(height: 16),
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

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: kPink,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.rule, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 8),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.black),
              children: [
                TextSpan(text: 'rules'),
                TextSpan(
                    text: 'check',
                    style: TextStyle(color: kPink)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FRC Season Year',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('Rules will be checked against the $_selectedYear game manual.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 12),
          Row(
            children: _years.map((year) {
              final selected = year == _selectedYear;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedYear = year),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? kPink : kPinkLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      year,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : kPink,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildImageArea() {
    return Container(
      width: double.infinity,
      height: 260,
      decoration: BoxDecoration(
        color: _imageBytes == null ? kPinkLight : null,
        border: _imageBytes == null
            ? Border.all(
                color: kPink,
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
                    color: kPink.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_outlined,
                      color: kPink, size: 30),
                ),
                const SizedBox(height: 14),
                const Text('No photo selected',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: kPink)),
                const SizedBox(height: 4),
                Text('Tap the button below to upload one',
                    style: TextStyle(
                        fontSize: 12,
                        color: kPink.withValues(alpha: 0.6))),
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
                        const CircularProgressIndicator(color: kPink),
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
            Icon(icon, color: kPink, size: 18),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: kPink)),
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
          color: ready ? kPink : kPink.withValues(alpha: 0.4),
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
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.rule, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('Check $_selectedYear rules',
                        style: const TextStyle(
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
      'AI will check your robot against the $_selectedYear FRC game manual.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.5),
    );
  }
}