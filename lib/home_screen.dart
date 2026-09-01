import 'package:flutter/material.dart';
import 'constants.dart';
import 'scan_screen.dart';
import 'rules_screen.dart';
import 'battery_screen.dart';
import 'batteryLOGIN_screen.dart';
import 'match_notifier_screen.dart';

// flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080

const pinkConstant = Color(0xFFCF2879);
const yellowConstant = Color(0xFFFFC107);
const grayConstant = Color.fromARGB(255, 204, 204, 204);
const orangeConstant = Color.fromARGB(255, 255, 160, 7);
const pinkConstantLight = Color(0xFFFFE4F0);
const yellowConstantLight = Color(0xFFFFF4E5);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void QuestionButton(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('About',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Icon(Icons.close, color: Colors.grey[400], size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Welcome to RoboLens! This app is designed to help FRC teams check their robots for issues and ensure they are compliant with the rules from a photo. You can use the tools below to scan your robot, check FRC rules, and track your competition batteries. More text will be added here in the future to explain the app and how to use it. Contact mira.j.maroni@gmail.com if there are any issues.'),
                  // style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: SafeArea(
        child: Column(
          children: [
            top(context),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // welcome(),
                    scanner(context),
                    rules(context),
                    battery(context),
                    stats(context),
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

  Widget top(BuildContext context) {
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
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'web/icons/Icon-200.png',
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.black),
              children: [
                TextSpan(text: 'Robo'),
                TextSpan(text: 'L', style: TextStyle(color: pinkConstant)),
                TextSpan(text: 'e', style: TextStyle(color: TealScan)),
                TextSpan(text: 'n', style: TextStyle(color: yellowConstant)),
                TextSpan(text: 's', style: TextStyle(color: orangeConstant)),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => QuestionButton(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: grayConstant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.question_mark_outlined,
                  color: Color.fromARGB(255, 255, 255, 255), size: 17),
            ),
          ),
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

  // Shared, responsive card used by scanner/rules/battery/stats below.
  // A LayoutBuilder measures the space actually available for this card and:
  //  - shrinks the corner icon as the card gets narrower
  //  - drops the icon entirely below a width threshold instead of letting it
  //    squeeze/clip the text
  //  - keeps the title/description/CTA in a flexible column that always wraps
  // so nothing gets cut off on smaller phones or with larger system font sizes.
  Widget _toolCard({
    required BuildContext context,
    required VoidCallback onTap,
    required Color color,
    required String title,
    required String description,
    required String ctaText,
    required Color ctaTextColor,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Below this width the icon has nowhere good to go, so hide it
            // rather than let it push/clip the text column.
            final showIcon = constraints.maxWidth >= 220;
            final iconSize = constraints.maxWidth < 300 ? 48.0 : 64.0;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
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
                        child: Text(
                          ctaText,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: ctaTextColor),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showIcon) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: iconSize, color: Colors.white24),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget scanner(BuildContext context) {
    return _toolCard(
      context: context,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      ),
      color: TealScan,
      title: 'Scan for issues',
      description:
          'In this tool, you can upload a photo of your robot and an AI will spot damage, loose wires, and more!',
      ctaText: 'Start scanning',
      ctaTextColor: TealScanText,
      icon: Icons.vrpano_outlined,
    );
  }

  Widget rules(BuildContext context) {
    return _toolCard(
      context: context,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RulesScreen()),
      ),
      color: pinkConstant,
      title: 'Check FRC rules',
      description:
          'In this tool, you can upload a photo of your robot and an AI will check if your robot passes the specific FRC inspection rules for a selected year!',
      ctaText: 'Check rules',
      ctaTextColor: pinkConstant,
      icon: Icons.fact_check_outlined,
    );
  }

  Widget battery(BuildContext context) {
    return _toolCard(
      context: context,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BatteryLoginScreen()),
      ),
      color: yellowConstant,
      title: 'Track your competition batteries',
      description:
          'In this tool, you can log your batteries with your team so that you can ensure optimal performance!',
      ctaText: 'Log batteries',
      ctaTextColor: yellowConstant,
      icon: Icons.battery_charging_full,
    );
  }

  Widget stats(BuildContext context) {
    return _toolCard(
      context: context,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MatchNotifierScreen()),
      ),
      color: orangeConstant,
      title: 'Look at FRC team stats',
      description:
          'In this tool, you can view and analyze FRC team statistics to improve your performance!',
      ctaText: 'View team stats',
      ctaTextColor: orangeConstant,
      icon: Icons.bar_chart,
    );
  }
}