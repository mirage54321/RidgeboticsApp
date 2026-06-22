import 'package:flutter/material.dart';
import 'constants.dart';
import 'scan_screen.dart';
import 'rules_screen.dart';
//  flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
// https://mirage54321.github.io/RidgeboticsApp/
const kPink = Color(0xFFCF2879);
const kYellow = Color(0xFFFFC107);
const kGrey = Color.fromARGB(255, 204, 204, 204);
const kOrange = Color.fromARGB(255, 255, 160, 7);
const kPinkLight = Color(0xFFFFE4F0);
const kYellowLight = Color(0xFFFFF4E5);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGreeting(),
                    _buildScanCard(context),
                    _buildRulesCard(context),
                    const SizedBox(height: 24),
                    _buildTipCard(),
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
              color: kGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.smart_toy, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 8),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.black),
              children: [
                TextSpan(text: 'robo'),
                TextSpan(text: 'l', style: TextStyle(color: kPink)),
                TextSpan(text: 'e', style: TextStyle(color: kBrand)),
                TextSpan(text: 'n', style: TextStyle(color: kYellow)),
                TextSpan(text: 's', style: TextStyle(color: kOrange)),
              ],
            ),
          ),
          const Spacer(),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: kGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.notifications_outlined,
                color: Color.fromARGB(255, 255, 255, 255), size: 17),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hey, ready to check your robot?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text('Pick a tool below to get started.',
              style: TextStyle(fontSize: 13, color: kGrey)),
        ],
      ),
    );
  }

  Widget _buildScanCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: kBrand,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOOL 1',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Scan for issues',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                    'Upload a photo and AI will spot damage, loose wires, and more.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.search, color: kBrand, size: 18),
                        SizedBox(width: 8),
                        Text('Start scanning',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: kBrandText)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.vrpano_outlined, size: 64, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RulesScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: kPink,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOOL 2',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Check FRC rules',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                    'Upload a photo and AI will check if your robot passes FRC inspection rules.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.rule, color: kPink, size: 18),
                        SizedBox(width: 8),
                        Text('Check rules',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: kPink)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.fact_check_outlined, size: 64, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildTipCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tip',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color.fromARGB(255, 255, 255, 255))),
                const SizedBox(height: 3),
                Text(
                  'Make sure your robot is well-lit and fully in frame for best results.',
                  style: TextStyle(
                      fontSize: 12,
                      color: const Color.fromARGB(255, 255, 255, 255).withValues(alpha: 0.8),
                      height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}