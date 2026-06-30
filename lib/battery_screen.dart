import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'batteryLOGIN_screen.dart';

const Yellor = Color(0xFFFFC107);
const YellorLight = Color(0xFFFFF4E5);
const YellorDark = Color(0xFFB38600);
const greenChar = Color(0xFF4CAF50);
const redChar = Color(0xFFD93025);

class FlagEntry {
  final String note;
  final DateTime flaggedAt;

  FlagEntry({
    required this.note,
    required this.flaggedAt,
  });

  factory FlagEntry.fromJson(Map<String, dynamic> json) {
    return FlagEntry(
      note: json['note'] as String? ?? '',
      flaggedAt: DateTime.parse(json['flaggedAt'] as String),
    );
  }
}

class Battery {
  final String label;
  final DateTime lastUsedAt;
  final List<FlagEntry> flags;

  bool isCharging;
  bool isInUse;

  Battery({
    required this.label,
    required this.lastUsedAt,
    required this.flags,
    required this.isCharging,
    required this.isInUse,
  });

  factory Battery.fromJson(Map<String, dynamic> json) {
    final flagsJson = json['flags'] as List<dynamic>? ?? [];

    return Battery(
      label: json['label'] as String? ?? '',
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      flags: flagsJson
          .map((f) => FlagEntry.fromJson(f as Map<String, dynamic>))
          .toList(),
      isCharging: json['isCharging'] as bool? ?? false,
      isInUse: json['isInUse'] as bool? ?? false,
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
  static const String _base = 'https://ridgeboticsapp.onrender.com';

  List<Battery> _batteries = [];
  bool _isLoading = true;
  String? _error;
  String? _passcode;
  String? teamNum;
  String? teamName;
  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final team = prefs.getString('battery_team');
    final pass = prefs.getString('battery_passcode');
    final guest = prefs.getBool('battery_guest') ?? false;
    final savedTeamName = prefs.getString('battery_team_name');

    if (team == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const BatteryLoginScreen()),
      );
      return;
    }

    teamNum = team;
    _passcode = pass;
    _isGuest = guest;
    teamName = savedTeamName;

    await loadingBatteries();
  }

  Future<void> loadingBatteries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final uri = _isGuest
          ? Uri.parse('$_base/battery/list?teamNumber=$teamNum&guest=true')
          : Uri.parse(
              '$_base/battery/list?teamNumber=$teamNum&passcode=$_passcode',
            );

      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode == 401) {
        await _logout();
        return;
      }

      if (res.statusCode == 404) {
        setState(() {
          _error = 'Team not found';
          _isLoading = false;
        });
        return;
      }

      if (res.statusCode != 200) {
        setState(() {
          _error = 'Could not load batteries';
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newTeamName = data['teamName'] as String?;

      if (newTeamName != null && newTeamName != teamName) {
        teamName = newTeamName;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('battery_team_name', newTeamName);
      }

      setState(() {
        _batteries = (data['batteries'] as List<dynamic>? ?? [])
            .map((b) => Battery.fromJson(b as Map<String, dynamic>))
            .toList();
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
    await prefs.remove('battery_team');
    await prefs.remove('battery_passcode');
    await prefs.remove('battery_guest');
    await prefs.remove('battery_team_name');

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const BatteryLoginScreen()),
    );
  }

  Future<void> inUse(Battery battery) async {
    if (_isGuest) return;

    try {
      final res = await http.post(
        Uri.parse('$_base/battery/use'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'teamNumber': teamNum,
          'passcode': _passcode,
          'label': battery.label,
        }),
      );

      if (res.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Use failed: ${res.statusCode}')),
        );
        return;
      }

      await loadingBatteries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update, try again')),
      );
    }
  }

  Future<void> charging(Battery battery) async {
    if (_isGuest) return;

    try {
      final res = await http.post(
        Uri.parse('$_base/battery/charging'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'teamNumber': teamNum,
          'passcode': _passcode,
          'label': battery.label,
        }),
      );

      if (res.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Charging failed: ${res.statusCode}')),
        );
        return;
      }

      await loadingBatteries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update, try again')),
      );
    }
  }

  Future<void> flagging(Battery battery) async {
    if (_isGuest) return;

    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Flag ${battery.label}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This marks the battery as weak or unreliable.'),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Example: died after auto',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: redChar),
            onPressed: () async {
              Navigator.pop(ctx);

              try {
                final res = await http.post(
                  Uri.parse('$_base/battery/flag'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'teamNumber': teamNum,
                    'passcode': _passcode,
                    'label': battery.label,
                    'note': noteCtrl.text.trim(),
                  }),
                );

                if (res.statusCode != 200) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Flag failed: ${res.statusCode}')),
                  );
                  return;
                }

                await loadingBatteries();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not flag battery.')),
                );
              }
            },
            child: const Text('Flag'),
          ),
        ],
      ),
    );
  }

  Future<void> addingBat() async {
    if (_isGuest) return;

    try {
      final res = await http.post(
        Uri.parse('$_base/battery/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'teamNumber': teamNum,
          'passcode': _passcode,
        }),
      );

      if (res.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add failed: ${res.statusCode}')),
        );
        return;
      }

      await loadingBatteries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add battery.')),
      );
    }
  }

  Color batteryColor(Battery battery) {
    if (battery.isInUse) return redChar;
    return battery.isCharging ? greenChar : redChar;
  }

  String batteryStatus(Battery battery) {
    if (battery.isInUse) return 'IN USE';
    if (battery.isCharging) return 'CHARGING';
    return 'NOT CHARGING';
  }

  String _formatRestTime(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m ago';
    return '${d.inDays}d ago';
  }

  Battery _recommendedBattery() {
    return _batteries.firstWhere(
      (b) => !b.isCharging && !b.isInUse,
      orElse: () => _batteries.first,
    );
  }

  void _viewFlags(Battery battery) {
    if (battery.flags.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${battery.label} Flags',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            ...battery.flags.reversed.map(
              (flag) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(flag.note.isEmpty ? 'No reason provided' : flag.note),
                    const SizedBox(height: 3),
                    Text(
                      _formatRestTime(
                        DateTime.now().difference(flag.flaggedAt),
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
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

  void _showPasscode() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Team Passcode'),
        content: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: YellorLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _passcode ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                    color: YellorDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy, color: Yellor),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _passcode ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied!')),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showChangePasscode() {
    final ctrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Change passcode'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'New passcode',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final newPass = ctrl.text.trim();

                if (newPass.length < 4) {
                  setDialogState(() => error = 'At least 4 characters');
                  return;
                }

                try {
                  final res = await http.post(
                    Uri.parse('$_base/battery/changePasscode'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'teamNumber': teamNum,
                      'passcode': _passcode,
                      'newPasscode': newPass,
                    }),
                  );

                  if (res.statusCode == 200) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('battery_passcode', newPass);
                    setState(() => _passcode = newPass);

                    if (!mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passcode updated')),
                    );
                  } else {
                    setDialogState(() => error = 'Failed, try again');
                  }
                } catch (e) {
                  setDialogState(() => error = 'Could not connect');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showStartFresh() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start fresh?'),
        content: const Text(
          'This will delete ALL batteries for your team. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: redChar),
            onPressed: () async {
              Navigator.pop(ctx);

              try {
                final res = await http.post(
                  Uri.parse('$_base/battery/reset'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'teamNumber': teamNum,
                    'passcode': _passcode,
                  }),
                );

                if (res.statusCode == 200) {
                  await loadingBatteries();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All batteries cleared')),
                  );
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not reset, try again')),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not reset, try again')),
                );
              }
            },
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Team $teamNum',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isGuest ? 'Viewing as guest' : 'Logged in',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 20),
            if (!_isGuest) ...[
              _settingsTile(
                Icons.visibility_outlined,
                'Show passcode',
                _showPasscode,
              ),
              _settingsTile(
                Icons.lock_outline,
                'Change passcode',
                _showChangePasscode,
              ),
              _settingsTile(
                Icons.refresh,
                'New comp / start fresh',
                _showStartFresh,
                color: redChar,
              ),
              const SizedBox(height: 8),
            ],
            _settingsTile(Icons.logout, 'Leave team', () {
              Navigator.pop(ctx);
              _logout();
            }),
          ],
        ),
      ),
    );
  }

  Widget _settingsTile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    final c = color ?? Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 15, color: c)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 248),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: buildWidgets()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final title = teamName != null
        ? 'Team $teamNum -> $teamName'
        : 'Team $teamNum';

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_isGuest)
                  Text(
                    'Guest view (read only)',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showSettings,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: YellorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.more_horiz, color: Yellor, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildWidgets() {
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
              onTap: loadingBatteries,
              child: const Text(
                'Try again',
                style: TextStyle(color: Yellor, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: Yellor,
      onRefresh: loadingBatteries,
      child: _batteries.isEmpty ? empty() : allBatteri(),
    );
  }

  Widget empty() {
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
          child: const Icon(
            Icons.battery_charging_full,
            color: Yellor,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'No batteries yet',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          _isGuest
              ? 'This team has no batteries logged yet.'
              : 'Add your first one below.',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        if (!_isGuest) ...[
          const SizedBox(height: 20),
          adding(),
        ],
      ],
    );
  }

  Widget allBatteri() {
    final recommendedBattery = _recommendedBattery();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        topPick(recommendedBattery),
        const SizedBox(height: 16),
        Text(
          'All batteries',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        ..._batteries.map(batteryTil),
        const SizedBox(height: 12),
        if (!_isGuest) adding(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget topPick(Battery battery) {
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
                Text(
                  'RECOMMENDED BATTERY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(.8),
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  battery.label,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  batteryStatus(battery),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: batteryColor(battery),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  battery.restTime.inDays >= 1000
                      ? 'Just added'
                      : 'Resting ${_formatRestTime(battery.restTime)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                if (battery.flags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _viewFlags(battery),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Flagged ${battery.flags.length}x',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_isGuest)
            Column(
              children: [
                GestureDetector(
                  onTap: () => charging(battery),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: battery.isCharging ? greenChar : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      battery.isCharging ? 'Charging' : 'Mark charging',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: battery.isCharging ? Colors.white : YellorDark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => flagging(battery),
                  child: Text(
                    'Flag weak',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(.85),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget batteryTil(Battery battery) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withOpacity(0.07),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 46,
            decoration: BoxDecoration(
              color: batteryColor(battery),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  battery.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (battery.isInUse)
                  const Text(
                    'IN USE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batteryStatus(battery),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: batteryColor(battery),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  battery.restTime.inDays >= 1000
                      ? 'Just added'
                      : 'Resting ${_formatRestTime(battery.restTime)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (battery.flags.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: () => _viewFlags(battery),
                    child: Text(
                      'flagged ${battery.flags.length}x -> tap to view',
                      style: const TextStyle(
                        fontSize: 11,
                        color: redChar,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_isGuest) ...[
            GestureDetector(
              onTap: () => charging(battery),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: battery.isCharging ? greenChar : YellorLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  battery.isCharging ? 'Charging' : 'Charge',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: battery.isCharging ? Colors.white : YellorDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => inUse(battery),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: battery.isInUse ? redChar : YellorLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  battery.isInUse ? 'In use' : 'Use',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: battery.isInUse ? Colors.white : YellorDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => flagging(battery),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.flag_outlined,
                  size: 16,
                  color: Colors.grey[500],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget adding() {
    return GestureDetector(
      onTap: addingBat,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.black.withOpacity(0.1),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Yellor, size: 18),
            const SizedBox(width: 7),
            Text(
              'Add battery',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}