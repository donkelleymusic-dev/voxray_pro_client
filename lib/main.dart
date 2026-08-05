// ==============================================================================
// COPYRIGHT AND OWNERSHIP DECLARATION
// ==============================================================================
// Copyright (c) 2026 Donald Bayard Kelley. All Rights Reserved.
//
// voXRay Enterprise DSP & Roformer Engine
//
// PROPRIETARY AND CONFIDENTIAL
// This source code, algorithms, binaries, and related documentation are the
// exclusive intellectual property of Donald Bayard Kelley.
//
// Unauthorized copying, reproduction, distribution, modification, reverse
// engineering, or use of this file, via any medium, is strictly prohibited
// without the express written consent of the copyright holder. This software
// contains trade secrets and proprietary methodologies protected by Canadian
// and International intellectual property laws.
//
// AUTHOR AND CONTACT INFORMATION:
// Developer / Owner: Donald Bayard Kelley
// Jurisdiction: British Columbia, Canada
// Direct Inquiries: donkelleymusic@gmail.com
// YouTube: @don-music
// Instagram: @donmusicyt
//
// By accessing this codebase, you acknowledge and agree to respect the
// proprietary nature of this software.
// ==============================================================================

// ── What lives here ──────────────────────────────────────────────────────────
//   main()          — app entry point and Supabase init
//   VoxrayDAW       — StatefulWidget shell
//     — widget lifecycle, UI state fields, build(), all dialogs
//
// ── What was extracted ───────────────────────────────────────────────────────
//   models/channel_state.dart   ← ChannelState, DragMode
//   daw/daw_audio_controller.dart ← SoLoud playback, stem/synth loading
//   daw/daw_api_service.dart    ← all HTTP, polling, save/load, export
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/gestures.dart'; // for windows

import 'models/channel_state.dart';
import 'daw/daw_audio_controller.dart';
import 'daw/daw_api_service.dart';

import 'ui/timeline_canvas.dart';
import 'ui/timeline_ruler.dart';
import 'pedagogy/live_analyzer.dart';
import 'audio/vox_synth.dart';
import 'services/supabase_service.dart';
import 'screens/auth_screen.dart';
import 'screens/wallet_screen.dart';
import 'screens/account_settings_screen.dart';
import 'screens/about_info_screen.dart';
import 'screens/feedback_screen.dart';
import 'ui/drum_submixer_group.dart';
import 'ui/bouncing_eq_indicator.dart';
import 'ui/performance_scorecard.dart';
import 'ui/macro_minimap.dart';
//import 'screens/god_mode_dashboard.dart'

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

import 'models/audio_channel.dart';
import 'ui/dual_xray_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

Future<void> configureAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionMode: AVAudioSessionMode.defaultMode,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.music,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  ));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await configureAudioSession();
  
  await Supabase.initialize(
    url: 'https://dazqevapqvdpbdoypwke.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
        '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhenFldmFwcXZkcGJkb3lwd2tlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODU1MTcsImV4cCI6MjA5ODk2MTUxN30'
        '.hJvau902z0lAXRnwHPLa30HoLJzxJg4zQDzSXuh_Tjs',
  );

  // 1. Initialize your audio engine BEFORE the app UI runs!
  await SoLoud.instance.init(
    //sampleRate: 48000,     // Force standard CD-quality sample rate across all devices
    bufferSize: 256,      // Bump from 2048 to 4096 to give the phone speaker thread breathing room
    //channels: Channels.stereo,
  );

  // 2. Wrap your actual app logic directly inside Sentry's appRunner
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://d6a836c92a35e39f8a73a143d2bca99d@o4511748451729408.ingest.us.sentry.io/4511748461363200';
      options.tracesSampleRate = 1.0; 
      options.autoInitializeNativeSdk = false;
    },
    appRunner: () => runApp(
      MaterialApp(
        // Force Windows/Mac to allow click-and-drag scrolling with a mouse!
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.trackpad},
        ),
        home: const AppGatekeeper(),
        theme: ThemeData(brightness: Brightness.dark),
      )
    ), 
  );
  
  // Notice: The duplicate runApp() that used to be down here is now completely removed!
}

class AiDetectionResult {
  final Map<String, dynamic> fileInfo;
  final Map<String, dynamic> summary;
  final List<double> waveform;
  final List<dynamic> events;

  AiDetectionResult({
    required this.fileInfo,
    required this.summary,
    required this.waveform,
    required this.events,
  });

  // --- COMPATIBILITY SHIMS FOR TIMELINE_CANVAS.DART ---
  // These translate the new Python backend data into the variables your old UI expects!
  
  double get overallConfidence => (summary['ai_probability_score'] ?? 0.0) / 100.0;
  
  bool get isAiDetected => (summary['ai_probability_score'] ?? 0.0) >= 50.0;
  
  List<String> get detectedArtifacts => events.map((e) => e['metric_name'].toString()).toList();
  
  List<Map<String, dynamic>> get heatmap => []; // Leave empty so the old canvas painter safely skips it

  // ----------------------------------------------------

  factory AiDetectionResult.fromJson(Map<String, dynamic> json) {
    return AiDetectionResult(
      fileInfo: Map<String, dynamic>.from(json['file_info'] ?? {}),
      summary: Map<String, dynamic>.from(json['summary'] ?? {}),
      waveform: List<double>.from((json['waveform'] as List? ?? []).map((x) => (x as num).toDouble())),
      events: List<dynamic>.from(json['events'] ?? []),
    );
  }
}

enum XrayCompareMode { overlay, split }

class DualTakeXraySettings {
  // Take Data
  Uint8List? takeBAudioBytes;
  String takeBName;
  List<dynamic> takeBNotes;
  
  // Visuals
  double takeBOffsetSeconds; 
  double opacityB;            
  XrayCompareMode mode;
  Color colorA;
  Color colorB;
  
  // Auto-Align & Forensic Match Data
  bool hasMatch;
  double matchStartSeconds;
  double matchEndSeconds;
  double matchConfidence; 
  double lockInPulse; // For the snap animation flare

  DualTakeXraySettings({
    this.takeBAudioBytes,
    this.takeBName = "Secondary Vocal",
    this.takeBNotes = const [],
    this.takeBOffsetSeconds = 0.0,
    this.opacityB = 0.55,
    this.mode = XrayCompareMode.overlay,
    this.colorA = const Color(0xFF00E5FF), // Cyan
    this.colorB = const Color(0xFFFF007F), // Magenta
    this.hasMatch = false,
    this.matchStartSeconds = 0.0,
    this.matchEndSeconds = 0.0,
    this.matchConfidence = 0.0,
    this.lockInPulse = 0.0,
  });
}

// =========================================================================
// HARDWARE OPTIMIZED VU METER
// =========================================================================

class ChannelVuMeter extends StatelessWidget {
  final double level;
  
  const ChannelVuMeter({Key? key, required this.level}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(48, 6), // Matches your exact original dimensions
        painter: _HorizontalVuMeterPainter(level: level),
      ),
    );
  }
}

class _HorizontalVuMeterPainter extends CustomPainter {
  final double level;
  
  _HorizontalVuMeterPainter({required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    const int segments = 8; 
    final double segmentWidth = (size.width / segments) - 1; 
    
    // NO MORE MATH HERE. We already did the perfect dB conversion in timeline_canvas.dart!
    // Just multiply the incoming 0.0-1.0 level by 8 segments.
    final int activeSegments = (level * segments).ceil().clamp(0, segments);

    for (int i = 0; i < segments; i++) {
      final double x = i * (segmentWidth + 1);
      final Rect rect = Rect.fromLTWH(x, 0, segmentWidth, size.height);

      Color segmentColor;
      if (i >= segments - 1) {
        segmentColor = Colors.redAccent; // Clipping
      } else if (i >= segments - 3) {
        segmentColor = Colors.amberAccent; // Warning zone
      } else {
        segmentColor = Colors.greenAccent; // Safe zone
      }

      // Dim inactive segments heavily to look like unlit LEDs
      if (i >= activeSegments) {
        segmentColor = segmentColor.withOpacity(0.15);
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()..color = segmentColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HorizontalVuMeterPainter oldDelegate) {
    // Now correctly checks if the actual NUMBER of lit LEDs changed
    return (oldDelegate.level * 8).ceil() != (level * 8).ceil();
  }
}

class GodModeDashboard extends StatefulWidget {
  const GodModeDashboard({Key? key}) : super(key: key);

  @override
  State<GodModeDashboard> createState() => _GodModeDashboardState();
}

class _GodModeDashboardState extends State<GodModeDashboard> {
  Timer? _pollTimer;
  Map<String, dynamic> _status = {};
  bool _isLoading = true;
  String _userEmail = "";
  
  // Replace with your actual Modal endpoint URL
  final String _baseUrl = "https://donkelleymusic--voxray-pro-api-api.modal.run"; 

  @override
  void initState() {
    super.initState();
    _userEmail = BackendService.supabase.auth.currentUser?.email ?? "";
    _fetchStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/automl/status'),
        headers: {"x-user-email": _userEmail},
      );

      if (!mounted) return;
      
      if (res.statusCode == 200) {
        if (mounted) {
          setState(() {
            _status = jsonDecode(res.body);
            _isLoading = false;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _triggerAction(String endpoint) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Triggering $endpoint...")));
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/automl/$endpoint'),
        headers: {"x-user-email": _userEmail},
      );
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Success! ${data.toString()}"),
          backgroundColor: Colors.teal,
        ));
        _fetchStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error: ${res.body}"),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Network Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userEmail != "donkelleymusic@gmail.com") {
      return const Scaffold(body: Center(child: Text("ACCESS DENIED", style: TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.bold))));
    }

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('God Mode: AutoML Engine', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.red[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Backup DB to HuggingFace',
            onPressed: () => _triggerAction('backup'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // STEP 1: INGESTION CARD
            Card(
              color: const Color(0xFF1E1E1E),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Step 1: Dataset Ingestion', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Divider(color: Colors.white24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatColumn('AI Tracks', '${_status['ai_tracks'] ?? 0}', Colors.redAccent),
                        _buildStatColumn('Human Tracks', '${_status['human_tracks'] ?? 0}', Colors.greenAccent),
                        _buildStatColumn('Total Cached', '${(_status['ai_tracks'] ?? 0) + (_status['human_tracks'] ?? 0)}', Colors.white),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.precision_manufacturing),
                      label: const Text('Scan Directory & Extract Features'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                      onPressed: () => _triggerAction('ingest'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "To add data, use Modal CLI: modal volume put voxray-data-vol local_song.mp3 /training_audio/ai/",
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // STEP 2: OPTIMIZATION CARD
            Card(
              color: const Color(0xFF1E1E1E),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Step 2: Bayesian Optimization', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Divider(color: Colors.white24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatColumn('Trials Complete', '${_status['trials'] ?? 0}', Colors.blueAccent),
                        _buildStatColumn('Best F1 Score', '${_status['best_f1'] ?? 0.0}', Colors.amber),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Run 50 Optimization Trials'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
                      onPressed: () => _triggerAction('optimize?n_trials=50'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // WEIGHTS OUTPUT
            if (_status['best_params'] != null)
              Card(
                color: Colors.black,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Best Algorithm Weights', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                      const Divider(color: Colors.white24),
                      Text(
                        const JsonEncoder.withIndent('  ').convert(_status['best_params']),
                        style: const TextStyle(fontFamily: 'monospace', color: Colors.white70, fontSize: 12),
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

  Widget _buildStatColumn(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: valueColor)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// APP GATEKEEPER (Checks for saved login session & PRO status on startup)
// ─────────────────────────────────────────────────────────────────────────────
class AppGatekeeper extends StatefulWidget {
  const AppGatekeeper({Key? key}) : super(key: key);

  @override
  State<AppGatekeeper> createState() => _AppGatekeeperState();
}

class _AppGatekeeperState extends State<AppGatekeeper> {
  bool? _isLoggedIn;
  bool _isPro = false; // 👈 Default to false, but let's handle the checking state cleanly
  bool _isCheckingProfile = true; // 👈 Add a dedicated checking flag
  bool _isRecoveringPassword = false;
  
  @override
  void initState() {
    super.initState();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    BackendService.supabase.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      final event = data.event;

      // 🚨 CATCH THE RECOVERY LINK
      if (event == AuthChangeEvent.passwordRecovery) {
        if (mounted) {
          setState(() {
            _isRecoveringPassword = true;
            _isCheckingProfile = false;
          });
        }
        return; // Stop processing normal login flow
      }
      
      if (session == null) {
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _isPro = false;
            _isCheckingProfile = false; // Safe to stop checking when logged out
          });
        }
      } else {
        // 🚨 THE FIX: Force the loader on immediately when a session appears
        if (mounted) {
          setState(() {
            _isLoggedIn = true;
            _isCheckingProfile = true; 
          });
        }
        
        try {
          final response = await BackendService.supabase
              .from('profiles')
              .select('is_pro')
              .eq('id', session.user.id)
              .single();

          if (mounted) {
            setState(() {
              _isPro = response['is_pro'] as bool? ?? false;
              _isCheckingProfile = false; // Now it's safe to reveal the UI
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _isPro = false;
              _isCheckingProfile = false;
            });
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 0. PASSWORD RECOVERY MODE
    if (_isRecoveringPassword) {
      final TextEditingController _newPasswordController = TextEditingController();
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_reset, size: 64, color: Colors.pinkAccent),
                const SizedBox(height: 24),
                const Text("Set New Password", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 24),
                TextField(
                  controller: _newPasswordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    labelStyle: TextStyle(color: Colors.pinkAccent),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.pinkAccent)),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16)),
                  onPressed: () async {
                    try {
                      // Tell Supabase to securely update the password for the active session
                      await BackendService.supabase.auth.updateUser(
                        UserAttributes(password: _newPasswordController.text),
                      );
                      
                      // Turn off recovery mode and let the Gatekeeper route them into the DAW!
                      setState(() => _isRecoveringPassword = false);
                      
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                    }
                  },
                  child: const Text('Update Password', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // 1. If we are still figuring out auth OR querying the profile table, show a sleek loader
    if (_isLoggedIn == null || (_isLoggedIn! && _isCheckingProfile)) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
      );
    }
    
    // 2. Not Logged In
    if (!_isLoggedIn!) {
      return const AuthScreen();
    }

    // 3. Logged In, but paywall active (is_pro is false)
    if (!_isPro) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_clock, size: 64, color: Colors.white54),
                const SizedBox(height: 24),
                const Text(
                  "Account Pending Activation",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Your voXRay account has been created, but requires an active approved account to unlock the DSP engine.\n\nPlease check your email for your beta approval link, or visit voxray.info for more info.",
                  style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, color: Colors.pinkAccent),
                  label: const Text("Check Status", style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.pinkAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: () {
                    setState(() => _isCheckingProfile = true);
                    _listenToAuthChanges();
                  },
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => BackendService.supabase.auth.signOut(),
                  child: const Text("Log Out", style: TextStyle(color: Colors.white54)),
                )
              ],
            ),
          ),
        ),
      );
    }

    // 4. Fully Logged In & Paid -> Boot up the DAW!
    return const VoxrayDAW();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP GATEKEEPER (Checks for saved login session on startup)
// ─────────────────────────────────────────────────────────────────────────────
/*class AppGatekeeper extends StatefulWidget {
  const AppGatekeeper({Key? key}) : super(key: key);

  @override
  State<AppGatekeeper> createState() => _AppGatekeeperState();
}

class _AppGatekeeperState extends State<AppGatekeeper> {
  bool? _isLoggedIn;
  bool? _isSubscribed;

  @override
  void initState() {
    super.initState();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    // Listen directly to Supabase session state changes
    BackendService.supabase.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session == null) {
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _isSubscribed = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoggedIn = true);
        
        // Fetch  status directly via the BackendService
        final active = await BackendService.isSubscriptionActive();
        if (mounted) {
          setState(() => _isSubscribed = active);
        }
      }
    });
  }

  //Where to trigger this next function (TODO!):

  //    Call resetMixerToDefaults(); inside your "New Project" / "Clear Project" function before the new audio loads.
  
  //    In your file loading/uploading function (e.g., loadOriginalAudio()), call it right after the file is successfully parsed.
  
  //    In your API return function (where stems finish generating and are added to the timeline), run a quick check to ensure they are muted:
  
  //Dart
  
  // When stems arrive from API (should help with synth and instrumental not being muted sometimes):
  //setState(() {
  //  mixerState['instrumental']?.isMuted = true;
  //  mixerState['synth']?.isMuted = true;
  //});
    

  @override
  Widget build(BuildContext context) {
    // 1. App is loading session or verifying  status
    if (_isLoggedIn == null || (_isLoggedIn! && _isSubscribed == null)) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Not Logged In
    if (!_isLoggedIn!) {
      return const AuthScreen();
    }

    // 3. Logged In, but paywall active (No  found)
    if (!_isSubscribed!) {
      return const AccountSettingsScreen(isForcedPaywall: true);
    }

    // 4. Fully Logged In & Paid -> Boot up the DAW!
    return const VoxrayDAW();
  }
}*/

// =========================================================================
// AI FORENSICS TESTBED DIALOG (SCROLLABLE & CALIBRATED)
// =========================================================================

class AiForensicsDialog extends StatefulWidget {
  final Map<String, dynamic> analysisData;

  const AiForensicsDialog({Key? key, required this.analysisData}) : super(key: key);

  @override
  State<AiForensicsDialog> createState() => _AiForensicsDialogState();
}

class _AiForensicsDialogState extends State<AiForensicsDialog> {
  double _currentPlaybackTime = 0.0;
  String? _selectedMetricFilter;

  @override
  Widget build(BuildContext context) {
    List<dynamic> events = widget.analysisData['events'] ?? [];
    if (_selectedMetricFilter != null) {
      events = events.where((e) => e['metric_key'] == _selectedMetricFilter).toList();
    }

    double duration = (widget.analysisData['file_info']?['duration_sec'] ?? 10.0).toDouble();
    var summary = widget.analysisData['summary'];
    double aiScore = (summary['ai_probability_score'] ?? 0.0).toDouble();

    // 1. Get the screen size to constrain the dialog dynamically
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: const Color(0xFF121212),
      insetPadding: const EdgeInsets.all(12), // Give it breathing room on small phones
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: screenSize.width * 0.95,
        height: screenSize.height * 0.90, // Almost full screen height to allow scrolling
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TITLE HEADER ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'AI Forensics Analysis', 
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54), 
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context)
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 16),
            
            // --- OVERVIEW HEADER CARD (Responsive) ---
            Card(
              color: const Color(0xFF1E1E1E),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.analysisData['file_info']['filename'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text("Dur: ${duration}s | SR: ${widget.analysisData['file_info']['sample_rate']}Hz", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text("Flags: ${widget.analysisData['events'].length}", style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "${aiScore.toStringAsFixed(1)}% AI",
                              style: TextStyle(
                                fontSize: 24, // Reduced from 32, scales down if needed
                                fontWeight: FontWeight.bold,
                                color: aiScore >= 50 ? Colors.redAccent : Colors.greenAccent,
                              ),
                            ),
                          ),
                          Text(summary['verdict'], style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70, fontSize: 11), textAlign: TextAlign.right),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // --- INTERACTIVE WAVEFORM & FILTERS CARD ---
            Card(
              color: const Color(0xFF1E1E1E),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Changed to a Wrap to prevent cutoff on portrait phones
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text('Playhead: ${_currentPlaybackTime.toStringAsFixed(2)}s', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        Wrap(
                          spacing: 4,
                          runSpacing: -8, // Keep chips tight vertically if they wrap
                          children: [
                            ChoiceChip(
                              label: const Text('All', style: TextStyle(fontSize: 9)),
                              selected: _selectedMetricFilter == null,
                              onSelected: (_) => setState(() => _selectedMetricFilter = null),
                              visualDensity: VisualDensity.compact,
                            ),
                            ChoiceChip(
                              label: const Text('Pitch', style: TextStyle(fontSize: 9)),
                              selected: _selectedMetricFilter == 'pitch_slew',
                              onSelected: (_) => setState(() => _selectedMetricFilter = 'pitch_slew'),
                              visualDensity: VisualDensity.compact,
                            ),
                            ChoiceChip(
                              label: const Text('Formants', style: TextStyle(fontSize: 9)),
                              selected: _selectedMetricFilter == 'formant_decoupling',
                              onSelected: (_) => setState(() => _selectedMetricFilter = 'formant_decoupling'),
                              visualDensity: VisualDensity.compact,
                            ),
                            ChoiceChip(
                              label: const Text('Grid', style: TextStyle(fontSize: 9)),
                              selected: _selectedMetricFilter == 'grid_lock',
                              onSelected: (_) => setState(() => _selectedMetricFilter = 'grid_lock'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Use LayoutBuilder for accurate tap math on any screen size
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          onTapDown: (details) {
                            double clickedRatio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                            setState(() => _currentPlaybackTime = clickedRatio * duration);
                          },
                          child: Container(
                            height: 50, // Slightly thinner for mobile landscape support
                            width: double.infinity,
                            color: Colors.black38,
                            child: CustomPaint(
                              painter: WaveformPainter(
                                waveformData: List<double>.from(widget.analysisData['waveform'].map((x) => (x as num).toDouble())),
                                events: events,
                                durationSec: duration,
                                playheadSec: _currentPlaybackTime,
                              ),
                            ),
                          ),
                        );
                      }
                    ),
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: _currentPlaybackTime.clamp(0.0, duration),
                        min: 0.0, max: duration,
                        activeColor: Colors.cyanAccent,
                        inactiveColor: Colors.white24,
                        onChanged: (val) => setState(() => _currentPlaybackTime = val),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // --- SCROLLABLE FORENSIC EVENT INSPECTOR ---
            Expanded(
              child: Card(
                color: const Color(0xFF1E1E1E),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Flagged Forensic Events (${events.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                      const Divider(color: Colors.white24),
                      Expanded(
                        child: ListView.builder(
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final event = events[index];
                            bool isSelected = (_currentPlaybackTime - (event['timestamp_sec'] as num).toDouble()).abs() < 1.0;
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white10 : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: event['severity'] == 'high' ? Colors.redAccent : (event['severity'] == 'medium' ? Colors.orangeAccent : Colors.amber),
                                  child: Text('${event['timestamp_sec']}s', style: const TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold)),
                                ),
                                title: Text(event['metric_name'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                subtitle: Text("${event['detail']}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                onTap: () {
                                  setState(() => _currentPlaybackTime = (event['timestamp_sec'] as num).toDouble());
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final List<dynamic> events;
  final double durationSec;
  final double playheadSec;

  WaveformPainter({
    required this.waveformData,
    required this.events,
    required this.durationSec,
    required this.playheadSec,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty || durationSec <= 0) return;

    final paintWave = Paint()
      ..color = Colors.blueGrey.shade700
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintPlayhead = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2.0;

    double barWidth = size.width / waveformData.length;
    double midY = size.height / 2;

    for (int i = 0; i < waveformData.length; i++) {
      double x = i * barWidth;
      double h = waveformData[i] * size.height * 1.5; // Scaled up slightly for visibility
      canvas.drawLine(Offset(x, midY - h / 2), Offset(x, midY + h / 2), paintWave);
    }

    for (var ev in events) {
      double tSec = (ev['timestamp_sec'] as num).toDouble();
      double xRatio = tSec / durationSec;
      double eventX = xRatio * size.width;

      final paintMarker = Paint()
        ..color = ev['severity'] == 'high' ? Colors.redAccent : Colors.amberAccent
        ..strokeWidth = 2.0;

      canvas.drawLine(Offset(eventX, 0), Offset(eventX, size.height), paintMarker);
      canvas.drawCircle(Offset(eventX, 10), 4, paintMarker);
    }

    double playheadX = (playheadSec / durationSec) * size.width;
    canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, size.height), paintPlayhead);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) => true;
}


class VoxrayDAW extends StatefulWidget {
  const VoxrayDAW({Key? key}) : super(key: key);
  @override
  State<VoxrayDAW> createState() => VoxrayDAWState();
}

// ─────────────────────────────────────────────────────────────────────────────
// STATE  (UI fields + lifecycle; business logic via mixins)
// ─────────────────────────────────────────────────────────────────────────────

abstract class VoxrayDAWStateBase extends State<VoxrayDAW> with WidgetsBindingObserver {

  // ── API base ──────────────────────────────────────────────────────────────
  final String apiBase = 'https://donkelleymusic--voxray-pro-api-api.modal.run';

  // ── Persistent storage / job tracking ────────────────────────────────────
  Set<String> stemsCurrentlyFetching = {};
  //final Map<String, String> cachedStemPaths = {};
  // The disk path cache (Used for Mobile/Desktop)
  Map<String, String> cachedStemPaths = {};
  
  // THE NEW RAM BUFFER (Crucial for Web!)
  Map<String, Uint8List> cachedStemBytes = {};
  
  Timer? autoSaveTimer;
  //Timer? __autoSaveTimer;
  //Timer? get _autoSaveTimer => __autoSaveTimer;
  //set _autoSaveTimer(Timer? v) => __autoSaveTimer = v;
  bool isRestoringState = false;

  // ── SoLoud audio engine handles ───────────────────────────────────────────
  AudioSource? masterSource;
  SoundHandle? masterHandle;
  AudioSource? synthSource;
  SoundHandle? synthHandle;
  Map<String, AudioSource> stemSources = {};
  Map<String, SoundHandle> stemHandles = {};

  bool isPlaying = false;
  Timer? positionTimer;

  Set<String> activePlaybackSources = {};
  bool isFetchingStems = false;

  // ── Global Trim Curtains (For Export/Playback) ────────────────────────────
  double projectTrimStart = 0.0;
  double projectTrimEnd = 9999.0; // Arbitrarily high until a file is loaded

  SynthSettings synthSettings = const SynthSettings();
  bool isSynthRendering = false;
  String synthMessage   = '';
  String processingMode = 'advanced';

  // ── AI Vocal Inspector State ──────────────────────────────────────────────
  AiDetectionResult? aiResult;
  bool isAnalyzingAiVocal = false;

  Map<String, ChannelState> mixerState = {
    'master': ChannelState(), 'synth': ChannelState(),
    'vocals': ChannelState(), 'instrumental': ChannelState(),
  };

  Set<String> soloedChannels = {};

  final Map<String, ValueNotifier<double>> channelLevels = {};

  // ── Scroll controllers ────────────────────────────────────────────────────
  final ScrollController horizontalScrollController = ScrollController();
  final ScrollController verticalScrollController   = ScrollController();
  final ScrollController rulerScrollController      = ScrollController();

  // ── Dynamic Channel Pools ──────────────────────────────────────────────
  List<AudioChannel> activeChannels = [];
  List<AudioChannel> trashBin = [];
  
  // ── Note / x-ray data ────────────────────────────────────────────────────
  Map<String, List<dynamic>> allStemsNotes        = {};
  Map<String, List<dynamic>> allStemsContinuousXray = {};
  Map<String, String> baselinePitchStates = {};
  String activeEditableStem = '';

  // Declare the AI state variables here if they aren't already:
  double aiDetectionScore = 0.0;
  bool isAiDetected = false;
  List<String> aiDetectedArtifacts = [];
  List<Map<String, dynamic>> aiHeatmapData = [];
  bool showAiHeatmapOverlay = false;

  // get control over 60fps updates while doing file uploading:
  bool isUploading = false;

  bool isHelpModeActive = false;

  // GLOBAL BUSY STATE GETTER
  bool get isApiBusy => isLoading || isPreviewing || isExporting || isSynthRendering || isXrayProcessing || isUploading;

  void _fitToScreen() {
    if (!horizontalScrollController.hasClients || !verticalScrollController.hasClients) return;
    
    double viewportWidth = horizontalScrollController.position.viewportDimension;
    double viewportHeight = verticalScrollController.position.viewportDimension;
    
    // Perfect zoomX (pixels per second to fit exactly in viewport)
    double optimalZoomX = viewportWidth / (songDuration > 0 ? songDuration : 30.0);
    
    // Perfect zoomY (pixels per MIDI note to fit all keys exactly in viewport)
    int totalNotes = maxMidi - minMidi + 1;
    double optimalZoomY = viewportHeight / totalNotes;
    
    setState(() {
      zoomX = optimalZoomX.clamp(10.0, 500.0);
      zoomY = optimalZoomY.clamp(4.0, 60.0);
    });
    
    // Snap scroll views instantly to the top-left origin
    horizontalScrollController.jumpTo(0.0);
    verticalScrollController.jumpTo(0.0);
  }

  void _showMatchSummaryModal({
    required double offsetSec,
    required double confidence,
    required int matchRegionsCount,
    required String sourceName,
    required String targetName,
  }) {
    double offsetMs = offsetSec * 1000.0;
    bool isTightMatch = confidence >= 0.85;
    bool isSamePerformance = confidence >= 0.70;

    String verdict = isTightMatch
        ? "VERDICT: Exceptional alignment. Highly probable double-track or exact take match."
        : isSamePerformance
            ? "VERDICT: Moderate correlation. Consistent performance with minor timing variance."
            : "VERDICT: Low correlation. Distinct performances or divergent phrasing detected.";

    Color verdictColor = isTightMatch ? Colors.tealAccent : (isSamePerformance ? Colors.amberAccent : Colors.redAccent);

    //bool get isApiBusy => isLoading || isPreviewing || isExporting || isSynthRendering || isXrayProcessing || isUploading;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333333)),
        ),
        title: Row(
          children: [
            const Icon(Icons.analytics, color: Color(0xFF00E5FF)),
            const SizedBox(width: 10),
            const Text(
              'FORENSIC MATCH SUMMARY',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comparing "$targetName" against master "$sourceName"',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const Divider(color: Color(0xFF333333), height: 20),
            _summaryRow('Time Shift Offset', '${offsetMs.toStringAsFixed(1)} ms'),
            _summaryRow('Confidence Score', '${(confidence * 100).toStringAsFixed(1)}%'),
            _summaryRow('Identical Regions', '$matchRegionsCount matched segments'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: verdictColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: verdictColor.withOpacity(0.4)),
              ),
              child: Text(
                verdict,
                style: TextStyle(color: verdictColor, fontSize: 12, fontWeight: FontWeight.bold, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _runNuclearPianoExtraction() async {
    if (originalAudioBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load an original track first to extract the piano.'), backgroundColor: Colors.red)
      );
      return;
    }

    setState(() {
      isLoading = true;
      processingMessage = "Going nuclear... Extracting pristine piano via MelBand-RoFormer...";
    });

    try {
      var uri = Uri.parse('$apiBase/extract-nuclear-piano');
      var request = http.MultipartRequest('POST', uri)
        ..fields['project_id'] = currentTaskId ?? 'temp_proj'
        ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'mix.wav'));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          Map<String, dynamic> stemData = data['stems'];
          
          if (stemData.containsKey('piano')) {
             Uint8List nuclearPianoBytes = base64Decode(stemData['piano']);
             
             setState(() {
               cachedStemBytes['piano'] = nuclearPianoBytes;
               if (!generatedStems.contains('piano')) generatedStems.add('piano');
               
               if (!channelLevels.containsKey('piano')) {
                 channelLevels['piano'] = ValueNotifier(1.0);
               }
               if (!mixerState.containsKey('piano')) {
                 mixerState['piano'] = ChannelState();
               }
             });
             
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Nuclear Piano Extraction Complete!'), backgroundColor: Colors.teal)
             );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Piano extraction failed: ${data['detail']}'), backgroundColor: Colors.red)
          );
        }
      }
    } catch (e) {
      debugPrint("Nuclear Piano Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          processingMessage = '';
        });
      }
    }
  }

  void _showPitchColorKeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(children: [
          Icon(Icons.palette, color: Colors.white),
          SizedBox(width: 8),
          Text('Timeline Color Key', style: TextStyle(color: Colors.white)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _legendRow(Colors.lightBlueAccent, 'Perfect Tuning (≤ 10¢)', 'Studio accurate pitch.'),
            _legendRow(Colors.amberAccent, 'Moderate Variance (11-25¢)', 'Natural human drift.'),
            _legendRow(Colors.redAccent, 'Poor Tuning (> 25¢)', 'Requires pitch correction.'),
            const Divider(color: Colors.white24, height: 24),
            _legendRow(Colors.grey, 'Grey Notes', 'Muted notes.'),
            _legendRow(Colors.white.withOpacity(0.5), 'Faded / Transparent', 'Quiet notes (Low Amplitude).'),
            _legendRow(null, '* Asterisk / White Border', 'User has manually edited this note.', isOutline: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }

  Widget _legendRow(Color? color, String title, String desc, {bool isOutline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16, height: 16,
            margin: const EdgeInsets.only(top: 2, right: 12),
            decoration: BoxDecoration(
              color: isOutline ? Colors.transparent : color,
              border: isOutline ? Border.all(color: Colors.white, width: 1.5) : null,
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.center,
            child: isOutline ? const Text('*', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)) : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          )
        ],
      ),
    );
  }
  
  Future<void> _showAboutApp(BuildContext context) async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    
    String version = packageInfo.version;
    String buildNumber = packageInfo.buildNumber;
  
    if (context.mounted) {
      showAboutDialog(
        context: context,
        applicationName: 'voXRay Forensic DAW',
        applicationVersion: 'Version $version (Build $buildNumber)',
        applicationLegalese: '©2026 Don Kelley @don-music',
        applicationIcon: const Icon(Icons.graphic_eq, color: Colors.pinkAccent, size: 48),
        children: [
          const SizedBox(height: 16),
          const Text('Enterprise DSP, forensic pitch analysis, and polyphonic mixed pitch editor.', style: TextStyle(color: Colors.white70)),
        ],
      );
    }
  }
    
  void _showDeleteAccountConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Account', style: TextStyle(color: Colors.redAccent)),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete your voXRay account? This action is permanent and cannot be undone.\n\nYour profile, all saved forensic data, and your remaining DSP tokens will be instantly deleted.\n\nYou will immediately lose access to voXRay.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx); 
              
              setState(() {
                isLoading = true;
                processingMessage = "Deleting account and wiping data...";
              });

              try {
                final session = BackendService.supabase.auth.currentSession;
                if (session == null) throw Exception("No active session found.");

                final response = await http.post(
                  Uri.parse('$apiBase/api/account/delete'),
                  body: {'access_token': session.accessToken},
                );

                if (response.statusCode == 200) {
                  await BackendService.supabase.auth.signOut();
                } else {
                  final errData = json.decode(response.body);
                  // Fixed: Removed the underscore
                  showSaveConfirmation('Deletion failed: ${errData['detail']}');
                }
              } catch (e) {
                // Fixed: Removed the underscore
                showSaveConfirmation('Network Error: Could not delete account.');
              } finally {
                if (mounted) {
                  setState(() {
                    isLoading = false;
                    processingMessage = "";
                  });
                }
              }
            },
            child: const Text('Delete My Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  
  // ── Global Log Multiplexer ──────────────────────────────────────────────
  String getPlatformString() {
    if (kIsWeb) return 'flutter_web';
    return 'flutter_${Platform.operatingSystem}';
  }

  double getEffectiveVolume(String key) {
    final state = getChannelState(key);
    if (state.isMuted) return 0.0;
    
    double baseVol = state.volume;
    bool isDrumSub = ['kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(key);
    
    // 1. VCA DRUM BUS MATH
    if (isDrumSub) {
      final drumBus = getChannelState('drums');
      if (drumBus.isMuted) return 0.0; // If master drums are muted, mute the subs
      baseVol *= drumBus.volume;       // Multiply sub volume by master bus volume
    }
    
    // 2. GLOBAL SOLO ROUTING
    if (soloedChannels.isNotEmpty) {
      if (!soloedChannels.contains(key) && !(isDrumSub && soloedChannels.contains('drums'))) {
        return 0.0;
      }
    }

    // 3. COMPRESSOR MAKEUP GAIN
    final plugins = [state.plugin1, state.plugin2, state.plugin3, state.plugin4];
    if (plugins.contains('Compressor')) {
      double makeupDb = state.compressorThreshold.abs() * (1.0 - (1.0 / state.compressorRatio)) * 0.4;
      double makeupLinear = math.pow(10.0, makeupDb / 20.0).toDouble();
      baseVol *= makeupLinear;
    }
    
    return baseVol.clamp(0.0, 4.0);
  }

  Future<bool> verifyTokens(int requiredTokens, String taskName) async {
    try {
      final session = BackendService.supabase.auth.currentSession;
      if (session == null) return false;

      final response = await BackendService.supabase
          .from('profiles')
          .select('dsp_tokens') // Adjust to your actual Supabase column if different
          .eq('id', session.user.id)
          .single();

      int currentTokens = (response['dsp_tokens'] ?? 0) as int;
      
      if (currentTokens < requiredTokens) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Row(children: [
                Icon(Icons.memory, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('Insufficient DSP Tokens', style: TextStyle(color: Colors.white)),
              ]),
              content: Text(
                'The $taskName engine requires $requiredTokens DSP token(s), but you only have $currentTokens remaining.\n\nPlease top up your wallet to continue processing.',
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx), 
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54))
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent[700]),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletScreen()));
                  },
                  child: const Text('Open Wallet', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      logToSupabase('Token verification failed: $e');
      return true; // Failsafe: let it through and let Python block it if it's a real issue
    }
  }

  void refreshAllVolumes() {
    // 🟢 REVIVE MIX CHANNEL IF DEAD
    if (originalAudioBytes != null && !getChannelState('original').isMuted) {
      activePlaybackSources.add('original'); // Ensure VU meters light up!
      if (masterHandle == null || !SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) {
        
        // Extract the true extension so the C++ engine knows how to decode MP3/M4A!
        String ext = originalFileName.contains('.') ? originalFileName.split('.').last : 'wav';
        
        SoLoud.instance.loadMem('master_revived.$ext', originalAudioBytes!).then((source) {
          masterSource = source;
          
          // 🟢 play() is synchronous! Assign it instantly, no .then() needed.
          masterHandle = SoLoud.instance.play(source, paused: !isPlaying);
          SoLoud.instance.seek(masterHandle!, Duration(milliseconds: (currentPosition * 1000).toInt()));
          SoLoud.instance.setVolume(masterHandle!, getEffectiveVolume('original'));
          SoLoud.instance.setPan(masterHandle!, getChannelState('original').pan);
        });
      } else {
        SoLoud.instance.setVolume(masterHandle!, getEffectiveVolume('original'));
      }
    } else if (masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) {
      SoLoud.instance.setVolume(masterHandle!, getEffectiveVolume('original'));
    }

    // Process Synth
    if (synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(synthHandle!)) {
      SoLoud.instance.setVolume(synthHandle!, getEffectiveVolume('synth'));
    }
    
    // Process Stems
    for (var entry in stemHandles.entries) {
      if (!SoLoud.instance.getIsValidVoiceHandle(entry.value)) continue;
      
      if (entry.key == 'drums') {
        // PERMANENT KILLSWITCH: Keep master drum audio silent if sub-stems exist to prevent phasing
        SoLoud.instance.setVolume(entry.value, 0.0);
      } else {
        SoLoud.instance.setVolume(entry.value, getEffectiveVolume(entry.key));
      }
    }
  }
  
  void logToSupabase(String message, {String severity = 'INFO'}) {
    debugPrint('[$severity] $message');
    BackendService.logEvent(
      platform: getPlatformString(),
      severity: severity,
      message: message,
    );
  }
  
  List<dynamic> get rawNotes =>
      activeEditableStem.isNotEmpty && allStemsNotes.containsKey(activeEditableStem)
          ? allStemsNotes[activeEditableStem]!
          : [];

  List<dynamic> get continuousXray =>
      activeEditableStem.isNotEmpty && allStemsContinuousXray.containsKey(activeEditableStem)
          ? allStemsContinuousXray[activeEditableStem]!
          : [];

  set rawNotes(List<dynamic> updatedNotes) {
    if (activeEditableStem.isNotEmpty) {
      allStemsNotes[activeEditableStem] = updatedNotes;
    }
  }

  // ── Stem catalogue ────────────────────────────────────────────────────────
  final List<String> popStems = [
    'vocals','instrumental','drums','bass','guitar','piano','other'
  ];
  final List<String> orchStems = [
    'violin','cello','contrabass','flute','oboe','bassoon',
    'trumpet','trombone','tuba','percussion','orchestral'
  ];
  final List<String> forensicStems = ['forensic_id'];

  // 1. Group your instruments logically in your state
  final Map<String, List<String>> instrumentCategories = {
    'Pop / Rock Band': ['vocals', 'drums', 'bass', 'guitar', 'piano'],
    'Orchestral & Acoustic': ['orchestral', 'violin', 'cello', 'flute', 'brass'],
    'Utilities': ['instrumental', 'other', 'forensic_id'],
  };
    
  // ── Stem selection ────────────────────────────────────────────────────────
  Set<String> targetStemsSelection = {};
  Set<String> generatedStems       = {};
  List<String> suggestedStems      = [];

  // ── Project flags ─────────────────────────────────────────────────────────
  bool isOriginalMixAvailable = false;
  bool isTestModeActive = false;
  bool isProjectLoaded = false;
  bool hasBeenSaved    = false;
  String? currentProjectPath;
  Set<String> dirtyStems = {};

  // ── Markers ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> markers = [
    {'id': 'mk_start', 'time': 0.0, 'label': 'Start'},
    {'id': 'mk_end',   'time': 30.0, 'label': 'End'},
  ];

  // ── Undo / Redo ───────────────────────────────────────────────────────────
  List<String> undoStack           = [];
  List<String> redoStack           = [];
  List<String> undoStackContinuous = [];
  List<String> redoStackContinuous = [];

  // ── Loading / progress ────────────────────────────────────────────────────
  bool   isLoading          = false;
  double processingProgress = 0.0;
  String processingMessage  = '';
  Timer? pollingTimer;
  String? currentTaskId;
  String? currentJobId;

  // ── X-Ray ─────────────────────────────────────────────────────────────────
  bool isXrayMode       = false;
  bool isXrayProcessing = false;

  // ── Dual-Take Experimental ────────────────────────────────────────────────
  bool isDualTakeMode = false;
  DualTakeXraySettings? dualTakeSettings;
  AnimationController? alignAnimationController;
  Animation<double>? offsetAnimation;
  Animation<double>? pulseAnimation;
  bool isDualContourOverlayActive = false;
  List<dynamic> dualContour1 = [];
  List<dynamic> dualContour2 = [];
  List<dynamic> dualContinuous1 = [];
  List<dynamic> dualContinuous2 = [];
  List<dynamic> identicalMatchRegions = [];
  String dualLabel1 = '';
  String dualLabel2 = '';
  
  // ── UI Draggable States ───────────────────────────────────────────────────
  double dualLegendLeft = 20.0;
  double dualLegendTop = 20.0;

  bool isDockedMixerVisible = true;
  bool isRegionMuteMode = false;
  Map<String, List<Map<String, double>>> mutedRegions = {};

  // ── Stem Time-Shifting (Offset in Seconds) ──────────────────────────────
  Map<String, double> stemTimeOffsets = {};
  
  // ── File info ─────────────────────────────────────────────────────────────
  String originalFileName = 'Unknown File';
  String originalFilePath = '';
  String originalMixLocalPath = ''; // 🟢 Tracks the persistent local copy of the original mix!

  // ── Timeline & playback ───────────────────────────────────────────────────
  double songDuration    = 30.0;
  double currentPosition = 0.0;
  double zoomX = 50.0;
  double zoomY = 8.0;

  // ── MIDI range helpers ────────────────────────────────────────────────────
  int get minMidi {
    switch (activeEditableStem) {
      case 'bass': case 'contrabass': case 'tuba': return 24;
      case 'violin': case 'flute': return 55;
      case 'piano': case 'original': return 21;
      default: return 36;
    }
  }

  int get maxMidi {
    switch (activeEditableStem) {
      case 'bass': case 'contrabass': case 'tuba': return 72;
      case 'violin': case 'flute': return 108;
      case 'piano': case 'original': return 108;
      default: return 84;
    }
  }

  // ── UI toggles ────────────────────────────────────────────────────────────
  bool isScrubMode = true;
  bool showNudgeControls = false; // 🟢 Global toggle for time-shift nudges
  DragMode currentDragMode = DragMode.off;

  String projectName = 'Voxray_Session';
  Uint8List? originalAudioBytes;

  bool isLiveModeActive  = false;
  bool isLoopModeActive  = false;
  double loopStartBoundary = 0.0;
  double loopEndBoundary = 30.0;

  bool isUserInteracting = false;
  
  bool   isExporting   = false;
  bool   isPreviewing  = false;
  String exportMessage = '';
  String selectedEngineProfile = 'studio';

  // ── Base Methods & Abstract Mixin Signatures ──────────────────────────────
  
  ChannelState getChannelState(String key) {
    if (!mixerState.containsKey(key)) {
      final newState = ChannelState();
      // Default to muted for synth and instrumental and original "mix"
      if (key == 'instrumental' || key == 'synth' || key == 'original') {
        newState.isMuted = true;
      }
      mixerState[key] = newState;
    }

    // Auto-initialize the fast UI notifier if missing
    if (!channelLevels.containsKey(key)) {
      channelLevels[key] = ValueNotifier<double>(0.0);
    }
    
    return mixerState[key]!;
  }

  // Abstract hooks for UI methods implemented in the subclass
  void showSaveConfirmation(String message, {bool isPreview = false});
  void showEngineRecommendationDialog();
  void registerUndoSnapshot();
  
  void addImportedStem(String baseType, String filePath, {bool isGenerated = true});

  // Abstract hooks for audio mixin methods called by API mixin
  void pauseAllPlayers();
  void playAllPlayers();
  void seekAllPlayers(double seconds);
  void applyStemPlugins(String stemName);
  void applyMasterPlugins();

} // <--- This closes VoxrayDAWStateBase!


// =========================================================================
// FINAL DAW STATE (Assembles the Base + Audio Mixin + API Mixin)
// =========================================================================
class VoxrayDAWState extends VoxrayDAWStateBase with TickerProviderStateMixin, DawAudioController, DawApiService {

  VideoPlayerController? _introController;
  bool _showIntroAnimation = true;
  
  @override
  void showSaveConfirmation(String message, {bool isPreview = false}) {
    _showSaveConfirmation(message, isPreview: isPreview);
  }

  @override
  void showEngineRecommendationDialog() => _showEngineRecommendationDialog();

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _introController = VideoPlayerController.asset('assets/launch_anim.mp4')
      ..initialize().then((_) {
        // Force a rebuild as soon as it's ready
        if (mounted) setState(() {}); 
        _introController!.play();
        
        // Ensure it doesn't loop forever, but stays for 5 seconds
        _introController!.setLooping(false);

        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() => _showIntroAnimation = false);
            Future.delayed(const Duration(seconds: 1), () {
              _introController?.dispose();
              _introController = null;
            });
          }
        });
      }).catchError((error) {
        // If the video fails to load, log it and hide the animation instantly so your app doesn't hang
        debugPrint("VIDEO PLAYER CRASH: $error");
        if (mounted) {
          setState(() {
            _showIntroAnimation = false;
            _introController = null;
          });
        }
      });
    
    horizontalScrollController.addListener(() {
      if (rulerScrollController.hasClients) {
        if ((rulerScrollController.position.pixels -
                horizontalScrollController.position.pixels)
            .abs() >
            0.1) {
          rulerScrollController
              .jumpTo(horizontalScrollController.position.pixels);
        }
      }
    });
    rulerScrollController.addListener(() {
      if (horizontalScrollController.hasClients) {
        if ((horizontalScrollController.position.pixels -
                rulerScrollController.position.pixels)
            .abs() >
            0.1) {
          horizontalScrollController
              .jumpTo(rulerScrollController.position.pixels);
        }
      }
    });

    // --- NEW: DYNAMIC DRUM VU SUMMATION ---
    // This mathematically combines the sub-stems in real-time
    void updateDrumMeter() {
      double sum = 0.0;
      for (String sub in ['kick', 'snare', 'hihat', 'toms', 'cymbals']) {
        if (channelLevels[sub] != null) sum += channelLevels[sub]!.value;
      }
      
      // Ensure the master drum notifier exists
      if (!channelLevels.containsKey('drums')) {
        channelLevels['drums'] = ValueNotifier<double>(0.0);
      }
      
      // Apply a slight scale (0.6) so 5 loud drums don't instantly peg the master to solid red
      channelLevels['drums']!.value = (sum * 0.6).clamp(0.0, 1.0);
    }

    // Attach the listener to the 5 sub-stems. 
    // Now, whenever a sub-stem bounces, the master drum meter bounces instantly!
    for (String sub in ['kick', 'snare', 'hihat', 'toms', 'cymbals']) {
      if (!channelLevels.containsKey(sub)) {
        channelLevels[sub] = ValueNotifier<double>(0.0);
      }
      channelLevels[sub]!.addListener(updateDrumMeter);
    }
    // --------------------------------------

    restoreAutoSaveOnStartup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pollingTimer?.cancel();
    positionTimer?.cancel();
    horizontalScrollController.dispose();
    verticalScrollController.dispose();
    rulerScrollController.dispose();
    SoLoud.instance.disposeAllSources();
    SoLoud.instance.deinit();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      logToSupabase('App resumed. Reclaiming OS audio session...');
      // 🟢 iOS/Android often steals the audio context for notifications or other apps while backgrounded. 
      // We must explicitly ask the OS to give us the hardware back!
      configureAudioSession(); 
      
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      logToSupabase('App backgrounded. Suspending hardware audio to prevent deadlocks.');
      // 🛑 If we leave voices open when the OS suspends the app, the C++ audio engine permanently corrupts!
      // Force pause immediately before the OS kills our thread.
      if (isPlaying) {
        pauseAllPlayers();
        setState(() {}); // Update the play button UI
      }
    }
  }

  void notifyChanged() => setState(() {});

  // =========================================================================
  // DYNAMIC STEM MANAGEMENT
  // =========================================================================

  void addImportedStem(String baseType, String filePath, {bool isGenerated = true}) {
    final String normalizedType = baseType.toLowerCase().trim();
    
    // Count existing channels of this exact base type
    final int existingCount = activeChannels.where((c) => c.baseType == normalizedType).length;
    
    // Create the unique stemKey (e.g. 'vocals', 'vocals2', 'vocals3')
    final String stemKey = existingCount == 0 
        ? normalizedType 
        : '$normalizedType${existingCount + 1}';

    // Create the UI display name (e.g. 'Vocals', 'Vocals 2')
    final String displayName = existingCount == 0 
        ? _capitalize(normalizedType) 
        : '${_capitalize(normalizedType)} ${existingCount + 1}';

    setState(() {
      // 1. Add to the new dynamic pool
      activeChannels.add(
        AudioChannel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: displayName,
          stemKey: stemKey,
          baseType: normalizedType,
          filePath: filePath,
        ),
      );

      // 2. Bridge it into your existing DAW rendering logic
      targetStemsSelection.add(stemKey);
      if (isGenerated) {
        generatedStems.add(stemKey);
      }
      
      // Auto-set as active editable stem
      activeEditableStem = stemKey;
    });
  }

  void deleteChannel(String stemKey) {
    setState(() {
      // Find the channel
      final index = activeChannels.indexWhere((c) => c.stemKey == stemKey);
      if (index != -1) {
        final removedChannel = activeChannels.removeAt(index);
        trashBin.add(removedChannel);
        
        // Remove from active UI sets, but KEEP in cached bytes/paths so it isn't lost
        targetStemsSelection.remove(stemKey);
        generatedStems.remove(stemKey);
        
        // Mute it in the audio engine
        if (stemHandles.containsKey(stemKey)) {
          SoLoud.instance.setVolume(stemHandles[stemKey]!, 0.0);
        }
      }
    });
  }

  void restoreChannel(AudioChannel channel) {
    setState(() {
      trashBin.remove(channel);
      activeChannels.add(channel);
      
      targetStemsSelection.add(channel.stemKey);
      generatedStems.add(channel.stemKey);
    });
  }

  String _capitalize(String s) => s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}';
  
  // =========================================================================
  // UNDO / REDO
  // =========================================================================

  void registerUndoSnapshot() {
    if (activeEditableStem.isNotEmpty) {
      setState(() {
        undoStack.add(json.encode(allStemsNotes));
        redoStack.clear();
        undoStackContinuous.add(json.encode(allStemsContinuousXray));
        dirtyStems.add(activeEditableStem);
        hasBeenSaved = false;
      });
      triggerAutoSave();
    }
  }

  void _evaluatePitchDirtyState() {
    if (activeEditableStem.isNotEmpty && baselinePitchStates.containsKey(activeEditableStem)) {
      String currentJson = json.encode(allStemsNotes[activeEditableStem] ?? []);
      String baselineJson = baselinePitchStates[activeEditableStem]!;
      
      // 1. Fast check: Do they match perfectly?
      if (currentJson == baselineJson) {
        dirtyStems.remove(activeEditableStem); // Turn the light off.
      } else {
        // 2. Deep check: Did the JSON only change because we added X-Ray visual data?
        var currentList = allStemsNotes[activeEditableStem] ?? [];
        var baselineList = json.decode(baselineJson) as List<dynamic>;
        
        String stripVisuals(List<dynamic> list) {
          return json.encode(list.map((n) {
            var map = Map<String, dynamic>.from(n as Map);
            map.remove('contour');
            map.remove('xray_cents');
            map.remove('forensics');
            return map;
          }).toList());
        }

        if (stripVisuals(currentList) == stripVisuals(baselineList)) {
          // The audio parameters are identical! Only visual data was added.
          // Silently update the baseline to include the new X-Ray data so future fast-checks pass.
          baselinePitchStates[activeEditableStem] = currentJson;
          dirtyStems.remove(activeEditableStem);
        } else {
          // Actual audio-altering edits (like cents_shift or volume) exist. Light it up!
          dirtyStems.add(activeEditableStem); 
        }
      }
    }
  }
  
  void _undo() {
    if (undoStack.isNotEmpty) {
      setState(() {
        redoStack.add(json.encode(allStemsNotes));
        allStemsNotes = Map<String, List<dynamic>>.from(
            json.decode(undoStack.removeLast()));
        redoStackContinuous.add(json.encode(allStemsContinuousXray));
        final Map<String, dynamic> decoded = json.decode(undoStackContinuous.removeLast());

        allStemsContinuousXray = decoded.map((key, value) {
          return MapEntry(key, List<dynamic>.from(value));
        });
        //allStemsContinuousXray =
        //    json.decode(undoStackContinuous.removeLast());
        _evaluatePitchDirtyState();
      });
    }
  }

  void _redo_old() {
    if (redoStack.isNotEmpty) {
      setState(() {
        undoStack.add(json.encode(allStemsNotes));
        allStemsNotes = Map<String, List<dynamic>>.from(
            json.decode(redoStack.removeLast()));
        undoStackContinuous.add(json.encode(allStemsContinuousXray));
        allStemsContinuousXray =
            json.decode(redoStackContinuous.removeLast());
      });
    }
  }
  
  void _redo() {
    if (redoStack.isNotEmpty) {
      setState(() {
        undoStack.add(json.encode(allStemsNotes));
        allStemsNotes = Map<String, List<dynamic>>.from(
            json.decode(redoStack.removeLast()));
  
        undoStackContinuous.add(json.encode(allStemsContinuousXray));
        
        // Explicit cast to prevent TypeError
        final Map<String, dynamic> decoded = json.decode(redoStackContinuous.removeLast());
        allStemsContinuousXray = decoded.map((key, value) {
          return MapEntry(key, List<dynamic>.from(value));
        });
        _evaluatePitchDirtyState();
      });
    }
  }

  // =========================================================================
  // ZOOM & TIMELINE NAVIGATION
  // =========================================================================

  void jumpToTimelinePosition(double seconds) {
    seekAllPlayers(seconds);
    setState(() => currentPosition = seconds);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (horizontalScrollController.hasClients &&
          horizontalScrollController.position.maxScrollExtent > 0) {
          
        double anchorOffset = horizontalScrollController.position.viewportDimension * 0.35;
        double targetX = math.max(0.0, (seconds * zoomX) - anchorOffset);
        
        horizontalScrollController.jumpTo(
            targetX.clamp(0.0, horizontalScrollController.position.maxScrollExtent));
      }
    });
  }


  void setZoomX(double newZoom) {
    if (!horizontalScrollController.hasClients) {
      setState(() => zoomX = newZoom);
      return;
    }
    double oldZoom      = zoomX;
    double currentPixels = horizontalScrollController.position.pixels;
    
    // Dynamic 35% offset so the playhead doesn't jump when zooming
    double anchorOffset = horizontalScrollController.position.viewportDimension * 0.35;
    
    double anchorTime   = (currentPixels + anchorOffset) / oldZoom;
    double newScrollX   = (anchorTime * newZoom) - anchorOffset;
    
    setState(() => zoomX = newZoom);
    horizontalScrollController.jumpTo(math.max(0.0, newScrollX));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (horizontalScrollController.hasClients) {
        horizontalScrollController.jumpTo(
            newScrollX.clamp(0.0, horizontalScrollController.position.maxScrollExtent));
      }
    });
  }


  void setZoomY(double newZoom) {
    if (!verticalScrollController.hasClients) {
      setState(() => zoomY = newZoom);
      return;
    }
    double oldZoom       = zoomY;
    double viewportHeight = verticalScrollController.position.viewportDimension;
    double currentPixels  = verticalScrollController.position.pixels;
    double anchorMidi;

    var activeNotes = rawNotes.where((n) {
      if (n['isDeleted'] == true) return false;
      double start = (n['start_time'] ?? 0).toDouble();
      double end   = (n['end_time']   ?? 0).toDouble();
      return start <= currentPosition && end >= currentPosition;
    }).toList();

    if (activeNotes.isNotEmpty) {
      List<double> midiValues = activeNotes
          .map<double>((n) => (n['display_midi'] ?? n['actual_midi'] ?? 60.0).toDouble())
          .toList()
        ..sort();
      anchorMidi = midiValues[midiValues.length ~/ 2];
    } else {
      anchorMidi = maxMidi -
          ((currentPixels + (viewportHeight / 2) - (oldZoom / 2)) / oldZoom);
    }

    double oldDistanceFromTop = ((maxMidi - anchorMidi) * oldZoom) + (oldZoom / 2);
    double screenY            = oldDistanceFromTop - currentPixels;
    double newDistanceFromTop = ((maxMidi - anchorMidi) * newZoom) + (newZoom / 2);
    double newScrollY         = newDistanceFromTop - screenY;

    setState(() => zoomY = newZoom);
    verticalScrollController.jumpTo(math.max(0.0, newScrollY));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (verticalScrollController.hasClients) {
        verticalScrollController.jumpTo(
            newScrollY.clamp(0.0, verticalScrollController.position.maxScrollExtent));
      }
    });
  }

  // =========================================================================
  // TRANSPORT
  // =========================================================================

  void _toggleMasterTransport() {
    if (isPlaying) {
      pauseAllPlayers();
    } else {
      // Snap to Trim Start if we are outside the valid boundaries!
      if (currentPosition < projectTrimStart || (projectTrimEnd < songDuration && currentPosition >= projectTrimEnd)) {
        jumpToTimelinePosition(projectTrimStart);
      }
      playAllPlayers();
    }
  }
  
  // =========================================================================
  // DUAL-STEM ANY-TO-ANY COMPARISON
  // =========================================================================

  Future<bool> _ensureXrayGenerated(String stemKey) async {
    List<dynamic> notes = allStemsNotes[stemKey] ?? [];
    
    // Check if it already has contour data
    if (notes.isNotEmpty && notes.any((n) => n.containsKey('contour') && n['contour'] != null)) {
      return true; 
    }

    setState(() {
      isLoading = true;
      processingMessage = 'Auto-generating high-res X-Ray data for ${stemKey.toUpperCase()}...';
    });

    try {
      if (currentTaskId == null) {
        if (!cachedStemPaths.containsKey(stemKey)) return false;
        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type']      = 'stem'
          ..fields['stem_target']      = stemKey
          ..fields['instruments_json'] = jsonEncode([stemKey])
          ..files.add(await http.MultipartFile.fromPath('file', cachedStemPaths[stemKey]!));

        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          currentTaskId = jsonDecode(await sessionRes.stream.bytesToString())['task_id'];
        } else return false;
      }

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-xray'))
        ..fields['task_id']         = currentTaskId!
        ..fields['stem_target']     = stemKey
        ..fields['notes_manifest']  = jsonEncode(enrichManifestWithPolyphonicContext(notes));

      var response = await request.send();
      if (response.statusCode == 200) {
        var data  = jsonDecode(await response.stream.bytesToString());
        String jobId = data['job_id'];

        bool isComplete = false;
        while (!isComplete) {
          await Future.delayed(const Duration(seconds: 3));
          var statusRes = await http.get(Uri.parse('$apiBase/get-task-status?task_id=$jobId'));
          if (statusRes.statusCode == 200) {
            var statusData = json.decode(statusRes.body);
            setState(() => processingMessage = statusData['message'] ?? 'Processing X-Ray...');

            if (statusData['status'] == 'complete') {
              final result = statusData['result'];
              setState(() {
                allStemsNotes[stemKey] = result['notes'];
                if (result['continuous_xray'] != null) {
                  allStemsContinuousXray[stemKey] = result['continuous_xray'];
                }
              });
              return true;
            } else if (statusData['status'] == 'error') {
              return false;
            }
          }
        }
      }
    } catch (e) {
      logToSupabase('Auto X-Ray error for $stemKey: $e');
    }
    return false;
  }
  
  Future<void> _runAnyToAnyForensicAlign(AudioChannel source, AudioChannel target) async {
    // 1. PRE-FLIGHT UX CHECK
    if (!await verifyTokens(2, 'Dual-Take Alignment')) return;

    setState(() {
      isLoading = true;
      processingProgress = 0.0;
      processingMessage = "Preparing audio and validating X-Ray data...";
    });

    bool sourceReady = await _ensureXrayGenerated(source.stemKey);
    bool targetReady = await _ensureXrayGenerated(target.stemKey);

    if (!sourceReady || !targetReady) {
      _showSaveConfirmation('Error: Could not generate required high-res X-Ray data.');
      setState(() { isLoading = false; processingMessage = ''; });
      return;
    }

    setState(() {
      processingMessage = "Uploading ${target.name} and ${source.name} for alignment...";
    });

    try {
      var uri = Uri.parse('$apiBase/api/dual-take/compare'); 
      var request = http.MultipartRequest('POST', uri);
      
      request.fields['session_id'] = currentTaskId ?? 'temp_session';
      request.fields['notes_a_json'] = jsonEncode(allStemsNotes[source.stemKey] ?? []);
      request.fields['notes_b_json'] = jsonEncode(allStemsNotes[target.stemKey] ?? []);

      // 2. SEND TOKEN TO PYTHON
      final session = BackendService.supabase.auth.currentSession;
      if (session != null) {
        request.fields['access_token'] = session.accessToken;
      }

      Uint8List? bytes1 = cachedStemBytes[source.stemKey];
      Uint8List? bytes2 = cachedStemBytes[target.stemKey];

      if (bytes1 == null || bytes2 == null) {
        _showSaveConfirmation('Error: Audio data missing from RAM cache.');
        setState(() { isLoading = false; processingMessage = ''; });
        return;
      }

      request.files.add(http.MultipartFile.fromBytes('file_1', bytes1, filename: source.name));
      request.files.add(http.MultipartFile.fromBytes('file_2', bytes2, filename: target.name));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'processing' && data['call_id'] != null) {
          String callId = data['call_id'];
          String taskId = data['task_id'] ?? '';
          
          setState(() {
            processingProgress = 0.05;
            processingMessage = "[5%] Initializing task on Modal GPU...";
          });

          bool isComplete = false;
          while (!isComplete) {
            await Future.delayed(const Duration(seconds: 2));
            
            var statusResponse = await http.get(
              Uri.parse('$apiBase/api/dual-take/status/$callId?task_id=$taskId')
            );
            
            if (statusResponse.statusCode == 200) {
              final statusData = json.decode(statusResponse.body);
              
              if (statusData['status'] == 'success') {
                isComplete = true;
                final double offsetSec = statusData['offset_sec'] ?? 0.0;
                
                setState(() {
                  // ── 1. APPLY PERFECTLY RECALCULATED NOTES ──
                  if (statusData['shifted_notes'] != null) {
                    allStemsNotes[target.stemKey] = statusData['shifted_notes'];
                  }
                  
                  // ── 2. SHIFT CONTINUOUS X-RAY IN DART (INSTANT MATH) ──
                  if (allStemsContinuousXray.containsKey(target.stemKey)) {
                    List<dynamic> originalCont = allStemsContinuousXray[target.stemKey]!;
                    List<dynamic> shiftedCont = [];
                    for (var point in originalCont) {
                      double t = (point[0] as num).toDouble() + offsetSec;
                      double f = (point[1] as num).toDouble();
                      shiftedCont.add([t, f]);
                    }
                    // Save the shifted array as the new baseline
                    allStemsContinuousXray[target.stemKey] = shiftedCont;
                    // Pass the shifted array to the Magenta Canvas overlay
                    dualContinuous2 = shiftedCont; 
                  } else {
                    dualContinuous2 = [];
                  }

                  // Pass the unshifted Master trace to the Cyan Canvas overlay
                  dualContinuous1 = allStemsContinuousXray[source.stemKey] ?? [];

                  // ── 3. POPULATE UI CANVAS DATA ──
                  dualContour1 = statusData['contour_1'] ?? [];
                  dualContour2 = statusData['contour_2'] ?? [];
                  identicalMatchRegions = statusData['identical_regions'] ?? [];
                  dualLabel1 = source.name;
                  dualLabel2 = target.name;
                  isDualContourOverlayActive = true;
              
                  // ── 4. PREP AUDIO CACHE & STOP PLAYER ──
                  cachedStemBytes.remove(target.stemKey);
                  if (stemHandles.containsKey(target.stemKey)) {
                    SoLoud.instance.stop(stemHandles[target.stemKey]!);
                    stemHandles.remove(target.stemKey);
                  }
                  
                  if (statusData['aligned_audio_b64'] != null) {
                    cachedStemBytes[target.stemKey] = base64Decode(statusData['aligned_audio_b64']);
                  }

                  // ── 5. SHIFT VU METER ENVELOPE ──
                  final trackState = getChannelState(target.stemKey);
                  if (trackState.rmsEnvelope.isNotEmpty && songDuration > 0) {
                    double fps = trackState.rmsEnvelope.length / songDuration;
                    int frameShift = (offsetSec * fps).round();
                    
                    if (frameShift > 0) {
                      trackState.rmsEnvelope = [
                        ...List.filled(frameShift, 0.0), 
                        ...trackState.rmsEnvelope
                      ];
                    } else if (frameShift < 0) {
                      int trim = frameShift.abs();
                      trackState.rmsEnvelope = trim < trackState.rmsEnvelope.length 
                          ? trackState.rmsEnvelope.sublist(trim) 
                          : [];
                    }
                  }
                });
              
                // Reload player with the new buffer
                await loadStemPlayerSource(target.stemKey, apiBase, currentTaskId ?? 'temp_session');
                dirtyStems.add(target.stemKey);
                registerUndoSnapshot();
                
                _showSaveConfirmation(
                  'Auto-Aligned! Offset applied: ${(offsetSec * 1000).toStringAsFixed(0)} ms.',
                  isPreview: true
                );
                
                _showMatchSummaryModal(
                  offsetSec: offsetSec,
                  confidence: statusData['confidence_score'] ?? 0.0,
                  matchRegionsCount: identicalMatchRegions.length,
                  sourceName: source.name,
                  targetName: target.name,
                );
                
              } else if (statusData['status'] == 'processing') {
                int percent = statusData['progress'] ?? 0;
                String stage = statusData['stage'] ?? 'Processing...';
                
                setState(() {
                  processingProgress = (percent / 100.0).clamp(0.0, 1.0);
                  processingMessage = "[$percent%] $stage";
                });
              } else {
                isComplete = true;
                _showSaveConfirmation('Alignment failed on server.');
              }
            } else {
              isComplete = true;
              _showSaveConfirmation('Error checking status: ${statusResponse.statusCode}');
            }
          }
        } else {
          _showSaveConfirmation('Server failed to start job.');
        }
      } else {
        _showSaveConfirmation('Upload error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("Dual Comparison Error: $e");
      _showSaveConfirmation('Comparison Error: $e');
    } finally {
      setState(() {
        isLoading = false;
        processingProgress = 0.0;
        processingMessage = '';
      });
    }
  }

  Future<void> _runAiVocalInspection() async { // not just for vocals any more!
    if (!await verifyTokens(1, 'AI Synthetic Detection')) return;

    List<http.MultipartFile> filesToSend = [];

    // 1. IF DRUMS ARE SELECTED: Bundle all available sub-stems
    if (activeEditableStem == 'drums') {
      List<String> drumSubs = ['kick', 'snare', 'hihat', 'toms', 'cymbals'];
      for (String sub in drumSubs) {
        Uint8List? subBytes;
        if (cachedStemBytes.containsKey(sub)) {
          subBytes = cachedStemBytes[sub];
        } else if (cachedStemPaths.containsKey(sub)) {
          subBytes = await File(cachedStemPaths[sub]!).readAsBytes();
        }
        
        if (subBytes != null) {
          // Notice the field name is 'files' (plural) for the Python array
          filesToSend.add(http.MultipartFile.fromBytes('files', subBytes, filename: '${sub}_check.wav'));
        }
      }
    } 
    // 2. OTHERWISE: Just send the single selected stem (vocal, mix, piano, etc.)
    else {
      Uint8List? audioBytes;
      if (cachedStemBytes.containsKey(activeEditableStem)) {
        audioBytes = cachedStemBytes[activeEditableStem];
      } else if (cachedStemPaths.containsKey(activeEditableStem)) {
        audioBytes = await File(cachedStemPaths[activeEditableStem]!).readAsBytes();
      } else if (activeEditableStem == 'original' && originalAudioBytes != null) {
        // ONLY allow the original file if they explicitly clicked the 'original' / 'mix' track
        audioBytes = originalAudioBytes;
      }

      if (audioBytes != null) {
        filesToSend.add(http.MultipartFile.fromBytes('files', audioBytes, filename: '${activeEditableStem}_check.wav'));
      }
    }

    if (filesToSend.isEmpty) {
      _showSaveConfirmation('No audio available for ${activeEditableStem.toUpperCase()}. Generate or load this stem first.');
      return;
    }

    setState(() {
      isAnalyzingAiVocal = true;
      isLoading = true;
      processingMessage = "Running deep forensic analysis on ${activeEditableStem.toUpperCase()}...";
    });

    try {
      var uri = Uri.parse('$apiBase/detect-ai-vocal');
      var request = http.MultipartRequest('POST', uri);
      
      // Attach the array of files (1 file, or 5 files)
      request.files.addAll(filesToSend);

      final session = BackendService.supabase.auth.currentSession;
      if (session != null) {
        request.fields['access_token'] = session.accessToken;
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          aiResult = AiDetectionResult.fromJson(data);
        });
        
        // LAUNCH THE NEW UI DIALOG
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AiForensicsDialog(analysisData: data),
          );
        }
      } else {
        _showSaveConfirmation('AI Inspection failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("AI Inspection Error: $e");
      _showSaveConfirmation('AI Inspection Error: $e');
    } finally {
      setState(() {
        isAnalyzingAiVocal = false;
        isLoading = false;
        processingMessage = '';
      });
    }
  }

  // =========================================================================
  // TOGGLE PLAYBACK SOURCE
  // =========================================================================

  Future<void> _togglePlaybackSource(String key, bool enabled) async {
    setState(() {
      if (enabled) activePlaybackSources.add(key);
      else activePlaybackSources.remove(key);
    });

    if (key == 'original') {
      if (masterHandle != null) {
        final origState = getChannelState('original');
        SoLoud.instance.setVolume(
            masterHandle!, enabled ? (origState.isMuted ? 0.0 : origState.volume) : 0.0);
        SoLoud.instance.setPan(masterHandle!, origState.pan);
      }
    } else if (key == 'synth') {
      if (enabled) {
        await loadSynthSource();
      } else {
        if (synthHandle != null) SoLoud.instance.setVolume(synthHandle!, 0.0);
      }
    } else {
      if (enabled) {
        if (!generatedStems.contains(key)) {
          await generateStemOnDemand(key);
        } else {
          await loadStemPlayerSource(key, apiBase, currentTaskId ?? '');
        }
      } else {
        if (stemHandles.containsKey(key)) {
          SoLoud.instance.setVolume(stemHandles[key]!, 0.0);
        }
      }
    }
  }


  // =========================================================================
  // DUAL-TAKE FORENSIC LOGIC
  // =========================================================================

  // =========================================================================
  // DUAL-TAKE AUTO-SYNC LOGIC
  // =========================================================================

  Future<void> _syncVocalTakes() async {
    if (!generatedStems.contains('vocals') || !generatedStems.contains('vocals2')) {
      _showSaveConfirmation('You must import both "vocals" and "vocals2" to sync them.');
      return;
    }

    setState(() {
      isLoading = true;
      processingMessage = "Mathematically syncing vocals2 to vocals...";
    });

    pauseAllPlayers();

    try {
      var uri = Uri.parse('$apiBase/api/dual-take/align-and-sync');
      var request = http.MultipartRequest('POST', uri)
        ..fields['session_id'] = currentTaskId ?? ''
        ..fields['take_a_id'] = 'vocals'
        ..fields['take_b_id'] = 'vocals2'
        ..fields['notes_b_json'] = jsonEncode(allStemsNotes['vocals2'] ?? []);

      var response = await request.send().timeout(const Duration(seconds: 60));
      var responseData = await http.Response.fromStream(response);

      if (responseData.statusCode == 200) {
        var data = json.decode(responseData.body);
        if (data['status'] == 'success') {
          
          setState(() {
            // 1. Update the JSON notes
            allStemsNotes['vocals2'] = data['shifted_notes'];
            
            // 2. Clear the old audio from RAM
            cachedStemBytes.remove('vocals2');
            if (stemHandles.containsKey('vocals2')) {
              SoLoud.instance.stop(stemHandles['vocals2']!);
              stemHandles.remove('vocals2');
            }
          });

          // 3. Download the newly padded/trimmed audio file
          await loadStemPlayerSource('vocals2', apiBase, currentTaskId!);
          
          // 4. Force the UI to repaint
          dirtyStems.add('vocals2');
          registerUndoSnapshot();
          
          _showSaveConfirmation('Takes Synced! Offset applied: ${(data['offset_sec'] * 1000).toStringAsFixed(0)} ms.');
        } else {
          _showSaveConfirmation('Sync failed: ${data['message']}');
        }
      } else {
        _showSaveConfirmation('Server error: ${responseData.statusCode}');
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
      _showSaveConfirmation('Sync Error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }
  
  Future<void> _loadSecondaryVocalTake() async {
    try {
      //import 'package:file_picker/file_picker.dart';
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'm4a', 'flac', 'aac'],
        withData: true, 
      );

      if (result != null && result.files.single.bytes != null) {
        PlatformFile file = result.files.single;

        // Trigger your Mix vs Stem popup
        bool? isMix = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text("Audio Type", style: TextStyle(color: Colors.white)),
              content: const Text(
                "Is this file a full mix or an isolated vocal stem?",
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Full Mix (Run Roformer)", style: TextStyle(color: Color(0xFFFF007F))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Vocal Stem", style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          },
        );

        if (isMix != null) {
          setState(() {
            isDualTakeMode = true;
            isLoading = true;
            processingMessage = isMix ? "Isolating vocals..." : "Extracting X-ray data for Take B...";
            
            dualTakeSettings = DualTakeXraySettings(
              takeBAudioBytes: file.bytes,
              takeBName: file.name,
            );
          });

          // 1. Send the file and instantly get a job ticket
          var uri = Uri.parse('$apiBase/api/dual-take/process-secondary');
          var request = http.MultipartRequest('POST', uri)
            ..fields['is_mix'] = isMix.toString()
            ..fields['session_id'] = currentTaskId ?? 'temp_session'
            ..files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));

          var streamedResponse = await request.send();
          var response = await http.Response.fromStream(streamedResponse);

          if (response.statusCode == 200) {
            var data = json.decode(response.body);
            String jobId = data['job_id']; // Grab the ticket!

            // 2. Poll the server safely until the heavy lifting finishes
            bool isComplete = false;
            while (!isComplete) {
              await Future.delayed(const Duration(seconds: 3));
              var statusRes = await http.get(Uri.parse('$apiBase/get-task-status?task_id=$jobId'));
              
              if (statusRes.statusCode == 200) {
                var statusData = json.decode(statusRes.body);
                
                setState(() {
                  processingMessage = statusData['message'] ?? 'Processing secondary take...';
                });

                if (statusData['status'] == 'complete') {
                  isComplete = true;
                  var result = statusData['result'];
                  
                  setState(() {
                    dualTakeSettings!.takeBNotes = result['notes'] ?? [];
                    if (result['isolated_audio_base64'] != null) {
                      dualTakeSettings!.takeBAudioBytes = base64Decode(result['isolated_audio_base64']);
                    }
                  });
                } else if (statusData['status'] == 'error') {
                  isComplete = true; // <-- BREAK THE LOOP
                  throw Exception(statusData['message']);
                }
              } else {
                isComplete = true; // <-- BREAK THE LOOP ON 404/500
                throw Exception('Server returned ${statusRes.statusCode}');
              }
            }
          } else {
             throw Exception('Server error: ${response.statusCode}');
          }
          
          setState(() => isLoading = false);
        }
      }
    } catch (e) {
      debugPrint("Secondary load error: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> _runForensicAutoAlign() async {
    if (dualTakeSettings == null || dualTakeSettings!.takeBAudioBytes == null || rawNotes.isEmpty) return;
    
    setState(() {
      isLoading = true;
      processingMessage = "Cross-correlating phase relationships...";
    });

    try {
      final response = await http.post(
        Uri.parse('$apiBase/api/dual-take/align'),
        body: {
          'session_id': currentTaskId ?? '',
          'take_b_path': '/data/takeB_${currentTaskId ?? 'temp_session'}.wav', // Handled by Modal
          'notes_a_json': jsonEncode(rawNotes),
          'notes_b_json': jsonEncode(dualTakeSettings!.takeBNotes),
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        double offsetSeconds = data['offset_ms'] / 1000.0;
        
        _animateSnapToFit(
          startOffset: dualTakeSettings!.takeBOffsetSeconds,
          targetOffset: offsetSeconds,
          confidence: data['confidence_score'] ?? 0.0,
          matchStart: data['match_start_sec'] ?? 0.0,
          matchEnd: data['match_end_sec'] ?? 0.0,
        );
      }
    } catch (e) {
      debugPrint("Alignment Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _animateSnapToFit({
    required double startOffset, required double targetOffset, 
    required double confidence, required double matchStart, required double matchEnd
  }) {
    alignAnimationController?.dispose();
    alignAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    offsetAnimation = Tween<double>(begin: startOffset, end: targetOffset).animate(
      CurvedAnimation(parent: alignAnimationController!, curve: Curves.easeInOutCubic),
    );

    pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 70),
    ]).animate(CurvedAnimation(parent: alignAnimationController!, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)));

    offsetAnimation!.addListener(() {
      setState(() {
        dualTakeSettings!.takeBOffsetSeconds = offsetAnimation!.value;
        dualTakeSettings!.lockInPulse = pulseAnimation!.value;
      });
    });

    alignAnimationController!.forward().then((_) {
      setState(() {
        dualTakeSettings!.hasMatch = true;
        dualTakeSettings!.matchConfidence = confidence;
        dualTakeSettings!.matchStartSeconds = matchStart;
        dualTakeSettings!.matchEndSeconds = matchEnd;
        dualTakeSettings!.mode = XrayCompareMode.overlay;
      });
    });
  }

  // Clear AI display and data in newProject and loadProject calls.
  void resetAiDetectorState() {
    setState(() {
      aiDetectionScore = 0.0;
      isAiDetected = false;
      aiDetectedArtifacts.clear();
      aiHeatmapData.clear();
      showAiHeatmapOverlay = false; // Toggle this off too if you have a visibility flag
    });
  }

  // --- FORENSIC REPORTING HELPERS ---
  String getForensicPitchDescription(String internalGrade) {
    switch (internalGrade) {
      case 'A+': return "Mechanically Precise (Possible Pitch Correction)";
      case 'A':  return "Extremely Accurate (Studio Standard)";
      case 'B':  return "Highly Accurate (Natural Human Variance)";
      case 'C':  return "Average Expressive Pitch (Standard Variance)";
      case 'D':  return "Loose Pitch (Stylistic or Pitchy)";
      case 'F':  return "Highly Variable (Raw / Unrestrained Phrasing)";
      default:   return "Unknown Pitch Variance";
    }
  }
  
  // --- X-RAY REPORT HELPERS ---
  List<String> getStemsWithXray() {
    List<String> validStems = [];
    for (var entry in allStemsNotes.entries) {
      if (entry.value.isNotEmpty && entry.value.any((n) => n is Map && n.containsKey('contour') && n['contour'] != null)) {
        validStems.add(entry.key);
      }
    }
    return validStems;
  }

  Future<String?> _promptForReportStem(List<String> availableStems, String reportName) async {
    if (availableStems.isEmpty) return null;
    if (availableStems.length == 1) return availableStems.first;

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Select Track for $reportName', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: availableStems.map((stem) => ListTile(
            title: Text(stem.toUpperCase(), style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.fingerprint, color: Colors.amberAccent, size: 20),
            onTap: () => Navigator.pop(ctx, stem),
          )).toList(),
        ),
      )
    );
  }
  
  // Inside your PopupMenu / Button Handlers:
  void _showScorecard() async {
    final xrayStems = getStemsWithXray();
    if (xrayStems.isEmpty) {
      _showSaveConfirmation('No X-Ray data to analyze. Please process a stem with X-Ray first.');
      return;
    }
    
    final targetStem = await _promptForReportStem(xrayStems, 'Scorecard');
    if (targetStem == null) return;

    showDialog(
      context: context,
      // You must update PerformanceScorecardDialog to accept this targetStem variable!
      builder: (context) => PerformanceScorecardDialog(dawState: this, targetStem: targetStem), 
    );
  }
  
  // =========================================================================
  // NEW PROJECT
  // =========================================================================

  Future<void> _newProject() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Create New Project?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Any unsaved edits across your instrument tracks will be permanently lost.',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset Workspace',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;

    pauseAllPlayers();
    SoLoud.instance.disposeAllSources();

    setState(() {
      isProjectLoaded   = false;
      hasBeenSaved      = false;
      dirtyStems.clear();
      allStemsNotes.clear();
      generatedStems.clear();
      targetStemsSelection.clear();
      cachedStemPaths.clear();
      stemHandles.clear();
      stemSources.clear();
      masterHandle           = null;
      masterSource           = null;
      synthHandle            = null;
      synthSource            = null;
      allStemsContinuousXray.clear();
      activePlaybackSources.clear();
      activeEditableStem     = '';
      isXrayMode             = false; 
      isXrayProcessing       = false;
      isAnalyzingAiVocal     = false;
      aiResult               = null;
      
      currentTaskId          = null;
      currentJobId           = null;
      currentProjectPath     = null;
      originalAudioBytes     = null;
      originalFileName       = 'Unknown File';
      songDuration           = 30.0;
      currentPosition        = 0.0;
      markers = [
        {'id': 'mk_start', 'time': 0.0, 'label': 'Start'},
        {'id': 'mk_end',   'time': 30.0, 'label': 'End'},
      ];
      undoStack.clear();
      redoStack.clear();

      // --- THE CRITICAL FIX: WIPE ALL REMAINING GHOST STATES ---
      mixerState.clear();
      for (var v in channelLevels.values) { v.value = 0.0; }
      activeChannels.clear();
      trashBin.clear();

      isDualContourOverlayActive = false;
      dualContour1.clear();
      dualContour2.clear();
      dualContinuous1.clear();
      dualContinuous2.clear();
      identicalMatchRegions.clear();
      dualLabel1 = '';
      dualLabel2 = '';
      dualTakeSettings = null;
      // ---------------------------------------------------------
    });

    resetAiDetectorState();

    // 🟢 Fire the Garbage Collector to free up gigabytes of phone storage!
    await wipePersistentCache();

    _showSaveConfirmation('New empty project loaded. Workspace storage cleared.');
  }

  // =========================================================================
  // MARKERS
  // =========================================================================

  void addMarkerAtCurrentPlayhead() {
    // Trust the UI playhead time directly!
    double targetTime = currentPosition.clamp(0.0, songDuration);
    
    // Reduce the collision threshold
    bool tooClose = markers.any((m) => ((m['time'] as double) - targetTime).abs() < 0.1);
    if (tooClose) {
      logToSupabase("Marker creation aborted: Too close to an existing marker.");
      return;
    }

    setState(() {
      markers = List.from(markers)..add({
        'id': 'mk_${DateTime.now().millisecondsSinceEpoch}',
        'time': targetTime,
        'label': 'Marker ${markers.length + 1}',
      });
    });
  }


  void setLoopFromMarkers(double start, double end) {
    setState(() { loopStartBoundary = start; loopEndBoundary = end; });
  }

  void deleteMarker(String id) {
    setState(() => markers.removeWhere((m) => m['id'] == id));
  }

  // =========================================================================
  // STUDIO MIXER DSP
  // =========================================================================

  void _applyMasterPlugins() {
    final state   = getChannelState('master');
    final plugins = [state.plugin1, state.plugin2, state.plugin3, state.plugin4];
    try {
      if (plugins.contains('Reverb')) {
        if (!SoLoud.instance.filters.freeverbFilter.isActive) {
          SoLoud.instance.filters.freeverbFilter.activate();
        }
      } else {
        if (SoLoud.instance.filters.freeverbFilter.isActive) {
          SoLoud.instance.filters.freeverbFilter.deactivate();
        }
      }
      if (plugins.contains('Compressor')) {
        if (!SoLoud.instance.filters.compressorFilter.isActive) {
          SoLoud.instance.filters.compressorFilter.activate();
        }
      } else {
        if (SoLoud.instance.filters.compressorFilter.isActive) {
          SoLoud.instance.filters.compressorFilter.deactivate();
        }
      }
      // 🎸 THE NEW OVERDRIVE BLOCK
      if (plugins.contains('Overdrive')) {
        if (!SoLoud.instance.filters.waveShaperFilter.isActive) {
          SoLoud.instance.filters.waveShaperFilter.activate();
        }
        // Set the intensity of the soft clipping based on your slider
        SoLoud.instance.filters.waveShaperFilter.amount.value = state.overdriveAmount;
      } else {
        if (SoLoud.instance.filters.waveShaperFilter.isActive) {
          SoLoud.instance.filters.waveShaperFilter.deactivate();
        }
      }
    } catch (e) {
      logToSupabase('Master DSP activation failed: $e');
    }
  }

  // =========================================================================
  // UI HELPERS
  // =========================================================================

  void _showSaveConfirmation(String message, {bool isPreview = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: TextStyle(color: isPreview ? Colors.white : Colors.orange)),
      backgroundColor:
          isPreview ? Colors.deepPurple[800] : Colors.black,
      duration: Duration(seconds: isPreview ? 6 : 4),
      action: isPreview
          ? SnackBarAction(
              label: 'Play',
              textColor: Colors.deepPurpleAccent,
              onPressed: playAllPlayers)
          : null,
    ));
  }

  void _showEngineRecommendationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(children: [
          Icon(Icons.auto_awesome, color: Colors.tealAccent),
          SizedBox(width: 8),
          Text('Ensemble Router Suggestion',
              style: TextStyle(color: Colors.white)),
        ]),
        content: Text(
          'Acoustic parameters suggest this is a classical or live chamber file. '
          'We recommend using the [${selectedEngineProfile.toUpperCase()}] processing engine layout profile '
          'to prevent dynamic gating artifacts.',
          style: const TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Accept Profile',
                  style: TextStyle(color: Colors.tealAccent))),
        ],
      ),
    );
  }

  // =========================================================================
  // STUDIO MIXER BOTTOM SHEET
  // =========================================================================

  void _showStudioMixer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Crucial for overriding default constraints
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setMixerState) {
            
            // 1. Detect if we are in Landscape Mode inside the builder
            bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

            Widget buildChannelStrip(String title, String key, Color highlight, {bool isMaster = false}) {
              final state       = getChannelState(key);
              bool isAudible    = activePlaybackSources.contains(key) || (isMaster && activePlaybackSources.isNotEmpty);
              double simulatedMeterValue = 0.0;
              if (isPlaying && isAudible) {
                simulatedMeterValue = (0.3 + (math.Random().nextDouble() * 0.6)) * state.volume;
              }

              return Container(
                width: 68,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isMaster ? Colors.redAccent.withOpacity(0.1) : Colors.black87,
                  border: Border.all(color: isMaster ? Colors.redAccent : Colors.white24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(title,
                        style: TextStyle(color: highlight, fontWeight: FontWeight.bold, fontSize: 10),
                        overflow: TextOverflow.ellipsis),
                  ),

                  // 🎚️ NEW REACTIVE VU METER
                  ValueListenableBuilder<double>(
                    valueListenable: channelLevels[key]!,
                    builder: (context, currentLevel, child) {
                      double displayLevel = (isPlaying && isAudible && !state.isMuted) ? currentLevel : 0.0;
                      return ChannelVuMeter(level: displayLevel);
                    },
                  ),
                  const SizedBox(height: 8),

                  // 🎛️ PLUGIN SLOTS 
                  buildPluginSlot(key,state.plugin1, highlight, (val) {
                    if (state.plugin1 != val) {
                      setMixerState(() => state.plugin1 = val!);
                      this.setState(() { hasBeenSaved = false; });
                      //this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                      if (!isMaster) applyStemPlugins(key); else applyMasterPlugins();
                    }
                  }),
                  buildPluginSlot(key,state.plugin2, highlight, (val) {
                    if (state.plugin2 != val) {
                      setMixerState(() => state.plugin2 = val!);
                      this.setState(() { hasBeenSaved = false; });
                      if (!isMaster) applyStemPlugins(key); else applyMasterPlugins();
                    }
                  }),
                  buildPluginSlot(key,state.plugin3, highlight, (val) {
                    if (state.plugin3 != val) {
                      setMixerState(() => state.plugin3 = val!);
                      this.setState(() { hasBeenSaved = false; });
                      if (!isMaster) applyStemPlugins(key); else applyMasterPlugins();
                    }
                  }),
                  buildPluginSlot(key,state.plugin4, highlight, (val) {
                    if (state.plugin4 != val) {
                      setMixerState(() => state.plugin4 = val!);
                      this.setState(() { hasBeenSaved = false; });
                      if (!isMaster) applyStemPlugins(key); else applyMasterPlugins();
                    }
                  }),
                  const SizedBox(height: 4),

                  if (!isMaster)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // MUTE
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              setMixerState(() => state.isMuted = !state.isMuted);
                              this.setState(() { hasBeenSaved = false; });
                              refreshAllVolumes();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                state.isMuted ? Icons.volume_off : Icons.volume_up,
                                color: state.isMuted ? Colors.redAccent : highlight,
                                size: 15,
                              ),
                            ),
                          ),
                          // SOLO
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              setMixerState(() {
                                if (soloedChannels.contains(key)) {
                                  soloedChannels.remove(key);
                                } else {
                                  soloedChannels.add(key);
                                }
                              });
                              this.setState(() { hasBeenSaved = false; });
                              refreshAllVolumes();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                soloedChannels.contains(key)
                                    ? Icons.headphones
                                    : Icons.headphones_outlined,
                                color: soloedChannels.contains(key)
                                    ? Colors.yellowAccent
                                    : Colors.white38,
                                size: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Volume fader
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: () {
                        if (key == 'master') {
                          SoLoud.instance.setGlobalVolume(1.0);
                        } else {
                          refreshAllVolumes();
                        }
                      },
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: highlight,
                            inactiveTrackColor: Colors.white10,
                          ),
                          child: Slider(
                            value: state.volume,
                            min: 0.0, max: 1.5,
                            onChanged: (v) { 
                              // 1. UPDATE THE UI STATE FIRST
                              setMixerState(() => state.volume = v);
                              this.setState(() { hasBeenSaved = false; });
                              
                              // 2. THEN TELL THE AUDIO ENGINE
                              if (key == 'master') {
                                SoLoud.instance.setGlobalVolume(v);
                              } else {
                                refreshAllVolumes();
                              }
                            }
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${(state.volume * 100).round()}%',
                      style: const TextStyle(fontSize: 9, color: Colors.white54)),
                  const SizedBox(height: 4),

                  // Pan slider
                  SizedBox(
                    height: 16,
                    child: GestureDetector(
                      onDoubleTap: () {
                        setMixerState(() => state.pan = 0.0);
                        this.setState(() { hasBeenSaved = false; });
                        if (key == 'master') {
                          if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, 0.0);
                          if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, 0.0);
                          for (var h in stemHandles.values) if (SoLoud.instance.getIsValidVoiceHandle(h)) SoLoud.instance.setPan(h, 0.0);
                        } else if (key == 'original') { if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, 0.0);
                        } else if (key == 'synth') { if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, 0.0);
                        } else if (stemHandles.containsKey(key)) { if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[key]!)) SoLoud.instance.setPan(stemHandles[key]!, 0.0); }
                      },
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: SliderComponentShape.noOverlay,
                          activeTrackColor: highlight,
                          inactiveTrackColor: Colors.white10,
                        ),
                        child: Slider(
                          value: state.pan, min: -1.0, max: 1.0,
                          onChanged: (v) { 
                            setMixerState(() => state.pan = v);
                            this.setState(() { hasBeenSaved = false; });
                            if (key == 'master') {
                              if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, v);
                              if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, v);
                              for (var h in stemHandles.values) if (SoLoud.instance.getIsValidVoiceHandle(h)) SoLoud.instance.setPan(h, v);
                            } else if (key == 'original') { if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, v);
                            } else if (key == 'synth') { if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, v);
                            } else if (stemHandles.containsKey(key)) { if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[key]!)) SoLoud.instance.setPan(stemHandles[key]!, v); }
                          }
                        ),
                      ),
                    ),
                  ),
                  Text(
                    state.pan == 0
                        ? 'C'
                        : (state.pan < 0
                            ? 'L ${-(state.pan * 100).round()}'
                            : 'R ${(state.pan * 100).round()}'),
                    style: const TextStyle(fontSize: 8, color: Colors.white54),
                  ),
                  const SizedBox(height: 4),
                ]),
              );
            }

            return Container(
              // 2. THE FIX: Dynamic height based on orientation!
              height: isLandscape 
                  ? MediaQuery.of(context).size.height * 0.90 // 90% in landscape
                  : MediaQuery.of(context).size.height * 0.52, // 52% in portrait
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: const Border(top: BorderSide(color: Colors.white24)),
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('STUDIO MIXER',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5)),
                      IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    children: [
                      buildChannelStrip('MASTER', 'master', Colors.redAccent, isMaster: true),
                      const SizedBox(width: 12),
                      
                      if (isOriginalMixAvailable)
                        buildChannelStrip('MIX', 'original', Colors.blueGrey),
                        
                      ...targetStemsSelection
                          .where((stem) => stem != 'instrumental' &&
                                           !['drums', 'kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(stem))
                          .map((stem) => buildChannelStrip(stem.toUpperCase(), stem, Colors.tealAccent)),
                          
                      if (targetStemsSelection.any((s) => ['drums', 'kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(s)))
                        DrumSubmixerGroupWidget(dawState: this),
                          
                      //if (targetStemsSelection.contains('instrumental'))
                        //buildChannelStrip('INSTRUMENTAL', 'instrumental', Colors.deepOrangeAccent),
                        
                      const SizedBox(width: 10),
                      buildChannelStrip('SYNTH', 'synth', Colors.purpleAccent),
                    ],
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }

  // 1. The Updated Plugin Slot (Now with a gear icon!)
  Widget buildPluginSlot(String stemKey, String pluginName, Color highlight, ValueChanged<String?> onChanged) {
    return Container(
      height: 20,
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(3)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: Colors.grey[850],
                  iconSize: 10,
                  style: TextStyle(
                      fontSize: 8,
                      color: pluginName == 'None' ? Colors.white38 : highlight),
                  value: pluginName,
                  items: ['None', 'Compressor', 'EQ', 'Reverb', 'Overdrive']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
          // Only show the gear if an effect is active
          if (pluginName != 'None')
            GestureDetector(
              onTap: () => showPluginSettingsDialog(stemKey, pluginName, highlight),
              child: Container(
                width: 16,
                alignment: Alignment.center,
                color: Colors.transparent,
                child: Icon(Icons.settings, size: 10, color: highlight.withOpacity(0.7)),
              ),
            )
          else
            const SizedBox(width: 16), // Spacer to keep alignment
        ],
      ),
    );
  }

  // 2. The Settings Dialog (Real-time Slider)
  void showPluginSettingsDialog(String stemKey, String pluginName, Color highlight) {
    final state = getChannelState(stemKey);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          List<Widget> sliders = [];

          if (pluginName == 'Reverb') {
            sliders.addAll([
              const Text('Mix (Wet/Dry)', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                value: state.reverbMix,
                min: 0.0, max: 1.0, activeColor: highlight,
                onChanged: (val) {
                  setDialogState(() => state.reverbMix = val); // (Make sure this matches the specific variable for each slider)
                  this.setState(() { hasBeenSaved = false; });
                  
                  // THE FIX: Route to the correct audio engine method!
                  if (stemKey == 'master') {
                    applyMasterPlugins();
                  } else {
                    applyStemPlugins(stemKey); 
                  }
                },
              ),
              const SizedBox(height: 12),
              const Text('Room Size', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                value: state.reverbRoomSize,
                min: 0.0, max: 1.0, activeColor: highlight,
                onChanged: (val) {
                  setDialogState(() => state.reverbRoomSize = val);
                  this.setState(() { hasBeenSaved = false; });
                  if (stemKey == 'master') {
                    applyMasterPlugins();
                  } else {
                    applyStemPlugins(stemKey); 
                  }
                },
              ),
            ]);
          } 
          else if (pluginName == 'EQ') {
            sliders.addAll([
              const Text('Low-Pass Cutoff (Hz)', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                value: state.eqCutoff,
                min: 0.0, max: 1.0, activeColor: highlight, // Changed from 200 - 20000
                onChanged: (val) {
                  setDialogState(() => state.eqCutoff = val);
                  this.setState(() { hasBeenSaved = false; });
                  if (stemKey == 'master') {
                    applyMasterPlugins();
                  } else {
                    applyStemPlugins(stemKey); 
                  } 
                },
              ),
            ]);
          }
          else if (pluginName == 'Overdrive') {
            sliders.addAll([
              const Text('Harmonic Drive (Saturation)', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                value: state.overdriveAmount,
                min: 0.0, 
                max: 1.0, // 0.0 is clean, 1.0 is heavy distortion
                activeColor: highlight,
                onChanged: (val) {
                  setDialogState(() => state.overdriveAmount = val);
                  this.setState(() { hasBeenSaved = false; });
                  if (stemKey == 'master') {
                    applyMasterPlugins();
                  } else {
                    applyStemPlugins(stemKey); 
                  } 
                },
              ),
            ]);
          }
          else if (pluginName == 'Compressor') {
            sliders.addAll([
              const Text('Threshold (dB)', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                // SoLoud uses roughly -60dB to 0dB for threshold
                value: state.compressorThreshold,
                min: -60.0, max: 0.0, activeColor: highlight,
                onChanged: (val) {
                  setDialogState(() => state.compressorThreshold = val);
                  this.setState(() { hasBeenSaved = false; });
                  if (stemKey == 'master') {
                    applyMasterPlugins();
                  } else {
                    applyStemPlugins(stemKey); 
                  } 
                },
              ),
              const SizedBox(height: 12),
              const Text('Ratio (X:1)', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                value: state.compressorRatio,
                min: 1.0, max: 20.0, activeColor: highlight,
                onChanged: (val) {
                  setDialogState(() => state.compressorRatio = val);
                  this.setState(() { hasBeenSaved = false; });
                  if (stemKey == 'master') {
                    applyMasterPlugins();
                  } else {
                    applyStemPlugins(stemKey); 
                  }
                },
              ),
            ]);
          }

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text('$pluginName Settings', style: TextStyle(color: highlight, fontSize: 14)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: sliders,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text('Close', style: TextStyle(color: Colors.white54))
              )
            ],
          );
        },
      ),
    );
  }


  // =========================================================================
  // SYNTH SETTINGS DIALOG
  // =========================================================================

  void _showSynthSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void update(SynthSettings Function(SynthSettings) fn) {
            setDialogState(() => synthSettings = fn(synthSettings));
            setState(() {});
          }

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Row(children: [
              Icon(Icons.piano, color: Colors.purpleAccent, size: 20),
              SizedBox(width: 8),
              Text('Synth Settings', style: TextStyle(color: Colors.white)),
            ]),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Plays back the note grid\'s pitch data directly — '
                      'useful for verifying detected pitches independent of the original recording.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(height: 16),
                    const Text('Waveform',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 4,
                      children: Waveform.values.map((w) {
                        bool selected = synthSettings.waveform == w;
                        return ChoiceChip(
                          label: Text(w.label,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: selected ? Colors.black : Colors.white70)),
                          selected: selected,
                          selectedColor: Colors.tealAccent,
                          backgroundColor: Colors.white10,
                          onSelected: (_) => update((s) => s.copyWith(waveform: w)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Envelope (ADSR)',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 11, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    _synthSlider('Attack', synthSettings.adsr.attack, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(attack: v)))),
                    _synthSlider('Decay', synthSettings.adsr.decay, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(decay: v)))),
                    _synthSlider('Sustain', synthSettings.adsr.sustain, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(sustain: v)))),
                    _synthSlider('Release', synthSettings.adsr.release, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(release: v)))),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Text(
                            'Full X-Ray pitch tracking\n(off = basic note values)',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                        Switch(
                          value: synthSettings.useXrayContour,
                          activeColor: Colors.amberAccent,
                          onChanged: (v) =>
                              update((s) => s.copyWith(useXrayContour: v)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  refreshSynthLayerIfActive();
                },
                child: const Text('Close', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent.withOpacity(0.2)),
                icon: const Icon(Icons.play_arrow, color: Colors.tealAccent, size: 16),
                label: const Text('Preview Synth',
                    style: TextStyle(color: Colors.tealAccent)),
                onPressed: rawNotes.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(context);
                        await _togglePlaybackSource('synth', true);
                        if (!isPlaying) playAllPlayers();
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _synthSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(
          width: 56,
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11))),
      Expanded(
          child: Slider(
              value: value,
              min: min, max: max,
              activeColor: Colors.tealAccent,
              onChanged: onChanged)),
      SizedBox(
          width: 36,
          child: Text(value.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white54, fontSize: 10))),
    ]);
  }

  // =========================================================================
  // EXPORT / DOWNLOADS DIALOGS
  // =========================================================================

  void _showAdvancedDownloadsDialog() {
    // Check if we have stems generated OR a valid task ID loaded
    if (generatedStems.isEmpty && currentTaskId == null) {
      _showSaveConfirmation('No active project to export.');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Advanced Downloads',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            /*TextButton(
              onPressed: () async {
                try {
                  throw Exception('Voxray test error!');
                } catch (exception, stackTrace) {
                  await Sentry.captureException(
                    exception,
                    stackTrace: stackTrace,
                  );
                }
              },
              child: const Text('Throw Test Error'),
            ),*/
            ListTile(
              leading: const Icon(Icons.multitrack_audio,
                  color: Colors.amberAccent, size: 28),
              title: const Text('Export Master Mix',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('WAV / FLAC / MP3',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _showExportDialog();
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.piano, color: Colors.purpleAccent, size: 28),
              title: const Text('Export Synth Audio',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('WAV format',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                exportSynthAudio(activeEditableStem);
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.analytics,
                  color: Colors.tealAccent, size: 28),
              title: const Text('Forensic Dossier',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('PDF Report',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                downloadDossier();
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.fingerprint,
                  color: Colors.blueAccent, size: 28),
              title: const Text('PitchPrint™ Graph',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Vector / High-Res',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _showPitchPrintOptions();
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.adjust, color: Colors.pinkAccent, size: 28),
              title: const Text('Export Marked Stem',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('WAV w/ Embedded DAW Markers',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              onTap: () async {
                Navigator.pop(context);
                final xrayStems = getStemsWithXray();
                if (xrayStems.isEmpty) {
                  _showSaveConfirmation('No X-Ray data to embed. Process a stem first.');
                  return;
                }
                final targetStem = await _promptForReportStem(xrayStems, 'Marked Stem Export');
                if (targetStem != null) {
                  exportMarkedStem(targetStem);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Export Format',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.audio_file, color: Colors.tealAccent, size: 30),
              title: const Text('WAV',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Lossless / Studio Quality',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async { 
                Navigator.pop(context); 
                await exportFinalMaster('wav'); 
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.library_music,
                  color: Colors.amberAccent, size: 30),
              title: const Text('FLAC',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Lossless / Compressed Size',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async { 
                Navigator.pop(context); 
                await exportFinalMaster('flac'); 
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.music_note, color: Colors.blueAccent, size: 30),
              title: const Text('MP3',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Standard / Web Optimized',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async { 
                Navigator.pop(context); 
                await exportFinalMaster('mp3'); 
              },
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }

  void _showPitchPrintOptions() async {
    // 1. Check for X-Ray data and prompt for the stem
    final xrayStems = getStemsWithXray();
    if (xrayStems.isEmpty) {
      _showSaveConfirmation('No X-Ray data available for PitchPrint™. Please process a stem first.');
      return;
    }
    
    final targetStem = await _promptForReportStem(xrayStems, 'PitchPrint™');
    if (targetStem == null) return;

    bool fullSong = true;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Row(children: [
            Icon(Icons.fingerprint, color: Colors.amberAccent, size: 20),
            SizedBox(width: 8),
            Text('Export PitchPrint™', style: TextStyle(color: Colors.white)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Generate a high-resolution pitch analysis graph.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                    color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                child: Column(children: [
                  RadioListTile<bool>(
                    value: true, groupValue: fullSong,
                    activeColor: Colors.amberAccent,
                    title: const Text('Full Song',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Complete performance analysis',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                    onChanged: (v) => setDialogState(() => fullSong = v!),
                  ),
                  RadioListTile<bool>(
                    value: false, groupValue: fullSong,
                    activeColor: Colors.amberAccent,
                    title: const Text('Visible Region',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Current timeline view only',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                    onChanged: (v) => setDialogState(() => fullSong = v!),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.tealAccent, size: 30),
                title: const Text('SVG Vector',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Scalable Vector Graphics',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  double visibleStart = horizontalScrollController.hasClients
                      ? horizontalScrollController.position.pixels / zoomX : 0.0;
                  double visibleEnd = horizontalScrollController.hasClients
                      ? (horizontalScrollController.position.pixels +
                              horizontalScrollController.position.viewportDimension) /
                          zoomX
                      : songDuration;
                      
                  // 2. Pass the selected targetStem to the download function!
                  downloadPitchPrint(
                      targetStem: targetStem,
                      fullSong: fullSong, format: 'svg',
                      visibleStart: visibleStart, visibleEnd: visibleEnd);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // DOSSIER (in-app) DIALOG
  // =========================================================================

  Future<void> _showDossier() async {
    // 1. Replaces the rawNotes.isEmpty check with our multi-track selector
    final xrayStems = getStemsWithXray();
    if (xrayStems.isEmpty) {
      _showSaveConfirmation('No X-Ray data to analyze. Please process a stem with X-Ray first.');
      return;
    }

    final targetStem = await _promptForReportStem(xrayStems, 'Dossier Summary');
    if (targetStem == null) return;

    setState(() {
      isLoading = true;
      processingMessage = 'Compiling Forensic Dossier for ${targetStem.toUpperCase()}...';
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse('$apiBase/generate-dossier'));
      
      // Preserved your offline fallback!
      request.fields['task_id'] = currentTaskId ?? 'offline_session';
      
      request.fields['session_meta'] = jsonEncode({
        'filename': originalFileName,
        'duration': songDuration,
        'stem_target': targetStem, // Now explicitly uses the selected track
        'xray_enabled': true,      // Guaranteed true because of getStemsWithXray()
        'version': '1.5.0'
      });
      
      // Pulls notes for the specific selected track rather than defaulting to rawNotes
      request.fields['notes_manifest'] = jsonEncode(allStemsNotes[targetStem] ?? []);

      final streamedResponse = await request.send();
      final responseData = await streamedResponse.stream.bytesToString();
      
      if (streamedResponse.statusCode == 200) {
        final decoded = jsonDecode(responseData);
        if (decoded['status'] == 'success') {
          final markdownData = decoded['report_md'] ?? '# Error\nMarkdown payload missing from server.';
          // Passes the targetStem to the modal for the header!
          if (mounted) _showDossierModal(context, markdownData, targetStem);
        } else {
          _showSaveConfirmation('Failed to generate dossier.');
        }
      } else {
        _showSaveConfirmation('Server error: ${streamedResponse.statusCode}');
      }
    } catch (e) {
      _showSaveConfirmation('Network error generating dossier: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Updated signature to accept targetStem
  void _showDossierModal(BuildContext context, String markdownData, String targetStem) {
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85, 
        minChildSize: 0.4, 
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161616), 
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), 
            border: Border.all(color: const Color(0xFF333333))
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                children: [
                  // NOTE: Removed 'const' from Flexible because targetStem is dynamic!
                  Flexible(
                    child: Row(children: [
                      const Icon(Icons.shield_outlined, color: Color(0xFF00E5FF)), 
                      const SizedBox(width: 12), 
                      Expanded(
                        child: Text(
                          'FORENSIC INTEGRITY DOSSIER: ${targetStem.toUpperCase()}', // Dynamic Title
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white), 
                          overflow: TextOverflow.ellipsis
                        )
                      )
                    ])
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54), 
                    onPressed: () => Navigator.pop(context)
                  ),
                ]
              ),
              const Divider(color: Color(0xFF333333), height: 24),
              Expanded(
                child: Markdown(
                  controller: scrollController, 
                  data: markdownData, 
                  selectable: true, 
                  styleSheet: MarkdownStyleSheet(
                    h1: const TextStyle(color: Color(0xFF00E5FF), fontSize: 20, fontWeight: FontWeight.bold), 
                    h2: const TextStyle(color: Color(0xFF00E5FF), fontSize: 16, fontWeight: FontWeight.bold), 
                    p: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5), 
                    listBullet: const TextStyle(color: Color(0xFF00E5FF))
                  )
                )
              ),
            ]
          ),
        ),
      ),
    );
  }
  
  void _showDossier_old() {
    if (rawNotes.isEmpty) return;

    String midiToName(num midi) {
      const noteNames = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
      int m = midi.round();
      return '${noteNames[m % 12]}${(m ~/ 12) - 1}';
    }

    int totalNotes = 0, perfectlyTuned = 0, mutedCount = 0, deletedCount = 0;
    double totalError = 0;
    Map<String, List<double>> noteErrors = {};
    bool hasXray = rawNotes.any((n) => n.containsKey('contour') && n['contour'] != null);

    for (var note in rawNotes) {
      if (note['isDeleted'] == true) { deletedCount++; continue; }
      double baseMidi = (note['actual_midi'] ?? 60.0).toDouble() + (note['semitone_shift'] ?? 0);
      if (baseMidi.round() == 36) continue;
      if (note['isMuted'] == true) mutedCount++;
      totalNotes++;

      double effectiveCents;
      if (note['contour'] != null && (note['contour'] as List).isNotEmpty) {
        List<dynamic> contour = note['contour'];
        effectiveCents = contour
                .map((c) => (c as num).toDouble().abs())
                .reduce((a, b) => a + b) /
            contour.length;
      } else {
        double rawCents   = (baseMidi - baseMidi.round()) * 100;
        double shiftCents = (note['cents_shift'] ?? 0).toDouble();
        effectiveCents    = (rawCents + shiftCents).abs();
      }

      totalError += effectiveCents;
      if (effectiveCents <= 10) perfectlyTuned++;
      String name = midiToName(baseMidi.round());
      noteErrors.putIfAbsent(name, () => []).add(effectiveCents);
    }

    double avgError  = totalNotes > 0 ? totalError / totalNotes : 0;
    double tunedPct  = totalNotes > 0 ? (perfectlyTuned / totalNotes) * 100 : 0;
    var worstNotes   = noteErrors.entries.toList()
      ..sort((a, b) {
        double aAvg = a.value.reduce((x, y) => x + y) / a.value.length;
        double bAvg = b.value.reduce((x, y) => x + y) / b.value.length;
        return bAvg.compareTo(aAvg);
      });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Row(children: [
          Text('Dossier: ${activeEditableStem.toUpperCase()}',
              style: const TextStyle(color: Colors.white)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: hasXray
                  ? Colors.amberAccent.withOpacity(0.2)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: hasXray
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.fingerprint, color: Colors.amberAccent, size: 14),
                    SizedBox(width: 4),
                    Text('X-Ray',
                        style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                  ])
                : const Text('X-Ray not enabled',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SUMMARY',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              _dossierRow('Notes analyzed', '$totalNotes'),
              _dossierRow('Muted notes', '$mutedCount'),
              _dossierRow('Deleted notes', '$deletedCount'),
              const SizedBox(height: 10),
              const Text('PITCH ACCURACY',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              _dossierRow('Avg pitch error', '${avgError.toStringAsFixed(1)} ¢'),
              _dossierRow(
                  'Studio-accurate (≤10¢)', '${tunedPct.toStringAsFixed(1)}%'),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: tunedPct / 100,
                  backgroundColor: Colors.redAccent.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    tunedPct >= 80
                        ? Colors.tealAccent
                        : tunedPct >= 50
                            ? Colors.amberAccent
                            : Colors.redAccent,
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              if (worstNotes.isNotEmpty) ...[
                const Text('MOST VARIANCE BY NOTE',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                ...worstNotes.take(5).map((entry) {
                  double avg =
                      entry.value.reduce((a, b) => a + b) / entry.value.length;
                  Color c = avg <= 10
                      ? Colors.tealAccent
                      : avg <= 25
                          ? Colors.amberAccent
                          : Colors.redAccent;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      SizedBox(
                          width: 36,
                          child: Text(entry.key,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                      const SizedBox(width: 4),
                      Expanded(
                          child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (avg / 100).clamp(0.0, 1.0),
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(c),
                          minHeight: 6,
                        ),
                      )),
                      const SizedBox(width: 4),
                      Text('${avg.toStringAsFixed(1)}¢',
                          style: TextStyle(color: c, fontSize: 11)),
                      Text(' ×${entry.value.length}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10)),
                    ]),
                  );
                }),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: avgError < 15
                      ? Colors.teal.withOpacity(0.15)
                      : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: avgError < 15
                          ? Colors.tealAccent.withOpacity(0.4)
                          : Colors.redAccent.withOpacity(0.4)),
                ),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                    children: avgError < 10
                        ? [
                            const TextSpan(
                                text:
                                    'VERDICT: Exceptional intonation. Studio-ready performance.',
                                style: TextStyle(color: Colors.tealAccent))
                          ]
                        : avgError < 15
                            ? [
                                const TextSpan(
                                    text:
                                        'VERDICT: Highly accurate. Minor touch-ups may be desired.',
                                    style: TextStyle(color: Colors.tealAccent))
                              ]
                            : avgError < 25
                                ? [
                                    const TextSpan(
                                        text:
                                            'VERDICT: Moderate variance detected. Pitch correction not detected. ',
                                        style: TextStyle(color: Colors.tealAccent)),
                                    const TextSpan(
                                        text:
                                            'On flagged notes, the tuning could be improved audibly.',
                                        style: TextStyle(color: Colors.redAccent)),
                                  ]
                                : [
                                    const TextSpan(
                                        text:
                                            'VERDICT: Significant tuning issues. Review red-flagged notes in the piano roll.',
                                        style: TextStyle(color: Colors.redAccent))
                                  ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _dossierRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // =========================================================================
  // STEM SELECTOR TREE DIALOG
  // =========================================================================

  void _showStemSelectorTreeDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setTreeState) {
          
          // 1. We keep your exact checkbox logic (handles recommendations and selection perfectly)
          Widget buildStemCheckbox(String stem) {
            bool isSuggested = suggestedStems.contains(stem);
            return CheckboxListTile(
              dense: true,
              title: Row(children: [
                Text(stem,
                    style: TextStyle(
                        fontSize: 13,
                        color: isSuggested ? Colors.yellowAccent : Colors.white70)),
                if (isSuggested)
                  const Padding(
                    padding: EdgeInsets.only(left: 6.0),
                    child: Text('RECOMMENDED',
                        style: TextStyle(
                            fontSize: 9,
                            color: Colors.yellowAccent,
                            fontWeight: FontWeight.bold)),
                  ),
              ]),
              value: targetStemsSelection.contains(stem),
              activeColor: Colors.tealAccent,
              onChanged: (bool? checked) {
                setTreeState(() {
                  if (checked == true) targetStemsSelection.add(stem);
                  else targetStemsSelection.remove(stem);
                });
                setState(() {}); // Updates the main background UI if necessary
              },
            );
          }

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Stem Extraction Matrix',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12.0),
                      child: Text(
                          'Select which stems will be available in the dropdown to generate later.',
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ),
                    
                    // 2. Wrap the lists in ExpansionTiles to compress the UI
                    // We use Theme to hide the default borders ExpansionTile draws
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: Column(
                        children: [
                          // POP & ROCK - Initially expanded since it's most common
                          ExpansionTile(
                            initiallyExpanded: true, 
                            iconColor: Colors.tealAccent,
                            collapsedIconColor: Colors.tealAccent,
                            title: const Text('POP & ROCK MODELS',
                                style: TextStyle(
                                    color: Colors.tealAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1)),
                            children: popStems.map(buildStemCheckbox).toList(),
                          ),
                          
                          // ORCHESTRAL - Collapsed by default
                          ExpansionTile(
                            initiallyExpanded: false,
                            iconColor: Colors.amberAccent,
                            collapsedIconColor: Colors.amberAccent,
                            title: const Text('ORCHESTRAL MODELS',
                                style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1)),
                            children: orchStems.map(buildStemCheckbox).toList(),
                          ),
                          
                          // FORENSICS - Collapsed by default
                          ExpansionTile(
                            initiallyExpanded: false,
                            iconColor: Colors.redAccent,
                            collapsedIconColor: Colors.redAccent,
                            title: const Text('FORENSIC SUITE',
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1)),
                            children: forensicStems.map(buildStemCheckbox).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Confirm Selection',
                      style: TextStyle(color: Colors.tealAccent))),
            ],
          );
        },
      ),
    );
  }

  // =========================================================================
  // MAIN MENU
  // =========================================================================

  List<PopupMenuEntry<String>> _buildMainMenu() {
    bool canSaveAs = isProjectLoaded;
    
    return [
      PopupMenuItem(
        value: 'toggle_help_mode',
        child: ListTile(
          leading: Icon(Icons.help_outline, color: isHelpModeActive ? Colors.amberAccent : Colors.white54),
          title: Text(isHelpModeActive ? 'Disable Inspection Mode' : 'Enable Inspection Mode (Help Overlay)'),
        ),
      ),
      PopupMenuItem(
          value: 'new_project',
          enabled: !isApiBusy,
          child: const ListTile(
              leading: Icon(Icons.add_box, color: Colors.amberAccent),
              title: Text('New Project (Clear Workspace)'))),
      const PopupMenuDivider(),
      PopupMenuItem(
          value: 'upload',
          enabled: !isApiBusy,
          child: const ListTile(
              leading: Icon(Icons.cloud_upload, color: Colors.tealAccent),
              title: Text('Load New Audio'))),
      PopupMenuItem(
          value: 'load',
          enabled: !isApiBusy,
          child: const ListTile(
              leading: Icon(Icons.folder_open), title: Text('Load Project'))),
      PopupMenuItem(
          value: 'save_as',
          enabled: canSaveAs && !isApiBusy,
          child: ListTile(
              leading: Icon(
                Icons.save_as, 
                color: (canSaveAs && !isApiBusy) ? Colors.white : Colors.white38
              ),
              title: Text(
                'Save Project As...', 
                style: TextStyle(color: (canSaveAs && !isApiBusy) ? Colors.white : Colors.white38)
              )
          )
      ),
      
      const PopupMenuDivider(),
      
      const PopupMenuItem(
          value: 'run_nuclear_piano',
          child: ListTile(
              leading: Icon(Icons.piano, color: Colors.purpleAccent),
              title: Text('Generate HQ Piano'))),
      const PopupMenuItem(
          value: 'synth_settings',
          child: ListTile(
              leading: Icon(Icons.piano, color: Colors.purpleAccent),
              title: Text('Synth Audio Settings'))),
      // 🟢 NEW: Nudge Control Toggle
      PopupMenuItem(
          value: 'toggle_nudge',
          child: ListTile(
              leading: Icon(Icons.compare_arrows, color: showNudgeControls ? Colors.amberAccent : Colors.white54),
              title: Text(showNudgeControls ? 'Hide Track Nudge Controls' : 'Show Track Nudge Controls'))),
      PopupMenuItem(
          value: 'scrub_toggle',
          child: ListTile(
              leading: Icon(Icons.touch_app, color: isScrubMode ? Colors.amberAccent : Colors.white54),
              title: Text(isScrubMode ? 'Play from Selected Note' : 'Play Continuous (Scrub off)'))),
      
      const PopupMenuDivider(),


      PopupMenuItem(
          value: 'import_stem',
          enabled: !isApiBusy,
          child: const ListTile(
              leading: Icon(Icons.file_open, color: Colors.tealAccent),
              title: Text('Import Individual Track'))),
      
      PopupMenuItem(
          value: 'restore_stems',
          enabled: trashBin.isNotEmpty && !isApiBusy,
          child: ListTile(
            leading: const Icon(Icons.restore_from_trash, color: Colors.tealAccent),
            title: Text(
              'Restore Hidden Stems (${trashBin.length})',
              style: TextStyle(color: trashBin.isNotEmpty ? Colors.white : Colors.white38),
            ),
          ),
      ),
      const PopupMenuDivider(),

    
      PopupMenuItem(
          value: 'show_scorecard',
          enabled: !isApiBusy,
          child: const ListTile(
              leading: Icon(Icons.assessment, color: Colors.greenAccent),
              title: Text('Show Scorecard'))),
      PopupMenuItem(
          value: 'show_color_key',
          child: const ListTile(
              leading: Icon(Icons.palette, color: Colors.lightBlueAccent),
              title: Text('Pitch Color Key'))),
      PopupMenuItem(
          value: 'show_dossier',
          enabled: !isApiBusy,
          child: const ListTile(
              leading: Icon(Icons.assessment, color: Colors.greenAccent),
              title: Text('Dossier Summary'))),
      PopupMenuItem(
          value: 'downloads',
          enabled: !isApiBusy,
          child: const ListTile(
              leading: Icon(Icons.download, color: Colors.blueAccent),
              title: Text('Advanced Downloads'))),
      
      // Removed the Dual X-Ray menu item as requested!
      PopupMenuItem(
          value: 'export_stems',
          enabled: !isApiBusy,
          child: const ListTile(
              leading: Icon(Icons.unarchive, color: Colors.amberAccent),
              title: Text('Export Stems Archive'))),
      
      const PopupMenuDivider(),
      
      const PopupMenuItem(
          value: 'about_info',
          child: ListTile(
              leading: Icon(Icons.info_outline, color: Colors.white54),
              title: Text('About / FAQ'))),
      const PopupMenuItem(
          value: 'feedback',
          child: ListTile(
              leading: Icon(Icons.info_outline, color: Colors.white54),
              title: Text('Submit Bugs / Features'))),
      
      const PopupMenuDivider(),
      
      PopupMenuItem(
          value: 'live_mode',
          enabled: !isApiBusy,
          child: ListTile(
              leading: Icon(Icons.mic_external_on, color: isLiveModeActive ? Colors.redAccent : Colors.white),
              title: Text(isLiveModeActive ? 'Disable Live Pedagogy' : 'Enable Live Pedagogy',
                  style: TextStyle(color: isLiveModeActive ? Colors.redAccent : Colors.white)))),
      
      const PopupMenuDivider(),
      
      const PopupMenuItem(enabled: false, child: Text('    DEBUG USE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold))),
      PopupMenuItem(
          value: 'reprocess',
          enabled: !isApiBusy,
          child: const ListTile(
              leading: Icon(Icons.sync_problem, color: Colors.orangeAccent),
              title: Text('Reprocess X-Ray', style: TextStyle(color: Colors.orangeAccent)))),
      const PopupMenuDivider(),

      PopupMenuItem(
          value: 'build_info',
          child: const ListTile(
              leading: Icon(Icons.manage_accounts, color: Colors.white54),
              title: Text('Build Info'))),
      PopupMenuItem(
          value: 'account_settings',
          child: const ListTile(
              leading: Icon(Icons.manage_accounts, color: Colors.white54),
              title: Text('Manage Account'))),
      PopupMenuItem(
          value: 'logout',
          child: const ListTile(
              leading: Icon(Icons.logout, color: Colors.redAccent),
              title: Text('Log Out', style: TextStyle(color: Colors.redAccent)))),
      PopupMenuItem(
          value: 'delete_account',
          child: const ListTile(
              leading: Icon(Icons.delete_forever, color: Colors.red),
              title: Text('Delete Account', style: TextStyle(color: Colors.red)))),
    ];
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'toggle_help_mode':
        setState(() => isHelpModeActive = !isHelpModeActive);
        _showSaveConfirmation(
          isHelpModeActive ? 'Inspection Mode Active. Tap any highlighted element to learn its function.' : 'Inspection Mode Disabled.',
          isPreview: true,
        );
        break;
      case 'new_project':     _newProject(); break;
      case 'upload':          loadFileAndAnalyze(context); break;
      case 'import_stem':     importIndividualStem(context); break;
      case 'stem_tree':       _showStemSelectorTreeDialog(); break;
      case 'load':            loadVoxrayProject(context); break;
      case 'save':            saveVoxrayProject(); break;
      case 'save_as':         saveVoxrayProjectAs(); break;
      case 'restore_stems':     _showRestoreStemsDialog(); break;
      case 'export_stems':    exportStemsAsZip(); break;
      case 'scrub_toggle':    setState(() => isScrubMode = !isScrubMode); break;
      case 'toggle_nudge':    setState(() => showNudgeControls = !showNudgeControls); break;
      case 'processing_mode':
        setState(() => processingMode = processingMode == 'classic' ? 'advanced' : 'classic');
        break;
      case 'run_nuclear_piano':  _runNuclearPianoExtraction(); break;
      case 'synth_settings':  _showSynthSettingsDialog(); break;
      case 'show_scorecard':    _showScorecard(); break;
      case 'show_color_key':  _showPitchColorKeyDialog(); break;
      case 'show_dossier':    _showDossier(); break;
      case 'downloads':       _showAdvancedDownloadsDialog(); break;
      case 'live_mode':       setState(() => isLiveModeActive = !isLiveModeActive); break;
      case 'reprocess':       forceReprocessXray(context); break;
      case 'detect_ai_vocal': _runAiVocalInspection(); break;
      case 'test_mode':       setState(() => isTestModeActive = !isTestModeActive); break;
      case 'build_info':      _showAboutApp(context); break;
      //case 'account_settings':
      //  Navigator.push(context, MaterialPageRoute(builder: (_) => AccountSettingsScreen()));
      //  break;
      case 'about_info':
        Navigator.push(context, MaterialPageRoute(builder: (_) => AboutInfoScreen(contentKey: 'about_me', pageTitle: 'About voXRay')));
        break;
      case 'feedback':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackScreen()));
        //Navigator.push(context, MaterialPageRoute(builder: (_) => FeedbackScreen(contentKey: 'bugs_feedback', pageTitle: 'Submit Bugs / Feedback')));
        break;
      case 'dual_take':       _loadSecondaryVocalTake(); break; // obsolete... fun for earli prototesting but not useful.
      //case 'sync_vocals':     _syncVocalTakes(); break;
        // Inside _handleMenuSelection(String value), add the case handler:
      case 'account_settings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsScreen()));
        break;
      case 'god_mode':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const GodModeDashboard()));
        break;
      case 'logout':
        BackendService.supabase.auth.signOut();
        break;
      case 'delete_account':
        _showDeleteAccountConfirmation();
        break;
      
    }
  }

  void _showRestoreStemsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(children: [
          Icon(Icons.restore_from_trash, color: Colors.tealAccent),
          SizedBox(width: 8),
          Text('Restore Hidden Stems', style: TextStyle(color: Colors.white)),
        ]),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: trashBin.length,
            itemBuilder: (context, index) {
              final channel = trashBin[index];
              return ListTile(
                title: Text(channel.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Type: ${channel.baseType}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    Navigator.pop(context);
                    restoreChannel(channel);
                    _showSaveConfirmation('Restored ${channel.name}!');
                  },
                  child: const Text('Restore', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildDockedMixer() {
    Widget buildChannelStrip(String title, String key, Color highlight, {bool isMaster = false}) {
      final state       = getChannelState(key);
      bool isAudible    = activePlaybackSources.contains(key) || (isMaster && activePlaybackSources.isNotEmpty);
      
      return Container(
        width: 68,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isMaster ? Colors.redAccent.withOpacity(0.1) : Colors.black87,
          border: Border.all(color: isMaster ? Colors.redAccent : Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(title, style: TextStyle(color: highlight, fontWeight: FontWeight.bold, fontSize: 10), overflow: TextOverflow.ellipsis),
          ),
          ValueListenableBuilder<double>(
            valueListenable: channelLevels[key]!,
            builder: (context, currentLevel, child) {
              double displayLevel = (isPlaying && isAudible && !state.isMuted) ? currentLevel : 0.0;
              return ChannelVuMeter(level: displayLevel);
            },
          ),
          const SizedBox(height: 8),
          buildPluginSlot(key,state.plugin1, highlight, (val) { if (state.plugin1 != val) { setState(() { state.plugin1 = val!; hasBeenSaved = false; }); if (!isMaster) applyStemPlugins(key); else applyMasterPlugins(); } }),
          buildPluginSlot(key,state.plugin2, highlight, (val) { if (state.plugin2 != val) { setState(() { state.plugin2 = val!; hasBeenSaved = false; }); if (!isMaster) applyStemPlugins(key); else applyMasterPlugins(); } }),
          buildPluginSlot(key,state.plugin3, highlight, (val) { if (state.plugin3 != val) { setState(() { state.plugin3 = val!; hasBeenSaved = false; }); if (!isMaster) applyStemPlugins(key); else applyMasterPlugins(); } }),
          buildPluginSlot(key,state.plugin4, highlight, (val) { if (state.plugin4 != val) { setState(() { state.plugin4 = val!; hasBeenSaved = false; }); if (!isMaster) applyStemPlugins(key); else applyMasterPlugins(); } }),
          const SizedBox(height: 4),
          if (!isMaster)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () { setState(() { state.isMuted = !state.isMuted; hasBeenSaved = false; }); refreshAllVolumes(); },
                    child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(state.isMuted ? Icons.volume_off : Icons.volume_up, color: state.isMuted ? Colors.redAccent : highlight, size: 15)),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () { setState(() { if (soloedChannels.contains(key)) soloedChannels.remove(key); else soloedChannels.add(key); hasBeenSaved = false; }); refreshAllVolumes(); },
                    child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(soloedChannels.contains(key) ? Icons.headphones : Icons.headphones_outlined, color: soloedChannels.contains(key) ? Colors.yellowAccent : Colors.white38, size: 15)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: GestureDetector(
              onDoubleTap: () { if (key == 'master') SoLoud.instance.setGlobalVolume(1.0); else refreshAllVolumes(); },
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderThemeData(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7), overlayShape: SliderComponentShape.noOverlay, activeTrackColor: highlight, inactiveTrackColor: Colors.white10),
                  child: Slider(
                    value: state.volume, min: 0.0, max: 1.5,
                    onChanged: (v) { 
                      setState(() { state.volume = v; hasBeenSaved = false; }); 
                      if (key == 'master') SoLoud.instance.setGlobalVolume(v); else refreshAllVolumes(); 
                    }
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(state.volume * 100).round()}%', style: const TextStyle(fontSize: 9, color: Colors.white54)),
          const SizedBox(height: 4),
          SizedBox(
            height: 16,
            child: GestureDetector(
              onDoubleTap: () {
                setState(() { state.pan = 0.0; hasBeenSaved = false; });
                if (key == 'master') { if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, 0.0); if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, 0.0); for (var h in stemHandles.values) if (SoLoud.instance.getIsValidVoiceHandle(h)) SoLoud.instance.setPan(h, 0.0); }
                else if (key == 'original') { if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, 0.0); }
                else if (key == 'synth') { if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, 0.0); }
                else if (stemHandles.containsKey(key)) { if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[key]!)) SoLoud.instance.setPan(stemHandles[key]!, 0.0); }
              },
              child: SliderTheme(
                data: SliderThemeData(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: SliderComponentShape.noOverlay, activeTrackColor: highlight, inactiveTrackColor: Colors.white10),
                child: Slider(
                  value: state.pan, min: -1.0, max: 1.0,
                  onChanged: (v) { 
                    setState(() { state.pan = v; hasBeenSaved = false; });
                    if (key == 'master') { if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, v); if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, v); for (var h in stemHandles.values) if (SoLoud.instance.getIsValidVoiceHandle(h)) SoLoud.instance.setPan(h, v); }
                    else if (key == 'original') { if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, v); }
                    else if (key == 'synth') { if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, v); }
                    else if (stemHandles.containsKey(key)) { if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[key]!)) SoLoud.instance.setPan(stemHandles[key]!, v); }
                  }
                ),
              ),
            ),
          ),
          Text(state.pan == 0 ? 'C' : (state.pan < 0 ? 'L ${-(state.pan * 100).round()}' : 'R ${(state.pan * 100).round()}'), style: const TextStyle(fontSize: 8, color: Colors.white54)),
          const SizedBox(height: 4),
        ]),
      );
    }

    return Container(
      height: 260, // Fixed height for docked mixer
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: const Border(top: BorderSide(color: Colors.black, width: 4)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('STUDIO MIXER', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => isDockedMixerVisible = false)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              buildChannelStrip('MASTER', 'master', Colors.redAccent, isMaster: true),
              const SizedBox(width: 12),
              if (isOriginalMixAvailable) buildChannelStrip('MIX', 'original', Colors.blueGrey),
              ...targetStemsSelection
                  .where((stem) => stem != 'instrumental' && !['drums', 'kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(stem))
                  .map((stem) => buildChannelStrip(stem.toUpperCase(), stem, Colors.tealAccent)),
              if (targetStemsSelection.any((s) => ['drums', 'kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(s)))
                DrumSubmixerGroupWidget(dawState: this),
              const SizedBox(width: 10),
              buildChannelStrip('SYNTH', 'synth', Colors.purpleAccent),
            ],
          ),
        ),
      ]),
    );
  }
  
  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    bool isCurrentStemGenerated = generatedStems.contains(activeEditableStem);
    // 1. Detect Orientation
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // 2. Extract the Status / Progress Content so we can place it dynamically
    Widget buildStatusContent(bool compact) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(Icons.audio_file, size: compact ? 12 : 14, color: Colors.white54),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                originalFileName != 'Unknown File'
                    ? '$originalFileName' +
                        (activeEditableStem.isNotEmpty ? '  [STEM: ${activeEditableStem.toUpperCase()}]' : '')
                    : 'No File Loaded',
                style: TextStyle(fontSize: compact ? 10 : 12, color: Colors.white70, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (projectName != 'Voxray_Session')
              Text(' [$projectName]', style: TextStyle(fontSize: compact ? 10 : 12, color: Colors.white38)),
          ]),
          if (isLoading) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                  child: LinearProgressIndicator(
                      value: processingProgress, color: Colors.tealAccent, backgroundColor: Colors.grey[800], minHeight: compact ? 2 : 4)),
              const SizedBox(width: 8),
              const BouncingEqIndicator(color: Colors.tealAccent, height: 12.0),
              const SizedBox(width: 6),
              Text(processingMessage, style: TextStyle(fontSize: compact ? 9 : 10, color: Colors.tealAccent)),
            ]),
          ] else if (isPreviewing || isExporting || isSynthRendering) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                  child: LinearProgressIndicator(
                      value: processingProgress, color: Colors.amberAccent, backgroundColor: Colors.grey[800], minHeight: compact ? 2 : 4)),
              const SizedBox(width: 8),
              const BouncingEqIndicator(color: Colors.amberAccent, height: 12.0),
              const SizedBox(width: 6),
              Text(exportMessage.isNotEmpty ? exportMessage : synthMessage,
                  style: TextStyle(fontSize: compact ? 9 : 10, color: Colors.amberAccent)),
            ]),
          ],
        ],
      );
    }

    // 3. Extract the Tool Group (Mixer + Pan + Preview + Analysis)
    Widget buildToolGroup() {
      
      // ── DYNAMIC CONTEXT STATES ──
      bool isDrumTrack  = ['drums', 'kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(activeEditableStem);
      bool isVocalTrack = activeEditableStem.startsWith('vocal');

      // 1. support imported stems
      bool hasTrackAudio = generatedStems.contains(activeEditableStem) || 
                           cachedStemBytes.containsKey(activeEditableStem) || 
                           cachedStemPaths.containsKey(activeEditableStem);
      
      // 1.1 X-Ray State Logic
      bool canRunXray  = activeEditableStem.isNotEmpty && !isDrumTrack && hasTrackAudio;
      bool hasXrayData = rawNotes.isNotEmpty && rawNotes.any((n) => n is Map && n.containsKey('contour') && n['contour'] != null);
      
      Color xrayColor;
      if (!canRunXray) {
        xrayColor = Colors.white24; // Disabled (e.g., Drums or not generated)
      } else if (isXrayMode) {
        xrayColor = Colors.amberAccent; // Generated & Active
      } else if (hasXrayData) {
        xrayColor = Colors.amberAccent.withOpacity(0.6); // Generated but toggled off
      } else {
        xrayColor = Colors.amberAccent.withOpacity(0.25); // Available but not run
      }

      // 2. Dual X-Ray State Logic
      // Available whenever there are at least 2 non-drum tracks in the project
      bool canRunDualXray = activeChannels.where((c) => !['drums', 'kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(c.stemKey)).length >= 2;
      
      Color dualBaseColor = isDualContourOverlayActive ? const Color(0xFF00E5FF) : (canRunDualXray ? const Color(0xFF00E5FF).withOpacity(0.25) : Colors.white24);
      Color dualTopColor  = isDualContourOverlayActive ? const Color(0xFFFF007F).withOpacity(0.8) : (canRunDualXray ? const Color(0xFFFF007F).withOpacity(0.25) : Colors.transparent);

      // 3. AI Detection State Logic
      //bool hasTrackAudio = generatedStems.contains(activeEditableStem) || cachedStemBytes.containsKey(activeEditableStem) || cachedStemPaths.containsKey(activeEditableStem);
      bool canRunAi = activeEditableStem.isNotEmpty && hasTrackAudio; // Removed isVocalTrack requirement
      // old, vocal only version:
      //bool hasVocalAudio = generatedStems.contains(activeEditableStem) || cachedStemBytes.containsKey(activeEditableStem) || cachedStemPaths.containsKey(activeEditableStem);
      //bool canRunAi = isVocalTrack && hasVocalAudio;
      
      Color aiColor;
      if (!canRunAi) {
        aiColor = Colors.white24; // Disabled (Non-vocal track)
      } else if (aiResult != null) {
        aiColor = Colors.cyanAccent; // Generated & Active (Results exist)
      } else {
        aiColor = Colors.cyanAccent.withOpacity(0.25); // Available but not run
      }
      // ────────────────────────────

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              icon: Icon(
                Icons.tune, 
                color: (MediaQuery.of(context).size.width > 900 && isDockedMixerVisible) ? Colors.white : Colors.orangeAccent, 
                size: 22
              ),
              tooltip: 'Studio Mixer',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () {
                // If it's a large screen, dock it. If it's a phone, use the popup!
                if (MediaQuery.of(context).size.width > 900) {
                  setState(() => isDockedMixerVisible = !isDockedMixerVisible);
                } else {
                  _showStudioMixer();
                }
              }),
          const SizedBox(width: 4),
          Container(
            height: 32,
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
            child: Row(
              children: [
                // ✂️ NEW: Mute Region Tool
                Tooltip(
                  message: 'Cut / Mute Region (Tap to delete cut)',
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32),
                    icon: Icon(Icons.content_cut, size: 18, color: isRegionMuteMode ? Colors.redAccent : Colors.white38),
                    onPressed: () => setState(() {
                      isRegionMuteMode = !isRegionMuteMode;
                      if (isRegionMuteMode) currentDragMode = DragMode.off; // Disable pitch drag when cutting
                    }),
                  ),
                ),
                PopupMenuButton<DragMode>(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.pan_tool, 
                    size: 18, 
                    color: currentDragMode == DragMode.semitone 
                        ? Colors.orangeAccent 
                        : (currentDragMode == DragMode.microTuning 
                            ? Colors.yellowAccent 
                            : Colors.greenAccent),
                  ),
                  tooltip: 'Drag Pitch Mode',
                  onSelected: (val) => setState(() => currentDragMode = val),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: DragMode.off, child: Text('Normal (Off)')),
                    PopupMenuItem(value: DragMode.semitone, child: Text('Semitone Drag')),
                    PopupMenuItem(value: DragMode.microTuning, child: Text('Micro-Tuning Drag')),
                  ],
                ),
                Tooltip(
                  message: 'Preview pitch/DSP edits',
                  child: IconButton(
                    icon: Icon(
                      Icons.hearing, 
                      size: 20,
                      color: dirtyStems.contains(activeEditableStem) ? Colors.redAccent : Colors.white38,
                      shadows: dirtyStems.contains(activeEditableStem)
                          ? [const Shadow(color: Colors.red, blurRadius: 10.0)]
                          : null,
                    ),
                    // 🟢 FIX: Removed the strict originalAudioBytes requirement!
                    onPressed: (!isApiBusy && rawNotes.isNotEmpty && dirtyStems.contains(activeEditableStem))
                        ? () => renderStemEdits(activeEditableStem)
                        : null,
                  ),
                ),
                const VerticalDivider(color: Colors.white24, width: 16, indent: 6, endIndent: 6),
                
                // 1. X-Ray Toggle
                Tooltip(
                  message: 'Toggle X-Ray',
                  child: isXrayProcessing
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0), 
                          child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent))
                        )
                      : IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
                        icon: Icon(Icons.fingerprint, size: 20, color: xrayColor),
                        onPressed: (!isApiBusy && canRunXray) ? toggleXrayMode : null,
                      ),
                ),
                
                // 2. Dual X-Ray Toggle
                Tooltip(
                  message: 'Dual X-Ray Comparison',
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
                    icon: Stack(
                      children: [
                        Icon(Icons.fingerprint, size: 20, color: dualBaseColor),
                        Positioned(
                          left: 3, top: 3,
                          child: Icon(Icons.fingerprint, size: 20, color: dualTopColor),
                        ),
                      ],
                    ),
                    onPressed: isApiBusy ? null : () {
                      // Check the continuous traces instead of the old unshifted contours
                      if (dualContinuous1.isNotEmpty && dualContinuous2.isNotEmpty) {
                        setState(() => isDualContourOverlayActive = !isDualContourOverlayActive);
                      } else if (canRunDualXray) {
                        showDialog(
                          context: context,
                          builder: (context) => DualXRayComparatorDialog(
                            availableChannels: activeChannels,
                            onRunComparison: (source, target) => _runAnyToAnyForensicAlign(source, target),
                          ),
                        );
                      }
                    },
                  ),
                ),

                // 3. AI Detection Tool
                Tooltip(
                  message: 'Detect AI Synthetic Vocals (experimental)',
                  child: isAnalyzingAiVocal
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)),
                        )
                      : IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
                          icon: Icon(
                            Icons.psychology_outlined,
                            size: 20,
                            color: aiColor,
                          ),
                          onPressed: (!isApiBusy && canRunAi) ? _runAiVocalInspection : null,
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 4. Extract the Meter Bridge ListView
    Widget buildMeterBridge() {
      List<String> sortedStems = targetStemsSelection
          .where((s) => !['kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(s))
          .toList();
      sortedStems.sort((a, b) {
        if (a == 'instrumental') return 1;
        if (b == 'instrumental') return -1;
        int idxA = popStems.indexOf(a);
        int idxB = popStems.indexOf(b);
        if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
        if (idxA != -1) return -1;
        if (idxB != -1) return 1;
        return a.compareTo(b);
      });

      return ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: sortedStems.length,
        itemBuilder: (context, index) {
          String stemName = sortedStems[index];
          bool isSelected = activeEditableStem == stemName;
          bool isSuggested = suggestedStems.contains(stemName);
          bool isMuted = getChannelState(stemName).isMuted;
          bool isGenerated = generatedStems.contains(stemName);

          return GestureDetector(
            onTap: () {
              setState(() {
                activeEditableStem = stemName;
                isXrayMode = rawNotes.isNotEmpty && rawNotes.any((n) => n.containsKey('contour') && n['contour'] != null);
              });
              if (!isGenerated && originalAudioBytes != null && currentTaskId != null && !isLoading) {
                generateStemOnDemand(stemName);
              }
            },
            // Long press a stem strip to non-destructively hide/delete it!
            onLongPress: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.grey[900],
                  title: Text('Hide "${stemName.toUpperCase()}"?', style: const TextStyle(color: Colors.white)),
                  content: const Text('This will hide the track and mute it. You can restore it anytime from the main menu under "Restore Hidden Stems".', style: TextStyle(color: Colors.white54)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () {
                        Navigator.pop(ctx);
                        deleteChannel(stemName);
                        _showSaveConfirmation('Hidden ${stemName.toUpperCase()}. Moved to Trash Bin.');
                      },
                      child: const Text('Hide Track', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
            child: Container(
              width: 96,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blueGrey[800] : Colors.black45,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: isSelected ? Colors.blueAccent : Colors.transparent, width: 1.5),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!isGenerated) const Icon(Icons.hourglass_empty, size: 10, color: Colors.white38),
                            if (isSuggested && !isMuted) const Icon(Icons.star, size: 10, color: Colors.yellowAccent),
                            const SizedBox(width: 2),
                            Text(
                              stemName.toUpperCase(),
                              style: TextStyle(
                                color: isMuted ? Colors.white38 : (isSelected ? Colors.white : Colors.grey[400]),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontStyle: isMuted ? FontStyle.italic : FontStyle.normal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: SizedBox(
                            height: 6,
                            child: ValueListenableBuilder<double>(
                              valueListenable: channelLevels[stemName] ?? ValueNotifier(0.0),
                              builder: (context, level, child) {
                                return CustomPaint(
                                  size: const Size(double.infinity, 6),
                                  painter: _HorizontalVuMeterPainter(level: level),
                                );
                              },
                            ),
                          ),
                        ),
                        // Time-Shift Nudge Controls
                        if (showNudgeControls) // 🟢 Hide by default to save space & prevent accidental taps!
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 🟢 Replaced IconButton with a tight GestureDetector
                              GestureDetector(
                                onTap: () => setState(() {
                                  double current = stemTimeOffsets[stemName] ?? 0.0;
                                  stemTimeOffsets[stemName] = (current - 0.1).clamp(-10.0, 10.0);
                                  hasBeenSaved = false;
                                }),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                  child: Icon(Icons.remove, size: 14, color: Colors.white54),
                                ),
                              ),
                              Text(
                                '${(stemTimeOffsets[stemName] ?? 0.0).toStringAsFixed(1)}s',
                                style: const TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              GestureDetector(
                                onTap: () => setState(() {
                                  double current = stemTimeOffsets[stemName] ?? 0.0;
                                  stemTimeOffsets[stemName] = (current + 0.1).clamp(-10.0, 10.0);
                                  hasBeenSaved = false;
                                }),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                  child: Icon(Icons.add, size: 14, color: Colors.white54),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // MUTE BUTTON OVERLAY (Top Left)
                  Positioned(
                    top: 2, left: 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          getChannelState(stemName).isMuted = !getChannelState(stemName).isMuted;
                          hasBeenSaved = false;
                        });
                        refreshAllVolumes();
                      },
                      child: Icon(
                        getChannelState(stemName).isMuted ? Icons.volume_off : Icons.volume_up,
                        size: 13,
                        color: getChannelState(stemName).isMuted ? Colors.redAccent : Colors.white38,
                      )
                    )
                  ),
                  // SOLO BUTTON OVERLAY (Top Right)
                  Positioned(
                    top: 2, right: 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (soloedChannels.contains(stemName)) soloedChannels.remove(stemName);
                          else soloedChannels.add(stemName);
                          hasBeenSaved = false;
                        });
                        refreshAllVolumes();
                      },
                      child: Icon(
                        soloedChannels.contains(stemName) ? Icons.headphones : Icons.headphones_outlined,
                        size: 13,
                        color: soloedChannels.contains(stemName) ? Colors.yellowAccent : Colors.white38,
                      )
                    )
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            toolbarHeight: isLandscape ? 40 : 56, // Shrink AppBar slightly in landscape
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                /*const Text('voXRay ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
                  child: const Text('PRO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white)),
                ),*/
                // ✅ TRANSPARENT LOGO REPLACEMENT
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: GestureDetector(
                    onLongPress: () {
                      // Secret God Mode Trigger
                      final email = BackendService.supabase.auth.currentUser?.email;
                      if (email == 'donkelleymusic@gmail.com') {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const GodModeDashboard()));
                      }
                    },
                    child: Image.asset(
                      'assets/images/voXRay_logo_transparent_crop.png', 
                      height: isLandscape ? 22 : 30,    
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (!isLandscape) // Hide subtitle in landscape to save horizontal space
                  const Text('Forensic Daw', style: TextStyle(fontWeight: FontWeight.w300, fontSize: 14, color: Colors.white70)),
                IconButton(
                  icon: Icon(Icons.memory, size: 20, color: Colors.greenAccent[400]), // Glowing money green DSP chip
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletScreen())),
                ),
              ],
            ),
            actions: [
              // 5. In Landscape, inject the Status Text right into the AppBar
              if (isLandscape)
                Container(
                  width: MediaQuery.of(context).size.width * 0.35, // Cap width so it doesn't overflow
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 8.0),
                  child: buildStatusContent(true),
                ),
              if (!isLiveModeActive)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Main Menu',
                  onSelected: _handleMenuSelection,
                  itemBuilder: (context) => _buildMainMenu(),
                ),
            ],
          ),
          body: SafeArea(
            child: isLiveModeActive
                ? LivePedagogyView(onExit: () => setState(() => isLiveModeActive = false))
                : Column(children: [
                    
                    // 6. In Portrait, render the classic Status Bar
                    if (!isLandscape)
                      Container(
                        width: double.infinity,
                        color: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: buildStatusContent(false),
                      ),
    
                    // 7. Dynamic Tools & Meter Bridge Row
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        border: const Border(bottom: BorderSide(color: Colors.black, width: 2)),
                      ),
                      child: isLandscape
                          // LANDSCAPE: Tools and Meters live on the SAME horizontal strip
                          ? SizedBox(
                              height: 72,
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6.0, right: 8.0),
                                    child: buildToolGroup(),
                                  ),
                                  Container(width: 2, color: Colors.black),
                                  Expanded(child: buildMeterBridge()),
                                ],
                              ),
                            )
                          // PORTRAIT: Stack them cleanly with full unclipped height
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  height: 36,
                                  width: double.infinity,
                                  color: Colors.black26,
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                  alignment: Alignment.centerLeft,
                                  child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: buildToolGroup()),
                                ),
                                // Restored full container height for portrait mode so text & meters never clip
                                SizedBox(
                                  height: 72,
                                  child: buildMeterBridge(),
                                ),
                              ],
                            ),
                    ),
    
                    // ── Horizontal zoom ──────────────────────────────────────────
                    SizedBox(
                      height: 24, // Expanded slightly to fit the icon comfortably
                      child: Row(
                        children: [
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(value: zoomX, min: 20.0, max: 500.0, onChanged: setZoomX),
                            ),
                          ),
                          Tooltip(
                            message: 'Fit to Screen',
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 40),
                              icon: const Icon(Icons.fit_screen, size: 16, color: Colors.white54),
                              onPressed: _fitToScreen,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    // THE MACRO MINIMAP ─────────────────────────────────────
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.white24, width: 1)),
                      ),
                      child: MacroMinimapWidget(dawState: this),
                    ),
                    // ── Workspace: Timeline + Sidebar ─────────────────────────────────────────────
                    Expanded(
                      child: Column(children: [
                        Row(children: [
                          Container(
                            width: 46,
                            height: 45,
                            color: Colors.grey[900],
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow, 
                                // 🟢 Dim the icon if the API/Engine is busy
                                color: isApiBusy ? Colors.white24 : Colors.tealAccent, 
                                size: 28
                              ),
                              // 🟢 Disable the tap entirely if busy
                              onPressed: isApiBusy ? null : _toggleMasterTransport,
                            ),
                          ),
                          // 🟢 1. PERFECT RULER ALIGNMENT (46 + 16 = 62px)
                          const SizedBox(width: 16),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: rulerScrollController,
                              scrollDirection: Axis.horizontal,
                              child: TimelineRulerWidget(dawState: this),
                            ),
                          ),
                          SizedBox(width: isLandscape ? 100 : 50),
                        ]),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 🟢 2. RESTORE CANVAS SLIDER COMPACT WIDTH (8 + 24 = 32px)
                              // (32px + 30px Piano Keys = 62px total, matching the Ruler perfectly!)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: SizedBox(
                                  width: 24,
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 2,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        overlayShape: SliderComponentShape.noOverlay,
                                      ),
                                      child: Slider(value: zoomY, min: 8.0, max: 60.0, onChanged: setZoomY),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: !isCurrentStemGenerated && originalAudioBytes != null && currentTaskId != null
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.music_note, size: 48, color: Colors.white24),
                                            if (!isLoading && activeEditableStem.isNotEmpty) ...[
                                              const SizedBox(height: 24),
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.teal,
                                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                                ),
                                                icon: const Icon(Icons.build),
                                                label: Text('Generate & Analyze ${activeEditableStem.toUpperCase()}'),
                                                onPressed: isApiBusy ? null : () => generateStemOnDemand(activeEditableStem),
                                              ),
                                            ],
                                          ],
                                        ),
                                      )
                                    : Stack(
                                        children: [
                                          Positioned.fill(
                                            child: TimelineCanvasWidget(
                                              dawState: this,
                                              horizontalScrollController: horizontalScrollController,
                                              verticalScrollController: verticalScrollController,
                                            ),
                                          ),
                                          // ── EXISTING DUAL X-RAY LEGEND OVERLAY ──
                                          if (isDualContourOverlayActive)
                                            Positioned(
                                              bottom: 30, // Moved to the bottom
                                              left: 20,   // Moved to the left
                                              child: IgnorePointer( // <--- Allows clicks/drags to pass through to the canvas underneath!
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Text(
                                                      'DUAL X-RAY KEY', 
                                                      style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)])
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Row(children: [
                                                      Container(width: 10, height: 10, color: const Color(0xFF00E5FF)),
                                                      const SizedBox(width: 6),
                                                      Text(dualLabel1, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                                                    ]),
                                                    const SizedBox(height: 4),
                                                    Row(children: [
                                                      Container(width: 10, height: 10, color: const Color(0xFFFF007F)),
                                                      const SizedBox(width: 6),
                                                      Text(dualLabel2, style: const TextStyle(color: Color(0xFFFF007F), fontSize: 11, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                                                    ]),
                                                    const SizedBox(height: 4),
                                                    Row(children: [
                                                      Container(width: 10, height: 14, color: Colors.greenAccent.withOpacity(0.8)),
                                                      const SizedBox(width: 6),
                                                      const Text('Identical Match Region', style: TextStyle(color: Colors.greenAccent, fontSize: 11, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                                                    ]),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                              ),
                              // Right: The Fully Restored Marker & Tool Sidebar
                              Container(
                                width: isLandscape ? 100 : 50,
                                decoration: BoxDecoration(
                                  color: Colors.grey[900],
                                  border: const Border(left: BorderSide(color: Colors.black, width: 2)),
                                ),
                                child: SingleChildScrollView(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 4.0, // Horizontal space between icons in landscape
                                      runSpacing: 8.0, // Vertical space between rows
                                      children: [
                                        
                                        // 1. Add Marker
                                        Tooltip(
                                          message: 'Add Marker',
                                          child: GestureDetector(
                                            onTapDown: (_) => addMarkerAtCurrentPlayhead(), // Instantly fires on touch!
                                            child: Container(
                                              constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                                              color: Colors.transparent, // Required to capture taps in an empty container
                                              child: const Icon(Icons.add_location_alt, size: 20, color: Colors.amberAccent),
                                            ),
                                          ),
                                        ),
                                
                                        // 2. Go To Marker (Dropdown)
                                        if (markers.isNotEmpty)
                                          PopupMenuButton<double>(
                                            icon: const Icon(Icons.location_on, color: Colors.amberAccent, size: 20),
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Go to Marker',
                                            itemBuilder: (context) => markers.map((marker) {
                                              int totalSeconds = (marker['time'] as double).round();
                                              String timestamp = '${(totalSeconds ~/ 60).toString().padLeft(2, '0')}:${(totalSeconds % 60).toString().padLeft(2, '0')}';
                                              return PopupMenuItem<double>(
                                                value: marker['time'],
                                                child: Row(children: [
                                                  const Icon(Icons.location_on, color: Colors.amberAccent, size: 16),
                                                  const SizedBox(width: 4),
                                                  Text('${marker['label']}  '),
                                                  Text(timestamp, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                                ]),
                                              );
                                            }).toList(),
                                            onSelected: (time) => jumpToTimelinePosition(time),
                                          ),
                                
                                        // 3. Set Loop Region Dropdown
                                        if (markers.length >= 2)
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.settings_overscan, size: 18, color: Colors.blueAccent),
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Set Loop Region',
                                            itemBuilder: (context) {
                                              List<PopupMenuItem<String>> items = [];
                                              for (int i = 0; i < markers.length; i++) {
                                                for (int j = i + 1; j < markers.length; j++) {
                                                  items.add(PopupMenuItem(
                                                    value: '${markers[i]['time']}_${markers[j]['time']}',
                                                    child: Text('${markers[i]['label']} → ${markers[j]['label']}', style: const TextStyle(fontSize: 12)),
                                                  ));
                                                }
                                              }
                                              return items;
                                            },
                                            onSelected: (val) {
                                              final parts = val.split('_');
                                              setLoopFromMarkers(double.parse(parts[0]), double.parse(parts[1]));
                                            },
                                          ),
                                
                                        // 4. Loop On / Off Toggle
                                        Tooltip(
                                          message: 'Toggle Loop Playback',
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                                            icon: Icon(Icons.loop, size: 20, color: isLoopModeActive ? Colors.tealAccent : Colors.white38),
                                            onPressed: () {
                                              setState(() {
                                                isLoopModeActive = !isLoopModeActive;
                                              });
                                            },
                                          ),
                                        ),
                                        // 🟢 3. MOVED GLOBAL TRIM BUTTONS HERE
                                        Tooltip(
                                          message: 'Set Mix Start (Trim Left)',
                                          child: IconButton(
                                            padding: EdgeInsets.zero, constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                                            icon: const Icon(Icons.arrow_right_alt, color: Colors.orangeAccent, size: 20),
                                            onPressed: () => setState(() => projectTrimStart = currentPosition),
                                          ),
                                        ),
                                        Tooltip(
                                          message: 'Set Mix End (Trim Right)',
                                          child: IconButton(
                                            padding: EdgeInsets.zero, constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                                            icon: const Icon(Icons.keyboard_backspace, color: Colors.orangeAccent, size: 20),
                                            onPressed: () => setState(() => projectTrimEnd = currentPosition),
                                          ),
                                        ),
                                        Tooltip(
                                          message: 'Clear Trims',
                                          child: IconButton(
                                            padding: EdgeInsets.zero, constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                                            icon: const Icon(Icons.clear_all, color: Colors.white38, size: 18),
                                            onPressed: () => setState(() { projectTrimStart = 0.0; projectTrimEnd = songDuration; }),
                                          ),
                                        ),
                                
                                        // Divider for Undo/Redo grouping
                                        Container(
                                          width: isLandscape ? 100 : 50,
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: Divider(color: Colors.grey[800], thickness: 1.5),
                                        ),
                                
                                        // 6. Undo
                                        Tooltip(
                                          message: 'Undo',
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                                            icon: const Icon(Icons.undo, size: 20),
                                            color: undoStack.isNotEmpty ? Colors.white : Colors.white24,
                                            onPressed: (!isApiBusy && undoStack.isNotEmpty) ? _undo : null,
                                          ),
                                        ),
                                        
                                        // 7. Redo
                                        Tooltip(
                                          message: 'Redo',
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                                            icon: const Icon(Icons.redo, size: 20),
                                            color: redoStack.isNotEmpty ? Colors.white : Colors.white24,
                                            onPressed: (!isApiBusy && redoStack.isNotEmpty) ? _redo : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ]),
                    ),
                    // 🟢 THE SMART DOCK: Shows up at the bottom only on wide screens!
                    if (MediaQuery.of(context).size.width > 900 && isDockedMixerVisible)
                      _buildDockedMixer(),
                  ]), // <--- Closes the main Workspace Column
            ), // <--- Closes the SafeArea

        ), // <--- THIS WAS MISSING! This completely closes the Scaffold.

        // 2. THE VIDEO OVERLAY (Now safely a sibling to the Scaffold, inside the Stack)
        if (_introController != null && _introController!.value.isInitialized)
          IgnorePointer(
            ignoring: !_showIntroAnimation, 
            child: AnimatedOpacity(
              opacity: _showIntroAnimation ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 800), 
              child: Container(
                color: Colors.black, 
                width: double.infinity,
                height: double.infinity,
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.contain, 
                  child: SizedBox(
                    width: _introController!.value.size.width,
                    height: _introController!.value.size.height,
                    child: VideoPlayer(_introController!),
                  ),
                ),
              ),
            ),
          ),

      ], // <--- Closes the Stack's children array
    ); // <--- Closes the Stack itself
  } // <--- Closes the build() method
} // <--- Closes the VoxrayDAWState class
