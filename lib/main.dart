// ==============================================================================
// COPYRIGHT AND OWNERSHIP DECLARATION
// ==============================================================================
// Copyright (c) 2026 Donald Bayard Kelley. All Rights Reserved.
//
// voXRAY Enterprise DSP & Roformer Engine
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
//   VoxrayDAWState  — widget lifecycle, UI state fields, build(), all dialogs
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

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://dazqevapqvdpbdoypwke.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
        '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhenFldmFwcXZkcGJkb3lwd2tlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODU1MTcsImV4cCI6MjA5ODk2MTUxN30'
        '.hJvau902z0lAXRnwHPLa30HoLJzxJg4zQDzSXuh_Tjs',
  );

  // 1. Initialize your audio engine BEFORE the app UI runs!
  await SoLoud.instance.init(
    bufferSize: 2048, // or 1024 or whatever, to stop audio glitching without bt earbuds etc.
  );

  // 2. Wrap your actual app logic directly inside Sentry's appRunner
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://d6a836c92a35e39f8a73a143d2bca99d@o4511748451729408.ingest.us.sentry.io/4511748461363200';
      options.tracesSampleRate = 1.0; 
    },
    appRunner: () => runApp(
      MaterialApp(
        home: const AppGatekeeper(),
        theme: ThemeData(brightness: Brightness.dark),
      )
    ), 
  );
  
  // Notice: The duplicate runApp() that used to be down here is now completely removed!
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

// ─────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// APP GATEKEEPER (Checks for saved login session on startup)
// ─────────────────────────────────────────────────────────────────────────────
class AppGatekeeper extends StatefulWidget {
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
        
        // Fetch subscription status directly via the BackendService
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
    // 1. App is loading session or verifying subscription status
    if (_isLoggedIn == null || (_isLoggedIn! && _isSubscribed == null)) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Not Logged In
    if (!_isLoggedIn!) {
      return const AuthScreen();
    }

    // 3. Logged In, but paywall active (No subscription found)
    if (!_isSubscribed!) {
      return const AccountSettingsScreen(isForcedPaywall: true);
    }

    // 4. Fully Logged In & Paid -> Boot up the DAW!
    return const VoxrayDAW();
  }
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

  SynthSettings synthSettings = const SynthSettings();
  bool isSynthRendering = false;
  String synthMessage   = '';
  String processingMode = 'advanced';

  Map<String, ChannelState> mixerState = {
    'master': ChannelState(), 'synth': ChannelState(),
    'vocals': ChannelState(), 'instrumental': ChannelState(),
  };

  final Map<String, ValueNotifier<double>> channelLevels = {};

  // ── Scroll controllers ────────────────────────────────────────────────────
  final ScrollController horizontalScrollController = ScrollController();
  final ScrollController verticalScrollController   = ScrollController();
  final ScrollController rulerScrollController      = ScrollController();

  // ── Note / x-ray data ────────────────────────────────────────────────────
  Map<String, List<dynamic>> allStemsNotes        = {};
  Map<String, List<dynamic>> allStemsContinuousXray = {};
  String activeEditableStem = '';

  // get control over 60fps updates while doing file uploading:
  bool isUploading = false;
  
  // ── Global Log Multiplexer ──────────────────────────────────────────────
  String getPlatformString() {
    if (kIsWeb) return 'flutter_web';
    return 'flutter_${Platform.operatingSystem}';
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

  // ── File info ─────────────────────────────────────────────────────────────
  String originalFileName = 'Unknown File';
  String originalFilePath = '';

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
  DragMode currentDragMode = DragMode.off;

  String projectName = 'Voxray_Session';
  Uint8List? originalAudioBytes;

  bool isLiveModeActive  = false;
  bool isLoopModeActive  = false;
  double loopStartBoundary = 0.0;
  double loopEndBoundary = 30.0;

  bool isUserScrolling = false;
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
class VoxrayDAWState extends VoxrayDAWStateBase with DawAudioController, DawApiService {

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

    restoreAutoSaveOnStartup();

    positionTimer =
        Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!isPlaying || !mounted) return;

      double currentT = 0.0;
      bool anyValid   = false;

      if (masterHandle != null &&
          SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) {
        currentT =
            SoLoud.instance.getPosition(masterHandle!).inMilliseconds / 1000.0;
        anyValid = true;
      } else if (stemHandles.isNotEmpty) {
        for (var handle in stemHandles.values) {
          if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
            currentT =
                SoLoud.instance.getPosition(handle).inMilliseconds / 1000.0;
            anyValid = true;
            break;
          }
        }
      } else if (synthHandle != null &&
          SoLoud.instance.getIsValidVoiceHandle(synthHandle!)) {
        currentT =
            SoLoud.instance.getPosition(synthHandle!).inMilliseconds / 1000.0;
        anyValid = true;
      }

      if (!anyValid) {
        pauseAllPlayers();
        jumpToTimelinePosition(0.0);
        return;
      }

      if (isLoopModeActive &&
          loopEndBoundary > loopStartBoundary &&
          loopEndBoundary > 0.0 &&
          currentT >= loopEndBoundary) {
        seekAllPlayers(loopStartBoundary);
        currentT = loopStartBoundary;
      }

      //setState(() => currentPosition = currentT); // old version, did 30fps which was gpu/cpu heavy.  now we use gaming hw timer.
      currentPosition = currentT;

      if (!isUserScrolling) {
        // Calculate dynamic offset (fallback to 0 if clients aren't attached yet)
        //double anchorOffset = horizontalScrollController.hasClients 
        //    ? horizontalScrollController.position.viewportDimension * 0.35 
        //    : 0.0;
            
        //double targetX = (currentT * zoomX) - anchorOffset;
        //if (targetX < 0) targetX = 0;
        
        //if (horizontalScrollController.hasClients &&
        //    horizontalScrollController.position.maxScrollExtent > 0) {
        //  horizontalScrollController.jumpTo(targetX.clamp(
        //      0.0, horizontalScrollController.position.maxScrollExtent));
        //}


        if (verticalScrollController.hasClients && rawNotes.isNotEmpty) {
          var activeNotes = rawNotes.where((n) {
            if (n['isDeleted'] == true) return false;
            double start = (n['start_time'] ?? 0).toDouble();
            double end   = (n['end_time']   ?? 0).toDouble();
            return start <= currentT && end >= currentT;
          }).toList();

          if (activeNotes.isNotEmpty) {
            List<int> midiValues = activeNotes
                .map<int>((n) =>
                    ((n['display_midi'] ?? n['actual_midi'] ?? 60)).round())
                .toList()
              ..sort();
            int medianMidi = midiValues[midiValues.length ~/ 2];

            double viewportHeight =
                verticalScrollController.position.viewportDimension;
            double noteY  = ((maxMidi - medianMidi) * zoomY) + (zoomY / 2);
            double currentY = verticalScrollController.position.pixels;
            double targetY  =
                (noteY - (viewportHeight / 2)).clamp(0.0,
                    verticalScrollController.position.maxScrollExtent);

            if ((targetY - currentY).abs() > 1.0) {
              verticalScrollController
                  .jumpTo(currentY + (targetY - currentY) * 0.15);
            }
          }
        }
      }
    });
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
      logToSupabase('App resumed. Polling timers will automatically catch up.');
    } else if (state == AppLifecycleState.paused) {
      logToSupabase('App backgrounded. OS suspended network sockets.');
    }
  }

  void notifyChanged() => setState(() {});

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
    if (isPlaying) pauseAllPlayers(); else playAllPlayers();
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
    });

    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/voxray_autosave.json');
    if (await file.exists()) await file.delete();

    _showSaveConfirmation('New empty project loaded.');
  }

  // =========================================================================
  // MARKERS
  // =========================================================================

  void addMarkerAtCurrentPlayhead() {
    double anchorOffset = horizontalScrollController.hasClients 
        ? horizontalScrollController.position.viewportDimension * 0.35 
        : 0.0;

    double visualPlayheadTime = (horizontalScrollController.hasClients
            ? (horizontalScrollController.position.pixels + anchorOffset) / zoomX
            : currentPosition)
        .clamp(0.0, songDuration);

    bool tooClose =
        markers.any((m) => ((m['time'] as double) - visualPlayheadTime).abs() < 0.5);
    if (tooClose) return;

    setState(() {
      markers.add({
        'id': 'mk_${DateTime.now().millisecondsSinceEpoch}',
        'time': visualPlayheadTime,
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
                  _pluginSlot(key,state.plugin1, highlight, (val) {
                    if (state.plugin1 != val) {
                      setMixerState(() => state.plugin1 = val!);
                      this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                      if (!isMaster) applyStemPlugins(key); else applyMasterPlugins();
                    }
                  }),
                  _pluginSlot(key,state.plugin2, highlight, (val) {
                    if (state.plugin2 != val) {
                      setMixerState(() => state.plugin2 = val!);
                      this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                      if (!isMaster) applyStemPlugins(key); else applyMasterPlugins();
                    }
                  }),
                  _pluginSlot(key,state.plugin3, highlight, (val) {
                    if (state.plugin3 != val) {
                      setMixerState(() => state.plugin3 = val!);
                      this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                      if (!isMaster) applyStemPlugins(key); else applyMasterPlugins();
                    }
                  }),
                  _pluginSlot(key,state.plugin4, highlight, (val) {
                    if (state.plugin4 != val) {
                      setMixerState(() => state.plugin4 = val!);
                      this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                      if (!isMaster) applyStemPlugins(key); else applyMasterPlugins();
                    }
                  }),
                  const SizedBox(height: 4),

                  if (!isMaster)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                          state.isMuted ? Icons.volume_off : Icons.volume_up,
                          color: !state.isMuted ? highlight : Colors.white38,
                          size: 18),
                      onPressed: () {
                        setMixerState(() => state.isMuted = !state.isMuted);
                        this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                        double targetVol = state.isMuted ? 0.0 : state.volume;
                        if (key == 'original') {
                          if (masterHandle != null) SoLoud.instance.setVolume(masterHandle!, targetVol);
                        } else if (key == 'synth') {
                          if (synthHandle != null) SoLoud.instance.setVolume(synthHandle!, targetVol);
                        } else if (stemHandles.containsKey(key)) {
                          SoLoud.instance.setVolume(stemHandles[key]!, targetVol);
                        }
                      },
                    ),

                  // Volume fader
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: () {
                        setMixerState(() => state.volume = 1.0);
                        this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                        if (state.isMuted) return;
                        if (key == 'master') SoLoud.instance.setGlobalVolume(1.0);
                        else if (key == 'original') { if (masterHandle != null) SoLoud.instance.setVolume(masterHandle!, 1.0); }
                        else if (key == 'synth') { if (synthHandle != null) SoLoud.instance.setVolume(synthHandle!, 1.0); }
                        else if (stemHandles.containsKey(key)) { if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[key]!)) SoLoud.instance.setVolume(stemHandles[key]!, 1.0); }
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
                              setMixerState(() => state.volume = v);
                              this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                              if (state.isMuted) return;
                              if (key == 'master') SoLoud.instance.setGlobalVolume(v);
                              else if (key == 'original') { if (masterHandle != null) SoLoud.instance.setVolume(masterHandle!, v); }
                              else if (key == 'synth') { if (synthHandle != null) SoLoud.instance.setVolume(synthHandle!, v); }
                              else if (stemHandles.containsKey(key)) { if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[key]!)) SoLoud.instance.setVolume(stemHandles[key]!, v); }
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
                        this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
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
                            this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
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
                          .where((stem) => stem != 'instrumental')
                          .map((stem) => buildChannelStrip(stem.toUpperCase(), stem, Colors.tealAccent)),
                          
                      if (targetStemsSelection.contains('instrumental'))
                        buildChannelStrip('INSTRUMENTAL', 'instrumental', Colors.deepOrangeAccent),
                        
                      const SizedBox(width: 12),
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
  Widget _pluginSlot(String stemKey, String pluginName, Color highlight, ValueChanged<String?> onChanged) {
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
                  items: ['None', 'Compressor', 'EQ', 'Reverb', 'De-esser']
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
              onTap: () => _showPluginSettingsDialog(stemKey, pluginName, highlight),
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
  void _showPluginSettingsDialog(String stemKey, String pluginName, Color highlight) {
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
                  this.setState(() { dirtyStems.add(stemKey); hasBeenSaved = false; });
                  
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
                  this.setState(() { dirtyStems.add(stemKey); hasBeenSaved = false; });
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
                  this.setState(() { dirtyStems.add(stemKey); hasBeenSaved = false; });
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
                  this.setState(() { dirtyStems.add(stemKey); hasBeenSaved = false; });
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
                  this.setState(() { dirtyStems.add(stemKey); hasBeenSaved = false; });
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

  void _showPitchPrintOptions() {
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
                  downloadPitchPrint(
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

  void _showDossier() {
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
      const PopupMenuItem(
          value: 'new_project',
          child: ListTile(
              leading: Icon(Icons.add_box, color: Colors.amberAccent),
              title: Text('New Project (Clear Workspace)'))),
      const PopupMenuDivider(),
      const PopupMenuItem(
          value: 'upload',
          child: ListTile(
              leading: Icon(Icons.cloud_upload, color: Colors.tealAccent),
              title: Text('Load New Audio'))),
      const PopupMenuItem(
          value: 'load',
          child: ListTile(
              leading: Icon(Icons.folder_open), title: Text('Load Project'))),
      PopupMenuItem(
          value: 'save_as',
          enabled: canSaveAs,
          child: ListTile(
              leading: Icon(Icons.save_as, color: canSaveAs ? Colors.white : Colors.white38),
              title: Text('Save Project As...', style: TextStyle(color: canSaveAs ? Colors.white : Colors.white38)))),
      
      const PopupMenuDivider(),
      
      const PopupMenuItem(
          value: 'synth_settings',
          child: ListTile(
              leading: Icon(Icons.piano, color: Colors.purpleAccent),
              title: Text('Synth Audio Settings'))),
      PopupMenuItem(
          value: 'scrub_toggle',
          child: ListTile(
              leading: Icon(Icons.touch_app, color: isScrubMode ? Colors.amberAccent : Colors.white54),
              title: Text(isScrubMode ? 'Play from Selected Note' : 'Play Continuous (Scrub off)'))),
      
      const PopupMenuDivider(),
      
      const PopupMenuItem(
          value: 'show_dossier',
          child: ListTile(
              leading: Icon(Icons.assessment, color: Colors.greenAccent),
              title: Text('View GUI Dossier'))),
      const PopupMenuItem(
          value: 'downloads',
          child: ListTile(
              leading: Icon(Icons.download, color: Colors.blueAccent),
              title: Text('Advanced Downloads'))),
      const PopupMenuItem(
          value: 'import_stem',
          child: ListTile(
              leading: Icon(Icons.file_open, color: Colors.tealAccent),
              title: Text('Import Individual Track'))),
      const PopupMenuItem(
          value: 'export_stems',
          child: ListTile(
              leading: Icon(Icons.unarchive, color: Colors.amberAccent),
              title: Text('Export Stems Archive'))),
      
      const PopupMenuDivider(),
      
      const PopupMenuItem(
          value: 'account_settings',
          child: ListTile(
              leading: Icon(Icons.person, color: Colors.blueAccent),
              title: Text('Account & Billing'))),
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
          child: ListTile(
              leading: Icon(Icons.mic_external_on, color: isLiveModeActive ? Colors.redAccent : Colors.white),
              title: Text(isLiveModeActive ? 'Disable Live Pedagogy' : 'Enable Live Pedagogy',
                  style: TextStyle(color: isLiveModeActive ? Colors.redAccent : Colors.white)))),
      
      const PopupMenuDivider(),
      
      // Debug Section
      const PopupMenuItem(enabled: false, child: Text('    DEBUG USE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold))),
      const PopupMenuItem(
          value: 'reprocess',
          child: ListTile(
              leading: Icon(Icons.sync_problem, color: Colors.orangeAccent),
              title: Text('Reprocess X-Ray', style: TextStyle(color: Colors.orangeAccent)))),
      PopupMenuItem(
          value: 'test_mode',
          child: ListTile(
              leading: Icon(Icons.bug_report, color: isTestModeActive ? Colors.redAccent : Colors.white38),
              title: Text(isTestModeActive ? 'Disable MOCK API Mode' : 'Enable MOCK API Mode',
                  style: TextStyle(color: isTestModeActive ? Colors.redAccent : Colors.white)))),
      
      // HIDDEN ITEMS
      // const PopupMenuItem(value: 'stem_tree', child: ListTile(leading: Icon(Icons.account_tree), title: Text('Stem Select Tree'))),
      // PopupMenuItem(value: 'save', enabled: canSave, child: ListTile(leading: Icon(Icons.save), title: Text('Save Project (Overwrite)'))),
      // PopupMenuItem(value: 'processing_mode', child: ListTile(title: Text('Mode: ADVANCED'))),
    ];
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'new_project':     _newProject(); break;
      case 'upload':          loadFileAndAnalyze(context); break;
      case 'import_stem':     importIndividualStem(context); break;
      case 'stem_tree':       _showStemSelectorTreeDialog(); break;
      case 'load':            loadVoxrayProject(context); break;
      case 'save':            saveVoxrayProject(); break;
      case 'save_as':         saveVoxrayProjectAs(); break;
      case 'export_stems':    exportStemsAsZip(); break;
      case 'scrub_toggle':    setState(() => isScrubMode = !isScrubMode); break;
      case 'processing_mode':
        setState(() => processingMode = processingMode == 'classic' ? 'advanced' : 'classic');
        break;
      case 'synth_settings':  _showSynthSettingsDialog(); break;
      case 'show_dossier':    _showDossier(); break;
      case 'downloads':       _showAdvancedDownloadsDialog(); break;
      case 'live_mode':       setState(() => isLiveModeActive = !isLiveModeActive); break;
      case 'reprocess':       forceReprocessXray(context); break;
      case 'test_mode':       setState(() => isTestModeActive = !isTestModeActive); break;
      case 'account_settings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => AccountSettingsScreen()));
        break;
      case 'about_info':
        Navigator.push(context, MaterialPageRoute(builder: (_) => AboutInfoScreen(contentKey: 'about_me', pageTitle: 'About voXRAY')));
        break;
      case 'feedback':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackScreen()));
        //Navigator.push(context, MaterialPageRoute(builder: (_) => FeedbackScreen(contentKey: 'bugs_feedback', pageTitle: 'Submit Bugs / Feedback')));
        break;
    }
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
            const SizedBox(height: 2),
            Row(children: [
              Expanded(
                  child: LinearProgressIndicator(
                      value: processingProgress, color: Colors.tealAccent, backgroundColor: Colors.grey[800], minHeight: compact ? 2 : 4)),
              const SizedBox(width: 4),
              Text(processingMessage, style: TextStyle(fontSize: compact ? 9 : 10, color: Colors.tealAccent)),
            ]),
          ] else if (isPreviewing || isExporting || isSynthRendering) ...[
            const SizedBox(height: 2),
            Row(children: [
              Expanded(
                  child: LinearProgressIndicator(
                      value: processingProgress, color: Colors.amberAccent, backgroundColor: Colors.grey[800], minHeight: compact ? 2 : 4)),
              const SizedBox(width: 4),
              Text(exportMessage.isNotEmpty ? exportMessage : synthMessage,
                  style: TextStyle(fontSize: compact ? 9 : 10, color: Colors.amberAccent)),
            ]),
          ],
        ],
      );
    }

    // 3. Extract the Tool Group (Mixer + Pan + Preview)
    Widget buildToolGroup() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              icon: const Icon(Icons.tune, color: Colors.orangeAccent, size: 22),
              tooltip: 'Studio Mixer',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _showStudioMixer),
          const SizedBox(width: 4),
          Container(
            height: 32,
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
            child: Row(
              children: [
                PopupMenuButton<DragMode>(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.pan_tool, size: 18, color: currentDragMode != DragMode.off ? Colors.amberAccent : Colors.white38),
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
                    icon: const Icon(Icons.preview, color: Colors.deepPurpleAccent, size: 20),
                    onPressed: (rawNotes.isNotEmpty && originalAudioBytes != null && !isPreviewing && !isExporting && dirtyStems.contains(activeEditableStem))
                        ? () => renderStemEdits(activeEditableStem)
                        : null,
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
      List<String> sortedStems = targetStemsSelection.toList();
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
            child: Container(
              width: 85,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blueGrey[800] : Colors.black45,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: isSelected ? Colors.blueAccent : Colors.transparent, width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isMuted) const Icon(Icons.volume_off, size: 10, color: Colors.white38),
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
                ],
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isLandscape ? 40 : 56, // Shrink AppBar slightly in landscape
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('voXRAY ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
              child: const Text('PRO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white)),
            ),
            const SizedBox(width: 4),
            if (!isLandscape) // Hide subtitle in landscape to save horizontal space
              const Text('Forensic Daw', style: TextStyle(fontWeight: FontWeight.w300, fontSize: 14, color: Colors.white70)),
            IconButton(
              icon: const Icon(Icons.account_balance_wallet, size: 20),
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
                          height: 52,
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
                              height: 52,
                              child: buildMeterBridge(),
                            ),
                          ],
                        ),
                ),

                // ── Horizontal zoom ──────────────────────────────────────────
                SizedBox(
                  height: 16,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(value: zoomX, min: 20.0, max: 500.0, onChanged: setZoomX),
                  ),
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
                          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.tealAccent, size: 28),
                          onPressed: _toggleMasterTransport,
                        ),
                      ),
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
                                        const SizedBox(height: 16),
                                        Text(
                                            'The ${activeEditableStem.isNotEmpty ? activeEditableStem.toUpperCase() : 'selected'} stem has not been extracted yet.',
                                            style: const TextStyle(color: Colors.white54)),
                                        const SizedBox(height: 24),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.teal,
                                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                                          icon: const Icon(Icons.build),
                                          label: Text('Generate & Analyze ${activeEditableStem.isNotEmpty ? activeEditableStem.toUpperCase() : ''}'),
                                          onPressed: isLoading || activeEditableStem.isEmpty ? null : () => generateStemOnDemand(activeEditableStem),
                                        ),
                                      ],
                                    ),
                                  )
                                : TimelineCanvasWidget(
                                    dawState: this,
                                    horizontalScrollController: horizontalScrollController,
                                    verticalScrollController: verticalScrollController,
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
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  runSpacing: 2.0,
                                  children: [
                                    // 1. Add Marker
                                    Tooltip(
                                      message: 'Add Marker',
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.add_location_alt, size: 20, color: Colors.white70),
                                        onPressed: () { /* Add Marker Logic */ },
                                      ),
                                    ),

                                    // 2. Go To Marker (Dropdown or Action)
                                    Tooltip(
                                      message: 'Go to Marker',
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.location_searching, size: 20, color: Colors.white70),
                                        onPressed: markers.isNotEmpty ? () {
                                          // Trigger your marker jump menu/logic here
                                        } : null,
                                      ),
                                    ),

                                    // 3. Loop Marker Chooser
                                    Tooltip(
                                      message: 'Loop Region / Markers',
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.repeat, size: 20, color: Colors.white70),
                                        onPressed: () { /* Open loop marker selector */ },
                                      ),
                                    ),

                                    // 4. Loop On / Off Toggle
                                    Tooltip(
                                      message: 'Toggle Loop Playback',
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        // Highlight green/teal when loop is active
                                        icon: Icon(Icons.loop, size: 20, color: isLoopActive ? Colors.tealAccent : Colors.white38),
                                        onPressed: () {
                                          setState(() {
                                            isLoopActive = !isLoopActive;
                                          });
                                          // Call your loop toggle handler here
                                        },
                                      ),
                                    ),

                                    // 5. X-Ray Toggle
                                    Tooltip(
                                      message: 'Toggle X-Ray',
                                      child: isXrayProcessing
                                          ? const Padding(padding: EdgeInsets.all(8.0), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent)))
                                          : IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: Icon(Icons.fingerprint, size: 20, color: isXrayMode ? Colors.amberAccent : Colors.white38),
                                              onPressed: generatedStems.contains(activeEditableStem) ? toggleXrayMode : null,
                                            ),
                                    ),

                                    // Divider for Undo/Redo grouping
                                    SizedBox(
                                      width: double.infinity,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                        child: Divider(color: Colors.grey[800], thickness: 1.5),
                                      ),
                                    ),

                                    // 6. Undo
                                    Tooltip(
                                      message: 'Undo',
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.undo, size: 20),
                                        color: undoStack.isNotEmpty ? Colors.white : Colors.white24,
                                        onPressed: undoStack.isNotEmpty ? _undo : null,
                                      ),
                                    ),
                                    
                                    // 7. Redo
                                    Tooltip(
                                      message: 'Redo',
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.redo, size: 20),
                                        color: redoStack.isNotEmpty ? Colors.white : Colors.white24,
                                        onPressed: redoStack.isNotEmpty ? _redo : null,
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
              ]),
      ),
    );
  }
}
