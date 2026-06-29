import 'package:flutter/material.dart';
import 'constants.dart';
import 'scan_screen.dart';
import 'rules_screen.dart';
import 'batteryLOGIN_screen.dart';
import 'battery_screen.dart';

// flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080


const pinkConstant = Color(0xFFCF2879);
const yellowConstant = Color(0xFFFFC107);
const grayConstant = Color.fromARGB(255, 204, 204, 204);
const orangeConstant = Color.fromARGB(255, 255, 160, 7);
const pinkConstantLight = Color(0xFFFFE4F0);
const yellowConstantLight = Color(0xFFFFF4E5);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: SafeArea(
        child: Column(
          children: [
            top(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // welcome(),
                    scanner(context),
                    rules(context),
                    battery(context),
                    const SizedBox(height: 24),
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

  Widget top() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: grayConstant,
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
                TextSpan(text: 'l', style: TextStyle(color: pinkConstant)),
                TextSpan(text: 'e', style: TextStyle(color: TealScan)),
                TextSpan(text: 'n', style: TextStyle(color: yellowConstant)),
                TextSpan(text: 's', style: TextStyle(color: orangeConstant)),
              ],
            ),
          ),
          const Spacer(),
          // Container(
          //   width: 34,
          //   height: 34,
          //   decoration: BoxDecoration(
          //     color: grayConstant,
          //     borderRadius: BorderRadius.circular(10),
          //   ),
          //   child: const Icon(Icons.notifications_outlined,
          //       color: Color.fromARGB(255, 255, 255, 255), size: 17),
          // ),
        ],
      ),
    );
  }

  Widget welcome() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hey, ready to check your robot?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          // Text('Pick a tool below to get started.',
          //     style: TextStyle(fontSize: 13, color: grayConstant)),
        ],
      ),
    );
  }

  Widget scanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: TealScan,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Text(
                  //   'TOOL 1',
                  //   style: TextStyle(
                  //     fontSize: 11,
                  //     color: Colors.white.withValues(alpha: 0.75),
                  //     fontWeight: FontWeight.w500,
                  //     letterSpacing: 0.5,
                  //   ),
                  // ),
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
                        // SizedBox(width: 8),
                        Text('Start scanning',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: TealScanText)),
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

  Widget rules(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RulesScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: pinkConstant,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Text(
                  //   'TOOL 2',
                  //   style: TextStyle(
                  //     fontSize: 11,
                  //     color: Colors.white.withValues(alpha: 0.75),
                  //     fontWeight: FontWeight.w500,
                  //     letterSpacing: 0.5,
                  //   ),
                  // ),
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
                        // Icon(Icons.rule, color: pinkConstant, size: 18),
                        // SizedBox(width: 8),
                        Text('Check rules',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: pinkConstant)),
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


  Widget battery(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BatteryLoginScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: yellowConstant,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Text(
                  //   'TOOL 2',
                  //   style: TextStyle(
                  //     fontSize: 11,
                  //     color: Colors.white.withValues(alpha: 0.75),
                  //     fontWeight: FontWeight.w500,
                  //     letterSpacing: 0.5,
                  //   ),
                  // ),
                  const SizedBox(height: 4),
                  const Text('Track your competition batteries',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                    'Log your batteries with your team to ensure optimal performance.',
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
                        // SizedBox(width: 8),
                        Text('Log batteries',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: yellowConstant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.battery_charging_full, size: 64, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}