// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'constants.dart';
// import 'ai_rules.dart';
// import 'results_screen.dart';


import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'batteryLOGIN_screen.dart';
import 'battery_screen.dart';


const Yellor = Color(0xFFFFC107);
const YellorLight = Color(0xFFFFF4E5);


class BatteryLoginScreen extends StatefulWidget {
  const BatteryLoginScreen({super.key});

  @override
  State<BatteryLoginScreen> createState() => _BatteryLoginScreenState();
}

class _BatteryLoginScreenState extends State<BatteryLoginScreen> {
  final _teamController = TextEditingController(text: '4388');
  final passcodeCont = TextEditingController();
  bool checking = false;
  String? error;

  static const String _backendUrl =
      'https://ridgeboticsapp.onrender.com/battery/login';

  Future<void> _login() async {
    final teamNumber = _teamController.text.trim();
    final passcode = passcodeCont.text.trim();

    if (teamNumber.isEmpty || passcode.isEmpty) {
      setState(() => error = 'Enter both fields');
      return;
    }

    setState(() {
      checking = true;
      error = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse(_backendUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'teamNumber': teamNumber,
              'passcode': passcode,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('battery_passcode', passcode);

        if (!mounted) return; // should be !
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BatteryScreen()),
        );
      } else {
        setState(() {
          error = 'Wrong team number or passcode';
          checking = false;
        });
        
      }
    } catch (e) {
      setState(() {
        error = 'Could not connect, try again';
        checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 248),
      body: SafeArea(
        child: Column(
          children: [
            Container(
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
                        color: YellorLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Yellor, size: 17),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Team login',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: YellorLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.battery_charging_full,
                          color: Yellor, size: 28),
                    ),
                    const SizedBox(height: 16),
                    const Text('Battery tracker',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('Enter your team number and passcode',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _teamController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Team number',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passcodeCont,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Passcode',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!,
                          style: const TextStyle(
                              color: Color(0xFFD93025), fontSize: 13)),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: checking ? null : _login,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: checking
                                ? Yellor.withValues(alpha: 0.4)
                                : Yellor,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: checking
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Log in',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}