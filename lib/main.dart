import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'domain/entities/health_reading.dart';
import 'domain/entities/wearable_device_info.dart';
import 'domain/services/i_wearable_service.dart';
import 'data/services/mock_wearable_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const PulseSyncMobileApp());
}

/// User Profile & Authenticated Session Model
class AuthUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String token;
  final String avatarInitials;
  final int stepGoal;
  final DateTime sessionStartTime;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.token,
    required this.avatarInitials,
    this.stepGoal = 10000,
    required this.sessionStartTime,
  });
}

final List<AuthUser> kDemoUsers = [
  AuthUser(
    id: 'user-alex-m',
    name: 'Dr. Alex Morgan',
    email: 'alex.morgan@healthpulse.io',
    role: 'Cardiology Specialist & Runner',
    token: 'jwt_mock_alex_998124_sess',
    avatarInitials: 'AM',
    stepGoal: 12000,
    sessionStartTime: DateTime.now(),
  ),
  AuthUser(
    id: 'user-sarah-c',
    name: 'Sarah Chen',
    email: 'sarah.chen@athletics.org',
    role: 'Triathlon Athlete',
    token: 'jwt_mock_sarah_118742_sess',
    avatarInitials: 'SC',
    stepGoal: 16000,
    sessionStartTime: DateTime.now(),
  ),
  AuthUser(
    id: 'user-marcus-v',
    name: 'Marcus Vance',
    email: 'marcus.vance@outlook.com',
    role: 'Cardiac Rehab Patient',
    token: 'jwt_mock_marcus_553201_sess',
    avatarInitials: 'MV',
    stepGoal: 7500,
    sessionStartTime: DateTime.now(),
  ),
];

class PulseSyncMobileApp extends StatelessWidget {
  const PulseSyncMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulseSync Wearable Health',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF020617), // slate-950
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF06B6D4), // cyan-500
          secondary: Color(0xFF10B981), // emerald-500
          surface: Color(0xFF0F172A), // slate-900
        ),
      ),
      home: const MobileHomeScreen(),
    );
  }
}

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final MockWearableService _wearableService = MockWearableService();
  
  // Authentication & Session State
  AuthUser? _currentUser; // Starts unauthenticated so Login page is shown first
  bool _isAuthenticated = false;

  // Live Telemetry State
  DeviceConnectionState _connectionState = DeviceConnectionState.connected;
  WearableDeviceInfo? _device;
  HealthReading? _latestReading;
  final List<HealthReading> _recentReadings = [];
  final List<double> _ecgWaveformData = [];
  int _batteryLevel = 88;
  bool _isNetworkOnline = true;
  bool _isSyncing = false;
  int _pendingSyncCount = 0;
  final List<String> _syncLogs = [];
  String _selectedActivity = 'Resting';
  int _selectedHistoryDays = 7;

  late AnimationController _pulseController;
  StreamSubscription? _connSub;
  StreamSubscription? _telemetrySub;
  StreamSubscription? _batterySub;
  Timer? _ecgTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _initEcgWaveform();
    _initWearableListeners();
  }

  void _initEcgWaveform() {
    for (int i = 0; i < 40; i++) {
      _ecgWaveformData.add(0.0);
    }

    int step = 0;
    _ecgTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (!mounted) return;
      step++;
      double val = 0.0;
      int mod = step % 24;
      if (mod == 3) val = 0.2;
      else if (mod == 4) val = -0.3;
      else if (mod == 5) val = 1.0;
      else if (mod == 6) val = -0.4;
      else if (mod == 7) val = 0.3;
      else if (mod == 8) val = 0.0;
      else val = (sin(step * 0.2) * 0.05);

      setState(() {
        if (_ecgWaveformData.length > 40) {
          _ecgWaveformData.removeAt(0);
        }
        _ecgWaveformData.add(val);
      });
    });
  }

  void _initWearableListeners() {
    _connSub = _wearableService.connectionStateStream.listen((state) {
      setState(() {
        _connectionState = state;
        _device = _wearableService.activeDevice;
      });
    });

    _telemetrySub = _wearableService.telemetryStream.listen((reading) {
      setState(() {
        _latestReading = reading;
        _batteryLevel = reading.batteryLevel;
        _recentReadings.insert(0, reading);
        if (_recentReadings.length > 30) {
          _recentReadings.removeLast();
        }
        if (!_isNetworkOnline) {
          _pendingSyncCount++;
        }
      });
    });

    _batterySub = _wearableService.batteryStream.listen((lvl) {
      setState(() => _batteryLevel = lvl);
    });

    // Auto-connect to wearable
    _wearableService.connect('pulse-band-pro-8f2a');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _connSub?.cancel();
    _telemetrySub?.cancel();
    _batterySub?.cancel();
    _ecgTimer?.cancel();
    _wearableService.dispose();
    super.dispose();
  }

  // Auth Operations: Login, Logout, Switch User
  void _loginUser(AuthUser user) {
    setState(() {
      _currentUser = user;
      _isAuthenticated = true;
    });
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Welcome back, ${user.name}! Authenticated session active.'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _logoutUser() {
    setState(() {
      _currentUser = null;
      _isAuthenticated = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signed out successfully. Session destroyed.'),
        backgroundColor: Color(0xFF0F172A),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openAuthModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildLoginBottomSheet(ctx),
    );
  }

  void _openSessionProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSessionProfileSheet(ctx),
    );
  }

  void _triggerSync() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _syncLogs.insert(0, '[${DateFormat('HH:mm:ss').format(DateTime.now())}] Sync started by user ${_currentUser?.name ?? 'Guest'}...');
    });

    await Future.delayed(const Duration(milliseconds: 1400));

    if (mounted) {
      setState(() {
        _isSyncing = false;
        final syncedItems = _pendingSyncCount > 0 ? _pendingSyncCount : 12;
        _pendingSyncCount = 0;
        _syncLogs.insert(0, '[${DateFormat('HH:mm:ss').format(DateTime.now())}] Uploaded $syncedItems records to patient account.');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud sync complete. All local records backed up to cloud.'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.favorite, color: Color(0xFF06B6D4), size: 18),
            ),
            const SizedBox(width: 8),
            const Text(
              'PulseSync',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          // Network Online/Offline Simulator
          IconButton(
            icon: Icon(
              _isNetworkOnline ? Icons.wifi : Icons.wifi_off,
              color: _isNetworkOnline ? const Color(0xFF38BDF8) : Colors.amberAccent,
              size: 20,
            ),
            tooltip: _isNetworkOnline ? 'Network Online' : 'Offline Mode',
            onPressed: () {
              setState(() {
                _isNetworkOnline = !_isNetworkOnline;
              });
            },
          ),
          // Battery Status Pill
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_connected, size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 4),
                Text('$_batteryLevel%', style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // User Avatar / Login Action
          Padding(
            padding: const EdgeInsets.only(right: 8.0, left: 4.0),
            child: _isAuthenticated && _currentUser != null
                ? GestureDetector(
                    onTap: _openSessionProfileSheet,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFF06B6D4),
                      child: Text(
                        _currentUser!.avatarInitials,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _openAuthModal,
                    icon: const Icon(Icons.login, size: 16, color: Color(0xFF06B6D4)),
                    label: const Text('Login', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
      body: !_isAuthenticated
          ? _buildMobileLoginScreen()
          : _buildSelectedTabContent(),
      bottomNavigationBar: !_isAuthenticated
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (idx) => setState(() => _selectedIndex = idx),
              backgroundColor: const Color(0xFF0F172A),
              selectedItemColor: const Color(0xFF06B6D4),
              unselectedItemColor: Colors.white38,
              type: BottomNavigationBarType.fixed,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              items: [
                const BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Live'),
                const BottomNavigationBarItem(icon: Icon(Icons.show_chart_rounded), label: 'Trends'),
                BottomNavigationBarItem(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.sync_rounded),
                      if (_pendingSyncCount > 0)
                        Positioned(
                          right: -6,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.indigoAccent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$_pendingSyncCount',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                  label: 'Sync Queue',
                ),
                const BottomNavigationBarItem(icon: Icon(Icons.bluetooth_audio_rounded), label: 'Device & BLE'),
              ],
            ),
    );
  }

  // ==========================================
  // AUTHENTICATION SCREENS & BOTTOM SHEETS
  // ==========================================

  /// Dedicated Full-Screen Mobile Login View (Shown first before Dashboard)
  Widget _buildMobileLoginScreen() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF020617),
            Color(0xFF0F172A),
            Color(0xFF020617),
          ],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Brand & Icon
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF06B6D4).withOpacity(0.15),
                        border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.4), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF06B6D4).withOpacity(0.2),
                            blurRadius: 20,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: const Icon(Icons.monitor_heart_rounded, size: 42, color: Color(0xFF06B6D4)),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'PulseSync Wearable',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Continuous Vital Intelligence & Edge Sync',
                      style: TextStyle(fontSize: 12, color: Color(0xFF38BDF8), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Biometric Quick Unlock Simulator Button
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Simulating Biometric Touch / Face ID unlock...'),
                      backgroundColor: Color(0xFF06B6D4),
                      duration: Duration(milliseconds: 900),
                    ),
                  );
                  Future.delayed(const Duration(milliseconds: 600), () {
                    _loginUser(kDemoUsers[0]);
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.fingerprint_rounded, color: Color(0xFF06B6D4), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Quick Unlock with Face / Touch ID', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('Simulate instant biometric authentication', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF06B6D4), size: 14),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Quick Persona 1-Tap Select
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'CHOOSE CLINICAL TEST PERSONA',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF06B6D4), letterSpacing: 0.5),
                  ),
                  Text('1-Tap Login', style: TextStyle(fontSize: 10, color: Colors.white38)),
                ],
              ),
              const SizedBox(height: 8),

              ...kDemoUsers.map((user) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: InkWell(
                    onTap: () => _loginUser(user),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF06B6D4).withOpacity(0.25),
                            child: Text(user.avatarInitials, style: const TextStyle(color: Color(0xFF06B6D4), fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                Text(user.role, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Enter', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 14),

              // Divider
              Row(
                children: const [
                  Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('OR SIGN IN WITH EMAIL', style: TextStyle(fontSize: 10, color: Colors.white38, letterSpacing: 0.5)),
                  ),
                  Expanded(child: Divider(color: Colors.white12)),
                ],
              ),
              const SizedBox(height: 14),

              // Custom Input Form
              TextField(
                controller: emailController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. alex.morgan@healthpulse.io',
                  hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                  prefixIcon: const Icon(Icons.email_outlined, size: 18, color: Color(0xFF06B6D4)),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF06B6D4))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter password (any accepted)',
                  hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                  prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF06B6D4)),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF06B6D4))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final email = emailController.text.trim();
                    final customUser = AuthUser(
                      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                      name: email.isNotEmpty ? email.split('@')[0] : 'Pulse User',
                      email: email.isNotEmpty ? email : 'user@pulsesync.io',
                      role: 'Authenticated User',
                      token: 'jwt_custom_${DateTime.now().millisecondsSinceEpoch}',
                      avatarInitials: email.isNotEmpty ? email.substring(0, min(2, email.length)).toUpperCase() : 'PU',
                      sessionStartTime: DateTime.now(),
                    );
                    _loginUser(customUser);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 4,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Enter PulseSync Dashboard', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 16),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text('AES-256 Encrypted Session • HIPAA Safe', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Interactive Login Modal with Presets & Custom Form
  Widget _buildLoginBottomSheet(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shield_outlined, color: Color(0xFF06B6D4), size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Sign In to PulseSync', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('Choose a test persona or sign in', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'SELECT PRESET CLINICAL TEST ACCOUNT',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF06B6D4), letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            ...kDemoUsers.map((user) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: InkWell(
                  onTap: () => _loginUser(user),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF020617),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF06B6D4).withOpacity(0.2),
                          child: Text(user.avatarInitials, style: const TextStyle(color: Color(0xFF06B6D4), fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                              Text(user.role, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            const Center(
              child: Text('— OR SIGN IN WITH CREDENTIALS —', style: TextStyle(fontSize: 10, color: Colors.white38, letterSpacing: 0.5)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                hintText: 'Enter clinical email (e.g. user@pulse.io)',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                prefixIcon: const Icon(Icons.email_outlined, size: 18, color: Color(0xFF06B6D4)),
                filled: true,
                fillColor: const Color(0xFF020617),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Enter password',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF06B6D4)),
                filled: true,
                fillColor: const Color(0xFF020617),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final email = emailController.text.trim();
                  final customUser = AuthUser(
                    id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                    name: email.isNotEmpty ? email.split('@')[0] : 'Pulse User',
                    email: email.isNotEmpty ? email : 'user@pulsesync.io',
                    role: 'Authenticated User',
                    token: 'jwt_custom_${DateTime.now().millisecondsSinceEpoch}',
                    avatarInitials: email.isNotEmpty ? email.substring(0, min(2, email.length)).toUpperCase() : 'PU',
                    sessionStartTime: DateTime.now(),
                  );
                  _loginUser(customUser);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Sign In to Session', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Active Session Information Bottom Sheet (User info, token, logout)
  Widget _buildSessionProfileSheet(BuildContext context) {
    if (_currentUser == null) return const SizedBox.shrink();
    final user = _currentUser!;
    final sessionDuration = DateTime.now().difference(user.sessionStartTime).inMinutes;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF06B6D4),
                child: Text(user.avatarInitials, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text(user.email, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6D4).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(user.role, style: const TextStyle(fontSize: 10, color: Color(0xFF06B6D4), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                _buildSessionRow('Session Status', 'Active • Encrypted (AES-256)'),
                _buildSessionRow('Session Age', '$sessionDuration min ago'),
                _buildSessionRow('Auth Token', '${user.token.substring(0, 16)}...'),
                _buildSessionRow('Daily Step Goal', '${user.stepGoal} steps'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openAuthModal();
                  },
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16, color: Color(0xFF06B6D4)),
                  label: const Text('Switch User', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF06B6D4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _logoutUser();
                  },
                  icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.redAccent),
                  label: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.12),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.redAccent)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildLiveDashboardTab();
      case 1:
        return _buildTrendsHistoryTab();
      case 2:
        return _buildSyncQueueTab();
      case 3:
        return _buildDeviceManagerTab();
      default:
        return _buildLiveDashboardTab();
    }
  }

  // ==========================================
  // TAB 0: LIVE VITALS DASHBOARD
  // ==========================================
  Widget _buildLiveDashboardTab() {
    final hr = _latestReading?.heartRate ?? 74;
    final spo2 = _latestReading?.spo2 ?? 98.4;
    final steps = _latestReading?.steps ?? 6420;
    final cal = _latestReading?.caloriesBurned ?? 280;
    final hrv = _latestReading != null ? (60000 / (_latestReading!.heartRate)).round() : 820;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active Authenticated Session Banner
          if (_currentUser != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Session: ${_currentUser!.name}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  Text(
                    'Goal: ${_currentUser!.stepGoal} stp',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF06B6D4), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

          // Connected Wearable Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF06B6D4).withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _connectionState == DeviceConnectionState.connected
                                ? const Color(0xFF10B981)
                                : Colors.amberAccent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _connectionState == DeviceConnectionState.connected ? 'BLE Connected' : 'Reconnecting...',
                          style: TextStyle(
                            color: _connectionState == DeviceConnectionState.connected
                                ? const Color(0xFF10B981)
                                : Colors.amberAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _device?.name ?? 'PulseSync Band Pro',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Streaming BLE Telemetry @ 1.0 Hz',
                      style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF020617),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Icon(Icons.watch_rounded, color: Color(0xFF06B6D4), size: 28),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Real-time Animated ECG Waveform Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: 1.0 + (_pulseController.value * 0.25),
                              child: const Icon(Icons.favorite, color: Colors.redAccent, size: 16),
                            );
                          },
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Live ECG / PPG Rhythm Stream',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$hr BPM',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 60,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: EcgWaveformPainter(waveformData: _ecgWaveformData),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 6 Key Vitals Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.15,
            children: [
              _buildMetricCard('Heart Rate', '$hr', 'BPM', Icons.favorite_rounded, Colors.redAccent, 'Normal Sinus'),
              _buildMetricCard('Blood Oxygen', '${spo2.toStringAsFixed(1)}', '%', Icons.air_rounded, const Color(0xFF06B6D4), 'Optimal 98%+'),
              _buildMetricCard('Daily Steps', '$steps', 'steps', Icons.directions_walk_rounded, const Color(0xFF10B981), 'Target: ${_currentUser?.stepGoal ?? 10000}'),
              _buildMetricCard('RR / HRV', '$hrv', 'ms', Icons.grain_rounded, Colors.purpleAccent, 'Balanced ANS'),
              _buildMetricCard('Active Burn', '$cal', 'kcal', Icons.local_fire_department_rounded, Colors.orangeAccent, 'Cardio Burn'),
              _buildMetricCard('Battery Level', '$_batteryLevel', '%', Icons.battery_charging_full_rounded, Colors.amberAccent, 'Estimated 4d'),
            ],
          ),

          const SizedBox(height: 18),

          // Activity & Telemetry Mode Controller
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Simulation & Activity State',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildActivityChip('Resting', Icons.nightlight_round),
                    _buildActivityChip('Cardio Workout', Icons.directions_run),
                    _buildActivityChip('Deep Sleep', Icons.bedtime),
                    _buildActivityChip('Recovery', Icons.spa_rounded),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Live Telemetry Event Log
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Live Telemetry Packets',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      '${_recentReadings.length} Packets buffered',
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_recentReadings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text('Awaiting first Bluetooth telemetry packet...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: min(5, _recentReadings.length),
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 12),
                    itemBuilder: (context, idx) {
                      final item = _recentReadings[idx];
                      final timeStr = DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(item.timestamp));
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF06B6D4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(timeStr, style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace')),
                            ],
                          ),
                          Text('${item.heartRate} BPM', style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('${item.spo2.toStringAsFixed(1)}% SpO2', style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 11)),
                          Text('${item.steps} stp', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11)),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityChip(String label, IconData icon) {
    final isSelected = _selectedActivity == label;
    return ChoiceChip(
      avatar: Icon(icon, size: 14, color: isSelected ? Colors.black : const Color(0xFF06B6D4)),
      label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.w600)),
      selected: isSelected,
      selectedColor: const Color(0xFF06B6D4),
      backgroundColor: const Color(0xFF020617),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? const Color(0xFF06B6D4) : Colors.white12)),
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedActivity = label;
          });
        }
      },
    );
  }

  // ==========================================
  // TAB 1: HISTORY & TRENDS
  // ==========================================
  Widget _buildTrendsHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Historical Vital Analytics',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    _buildRangeButton('24H', 1),
                    _buildRangeButton('7D', 7),
                    _buildRangeButton('30D', 30),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Multi-day Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildSummaryStatCard('Avg Resting HR', '62 BPM', Icons.favorite_border, Colors.redAccent, '-2 vs last wk'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryStatCard('SpO2 Average', '98.6%', Icons.air, const Color(0xFF06B6D4), 'Stable 100%'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryStatCard('Daily Steps Avg', '8,420', Icons.directions_walk, const Color(0xFF10B981), '+14% target'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryStatCard('Deep Sleep', '7h 42m', Icons.bedtime, Colors.purpleAccent, '92% Recovery'),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 7-Day Heart Rate Trend Graph Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Heart Rate Distribution (BPM)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                    Text('Min: 58 • Max: 142', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: TrendChartPainter(
                      dataPoints: [64, 68, 72, 61, 88, 124, 98, 76, 70, 65, 62, 66],
                      lineColor: Colors.redAccent,
                      fillColor: Colors.redAccent.withOpacity(0.15),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Mon', style: TextStyle(fontSize: 10, color: Colors.white38)),
                    Text('Tue', style: TextStyle(fontSize: 10, color: Colors.white38)),
                    Text('Wed', style: TextStyle(fontSize: 10, color: Colors.white38)),
                    Text('Thu', style: TextStyle(fontSize: 10, color: Colors.white38)),
                    Text('Fri', style: TextStyle(fontSize: 10, color: Colors.white38)),
                    Text('Sat', style: TextStyle(fontSize: 10, color: Colors.white38)),
                    Text('Sun', style: TextStyle(fontSize: 10, color: Colors.white38)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Activity Zones Breakdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cardio Zones & Duration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                const SizedBox(height: 14),
                _buildZoneProgress('Peak Intensity (150+ BPM)', 0.12, Colors.purpleAccent, '18 min'),
                const SizedBox(height: 10),
                _buildZoneProgress('Cardio Workout (120-150 BPM)', 0.38, Colors.redAccent, '45 min'),
                const SizedBox(height: 10),
                _buildZoneProgress('Fat Burn Zone (90-120 BPM)', 0.55, Colors.orangeAccent, '1h 12m'),
                const SizedBox(height: 10),
                _buildZoneProgress('Resting / Recovery (<90 BPM)', 0.85, const Color(0xFF10B981), '8h 20m'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeButton(String label, int days) {
    final isSel = _selectedHistoryDays == days;
    return GestureDetector(
      onTap: () => setState(() => _selectedHistoryDays = days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF06B6D4) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSel ? Colors.black : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryStatCard(String label, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildZoneProgress(String label, double progress, Color color, String duration) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            Text(duration, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFF020617),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: SYNC QUEUE & OFFLINE ENGINE
  // ==========================================
  Widget _buildSyncQueueTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Offline & Cloud Sync Status Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0F172A),
                  _isNetworkOnline ? const Color(0xFF1E293B) : const Color(0xFF451A03),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _isNetworkOnline ? Colors.white10 : Colors.amber.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isNetworkOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          color: _isNetworkOnline ? const Color(0xFF10B981) : Colors.amberAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isNetworkOnline ? 'Cloud Sync Online' : 'Offline Queue Active',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _isNetworkOnline ? const Color(0xFF10B981) : Colors.amberAccent,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _triggerSync,
                      icon: _isSyncing
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.sync_rounded, size: 16, color: Colors.black),
                      label: Text(_isSyncing ? 'Syncing...' : 'Sync Now', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF06B6D4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF020617),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pending in SQLite', style: TextStyle(fontSize: 11, color: Colors.white54)),
                            const SizedBox(height: 4),
                            Text('$_pendingSyncCount records', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF020617),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Retry Strategy', style: TextStyle(fontSize: 11, color: Colors.white54)),
                            const SizedBox(height: 4),
                            const Text('Exponential (2^n)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF06B6D4))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Offline Queue Inspector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Local SQLite Transaction Logs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 12),
                if (_syncLogs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No recent sync errors or batch uploads yet. Toggle offline mode to test.', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: min(6, _syncLogs.length),
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 12),
                    itemBuilder: (context, idx) {
                      return Text(
                        _syncLogs[idx],
                        style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'monospace'),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: DEVICE & BLE MANAGER
  // ==========================================
  Widget _buildDeviceManagerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bluetooth Low Energy Hardware', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 14),

          // Active Hardware Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bluetooth_connected, color: Color(0xFF06B6D4), size: 22),
                        const SizedBox(width: 8),
                        Text(
                          _device?.name ?? 'PulseSync Band Pro',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Paired & Active', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Colors.white10),
                const SizedBox(height: 8),
                _buildDeviceInfoRow('MAC Address', 'F2:8B:C1:3D:8F:2A'),
                _buildDeviceInfoRow('Firmware Version', 'v3.4.1-ble'),
                _buildDeviceInfoRow('Hardware Revision', 'REV-B (Nordic nRF52840)'),
                _buildDeviceInfoRow('RSSI Signal Strength', '-58 dBm (Strong)'),
                _buildDeviceInfoRow('Sampling Frequency', '1.0 Hz (Continuous)'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Hardware Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _wearableService.disconnect(reason: 'User manual disconnect');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Device disconnected.'), duration: Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.bluetooth_disabled, size: 16, color: Colors.redAccent),
                  label: const Text('Disconnect', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.redAccent)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _wearableService.connect('pulse-band-pro-8f2a');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reconnected to PulseSync Band Pro.'), duration: Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.black),
                  label: const Text('Reconnect', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Discovered Nearby Devices
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nearby Discovered Wearables', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 12),
                _buildNearbyDeviceTile('PulseSync Smart Ring v2', 'SR-200-BLE', '-54 dBm', () {
                  _wearableService.connect('smart-ring-pro-9a1b');
                }),
                const Divider(color: Colors.white10, height: 16),
                _buildNearbyDeviceTile('PulseSync Chest Strap HRM', 'CS-900-ECG', '-68 dBm', () {
                  _wearableService.connect('pulse-chest-strap-01');
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          Text(value, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildNearbyDeviceTile(String name, String model, String rssi, VoidCallback onPair) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('$model • RSSI $rssi', style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
        OutlinedButton(
          onPressed: onPair,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF06B6D4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          ),
          child: const Text('Pair', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11)),
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, String unit, IconData icon, Color color, String caption) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500)),
              Icon(icon, size: 18, color: color),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(width: 4),
                  Text(unit, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                ],
              ),
              const SizedBox(height: 2),
              Text(caption, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// CUSTOM PAINTER: ECG / PPG WAVEFORM
// ==========================================
class EcgWaveformPainter extends CustomPainter {
  final List<double> waveformData;

  EcgWaveformPainter({required this.waveformData});

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFF06B6D4)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = const Color(0xFF06B6D4).withOpacity(0.3)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final stepX = size.width / (waveformData.length - 1);
    final centerY = size.height / 2;

    for (int i = 0; i < waveformData.length; i++) {
      final x = i * stepX;
      final y = centerY - (waveformData[i] * (size.height * 0.42));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);

    // Draw leading glow pulse dot
    if (waveformData.isNotEmpty) {
      final lastX = (waveformData.length - 1) * stepX;
      final lastY = centerY - (waveformData.last * (size.height * 0.42));
      canvas.drawCircle(Offset(lastX, lastY), 4, Paint()..color = const Color(0xFF10B981));
    }
  }

  @override
  bool shouldRepaint(covariant EcgWaveformPainter oldDelegate) => true;
}

// ==========================================
// CUSTOM PAINTER: TREND LINE CHART
// ==========================================
class TrendChartPainter extends CustomPainter {
  final List<double> dataPoints;
  final Color lineColor;
  final Color fillColor;

  TrendChartPainter({required this.dataPoints, required this.lineColor, required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final minVal = dataPoints.reduce(min);
    final maxVal = dataPoints.reduce(max);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (dataPoints.length - 1);

    for (int i = 0; i < dataPoints.length; i++) {
      final normY = 1.0 - ((dataPoints[i] - minVal) / range);
      final x = i * stepX;
      final y = 10 + (normY * (size.height - 20));

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Draw point circles
    for (int i = 0; i < dataPoints.length; i++) {
      final normY = 1.0 - ((dataPoints[i] - minVal) / range);
      final x = i * stepX;
      final y = 10 + (normY * (size.height - 20));
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant TrendChartPainter oldDelegate) => false;
}
