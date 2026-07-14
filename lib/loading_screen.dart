import 'package:flutter/material.dart';
import 'constants.dart';
import 'home_screen.dart';

const pinkConstant = Color(0xFFCF2879);
const yellowConstant = Color(0xFFFFC107);
const grayConstant = Color.fromARGB(255, 204, 204, 204);
const orangeConstant = Color.fromARGB(255, 255, 160, 7);

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  late Animation<double> fadeAnim;
  late Animation<double> scaling;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    fadeAnim = CurvedAnimation(
      parent: controller,
      curve: Curves.easeIn,
    );

    scaling = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutBack),
    );

    controller.forward();

    _navigateNext();
  }

  Future<void> _navigateNext() async {
    // Replace this delay
    await Future.delayed(const Duration(milliseconds: 3000));
  
  
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: fadeAnim,
          child: ScaleTransition(
            scale: scaling,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: grayConstant,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.smart_toy,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 20),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                        fontSize: 28,
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
                const SizedBox(height: 28),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(TealScan),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}