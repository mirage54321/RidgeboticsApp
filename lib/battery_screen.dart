import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'batteryLOGIN_screen.dart';

const Yellor = Color(0xFFFFC107);
const YellorLight = Color(0xFFFFF4E5);
const YellorDark = Color(0xFFB38600);

class FlagEntry {
  final String note;
  final DateTime flaggedAt;
  FlagEntry({required this.note, required this.flaggedAt});

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

  Battery({required this.label, required this.lastUsedAt, required this.flags});

  factory Battery.fromJson(Map<String, dynamic> json) {
    final flagsJson = json['flags'] as List<dynamic>? ?? [];
    return Battery(
      label: json['label'] as String,
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      flags: flagsJson.map((f) => FlagEntry.fromJson(f)).toList(),
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
  String? _teamNumber;
  String? _teamName;
  bool _isGuest = false;

  String? _recommendedLabel;
  String? _recommendReason;
  bool _loadingRecommendation = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final team = prefs.getString('battery_team');
    final pass = prefs.getString('battery_passcode');
    final guest = prefs.getBool('battery_guest') ?? false;
    final teamName = prefs.getString('battery_team_name');

    if (team == null) {
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const BatteryLoginScreen()));
      return;
    }

    _teamNumber = team;
    _passcode = pass;
    _isGuest = guest;
    _teamName = teamName;
    await _loadBatteries();
  }

  Future<void> _loadBatteries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final uri = _isGuest
          ? Uri.parse('$_base/battery/list?teamNumber=$_teamNumber&guest=true')
          : Uri.parse(
              '$_base/battery/list?teamNumber=$_teamNumber&passcode=$_passcode');

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

      final data = jsonDecode(res.body);
      final teamName = data['teamName'] as String?;
      if (teamName != null && teamName != _teamName) {
        _teamName = teamName;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('battery_team_name', teamName);
      }

      setState(() {
        _batteries = (data['batteries'] as List<dynamic>)
            .map((b) => Battery.fromJson(b))
            .toList();
        _isLoading = false;
        _recommendedLabel = null;
        _recommendReason = null;
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
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const BatteryLoginScreen()));
  }

  Future<void> _markInUse(Battery battery) async {
    if (_isGuest) return;
    try {
      await http.post(Uri.parse('$_base/battery/use'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'teamNumber': _teamNumber,
            'passcode': _passcode,
            'label': battery.label,
          }));
      await _loadBatteries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update, try again')));
    }
  }

  Future<void> _askAiRecommendation() async {
    if (_isGuest || _batteries.isEmpty) return;
    setState(() => _loadingRecommendation = true);
    try {
      final res = await http.post(
        Uri.parse('$_base/battery/recommend'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'teamNumber': _teamNumber, 'passcode': _passcode}),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _recommendedLabel = data['recommendedLabel'] as String?;
          _recommendReason = data['reason'] as String?;
          _loadingRecommendation = false;
        });
      } else {
        setState(() => _loadingRecommendation = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get a recommendation')));
      }
    } catch (e) {
      setState(() => _loadingRecommendation = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect, try again')));
    }
  }

  Future<void> _flagWeak(Battery battery) async {
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
            const Text('Marks this battery as underperforming.'),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: 'Why? (optional)',
                hintText: 'e.g. died after 2 minutes',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await http.post(Uri.parse('$_base/battery/flag'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'teamNumber': _teamNumber,
                      'passcode': _passcode,
                      'label': battery.label,
                      'note': noteCtrl.text.trim(),
                    }));
                await _loadBatteries();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not flag, try again')));
              }
            },
            child: const Text('Flag it'),
          ),
        ],
      ),
    );
  }

  void _viewFlags(Battery battery) {
    if (battery.flags.isEmpty) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${battery.label} flags',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            ...battery.flags.reversed.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.note.isEmpty ? 'No reason given' : f.note,
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        _formatRestTime(DateTime.now().difference(f.flaggedAt)),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _addBattery() async {
    if (_isGuest) return;
    try {
      await http.post(Uri.parse('$_base/battery/add'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'teamNumber': _teamNumber, 'passcode': _passcode}));
      await _loadBatteries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add battery, try again')));
    }
  }

  void _showPasscode() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your passcode'),
        content: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: YellorLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_passcode ?? '',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: YellorDark,
                        letterSpacing: 2)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy, color: Yellor),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _passcode ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')));
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'New passcode',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                      'teamNumber': _teamNumber,
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
                        const SnackBar(content: Text('Passcode updated')));
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
            'This will delete ALL batteries for your team. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final res = await http.post(Uri.parse('$_base/battery/reset'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'teamNumber': _teamNumber,
                      'passcode': _passcode,
                    }));
                if (res.statusCode == 200) {
                  await _loadBatteries();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All batteries cleared')));
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not reset, try again')));
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not reset, try again')));
              }
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFD93025)),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Team $_teamNumber',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(_isGuest ? 'Viewing as guest' : 'Logged in',
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 20),
            if (!_isGuest) ...[
              _settingsTile(Icons.visibility_outlined, 'Show passcode', _showPasscode),
              _settingsTile(Icons.lock_outline, 'Change passcode', _showChangePasscode),
              _settingsTile(Icons.refresh, 'New comp / start fresh', _showStartFresh,
                  color: const Color(0xFFD93025)),
              const SizedBox(height: 8),
            ],
            _settingsTile(Icons.logout, 'Log out', () {
              Navigator.pop(ctx);
              _logout();
            }),
          ],
        ),
      ),
    );
  }

  Widget _settingsTile(IconData icon, String label, VoidCallback onTap, {Color? color}) {
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

  String _formatRestTime(Duration d) {
    if (d.inMinutes < 1) return 'just now';
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
    final title = _teamName != null
        ? 'Team $_teamNumber — $_teamName'
        : 'Team $_teamNumber';
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
                  color: YellorLight, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.arrow_back, color: Yellor, size: 17),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                if (_isGuest)
                  Text('Guest view — read only',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showSettings,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: YellorLight, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.more_horiz, color: Yellor, size: 18),
            ),
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
                  style: TextStyle(color: Yellor, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: Yellor,
      onRefresh: _loadBatteries,
      child: _batteries.isEmpty ? _emptyState() : _list(),
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
              color: YellorLight, borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.battery_charging_full, color: Yellor, size: 28),
        ),
        const SizedBox(height: 16),
        const Text('No batteries yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(
            _isGuest
                ? 'This team has no batteries logged yet.'
                : 'Add your first one below.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        if (!_isGuest) ...[const SizedBox(height: 20), _addButton()],
      ],
    );
  }

  Widget _list() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _topPick(),
        if (!_isGuest) ...[
          const SizedBox(height: 10),
          _aiRecommendCard(),
        ],
        const SizedBox(height: 16),
        Text('All batteries',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600])),
        const SizedBox(height: 8),
        ..._batteries.skip(1).map(_batteryTile),
        const SizedBox(height: 12),
        if (!_isGuest) _addButton(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _aiRecommendCard() {
    if (_loadingRecommendation) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: const [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Yellor),
            ),
            SizedBox(width: 10),
            Text('Asking AI which battery to use...',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }

    if (_recommendedLabel != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: YellorLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: YellorDark, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI suggests $_recommendedLabel',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: YellorDark)),
                  if (_recommendReason != null)
                    Text(_recommendReason!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _askAiRecommendation,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.1), width: 0.5),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, color: YellorDark, size: 16),
            SizedBox(width: 7),
            Text('Ask AI which battery to use',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: YellorDark)),
          ],
        ),
      ),
    );
  }

  Widget _topPick() {
    final battery = _batteries.first;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Yellor, borderRadius: BorderRadius.circular(20)),
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
                if (battery.flags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _viewFlags(battery),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('flagged ${battery.flags.length}x',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white)),
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
                  onTap: () => _markInUse(battery),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12)),
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
        border: Border.all(color: Colors.black.withValues(alpha: 0.07), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: YellorLight, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(battery.label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: YellorDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resting ${_formatRestTime(battery.restTime)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                if (battery.flags.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: () => _viewFlags(battery),
                    child: Text('flagged ${battery.flags.length}x — tap to view',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFD93025))),
                  ),
                ],
              ],
            ),
          ),
          if (!_isGuest) ...[
            GestureDetector(
              onTap: () => _markInUse(battery),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: YellorLight, borderRadius: BorderRadius.circular(10)),
                child: const Text('Use',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500, color: YellorDark)),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _flagWeak(battery),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.flag_outlined, size: 16, color: Colors.grey[500]),
              ),
            ),
          ],
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
          border: Border.all(color: Colors.black.withValues(alpha: 0.1), width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Yellor, size: 18),
            const SizedBox(width: 7),
            Text('Add battery',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}