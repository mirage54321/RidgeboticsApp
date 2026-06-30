import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'batteryLOGIN_screen.dart';

const Yellor = Color(0xFFFFC107);
const YellorLight = Color(0xFFFFF4E5);
const YellorDark = Color(0xFFB38600);

class Battery {
  final String label;
  final DateTime lastUsedAt;
  final int flagCount;

  Battery({
    required this.label,
    required this.lastUsedAt,
    required this.flagCount,
  });

  factory Battery.fromJson(Map<String, dynamic> json) {
    final flags = json['flags'] as List<dynamic>? ?? [];
    return Battery(
      label: json['label'] as String,
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      flagCount: flags.length,
    );
  }

  Duration get restTime => DateTime.now().difference(lastUsedAt);
}

class BatteryScreen extends StatefulWidget {
  const BatteryScreen({super.key});

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  static const String _baseUrl = 'https://ridgeboticsapp.onrender.com';

  List<Battery> _batteries = [];
  bool _isLoading = true;
  String? _error;
  String? _passcode;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final passcode = prefs.getString('battery_passcode');

    if (passcode == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const BatteryLoginScreen()),
      );
      return;
    }

    _passcode = passcode;
    await _loadBatteries();
  }

  Future<void> _loadBatteries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/battery/list?passcode=$_passcode'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        await _logout();
        return;
      }

      if (response.statusCode != 200) {
        setState(() {
          _error = 'Could not load batteries';
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(response.body);
      final batteriesJson = data['batteries'] as List<dynamic>;

      setState(() {
        _batteries =
            batteriesJson.map((b) => Battery.fromJson(b)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not connect, try again';
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('battery_passcode');
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const BatteryLoginScreen()),
    );
  }

  Future<void> _markInUse(Battery battery) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/battery/use'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'label': battery.label,
          'passcode': _passcode,
        }),
      );
      await _loadBatteries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update, try again')),
      );
    }
  }

  Future<void> _flagWeak(Battery battery) async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Flag ${battery.label}?'),
        content: const Text(
          'This marks the battery as underperforming so the team can keep an eye on it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await http.post(
                  Uri.parse('$_baseUrl/battery/flag'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'label': battery.label,
                    'passcode': _passcode,
                  }),
                );
                await _loadBatteries();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not flag, try again')),
                );
              }
            },
            child: const Text('Flag it'),
          ),
        ],
      ),
    );
  }

  Future<void> _addBattery() async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/battery/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'passcode': _passcode}),
      );
      await _loadBatteries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add battery, try again')),
      );
    }
  }

  String _formatRestTime(Duration d) {
    if (d.inMinutes < 1) return 'just used';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 248),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
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
                color: YellorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back, color: Yellor, size: 17),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Batteries',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: _logout,
            child: Text('Log out',
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Yellor));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _loadBatteries,
              child: const Text('Try again',
                  style: TextStyle(
                      color: Yellor, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: Yellor,
      onRefresh: _loadBatteries,
      child: _batteries.isEmpty ? _emptyState() : _grid(),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 60),
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
        const Text('No batteries yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('Add your first one below',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 20),
        _addButton(),
      ],
    );
  }

  Widget _grid() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_batteries.isNotEmpty) _topPick(),
        const SizedBox(height: 16),
        Text('All batteries',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600])),
        const SizedBox(height: 8),
        ..._batteries.skip(1).map(_batteryTile),
        const SizedBox(height: 12),
        _addButton(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _topPick() {
    final battery = _batteries.first;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Yellor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GRAB THIS ONE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.8),
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(battery.label,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text('Resting ${_formatRestTime(battery.restTime)}',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85))),
                if (battery.flagCount > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'flagged ${battery.flagCount}x',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            children: [
              GestureDetector(
                onTap: () => _markInUse(battery),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Mark used',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: YellorDark)),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _flagWeak(battery),
                child: Text('Flag weak',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _batteryTile(Battery battery) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.black.withValues(alpha: 0.07), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: YellorLight,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(battery.label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: YellorDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resting ${_formatRestTime(battery.restTime)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                if (battery.flagCount > 0) ...[
                  const SizedBox(height: 3),
                  Text('flagged ${battery.flagCount}x',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFD93025))),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _markInUse(battery),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: YellorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Use',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: YellorDark)),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _flagWeak(battery),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.flag_outlined, size: 16, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addButton() {
    return GestureDetector(
      onTap: _addBattery,
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
            const Icon(Icons.add, color: Yellor, size: 18),
            const SizedBox(width: 7),
            Text('Add battery',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}