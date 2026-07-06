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

import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; 
import 'dart:math' as math;
import 'package:file_saver/file_saver.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:archive/archive.dart'; 
import 'dart:typed_data';

import 'ui/timeline_canvas.dart';
import 'pedagogy/live_analyzer.dart';
import 'ui/timeline_ruler.dart';
import 'audio/vox_synth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SoLoud.instance.init();
  runApp(MaterialApp(
    home: const VoxrayDAW(), 
    theme: ThemeData(brightness: Brightness.dark)
  ));
}

// --- MIXER STATE MODEL ---
class ChannelState {
  double volume;
  double pan; 
  bool isMuted;
  bool isSoloed;

  String plugin1;
  String plugin2;
  String plugin3;
  String plugin4;

  double reverbMix;
  double compressionThreshold; 
  double compressionRatio;
  double eqLowGain;
  double eqMidGain;
  double eqHighGain;

  ChannelState({
    this.volume = 1.0,
    this.pan = 0.0,
    this.isMuted = false,
    this.isSoloed = false,
    this.plugin1 = 'None',
    this.plugin2 = 'None',
    this.plugin3 = 'None',
    this.plugin4 = 'None',
    this.reverbMix = 0.0,
    this.compressionThreshold = 0.0,
    this.compressionRatio = 1.0,
    this.eqLowGain = 0.0,
    this.eqMidGain = 0.0,
    this.eqHighGain = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'volume': volume,
    'pan': pan,
    'isMuted': isMuted,
    'isSoloed': isSoloed,
    'plugin1': plugin1,
    'plugin2': plugin2,
    'plugin3': plugin3,
    'plugin4': plugin4,
  };

  factory ChannelState.fromJson(Map<String, dynamic> json) {
    return ChannelState(
      volume: json['volume'] ?? 1.0,
      pan: (json['pan'] ?? 0.0).toDouble(),
      isMuted: json['isMuted'] ?? false,
      isSoloed: json['isSoloed'] ?? false,
      plugin1: json['plugin1'] ?? 'None',
      plugin2: json['plugin2'] ?? 'None',
      plugin3: json['plugin3'] ?? 'None',
      plugin4: json['plugin4'] ?? 'None',
    );
  }

  ChannelState copyWith({
    double? volume,
    double? pan,
    bool? isMuted,
    bool? isSoloed,
    String? plugin1,
    String? plugin2,
    String? plugin3,
    String? plugin4,
  }) {
    return ChannelState(
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      isMuted: isMuted ?? this.isMuted,
      isSoloed: isSoloed ?? this.isSoloed,
      plugin1: plugin1 ?? this.plugin1,
      plugin2: plugin2 ?? this.plugin2,
      plugin3: plugin3 ?? this.plugin3,
      plugin4: plugin4 ?? this.plugin4,
    );
  }
}

enum DragMode { off, semitone, microTuning }

class VoxrayDAW extends StatefulWidget {
  const VoxrayDAW({Key? key}) : super(key: key);
  @override
  State<VoxrayDAW> createState() => VoxrayDAWState(); 
}

class VoxrayDAWState extends State<VoxrayDAW> {
  // --- SoLoud Audio Engine Handles ---
  AudioSource? masterSource;
  SoundHandle? masterHandle;
  
  AudioSource? synthSource;
  SoundHandle? synthHandle;
  
  Map<String, AudioSource> stemSources = {};
  Map<String, SoundHandle> stemHandles = {};
  
  bool isPlaying = false;
  Timer? positionTimer;

  Set<String> activePlaybackSources = {};
  final Map<String, Uint8List> cachedStemBytes = {}; 
  bool isFetchingStems = false;

  SynthSettings synthSettings = const SynthSettings();
  bool isSynthRendering = false;
  String synthMessage = '';
  String processingMode = 'advanced'; 
  
  Map<String, ChannelState> mixerState = {
    'master': ChannelState(),
    'synth': ChannelState(),
    'vocals': ChannelState(),
    'instrumental': ChannelState(),
  };
  
  final ScrollController horizontalScrollController = ScrollController();
  final ScrollController verticalScrollController = ScrollController();
  final ScrollController rulerScrollController = ScrollController();
  
  Map<String, List<dynamic>> allStemsNotes = {};
  String activeEditableStem = ''; 

  Set<String> targetStemsSelection = {};
  Set<String> generatedStems = {}; 
  List<String> suggestedStems = []; 
  
  // State flags for project management
  bool isOriginalMixAvailable = false; 
  bool isTestModeActive = false; 
  bool isProjectLoaded = false;
  bool hasBeenSaved = false;
  String? currentProjectPath;
  Set<String> dirtyStems = {}; 

  List<dynamic> get rawNotes => activeEditableStem.isNotEmpty && allStemsNotes.containsKey(activeEditableStem) 
      ? allStemsNotes[activeEditableStem]! 
      : [];

  set rawNotes(List<dynamic> updatedNotes) {
    if (activeEditableStem.isNotEmpty) {
      allStemsNotes[activeEditableStem] = updatedNotes;
    }
  }

  final List<String> popStems = ['vocals', 'instrumental', 'drums', 'bass', 'guitar', 'piano', 'other'];
  final List<String> orchStems = ['violin', 'cello', 'contrabass', 'flute', 'oboe', 'bassoon', 'trumpet', 'trombone', 'tuba', 'percussion', 'orchestral'];
  final List<String> forensicStems = ['forensic_id'];

  List<Map<String, dynamic>> markers = [
    {"id": "mk_start", "time": 0.0, "label": "Start"},
    {"id": "mk_end", "time": 30.0, "label": "End"}
  ];
  
  List<String> undoStack = [];
  List<String> redoStack = [];
  
  bool isLoading = false;
  double processingProgress = 0.0; 
  String processingMessage = "";   
  Timer? pollingTimer;     
  String? currentTaskId; 
  String? currentJobId;  

  bool isXrayMode = false;
  bool isXrayProcessing = false;
  String originalFileName = "Unknown File"; 
  String originalFilePath = "";

  double songDuration = 30.0;
  double currentPosition = 0.0;
  
  double zoomX = 50.0;
  double zoomY = 8.0;
  
  // FIXED: Adjusted MIDI constraints to match 88-key piano boundaries (A0 to C8)
  final int minMidi = 21;
  final int maxMidi = 108;

  bool isScrubMode = true;
  DragMode currentDragMode = DragMode.off;
  
  String projectName = "Voxray_Session";
  Uint8List? originalAudioBytes;
  
  bool isLiveModeActive = false;
  bool isLoopModeActive = false;
  double loopStartBoundary = 0.0;
  double loopEndBoundary = 30.0;

  bool isUserScrolling = false;
  bool isExporting = false;
  bool isPreviewing = false;
  String exportMessage = '';
  String selectedEngineProfile = 'studio';

  final String apiBase = 'https://donkelleymusic--voxray-pro-api-api.modal.run';

  @override
  void initState() {
    super.initState();
    horizontalScrollController.addListener(() {
      if (rulerScrollController.hasClients) {
        if ((rulerScrollController.position.pixels - horizontalScrollController.position.pixels).abs() > 0.1) {
          rulerScrollController.jumpTo(horizontalScrollController.position.pixels);
        }
      }
    });
    rulerScrollController.addListener(() {
      if (horizontalScrollController.hasClients) {
        if ((horizontalScrollController.position.pixels - rulerScrollController.position.pixels).abs() > 0.1) {
          horizontalScrollController.jumpTo(rulerScrollController.position.pixels);
        }
      }
    });
    
    positionTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!isPlaying || !mounted) return;
      
      double currentT = 0.0;
      if (masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) {
        currentT = SoLoud.instance.getPosition(masterHandle!).inMilliseconds / 1000.0;
      } else if (stemHandles.isNotEmpty) {
        final firstHandle = stemHandles.values.first;
        if (SoLoud.instance.getIsValidVoiceHandle(firstHandle)) {
          currentT = SoLoud.instance.getPosition(firstHandle).inMilliseconds / 1000.0;
        }
      } else if (synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(synthHandle!)) {
        currentT = SoLoud.instance.getPosition(synthHandle!).inMilliseconds / 1000.0;
      }

      if (isLoopModeActive && 
          loopEndBoundary > loopStartBoundary && 
          loopEndBoundary > 0.0 &&
          currentT >= loopEndBoundary) {
        seekAllPlayers(loopStartBoundary);
        currentT = loopStartBoundary;
      }

      setState(() => currentPosition = currentT);

      if (!isUserScrolling) {
        double targetX = (currentT * zoomX) - 150.0;
        if (targetX < 0) targetX = 0;
        if (horizontalScrollController.hasClients && horizontalScrollController.position.maxScrollExtent > 0) {
          horizontalScrollController.jumpTo(
            targetX.clamp(0.0, horizontalScrollController.position.maxScrollExtent)
          );
        }

        if (verticalScrollController.hasClients && rawNotes.isNotEmpty) {
          var activeNotes = rawNotes.where((n) {
            if (n['isDeleted'] == true) return false;
            double start = (n['start_time'] ?? 0).toDouble();
            double end = (n['end_time'] ?? 0).toDouble();
            return start <= currentT && end >= currentT;
          }).toList();

          if (activeNotes.isNotEmpty) {
            List<int> midiValues = activeNotes
                .map<int>((n) => ((n['display_midi'] ?? n['actual_midi'] ?? 60)).round())
                .toList()
              ..sort();
            int medianMidi = midiValues[midiValues.length ~/ 2];

            double viewportHeight = verticalScrollController.position.viewportDimension;
            double targetY = ((maxMidi - medianMidi) * zoomY) + (zoomY / 2) - (viewportHeight / 2);
            targetY = targetY.clamp(0.0, verticalScrollController.position.maxScrollExtent);

            verticalScrollController.animateTo(
              targetY,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    pollingTimer?.cancel();
    positionTimer?.cancel();
    horizontalScrollController.dispose();
    verticalScrollController.dispose();
    rulerScrollController.dispose();
    SoLoud.instance.disposeAllSources();
    SoLoud.instance.deinit();
    super.dispose();
  }

  void notifyChanged() {
    setState(() {});
  }

  void registerUndoSnapshot() {
    if (activeEditableStem.isNotEmpty) {
      setState(() {
        undoStack.add(json.encode(allStemsNotes));
        redoStack.clear();
        cachedStemBytes.remove(activeEditableStem);
        dirtyStems.add(activeEditableStem); 
        hasBeenSaved = false; 
      });
    }
  }

  ChannelState getChannelState(String key) {
    if (!mixerState.containsKey(key)) {
      mixerState[key] = ChannelState();
    }
    return mixerState[key]!;
  }

  void jumpToTimelinePosition(double seconds) {
    seekAllPlayers(seconds);
    setState(() => currentPosition = seconds);

    double targetX = (seconds * zoomX) - 150.0;
    if (targetX < 0) targetX = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (horizontalScrollController.hasClients &&
          horizontalScrollController.positions.length == 1 &&
          horizontalScrollController.position.maxScrollExtent > 0) {
        horizontalScrollController.jumpTo(
          targetX.clamp(0.0, horizontalScrollController.position.maxScrollExtent)
        );
      }
    });
  }

  void setZoomX(double newZoom) {
    if (!horizontalScrollController.hasClients) {
      setState(() => zoomX = newZoom);
      return;
    }
    
    double oldZoom = zoomX;
    double viewportWidth = horizontalScrollController.position.viewportDimension;
    double currentPixels = horizontalScrollController.position.pixels;
    
    double centerTime = (currentPixels + (viewportWidth / 2)) / oldZoom;
    double newScrollX = (centerTime * newZoom) - (viewportWidth / 2);
    
    setState(() => zoomX = newZoom);
    
    horizontalScrollController.jumpTo(math.max(0.0, newScrollX));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (horizontalScrollController.hasClients) {
        horizontalScrollController.jumpTo(
          newScrollX.clamp(0.0, horizontalScrollController.position.maxScrollExtent)
        );
      }
    });
  }

  void setZoomY(double newZoom) {
    if (!verticalScrollController.hasClients) {
      setState(() => zoomY = newZoom);
      return;
    }
    
    double oldZoom = zoomY;
    double viewportHeight = verticalScrollController.position.viewportDimension;
    double currentPixels = verticalScrollController.position.pixels;
    
    double centerMidi = maxMidi - ((currentPixels + (viewportHeight / 2) - (oldZoom / 2)) / oldZoom);
    double newScrollY = ((maxMidi - centerMidi) * newZoom) + (newZoom / 2) - (viewportHeight / 2);
    
    setState(() => zoomY = newZoom);
    
    verticalScrollController.jumpTo(math.max(0.0, newScrollY));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (verticalScrollController.hasClients) {
        verticalScrollController.jumpTo(
          newScrollY.clamp(0.0, verticalScrollController.position.maxScrollExtent)
        );
      }
    });
  }

  // ============================================================
  // MULTI-SOURCE NATIVE PLAYBACK MIXER (SoLoud)
  // ============================================================

  void seekAllPlayers(double seconds) {
    final time = Duration(milliseconds: (seconds * 1000).round());
    if (masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) {
      SoLoud.instance.seek(masterHandle!, time);
    }
    if (synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(synthHandle!)) {
      SoLoud.instance.seek(synthHandle!, time);
    }
    for (var handle in stemHandles.values) {
      if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
        SoLoud.instance.seek(handle, time);
      }
    }
  }

  void playAllPlayers() {
    setState(() => isPlaying = true);
    if (masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) {
      SoLoud.instance.setPause(masterHandle!, false);
    }
    if (synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(synthHandle!)) {
      SoLoud.instance.setPause(synthHandle!, false);
    }
    for (var handle in stemHandles.values) {
      if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
        SoLoud.instance.setPause(handle, false);
      }
    }
  }

  void pauseAllPlayers() {
    setState(() => isPlaying = false);
    if (masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) {
      SoLoud.instance.setPause(masterHandle!, true);
    }
    if (synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(synthHandle!)) {
      SoLoud.instance.setPause(synthHandle!, true);
    }
    for (var handle in stemHandles.values) {
      if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
        SoLoud.instance.setPause(handle, true);
      }
    }
  }

  void setSynthVolume(double vol) {
    if (synthHandle != null) SoLoud.instance.setVolume(synthHandle!, vol);
  }

  Future<void> playPreviewTone(double freq) async {
    try {
      final dummyNote = [{
        'start_time': 0.0, 'end_time': 0.5,
        'actual_midi': 69.0 + (12 * math.log(freq / 440.0) / math.ln2),
        'cents_shift': 0, 'volume': 1.0, 'isMuted': false, 'isDeleted': false,
        'time_ratio': 1.0, 'vibrato_scale': 1.0, 'drift_scale': 1.0, 'amplitude': 1.0,
      }];
      final wavBytes = renderNotesToWavBytes(notes: dummyNote, duration: 0.5, settings: synthSettings);
      final previewSrc = await SoLoud.instance.loadMem("preview", wavBytes);
      SoLoud.instance.play(previewSrc, volume: 0.7);
    } catch (e) {
      debugPrint("Preview error: $e");
    }
  }

  void _toggleMasterTransport() {
    if (isPlaying) {
      pauseAllPlayers();
    } else {
      playAllPlayers();
    }
  }

  // ============================================================
  // CONTEXT ENRICHMENT FOR POLYPHONIC SEPARATION
  // ============================================================
  List<Map<String, dynamic>> _enrichManifestWithPolyphonicContext(List<dynamic> targetNotesList) {
    List<Map<String, dynamic>> enrichedList = [];
    
    for (var entry in targetNotesList) {
      Map<String, dynamic> note = Map<String, dynamic>.from(entry);
      double start = (note['start_time'] ?? 0.0).toDouble();
      double end = (note['end_time'] ?? 0.0).toDouble();
      double actualMidi = (note['actual_midi'] ?? 60.0).toDouble();
      
      var overlaps = targetNotesList.where((alt) {
        if (alt['isDeleted'] == true) return false;
        double altStart = (alt['start_time'] ?? 0.0).toDouble();
        double altEnd = (alt['end_time'] ?? 0.0).toDouble();
        return (start < altEnd && end > altStart);
      }).toList();
      
      note['is_poly'] = overlaps.length > 1;
      note['target_freq'] = 440.0 * math.pow(2.0, (actualMidi - 69.0) / 12.0);
      note['component_count'] = overlaps.length;
      
      enrichedList.add(note);
    }
    return enrichedList;
  }

  // ============================================================
  // CORE API WORKFLOWS
  // ============================================================
  
  Future<void> _requestSnippetSplice(Map<String, dynamic> modifiedNote) async {
    if (activeEditableStem.isEmpty) return;
    try {
      modifiedNote['processing_mode'] = processingMode;
      var response = await http.post(
        Uri.parse('$apiBase/render-snippet'),
        body: {
          'task_id': currentTaskId!,
          'stem_name': activeEditableStem,
          'edit_data': jsonEncode(modifiedNote)
        }
      );
      
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() {
            modifiedNote['type'] = 'splice';
            modifiedNote['snippet_b64'] = data['snippet_b64'];
            modifiedNote['splice_mode'] = 'replace'; 
        });
      }
    } catch (e) {
      debugPrint("Splice generation failed: $e");
    }
  }

  Future<Map<String, String>?> _showUploadTypeDialog() async {
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String selectedType = 'mix';
        String selectedStem = 'vocals';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text("Audio Upload Type", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<String>(
                    title: const Text("Full Mix", style: TextStyle(color: Colors.white)),
                    subtitle: const Text("Contains multiple instruments.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    value: 'mix',
                    groupValue: selectedType,
                    activeColor: Colors.tealAccent,
                    onChanged: (val) => setDialogState(() => selectedType = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text("Single Stem", style: TextStyle(color: Colors.white)),
                    subtitle: const Text("Already isolated instrument.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    value: 'stem',
                    groupValue: selectedType,
                    activeColor: Colors.tealAccent,
                    onChanged: (val) => setDialogState(() => selectedType = val!),
                  ),
                  if (selectedType == 'stem') ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 16.0, bottom: 8.0, left: 16.0),
                      child: Text("Identify this stem:", style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: Colors.grey[850],
                        value: selectedStem,
                        items: [...popStems, ...orchStems, ...forensicStems].map((s) {
                          return DropdownMenuItem(value: s, child: Text(s.toUpperCase(), style: const TextStyle(color: Colors.white)));
                        }).toList(),
                        onChanged: (val) => setDialogState(() => selectedStem = val!),
                      ),
                    ),
                  ]
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, null), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () => Navigator.pop(context, {'type': selectedType, 'stem': selectedStem}), 
                  child: const Text("Proceed")
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _showEngineRecommendationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(children: [Icon(Icons.auto_awesome, color: Colors.tealAccent), SizedBox(width: 8), Text("Ensemble Router Suggestion", style: TextStyle(color: Colors.white))]),
        content: Text("Acoustic parameters suggest this is a classical or live chamber file. We recommend using the [${selectedEngineProfile.toUpperCase()}] processing engine layout profile to prevent dynamic gating artifacts.", style: const TextStyle(color: Colors.white54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Accept Profile", style: TextStyle(color: Colors.tealAccent))),
        ],
      )
    );
  }

  Future<void> _newProject() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Create New Project?", style: TextStyle(color: Colors.white)),
        content: const Text("Any unsaved edits across your instrument tracks will be permanently lost.", style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("Reset Workspace", style: TextStyle(color: Colors.white))),
        ],
      )
    );
    if (confirm != true) return;
    
    pauseAllPlayers(); 
    SoLoud.instance.disposeAllSources();
    
    setState(() {
      isProjectLoaded = false;
      hasBeenSaved = false;
      dirtyStems.clear();
      allStemsNotes.clear(); 
      generatedStems.clear(); 
      targetStemsSelection.clear(); 
      cachedStemBytes.clear();
      stemHandles.clear(); 
      stemSources.clear(); 
      masterHandle = null; 
      masterSource = null; 
      synthHandle = null; 
      synthSource = null;
      activePlaybackSources.clear(); 
      activeEditableStem = ''; 
      currentTaskId = null; 
      currentJobId = null;
      currentProjectPath = null; 
      originalAudioBytes = null; 
      originalFileName = "Unknown File"; 
      songDuration = 30.0; 
      currentPosition = 0.0;
      markers = [{"id": "mk_start", "time": 0.0, "label": "Start"}, {"id": "mk_end", "time": 30.0, "label": "End"}];
      undoStack.clear();
      redoStack.clear();
    });
    
    _showSaveConfirmation("New empty project loaded.");
  }

  Future<void> _importIndividualStem() async {
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.audio, withData: true);
    if (result == null) return;
    
    Uint8List bytes = result.files.single.bytes ?? await File(result.files.single.path!).readAsBytes();
    
    String? chosenIdentity = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String selected = 'vocals';
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text("Identify Imported Track", style: TextStyle(color: Colors.white)),
            content: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: Colors.grey[850],
              value: selected,
              items: [...popStems, ...orchStems].map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase(), style: const TextStyle(color: Colors.white)))).toList(),
              onChanged: (v) => setDialogState(() => selected = v!),
            ),
            actions: [
               TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
               ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent), onPressed: () => Navigator.pop(ctx, selected), child: const Text("Import", style: TextStyle(color: Colors.black))),
            ],
          );
        });
      }
    );
    if (chosenIdentity == null) return;
    
    setState(() {
      originalAudioBytes = bytes; 
      originalFileName = result.files.single.name;
      isLoading = true; processingMessage = "Ingesting stem and generating tracking matrices...";
      targetStemsSelection.add(chosenIdentity); 
      activeEditableStem = chosenIdentity;
      cachedStemBytes[chosenIdentity] = bytes;
    });
    
    try {
      var req = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
        ..fields['upload_type'] = 'stem'
        ..fields['stem_target'] = chosenIdentity
        ..fields['instruments_json'] = jsonEncode([chosenIdentity])
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: result.files.single.name));
      
      var res = await req.send();
      var data = jsonDecode(await res.stream.bytesToString());
      currentTaskId = data['task_id']; 
      currentJobId = data['job_id'];
      
      _pollForStemData(currentJobId!, chosenIdentity);
    } catch (e) {
      setState(() { isLoading = false; }); 
      _showSaveConfirmation("Import matrix generation crashed: $e");
    }
  }

  _loadFileAndAnalyze() async {
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.audio, withData: true);
    if (result == null) return;

    var uploadOptions = await _showUploadTypeDialog();
    if (uploadOptions == null) return;

    Uint8List? audioBytes;
    if (result.files.single.bytes != null) {
      audioBytes = result.files.single.bytes!;
    } else if (result.files.single.path != null) {
      audioBytes = await File(result.files.single.path!).readAsBytes();
    } else return;

    setState(() {
      isLoading = true;
      processingProgress = 0.0;
      originalAudioBytes = audioBytes;
      originalFileName = result.files.single.name; 
      originalFilePath = result.files.single.path ?? "";
      
      isProjectLoaded = true;
      hasBeenSaved = false;
      dirtyStems.clear();

      cachedStemBytes.clear();
      for(var h in stemHandles.values) SoLoud.instance.stop(h);
      stemHandles.clear();
      stemSources.clear();
      activePlaybackSources.clear();
      allStemsNotes.clear();
      generatedStems.clear();
      currentTaskId = null;
      currentJobId = null;
      suggestedStems.clear();

      if (uploadOptions['type'] == 'mix') {
        isOriginalMixAvailable = true;
        activePlaybackSources.add('original');
        processingMessage = "Analyzing profile and dynamic parameters...";
      } else {
        isOriginalMixAvailable = false;
        activeEditableStem = uploadOptions['stem']!;
        activePlaybackSources.add(activeEditableStem);
        targetStemsSelection.add(activeEditableStem);
        processingMessage = "Analyzing ${activeEditableStem.toUpperCase()} stem notes...";
      }
    });

    if (synthHandle != null) SoLoud.instance.stop(synthHandle!);
    if (masterHandle != null) SoLoud.instance.stop(masterHandle!);

    try {
      masterSource = await SoLoud.instance.loadMem("master", originalAudioBytes!);
      masterHandle = SoLoud.instance.play(masterSource!, paused: true);
      SoLoud.instance.setPause(masterHandle!, true);
      ChannelState origState = getChannelState('original');
      SoLoud.instance.setVolume(masterHandle!, origState.isMuted ? 0.0 : origState.volume);
      SoLoud.instance.setPan(masterHandle!, origState.pan);
    } catch (e) {
      debugPrint("Audio preview setup failed (non-fatal): $e");
    }

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
        ..fields['instruments_json'] = jsonEncode(targetStemsSelection.toList())
        ..fields['upload_type'] = uploadOptions['type']! 
        ..fields['stem_target'] = uploadOptions['type'] == 'stem' ? uploadOptions['stem']! : 'none'
        ..fields['is_test_mode'] = isTestModeActive.toString()
        ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: result.files.single.name));
      
      var response = await request.send();
      if (response.statusCode != 200) throw Exception("Server rejected file upload");
      
      var data = json.decode(await response.stream.bytesToString());
      
      currentTaskId = data['task_id']; 
      
      if (data['detected_instruments'] != null) {
        suggestedStems = List<String>.from(data['detected_instruments']);
      }

      if (data['recommended_engine'] != null) {
        selectedEngineProfile = data['recommended_engine'];
      }

      if (uploadOptions['type'] == 'mix') {
        if (selectedEngineProfile != 'studio') {
          _showEngineRecommendationDialog();
        }
        setState(() {
          isLoading = false;
          songDuration = (data['duration'] ?? 30.0).toDouble(); 
          loopEndBoundary = songDuration;
          int endIdx = markers.indexWhere((m) => m['id'] == 'mk_end');
          if (endIdx != -1) markers[endIdx]['time'] = songDuration;
        });
        return;
      }

      currentJobId = data['job_id']; 
      _pollForStemData(currentJobId!, uploadOptions['stem']!);

    } catch (e) {
      debugPrint("Initialization Failed: $e");
      setState(() { isLoading = false; processingMessage = "Failed to start."; });
      _showSaveConfirmation('Initialization Failed: $e');
    }
  }

  void _pollForStemData(String jobId, String targetStem) {
    pollingTimer?.cancel();
    pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        var statusRes = await http.get(Uri.parse('$apiBase/get-task-status?task_id=$jobId'));
        if (statusRes.statusCode == 200) {
          var statusData = json.decode(statusRes.body);
          
          setState(() {
            processingProgress = (statusData['progress'] ?? 0).toDouble() / 100.0;
            processingMessage = statusData['message'] ?? "Processing...";
          });

          if (statusData['status'] == 'complete') {
            timer.cancel();
            final result = statusData['result'];

            List<dynamic> stemNotes = [];
            final allStemsMap = result['all_stems_notes'];
            if (allStemsMap != null && allStemsMap[targetStem] != null) {
              stemNotes = json.decode(json.encode(allStemsMap[targetStem]));
            } else {
              stemNotes = json.decode(json.encode(result['notes'] ?? []));
            }

            setState(() {
              allStemsNotes[targetStem] = stemNotes;
              generatedStems.add(targetStem);
              activePlaybackSources.add(targetStem); 
              
              double newDuration = (result['duration'] ?? songDuration).toDouble();
              if (newDuration > 0) {
                 songDuration = newDuration;
                 loopEndBoundary = songDuration;
                 int endIdx = markers.indexWhere((m) => m['id'] == 'mk_end');
                 if (endIdx != -1) markers[endIdx]['time'] = songDuration;
              }
              isLoading = false;
              processingMessage = '';
            });

            _loadStemPlayerSource(targetStem);
          } else if (statusData['status'] == 'error') {
            timer.cancel();
            setState(() { 
              isLoading = false; 
              processingMessage = "Error: ${statusData['message']}"; 
              activePlaybackSources.remove(targetStem);
            });
            _showSaveConfirmation('Processing Error: ${statusData['message']}');
          }
        } else {
          timer.cancel();
          setState(() { 
            isLoading = false; 
            processingMessage = "Error: Server returned ${statusRes.statusCode}"; 
            activePlaybackSources.remove(targetStem);
          });
          _showSaveConfirmation('Processing Error: Server returned ${statusRes.statusCode}');
        }
      } catch (e) {
        debugPrint("Polling error: $e");
        timer.cancel();
        setState(() { 
          isLoading = false; 
          processingMessage = "Error: $e"; 
          activePlaybackSources.remove(targetStem);
        });
        _showSaveConfirmation('Connection error during polling.');
      }
    });
  }

  Future<void> _generateStemOnDemand(String targetToGenerate) async {
    if (currentTaskId == null) return;
    
    if (generatedStems.contains(targetToGenerate)) {
      return;
    }

    setState(() {
      isLoading = true;
      processingProgress = 0.0;
      processingMessage = "Isolating $targetToGenerate & extracting notes...";
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/generate-stem-on-demand'))
        ..fields['task_id'] = currentTaskId!
        ..fields['target_stem'] = targetToGenerate;

      var res = await request.send();
      if (res.statusCode == 200) {
         final resData = json.decode(await res.stream.bytesToString());
         final String jobId = resData['job_id'];
         currentJobId = jobId;
         _pollForStemData(jobId, targetToGenerate);
      } else {
        throw Exception("Server returned status code ${res.statusCode}");
      }
    } catch (e) {
      setState(() { 
        isLoading = false; 
        processingMessage = ""; 
        activePlaybackSources.remove(targetToGenerate);
        if (generatedStems.isNotEmpty && !generatedStems.contains(activeEditableStem)) {
           activeEditableStem = generatedStems.first;
        }
      });
      _showSaveConfirmation("Failed to generate ${targetToGenerate.toUpperCase()} stem: $e");
    }
  }

  Future<void> _forceReprocessXray() async {
    if (rawNotes.isEmpty) return;

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
          SizedBox(width: 8),
          Text("Force Reprocess", style: TextStyle(color: Colors.white)),
        ]),
        content: Text(
          "This will re-run the heavy X-Ray pitch extraction on the server for the current [${activeEditableStem.toUpperCase()}] stem and overwrite your current pitch contours. Proceed?",
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text("Cancel", style: TextStyle(color: Colors.white54))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent[700]),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Proceed"),
          ),
        ],
      )
    );

    if (confirm != true) return;

    bool cachedTransportState = isPlaying;
    pauseAllPlayers();

    setState(() { 
      isXrayProcessing = true; 
      isXrayMode = true; 
    });

    try {
      if (currentTaskId == null) {
        if (!cachedStemBytes.containsKey(activeEditableStem)) {
           throw Exception("Audio data not found in cache.");
        }
        
        _showSaveConfirmation('Establishing new server session for Reprocess...');

        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type'] = 'stem'
          ..fields['stem_target'] = activeEditableStem
          ..fields['instruments_json'] = jsonEncode([activeEditableStem])
          ..files.add(http.MultipartFile.fromBytes('file', cachedStemBytes[activeEditableStem]!, filename: '${activeEditableStem}_offline.ogg'));
        
        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          var sessionData = jsonDecode(await sessionRes.stream.bytesToString());
          currentTaskId = sessionData['task_id'];
        } else {
          throw Exception("Could not establish background server session.");
        }
      }

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-xray'))
        ..fields['task_id'] = currentTaskId!
        ..fields['notes_manifest'] = jsonEncode(_enrichManifestWithPolyphonicContext(rawNotes)); 

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);
      
      if (responseData.statusCode == 200) {
        var data = jsonDecode(responseData.body);
        if (data['status'] == 'success') {
          setState(() {
            rawNotes = data['notes']; 
            registerUndoSnapshot();
          });
          _showSaveConfirmation('X-Ray data successfully reprocessed.');
        } else {
          _showSaveConfirmation('Reprocess failed: ${data['message']}');
        }
      }
    } catch (e) {
      debugPrint("XRAY Reprocess error: $e");
      _showSaveConfirmation('Reprocess failed: $e');
    } finally {
      setState(() => isXrayProcessing = false);
      if (cachedTransportState) playAllPlayers(); else pauseAllPlayers();
    }
  }

  Future<void> _toggleXrayMode() async {
    if (rawNotes.isEmpty) return;
    
    bool cachedTransportState = isPlaying;
    
    if (isXrayMode || rawNotes.any((n) => n.containsKey('contour'))) {
      setState(() => isXrayMode = !isXrayMode);
      return;
    }

    pauseAllPlayers();
    setState(() { isXrayProcessing = true; isXrayMode = true; });

    try {
      if (currentTaskId == null) {
        String lookupKey = activeEditableStem.toLowerCase().trim();
        bool found = false;
        
        for (String key in cachedStemBytes.keys) {
            if (key.toLowerCase().trim() == lookupKey) {
                found = true;
                activeEditableStem = key; 
                break;
            }
        }

        if (!found) {
            debugPrint("DEBUG: Failed to find key '$lookupKey'. Available keys: ${cachedStemBytes.keys.toList()}");
            _showSaveConfirmation('Missing audio data. Available keys: ${cachedStemBytes.keys.toList()}');
            setState(() { isXrayProcessing = false; isXrayMode = false; });
            if (cachedTransportState) playAllPlayers();
            return;
        }

        _showSaveConfirmation('Establishing new server session for X-Ray...');

        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type'] = 'stem'
          ..fields['stem_target'] = activeEditableStem
          ..fields['instruments_json'] = jsonEncode([activeEditableStem])
          ..files.add(http.MultipartFile.fromBytes('file', cachedStemBytes[activeEditableStem]!, filename: '${activeEditableStem}_offline.ogg'));
        
        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          var sessionData = jsonDecode(await sessionRes.stream.bytesToString());
          currentTaskId = sessionData['task_id'];
        } else {
          throw Exception("Could not establish background server session.");
        }
      }

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-xray'))
        ..fields['task_id'] = currentTaskId!
        ..fields['notes_manifest'] = jsonEncode(_enrichManifestWithPolyphonicContext(rawNotes));

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);
      
      if (responseData.statusCode == 200) {
        var data = jsonDecode(responseData.body);
        if (data['status'] == 'success') {
          setState(() {
            rawNotes = data['notes'];
            registerUndoSnapshot(); 
          });
        } else {
          _showSaveConfirmation('XRAY failed: ${data['message']}');
          setState(() => isXrayMode = false);
        }
      }
    } catch (e) {
      debugPrint("XRAY error: $e");
      _showSaveConfirmation('Connection error: $e');
      setState(() => isXrayMode = false);
    } finally {
      setState(() { isXrayProcessing = false; });
      if (cachedTransportState) playAllPlayers(); else pauseAllPlayers();
    }
  }

  Future<Uint8List> _fetchStemBytes(String stemName) async {
    if (currentTaskId == null) throw Exception("No active session");
    final stemRes = await http.get(Uri.parse('$apiBase/api/stem/$currentTaskId/$stemName?format=ogg'));
    if (stemRes.statusCode == 200) return stemRes.bodyBytes;
    throw Exception("Stem fetch error ${stemRes.statusCode}");
  }

  Future<void> _loadStemPlayerSource(String stemName) async {
    setState(() { isFetchingStems = true; });

    bool wasPlaying = isPlaying;
    if (wasPlaying) pauseAllPlayers(); 

    try {
      final Uint8List bytes = cachedStemBytes[stemName] ?? await _fetchStemBytes(stemName);
      cachedStemBytes[stemName] = bytes;

      if (stemHandles.containsKey(stemName)) {
        SoLoud.instance.stop(stemHandles[stemName]!);
      }

      stemSources[stemName] = await SoLoud.instance.loadMem("stem_$stemName", bytes);
      stemHandles[stemName] = SoLoud.instance.play(stemSources[stemName]!, paused: true);
      SoLoud.instance.setPause(stemHandles[stemName]!, true); 

      ChannelState state = getChannelState(stemName);
      double effectiveVolume = state.isMuted ? 0.0 : state.volume;
      
      SoLoud.instance.setVolume(stemHandles[stemName]!, effectiveVolume);
      SoLoud.instance.setPan(stemHandles[stemName]!, state.pan); 
    } catch (e) {
      debugPrint("Stem track layer $stemName build failed: $e");
      _showSaveConfirmation('Stem layer $stemName unavailable: $e');
      setState(() => activePlaybackSources.remove(stemName));
    } finally {
      setState(() { isFetchingStems = false; });
      seekAllPlayers(currentPosition); 
      if (wasPlaying) {
        await Future.delayed(const Duration(milliseconds: 50));
        playAllPlayers();
      } else {
        pauseAllPlayers();
      }
    }
  }

  Future<void> _loadSynthSource() async {
    if (rawNotes.isEmpty) return;
    setState(() { isSynthRendering = true; synthMessage = "Synthesizing note data..."; });

    bool wasPlaying = isPlaying;
    if (wasPlaying) pauseAllPlayers();

    try {
      final Uint8List wavBytes = renderNotesToWavBytes(
        notes: rawNotes,
        duration: songDuration,
        settings: synthSettings,
      );

      if (synthHandle != null) SoLoud.instance.stop(synthHandle!);
      synthSource = await SoLoud.instance.loadMem("synth_layer", wavBytes);
      synthHandle = SoLoud.instance.play(synthSource!, paused: true);
      SoLoud.instance.setPause(synthHandle!, true);
      
      ChannelState state = getChannelState('synth');
      SoLoud.instance.setVolume(synthHandle!, state.isMuted ? 0.0 : state.volume);
      SoLoud.instance.setPan(synthHandle!, state.pan); 
    } catch (e) {
      debugPrint("Synth layer load failed: $e");
      _showSaveConfirmation('Synth layer failed: $e');
      setState(() => activePlaybackSources.remove('synth'));
    } finally {
      setState(() { isSynthRendering = false; synthMessage = ''; });
      seekAllPlayers(currentPosition);
      if (wasPlaying) {
        playAllPlayers();
      } else {
        pauseAllPlayers();
      }
    }
  }

  Future<void> _refreshSynthLayerIfActive() async {
    if (activePlaybackSources.contains('synth')) {
      await _loadSynthSource();
    }
  }

  Future<void> _togglePlaybackSource(String key, bool enabled) async {
    setState(() {
      if (enabled) {
        activePlaybackSources.add(key);
      } else {
        activePlaybackSources.remove(key);
      }
    });

    if (key == 'original') {
      if (masterHandle != null) {
        ChannelState origState = getChannelState('original');
        SoLoud.instance.setVolume(masterHandle!, enabled ? (origState.isMuted ? 0.0 : origState.volume) : 0.0);
        SoLoud.instance.setPan(masterHandle!, origState.pan);
      }
    } else if (key == 'synth') {
      if (enabled) {
        await _loadSynthSource();
      } else {
        if (synthHandle != null) SoLoud.instance.setVolume(synthHandle!, 0.0);
      }
    } else {
      if (enabled) {
        if (!generatedStems.contains(key)) {
          await _generateStemOnDemand(key);
        } else {
          await _loadStemPlayerSource(key);
        }
      } else {
        if (stemHandles.containsKey(key)) {
          SoLoud.instance.setVolume(stemHandles[key]!, 0.0);
        }
      }
    }
  }

  // ============================================================
  // PROJECT SAVING & EXPORTS
  // ============================================================

  void _undo() {
    if (undoStack.isNotEmpty) {
      setState(() {
        redoStack.add(json.encode(allStemsNotes));
        allStemsNotes = Map<String, List<dynamic>>.from(json.decode(undoStack.removeLast()));
      });
    }
  }

  void _redo() {
    if (redoStack.isNotEmpty) {
      setState(() {
        undoStack.add(json.encode(allStemsNotes));
        allStemsNotes = Map<String, List<dynamic>>.from(json.decode(redoStack.removeLast()));
      });
    }
  }

  Future<Uint8List?> _pollRenderJob(String jobId) async {
    bool isComplete = false;
    int retryCount = 0;
    const int maxRetries = 100; 
    
    while (!isComplete && retryCount < maxRetries) {
      try {
        final res = await http.get(Uri.parse('$apiBase/get-task-status?task_id=$jobId'));
        if (res.statusCode == 200) {
          final taskData = jsonDecode(res.body);
          final status = taskData['status'];
          
          setState(() {
            processingProgress = (taskData['progress'] ?? 0).toDouble() / 100.0;
            if (isPreviewing) exportMessage = taskData['message'] ?? 'Processing...';
          });

          if (status == 'complete') {
            return base64Decode(taskData['result']['master_mix_b64']);
          } else if (status == 'error') {
            throw Exception(taskData['message']);
          }
        } else if (res.statusCode == 404) {
          throw Exception('Task expired or crashed on server');
        }
      } catch (e) {
        debugPrint('Polling network blink: $e');
      }
      await Future.delayed(const Duration(seconds: 3));
      retryCount++;
    }
    throw Exception('Polling timed out after 5 minutes.');
  }

  Future<void> _renderStemEdits() async {
    if (originalAudioBytes == null || activeEditableStem.isEmpty) return;
    
    setState(() { isPreviewing = true; exportMessage = "Queueing edits via Server..."; processingProgress = 0.0; });

    try {
      // --- NEW LOGIC: Re-establish server session if offline ---
      if (currentTaskId == null) {
        if (!cachedStemBytes.containsKey(activeEditableStem)) {
           throw Exception("Audio data not found in cache.");
        }
        
        _showSaveConfirmation('Establishing new server session for Preview...');

        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type'] = 'stem'
          ..fields['stem_target'] = activeEditableStem
          ..fields['instruments_json'] = jsonEncode([activeEditableStem])
          ..files.add(http.MultipartFile.fromBytes('file', cachedStemBytes[activeEditableStem]!, filename: '${activeEditableStem}_offline.ogg'));
        
        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          var sessionData = jsonDecode(await sessionRes.stream.bytesToString());
          currentTaskId = sessionData['task_id'];
        } else {
          throw Exception("Could not establish background server session.");
        }
      }
      // ---------------------------------------------------------

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['edit_manifest'] = jsonEncode({
          'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
          'edits': _enrichManifestWithPolyphonicContext(rawNotes),
          'solo_stem': activeEditableStem,
          'processing_mode': processingMode
        })
        ..fields['task_id'] = currentTaskId!
        ..fields['is_test_mode'] = isTestModeActive.toString()
        ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'audio.wav'));

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);
      
      if (responseData.statusCode != 200) {
        throw Exception("Server error ${responseData.statusCode}: ${responseData.body}");
      }

      var result = jsonDecode(responseData.body);
      if (result['status'] == 'success') {
        String jobId = result['job_id'];
        Uint8List previewBytes = await _pollRenderJob(jobId) ?? Uint8List(0);

        cachedStemBytes[activeEditableStem] = previewBytes;

        if (stemHandles.containsKey(activeEditableStem) && SoLoud.instance.getIsValidVoiceHandle(stemHandles[activeEditableStem]!)) {
          SoLoud.instance.stop(stemHandles[activeEditableStem]!);
        }

        stemSources[activeEditableStem] = await SoLoud.instance.loadMem("stem_${activeEditableStem}_edited", previewBytes);
        stemHandles[activeEditableStem] = SoLoud.instance.play(stemSources[activeEditableStem]!, paused: true);
        
        SoLoud.instance.setVolume(stemHandles[activeEditableStem]!, getChannelState(activeEditableStem).volume);
        SoLoud.instance.setPan(stemHandles[activeEditableStem]!, getChannelState(activeEditableStem).pan);
        
        seekAllPlayers(currentPosition);
        if (isPlaying) {
          SoLoud.instance.setPause(stemHandles[activeEditableStem]!, false);
        }

        if (!activePlaybackSources.contains(activeEditableStem)) {
           setState(() { activePlaybackSources.add(activeEditableStem); });
        }

        setState(() {
          dirtyStems.remove(activeEditableStem); 
        });

        if (isPlaying) {
          _showSaveConfirmation('Edits applied to ${activeEditableStem.toUpperCase()} stem.', isPreview: true);
        } else {
          _showSaveConfirmation('Stem updated — tap Play to hear edits.', isPreview: true);
        }
      } else {
        _showSaveConfirmation('Render failed: ${result['message'] ?? 'unknown error'}');
      }
    } catch (e) {
      debugPrint("Stem render failed: $e");
      _showSaveConfirmation('Render failed: $e');
    } finally {
      setState(() { isPreviewing = false; exportMessage = ''; processingProgress = 0.0; });
    }
  }

  Future<void> _renderStemPlugins(String stem) async {
    if (originalAudioBytes == null) return;
    
    setState(() { isPreviewing = true; exportMessage = "Rendering plugins for $stem..."; processingProgress = 0.0; });

    try {
      // --- NEW LOGIC: Re-establish server session if offline ---
      if (currentTaskId == null) {
        if (!cachedStemBytes.containsKey(stem)) {
           throw Exception("Audio data not found in cache.");
        }
        
        _showSaveConfirmation('Establishing new server session for Plugin Render...');

        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type'] = 'stem'
          ..fields['stem_target'] = stem
          ..fields['instruments_json'] = jsonEncode([stem])
          ..files.add(http.MultipartFile.fromBytes('file', cachedStemBytes[stem]!, filename: '${stem}_offline.ogg'));
        
        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          var sessionData = jsonDecode(await sessionRes.stream.bytesToString());
          currentTaskId = sessionData['task_id'];
        } else {
          throw Exception("Could not establish background server session.");
        }
      }
      // ---------------------------------------------------------

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['edit_manifest'] = jsonEncode({
          'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
          'edits': _enrichManifestWithPolyphonicContext(allStemsNotes[stem] ?? []),
          'solo_stem': stem,
          'processing_mode': processingMode
        })
        ..fields['task_id'] = currentTaskId!
        ..fields['is_test_mode'] = isTestModeActive.toString()
        ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'audio.wav'));

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);
      
      if (responseData.statusCode == 200) {
        var result = jsonDecode(responseData.body);
        if (result['status'] == 'success') {
          String jobId = result['job_id'];
          Uint8List previewBytes = await _pollRenderJob(jobId) ?? Uint8List(0);

          cachedStemBytes[stem] = previewBytes;

          if (stemHandles.containsKey(stem) && SoLoud.instance.getIsValidVoiceHandle(stemHandles[stem]!)) {
             SoLoud.instance.stop(stemHandles[stem]!);
          }

          stemSources[stem] = await SoLoud.instance.loadMem("stem_${stem}_edited", previewBytes);
          
          stemHandles[stem] = SoLoud.instance.play(stemSources[stem]!, paused: true);
          
          SoLoud.instance.setVolume(stemHandles[stem]!, getChannelState(stem).volume);
          SoLoud.instance.setPan(stemHandles[stem]!, getChannelState(stem).pan);
          
          seekAllPlayers(currentPosition);
          
          if (isPlaying) {
             SoLoud.instance.setPause(stemHandles[stem]!, false);
          }
          
          setState(() {
            dirtyStems.remove(stem); 
          });
        }
      }
    } catch (e) {
      debugPrint("Plugin render failed: $e");
      _showSaveConfirmation('Plugin render failed: $e');
    } finally {
      setState(() { isPreviewing = false; exportMessage = ''; processingProgress = 0.0; });
    }
  }


  Future<void> _exportSynthAudio() async {
    if (rawNotes.isEmpty) return;
    setState(() { isSynthRendering = true; synthMessage = "Rendering synth audio..."; });

    try {
      final Uint8List wavBytes = renderNotesToWavBytes(
        notes: rawNotes,
        duration: songDuration,
        settings: synthSettings,
      );

      String defaultName = originalFileName.contains('.')
          ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
          : (originalFileName.isNotEmpty ? originalFileName : projectName);
      defaultName = '${defaultName}_synth';

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: defaultName,
          bytes: wavBytes,
          fileExtension: 'wav',
          mimeType: MimeType.custom,
          customMimeType: 'audio/wav',
        );
        _showSaveConfirmation('Synth audio exported as WAV.');
      } else {
        String? path = await FileSaver.instance.saveAs(
          name: defaultName,
          bytes: wavBytes,
          fileExtension: 'wav',
          mimeType: MimeType.custom,
          customMimeType: 'audio/wav',
        );
        if (path != null && path.isNotEmpty) {
          _showSaveConfirmation('Synth audio exported as WAV.');
        } else {
          _showSaveConfirmation('Export cancelled.');
        }
      }
    } catch (e) {
      debugPrint("Synth export failed: $e");
      _showSaveConfirmation('Synth export failed: $e');
    } finally {
      setState(() { isSynthRendering = false; synthMessage = ''; });
    }
  }

  Future<void> _exportFinalMaster(String format) async {
    if (originalAudioBytes == null) return;
    setState(() { isExporting = true; exportMessage = "Queuing $format Master..."; processingProgress = 0.0; });

    Map<String, dynamic> enrichedStemsNotesMap = {};
    allStemsNotes.forEach((stemKey, notesList) {
      enrichedStemsNotesMap[stemKey] = _enrichManifestWithPolyphonicContext(notesList);
    });

    try {
      // --- NEW LOGIC: Re-establish server session if offline ---
      if (currentTaskId == null) {
        String lookupStem = activeEditableStem.isNotEmpty ? activeEditableStem : (cachedStemBytes.isNotEmpty ? cachedStemBytes.keys.first : '');
        if (lookupStem.isEmpty || !cachedStemBytes.containsKey(lookupStem)) {
           throw Exception("No valid track state found in cache to generate fallback export context.");
        }
        
        _showSaveConfirmation('Establishing server architecture link for Master Mix...');

        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type'] = 'stem'
          ..fields['stem_target'] = lookupStem
          ..fields['instruments_json'] = jsonEncode([lookupStem])
          ..files.add(http.MultipartFile.fromBytes('file', cachedStemBytes[lookupStem]!, filename: '${lookupStem}_offline.ogg'));
        
        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          var sessionData = jsonDecode(await sessionRes.stream.bytesToString());
          currentTaskId = sessionData['task_id'];
        } else {
          throw Exception("Could not build a backend framework pipeline target session.");
        }
      }
      // ---------------------------------------------------------

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['edit_manifest'] = json.encode({
          "mixer_state": mixerState.map((k, v) => MapEntry(k, v.toJson())),
          "all_stems_notes": enrichedStemsNotesMap,
          "processing_mode": processingMode
        })
        ..fields['task_id'] = currentTaskId!
        ..fields['export_format'] = format 
        ..fields['is_test_mode'] = isTestModeActive.toString()
        ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'master.wav'));

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);
      
      if (responseData.statusCode != 200) {
        throw Exception("Server error ${responseData.statusCode}: ${responseData.body}");
      }
      
      var data = jsonDecode(responseData.body);

      if (data['status'] == 'success') {
        String jobId = data['job_id'];
        final Uint8List bytes = await _pollRenderJob(jobId) ?? Uint8List(0);

        String mimeType = 'audio/wav';
        if (format == 'mp3') mimeType = 'audio/mpeg';
        if (format == 'flac') mimeType = 'audio/flac';
        if (format == 'opus') mimeType = 'audio/ogg';

        final fileExt = format == 'opus' ? 'ogg' : format;

        String defaultName = originalFileName.contains('.')
            ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
            : originalFileName;
        defaultName = '${defaultName}_voxray_master';

        String? path = await FileSaver.instance.saveAs(
          name: defaultName,
          bytes: bytes,
          fileExtension: fileExt,
          mimeType: MimeType.custom,
          customMimeType: mimeType,
        );
        
        if (path != null && path.isNotEmpty) {
          _showSaveConfirmation('Master mix saved as ${format.toUpperCase()}.');
        } else {
          _showSaveConfirmation('Export cancelled.');
        }
      } else {
        _showSaveConfirmation('Export failed: ${data['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      debugPrint("Export error: $e");
      _showSaveConfirmation('Export failed: $e');
    } finally {
      setState(() { isExporting = false; exportMessage = ''; processingProgress = 0.0; });
    }
  }

  Future<void> _exportStemsAsZip() async {
    if (cachedStemBytes.isEmpty) { 
      _showSaveConfirmation("No extracted audio stems available to export."); 
      return; 
    }
    setState(() { isExporting = true; exportMessage = "Packing unmixed multi-track stems archive..."; });
    try {
      Archive arch = Archive();
      cachedStemBytes.forEach((k, v) => arch.addFile(ArchiveFile('${projectName}_stem_$k.ogg', v.length, v)));
      Uint8List zip = Uint8List.fromList(ZipEncoder().encode(arch)!);
      await FileSaver.instance.saveAs(name: "${projectName}_stems", bytes: zip, fileExtension: 'zip', mimeType: MimeType.zip);
      _showSaveConfirmation("All tracks exported successfully as unmixed multi-track stems.");
    } catch (e) { 
      _showSaveConfirmation("Stem tree generation failed: $e"); 
    } finally {
      setState(() { isExporting = false; });
    }
  }

  Future<void> _downloadDossier() async {
    if (rawNotes.isEmpty) return;
    setState(() { isExporting = true; exportMessage = "Generating dossier PDF..."; });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/generate-dossier'))
        ..fields['task_id'] = currentTaskId ?? ''
        ..fields['notes_manifest'] = jsonEncode(_enrichManifestWithPolyphonicContext(rawNotes))
        ..fields['session_meta'] = jsonEncode({
          'filename': originalFileName,
          'duration': songDuration,
          'stem_target': activeEditableStem,
          'xray_enabled': rawNotes.any((n) => n.containsKey('contour')),
          'version': '1.5.0',
        });

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);

      if (responseData.statusCode != 200) {
        throw Exception("Server error ${responseData.statusCode}");
      }

      var result = jsonDecode(responseData.body);
      if (result['status'] == 'success') {
        final Uint8List bytes = base64Decode(result['pdf_b64']);
        String saveName = originalFileName.contains('.')
            ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
            : originalFileName;

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: '${saveName}_dossier', bytes: bytes,
            fileExtension: 'pdf', mimeType: MimeType.custom, customMimeType: 'application/pdf',
          );
        } else {
          String? path = await FileSaver.instance.saveAs(
            name: '${saveName}_dossier',
            bytes: bytes,
            fileExtension: 'pdf',
            mimeType: MimeType.custom,
            customMimeType: 'application/pdf',
          );
          if (path != null && path.isNotEmpty) {
            _showSaveConfirmation('Dossier saved successfully.');
          } else {
            _showSaveConfirmation('Save cancelled.');
          }
        }
      }
    } catch (e) {
      _showSaveConfirmation('Dossier generation failed: $e');
    } finally {
      setState(() { isExporting = false; exportMessage = ''; });
    }
  }

  Future<void> _downloadPitchPrint({required bool fullSong, required String format}) async {
    if (rawNotes.isEmpty) return;
    setState(() { isExporting = true; exportMessage = "Generating PitchPrint™..."; });

    double visibleStart = horizontalScrollController.hasClients
        ? horizontalScrollController.position.pixels / zoomX
        : 0.0;
    double visibleEnd = horizontalScrollController.hasClients
        ? (horizontalScrollController.position.pixels + horizontalScrollController.position.viewportDimension) / zoomX
        : songDuration;

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/generate-pitchprint'))
        ..fields['task_id'] = currentTaskId ?? ''
        ..fields['notes_manifest'] = jsonEncode(_enrichManifestWithPolyphonicContext(rawNotes))
        ..fields['full_song'] = fullSong.toString()
        ..fields['visible_start'] = visibleStart.toString()
        ..fields['visible_end'] = visibleEnd.toString()
        ..fields['song_duration'] = songDuration.toString();

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);

      if (responseData.statusCode != 200) {
        throw Exception("Server error ${responseData.statusCode}");
      }

      var result = jsonDecode(responseData.body);
      if (result['status'] == 'success') {
        final Uint8List bytes = base64Decode(result['svg_b64']);
        String saveName = originalFileName.contains('.')
            ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
            : originalFileName;

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: '${saveName}_pitchprint', bytes: bytes,
            fileExtension: 'svg', mimeType: MimeType.custom, customMimeType: 'image/svg+xml',
          );
        } else {
          String? path = await FileSaver.instance.saveAs(
            name: '${saveName}_pitchprint',
            bytes: bytes,
            fileExtension: 'svg',
            mimeType: MimeType.custom,
            customMimeType: 'image/svg+xml',
          );
          if (path != null && path.isNotEmpty) {
            _showSaveConfirmation('PitchPrint™ saved successfully.');
          } else {
            _showSaveConfirmation('Save cancelled.');
          }
        }
      }
    } catch (e) {
      _showSaveConfirmation('PitchPrint™ generation failed: $e');
    } finally {
      setState(() { isExporting = false; exportMessage = ''; });
    }
  }

  Uint8List _packageProjectBytes() {
    Map<String, dynamic> projectData = {
      "voxray_version": "1.5.0",
      "project_name": projectName,
      "original_file": originalFileName, 
      "original_file_path": originalFilePath, 
      "song_duration": songDuration,
      "is_original_mix_available": isOriginalMixAvailable,
      "mixer_state": mixerState.map((k, v) => MapEntry(k, v.toJson())),
      "target_stems_selection": targetStemsSelection.toList(),
      "generated_stems": generatedStems.toList(),
      "all_stems_notes": allStemsNotes,
      "active_editable_stem": activeEditableStem,
      "history": {"undo_stack": undoStack, "redo_stack": redoStack}
    };

    String jsonString = json.encode(projectData);
    List<int> jsonBytes = utf8.encode(jsonString);

    Archive archive = Archive();
    archive.addFile(ArchiveFile('project.json', jsonBytes.length, jsonBytes));

    if (originalAudioBytes != null) {
      archive.addFile(ArchiveFile('original_audio.dat', originalAudioBytes!.length, originalAudioBytes));
    }

    for (var entry in cachedStemBytes.entries) {
      archive.addFile(ArchiveFile('${entry.key}.ogg', entry.value.length, entry.value));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  Future<void> _saveVoxrayProject() async {
    if (currentProjectPath == null || kIsWeb) {
      await _saveVoxrayProjectAs();
      return;
    }
    
    final bytes = _packageProjectBytes();
    try {
      await File(currentProjectPath!).writeAsBytes(bytes);
      setState(() {
        hasBeenSaved = true;
        dirtyStems.clear();
      });
      _showSaveConfirmation("Project file successfully overwritten on disk.");
    } catch (e) { 
      _showSaveConfirmation("Overwrite failed: $e"); 
    }
  }

  Future<void> _saveVoxrayProjectAs() async {
    final bytes = _packageProjectBytes();
    
    String defaultSaveName = originalFileName.contains('.')
        ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
        : (originalFileName.isNotEmpty ? originalFileName : projectName);

    try {
      String? path = await FileSaver.instance.saveAs(
        name: defaultSaveName,
        bytes: bytes,
        fileExtension: 'vxp',
        mimeType: MimeType.custom,
        customMimeType: 'application/octet-stream',
      );
	  if (path != null && path.isNotEmpty) {
        setState(() {
          currentProjectPath = path;
          hasBeenSaved = true;
          dirtyStems.clear(); 
        });
        _showSaveConfirmation('Project saved successfully as offline .vxp archive.');
      } else {
        _showSaveConfirmation('Save cancelled.');
      }
    } catch (e) {
      debugPrint("Save error: $e");
      _showSaveConfirmation('Save failed: $e');
    }
  }

  Future<void> _loadVoxrayProject() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom, 
      allowedExtensions: ['vxp'], 
      withData: true,
    );
    
    if (result == null) return;
    
    String fileName = result.files.single.name.toLowerCase();
    if (!fileName.endsWith('.vxp')) {
      _showSaveConfirmation("Invalid format: Please select a valid Voxray (.vxp) project archive.");
      return;
    }
    
    pauseAllPlayers();

    Uint8List vxpBytes;
    if (result.files.single.bytes != null) {
      vxpBytes = result.files.single.bytes!;
    } else if (result.files.single.path != null) {
      vxpBytes = await File(result.files.single.path!).readAsBytes();
      currentProjectPath = result.files.single.path;
    } else {
      return;
    }

    setState(() {
      isPlaying = false;
      isLoading = true;
      processingMessage = "Unpacking .vxp archive and loading offline files...";
      
      isProjectLoaded = true;
      hasBeenSaved = true;
      dirtyStems.clear();

      cachedStemBytes.clear();
      for(var h in stemHandles.values) SoLoud.instance.stop(h);
      stemHandles.clear();
      stemSources.clear();
      activePlaybackSources.clear();
      allStemsNotes.clear();
      generatedStems.clear();
      if (masterHandle != null) SoLoud.instance.stop(masterHandle!);
      if (synthHandle != null) SoLoud.instance.stop(synthHandle!);
    });

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(vxpBytes);
    } catch (e) {
      setState(() { isLoading = false; processingMessage = ""; });
      _showSaveConfirmation("Failed to parse .vxp archive.");
      return;
    }

    Map<String, dynamic> projectData = {};
    for (ArchiveFile file in archive) {
      if (file.name == 'project.json') {
        projectData = json.decode(utf8.decode(file.content as List<int>));
      } else if (file.name == 'original_audio.dat') {
        originalAudioBytes = file.content as Uint8List;
      } else if (file.name.endsWith('.ogg')) {
        String stemName = file.name.replaceAll('.ogg', '');
        cachedStemBytes[stemName] = file.content as Uint8List;
      }
    }

    if (projectData.isEmpty) {
      setState(() { isLoading = false; processingMessage = ""; });
      _showSaveConfirmation("Invalid project format: missing JSON configuration.");
      return;
    }
    
    setState(() {
      projectName = projectData['project_name'] ?? "Voxray_Session";
      originalFileName = projectData['original_file'] ?? "Unknown File";
      originalFilePath = projectData['original_file_path'] ?? "";
      isOriginalMixAvailable = projectData['is_original_mix_available'] ?? true;

      if (projectData.containsKey('song_duration')) {
        songDuration = (projectData['song_duration'] as num).toDouble();
      } else {
        double maxTime = 30.0;
        if (projectData['all_stems_notes'] != null) {
          Map<String, dynamic> savedNotes = projectData['all_stems_notes'];
          savedNotes.forEach((stem, notesList) {
            for (var note in notesList) {
              double endTime = (note['end_time'] ?? 0.0).toDouble();
              if (endTime > maxTime) maxTime = endTime;
            }
          });
        }
        songDuration = maxTime;
      }
      
      loopEndBoundary = songDuration;
      int endIdx = markers.indexWhere((m) => m['id'] == 'mk_end');
      if (endIdx != -1) markers[endIdx]['time'] = songDuration;
      
      if (projectData['mixer_state'] != null) {
        Map<String, dynamic> ms = projectData['mixer_state'];
        mixerState = ms.map((k, v) => MapEntry(k, ChannelState.fromJson(v)));
      }
      
      if (projectData['target_stems_selection'] != null) {
        targetStemsSelection = Set<String>.from(projectData['target_stems_selection']);
      }
      if (projectData['generated_stems'] != null) {
        generatedStems = Set<String>.from(projectData['generated_stems']);
      }
      if (projectData['all_stems_notes'] != null) {
        allStemsNotes = Map<String, List<dynamic>>.from(projectData['all_stems_notes']);
      }
      activeEditableStem = projectData['active_editable_stem'] ?? '';
      
      if (projectData['history'] != null) {
        undoStack = List<String>.from(projectData['history']['undo_stack']);
        redoStack = List<String>.from(projectData['history']['redo_stack']);
      }
      if (rawNotes.isNotEmpty && rawNotes.first.containsKey('contour')) {
        isXrayMode = true;
      }
    });

    if (originalAudioBytes != null && isOriginalMixAvailable) {
       activePlaybackSources.add('original');
       try {
         masterSource = await SoLoud.instance.loadMem("master", originalAudioBytes!);
         masterHandle = SoLoud.instance.play(masterSource!, paused: true);
         
         ChannelState origState = getChannelState('original');
         SoLoud.instance.setVolume(masterHandle!, origState.isMuted ? 0.0 : origState.volume);
         SoLoud.instance.setPan(masterHandle!, origState.pan);
       } catch (e) {
         debugPrint("Offline master preview load failed (unsupported format): $e");
         _showSaveConfirmation("Warning: Original mix format unsupported by local player. Muted.");
       }
    }

    for (String stem in generatedStems) {
       if (cachedStemBytes.containsKey(stem)) {
          activePlaybackSources.add(stem); 
          await _loadStemPlayerSource(stem);
       }
    }

    if (rawNotes.isNotEmpty && rawNotes.first.containsKey('contour')) {
       await _loadSynthSource();
    }

    seekAllPlayers(0.0);

    setState(() { 
      currentPosition = 0.0;
      isLoading = false; 
      processingMessage = ""; 
    });
    _showSaveConfirmation("Project fully restored from offline archive.");
  }

  // --- TIMELINE & MARKER UTILS ---

  void addMarkerAtCurrentPlayhead() {
    double visualPlayheadTime = (horizontalScrollController.hasClients
        ? (horizontalScrollController.position.pixels + 150) / zoomX
        : currentPosition);
    
    visualPlayheadTime = visualPlayheadTime.clamp(0.0, songDuration);

    bool tooClose = markers.any((m) => 
        ((m['time'] as double) - visualPlayheadTime).abs() < 0.5);
    if (tooClose) return;

    setState(() {
      markers.add({
        "id": "mk_${DateTime.now().millisecondsSinceEpoch}",
        "time": visualPlayheadTime,
        "label": "Marker ${markers.length + 1}"
      });
    });
  }

  void setLoopFromMarkers(double start, double end) {
    setState(() {
      loopStartBoundary = start;
      loopEndBoundary = end;
    });
  }

  void deleteMarker(String id) {
    setState(() {
      markers.removeWhere((m) => m['id'] == id);
    });
  }

  // --- STUDIO MIXER UI ---

  void _applyMasterPlugins() {
    ChannelState state = getChannelState('master');
    List<String> plugins = [state.plugin1, state.plugin2, state.plugin3, state.plugin4];

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
      if (plugins.contains('EQ')) {
        //if (!SoLoud.instance.filters.eqFilter.isActive) {
          //SoLoud.instance.filters.eqFilter.activate();
        //}
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
      debugPrint("Master DSP activation failed: $e");
    }
  }

  void _showStudioMixer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setMixerState) {
              
              Widget buildChannelStrip(String title, String key, Color highlight, {bool isMaster = false}) {
                ChannelState state = getChannelState(key);
                bool isAudible = activePlaybackSources.contains(key) || (isMaster && activePlaybackSources.isNotEmpty);
                
                double simulatedMeterValue = 0.0;
                if (isPlaying && isAudible) {
                  simulatedMeterValue = 0.3 + (math.Random().nextDouble() * 0.6); 
                  simulatedMeterValue *= state.volume;
                }

                return Container(
                  width: 68, 
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: isMaster ? Colors.redAccent.withOpacity(0.1) : Colors.black87,
                    border: Border.all(color: isMaster ? Colors.redAccent : Colors.white24),
                    borderRadius: BorderRadius.circular(6)
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text(title, style: TextStyle(color: highlight, fontWeight: FontWeight.bold, fontSize: 10), overflow: TextOverflow.ellipsis),
                      ),
                      
                      // DB Meter Simulation
                      Container(
                        height: 6,
                        width: 48,
                        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(3)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: simulatedMeterValue.clamp(0.0, 1.0),
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(colors: [Colors.green, Colors.yellow, Colors.red])
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Plugins
                      _pluginDropdown(state.plugin1, highlight, (val) {
                         if(state.plugin1 != val) {
                             setMixerState(() => state.plugin1 = val!);
                             this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                             if (!isMaster) _renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      _pluginDropdown(state.plugin2, highlight, (val) {
                         if(state.plugin2 != val) {
                             setMixerState(() => state.plugin2 = val!);
                             this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                             if (!isMaster) _renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      _pluginDropdown(state.plugin3, highlight, (val) {
                         if(state.plugin3 != val) {
                             setMixerState(() => state.plugin3 = val!);
                             this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                             if (!isMaster) _renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      _pluginDropdown(state.plugin4, highlight, (val) {
                         if(state.plugin4 != val) {
                             setMixerState(() => state.plugin4 = val!);
                             this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                             if (!isMaster) _renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      
                      const SizedBox(height: 4),

                      if (!isMaster)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(state.isMuted ? Icons.volume_off : Icons.volume_up, color: !state.isMuted ? highlight : Colors.white38, size: 18),
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
                      
                      // Vertical Fader
                      Expanded(
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
                              min: 0.0, 
                              max: 1.5, 
                              onChanged: (v) {
                                setMixerState(() => state.volume = v);
                                this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                                if (state.isMuted) return;
                                
                                // Volume Slider Fix
                                if (key == 'master') {
                                  SoLoud.instance.setGlobalVolume(v);
                                } else if (key == 'original') {
                                  if (masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) SoLoud.instance.setVolume(masterHandle!, v);
                                } else if (key == 'synth') {
                                  if (synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(synthHandle!)) SoLoud.instance.setVolume(synthHandle!, v);
                                } else if (stemHandles.containsKey(key)) {
                                  if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[key]!)) SoLoud.instance.setVolume(stemHandles[key]!, v);
                                }
                              }
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text("${(state.volume * 100).round()}%", style: const TextStyle(fontSize: 9, color: Colors.white54)),
                      const SizedBox(height: 6),

                      // Pan Slider
                      SizedBox(
                        height: 16,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: highlight,
                            inactiveTrackColor: Colors.white10,
                          ),
                          child: Slider(
                            value: state.pan, 
                            min: -1.0, 
                            max: 1.0, 
                            onChanged: (v) {
                              setMixerState(() => state.pan = v);
                              this.setState(() { dirtyStems.add(key); hasBeenSaved = false; });
                              
                              // Pan Slider Fix
                              if (key == 'master') {
                                if (masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) SoLoud.instance.setPan(masterHandle!, v);
                                if (synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(synthHandle!)) SoLoud.instance.setPan(synthHandle!, v);
                                for (var handle in stemHandles.values) {
                                  if (SoLoud.instance.getIsValidVoiceHandle(handle)) SoLoud.instance.setPan(handle, v);
                                }
                              } else if (key == 'original') {
                                if (masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(masterHandle!)) SoLoud.instance.setPan(masterHandle!, v);
                              } else if (key == 'synth') {
                                if (synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(synthHandle!)) SoLoud.instance.setPan(synthHandle!, v);
                              } else if (stemHandles.containsKey(key)) {
                                if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[key]!)) SoLoud.instance.setPan(stemHandles[key]!, v);
                              }
                            }
                          ),
                        ),
                      ),
                      Text(state.pan == 0 ? "C" : (state.pan < 0 ? "L ${-(state.pan * 100).round()}" : "R ${(state.pan * 100).round()}"), style: const TextStyle(fontSize: 8, color: Colors.white54)),
                      const SizedBox(height: 6),
                    ],
                  ),
                );
              }

              return Container(
                height: MediaQuery.of(context).size.height * 0.52,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: const Border(top: BorderSide(color: Colors.white24))
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("STUDIO MIXER", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context))
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        children: [
                          if (isOriginalMixAvailable) buildChannelStrip("MIX", "original", Colors.blueGrey),
                          buildChannelStrip("SYNTH", "synth", Colors.purpleAccent),
                          ...targetStemsSelection.map((stem) => buildChannelStrip(stem.toUpperCase(), stem, Colors.tealAccent)),
                          const SizedBox(width: 12),
                          buildChannelStrip("MASTER", "master", Colors.redAccent, isMaster: true),
                        ],
                      ),
                    )
                  ],
                ),
              );
            }
          ),
        );
      }
    );
  }

  Widget _pluginDropdown(String currentValue, Color highlightColor, ValueChanged<String?> onChanged) {
    return Container(
      height: 20,
      width: 62,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(3)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          dropdownColor: Colors.grey[850],
          iconSize: 10,
          style: TextStyle(fontSize: 8, color: currentValue == 'None' ? Colors.white38 : highlightColor),
          value: currentValue,
          items: ['None', 'Compressor', 'EQ', 'Reverb', 'De-esser'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

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
                    const Text("Plays back the note grid's pitch data directly — "
                        "useful for verifying detected pitches independent of the original recording.",
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 16),
                    const Text('Waveform', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.0)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: Waveform.values.map((w) {
                        bool selected = synthSettings.waveform == w;
                        return ChoiceChip(
                          label: Text(w.label, style: TextStyle(fontSize: 12, color: selected ? Colors.black : Colors.white70)),
                          selected: selected,
                          selectedColor: Colors.tealAccent,
                          backgroundColor: Colors.white10,
                          onSelected: (_) => update((s) => s.copyWith(waveform: w)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Envelope (ADSR)', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.0)),
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
                          child: Text("Full X-Ray pitch tracking\n(off = basic note values)",
                              style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                        Switch(
                          value: synthSettings.useXrayContour,
                          activeColor: Colors.amberAccent,
                          onChanged: (v) => update((s) => s.copyWith(useXrayContour: v)),
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
                  _refreshSynthLayerIfActive();
                },
                child: const Text('Close', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent.withOpacity(0.2)),
                icon: const Icon(Icons.play_arrow, color: Colors.tealAccent, size: 16),
                label: const Text('Preview Synth', style: TextStyle(color: Colors.tealAccent)),
                onPressed: rawNotes.isEmpty ? null : () async {
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

  Widget _synthSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))),
        Expanded(child: Slider(value: value, min: min, max: max, activeColor: Colors.tealAccent, onChanged: onChanged)),
        SizedBox(width: 36, child: Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.white54, fontSize: 10))),
      ],
    );
  }

  void _showAdvancedDownloadsDialog() {
    if (rawNotes.isEmpty || originalAudioBytes == null) {
      _showSaveConfirmation("No active project to export.");
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Advanced Downloads", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.multitrack_audio, color: Colors.amberAccent, size: 28),
                title: const Text("Export Master Mix", style: TextStyle(color: Colors.white)),
                subtitle: const Text("WAV / FLAC / MP3", style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () { Navigator.pop(context); _showExportDialog(); }
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.piano, color: Colors.purpleAccent, size: 28),
                title: const Text("Export Synth Audio", style: TextStyle(color: Colors.white)),
                subtitle: const Text("WAV format", style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () { Navigator.pop(context); _exportSynthAudio(); }
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.analytics, color: Colors.tealAccent, size: 28),
                title: const Text("Forensic Dossier", style: TextStyle(color: Colors.white)),
                subtitle: const Text("PDF Report", style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () { Navigator.pop(context); _downloadDossier(); }
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.fingerprint, color: Colors.blueAccent, size: 28),
                title: const Text("PitchPrint™ Graph", style: TextStyle(color: Colors.white)),
                subtitle: const Text("Vector / High-Res", style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () { Navigator.pop(context); _showPitchPrintOptions(); }
              ),
            ]
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text("Cancel", style: TextStyle(color: Colors.white54))
            )
          ],
        );
      }
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Export Format", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.audio_file, color: Colors.tealAccent, size: 30),
                title: const Text("WAV", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Lossless / Studio Quality", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); _exportFinalMaster('wav'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.library_music, color: Colors.amberAccent, size: 30),
                title: const Text("FLAC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Lossless / Compressed Size", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); _exportFinalMaster('flac'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.music_note, color: Colors.blueAccent, size: 30),
                title: const Text("MP3", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Standard / Web Optimized", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); _exportFinalMaster('mp3'); },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54)))
          ],
        );
      }
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
              const Text(
                'Generate a high-resolution pitch analysis graph.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      value: true,
                      groupValue: fullSong,
                      activeColor: Colors.amberAccent,
                      title: const Text('Full Song', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Complete performance analysis', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      onChanged: (v) => setDialogState(() => fullSong = v!),
                    ),
                    RadioListTile<bool>(
                      value: false,
                      groupValue: fullSong,
                      activeColor: Colors.amberAccent,
                      title: const Text('Visible Region', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Current timeline view only', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      onChanged: (v) => setDialogState(() => fullSong = v!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.tealAccent, size: 30),
                title: const Text("SVG Vector", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Scalable Vector Graphics", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); _downloadPitchPrint(fullSong: fullSong, format: 'svg'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.photo, color: Colors.amberAccent, size: 30),
                title: const Text("PNG Image", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("High-Resolution Image", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); _downloadPitchPrint(fullSong: fullSong, format: 'png'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.blueAccent, size: 30),
                title: const Text("PDF Print", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Print-ready Document", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); _downloadPitchPrint(fullSong: fullSong, format: 'pdf'); },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ],
        ),
      ),
    );
  }

  void _showDossier() {
    if (rawNotes.isEmpty) return;

    String midiToName(num midi) {
      const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
      int m = midi.round();
      return '${noteNames[m % 12]}${(m ~/ 12) - 1}';
    }

    int totalNotes = 0;
    double totalError = 0;
    int perfectlyTuned = 0;
    int mutedCount = 0;
    int deletedCount = 0;

    Map<String, List<double>> noteErrors = {};

    bool hasXray = rawNotes.any((n) => n.containsKey('contour') && n['contour'] != null);

    for (var note in rawNotes) {
      if (note['isDeleted'] == true) { deletedCount++; continue; }
      
      double baseMidi = (note['actual_midi'] ?? 60.0).toDouble();
      int semitoneShift = note['semitone_shift'] ?? 0;
      baseMidi += semitoneShift; 
      
      if (baseMidi.round() == 36) continue; 

      if (note['isMuted'] == true) mutedCount++;
      totalNotes++;

      double effectiveCents;

      if (note['contour'] != null && (note['contour'] as List).isNotEmpty) {
        List<dynamic> contour = note['contour'];
        double avgDrift = contour.map((c) => (c as num).toDouble().abs()).reduce((a, b) => a + b) / contour.length;
        effectiveCents = avgDrift;
      } else {
        double rawCents = (baseMidi - baseMidi.round()) * 100;
        double shiftCents = (note['cents_shift'] ?? 0).toDouble();
        effectiveCents = (rawCents + shiftCents).abs();
      }

      totalError += effectiveCents;
      if (effectiveCents <= 10) perfectlyTuned++;

      String name = midiToName(baseMidi.round());
      noteErrors.putIfAbsent(name, () => []);
      noteErrors[name]!.add(effectiveCents);
    }

    double avgError = totalNotes > 0 ? totalError / totalNotes : 0;
    double tunedPct = totalNotes > 0 ? (perfectlyTuned / totalNotes) * 100 : 0;

    var worstNotes = noteErrors.entries.toList()
      ..sort((a, b) {
        double aAvg = a.value.reduce((x, y) => x + y) / a.value.length;
        double bAvg = b.value.reduce((x, y) => x + y) / b.value.length;
        return bAvg.compareTo(aAvg);
      });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Row(
          children: [
            Text("Dossier: ${activeEditableStem.toUpperCase()}", style: const TextStyle(color: Colors.white)),
            const Spacer(),
            if (hasXray)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.fingerprint, color: Colors.amberAccent, size: 14),
                  SizedBox(width: 4),
                  Text('X-Ray', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                ]),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                child: const Text('X-Ray not enabled', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("SUMMARY", style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              _dossierRow("Notes analyzed", "$totalNotes"),
              _dossierRow("Muted notes", "$mutedCount"),
              _dossierRow("Deleted notes", "$deletedCount"),
              const SizedBox(height: 10),

              const Text("PITCH ACCURACY", style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              if (!hasXray)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.info_outline, color: Colors.white38, size: 14),
                    SizedBox(width: 8),
                    Flexible(child: Text(
                      'Enable X-Ray mode for detailed pitch contour analysis. Basic MIDI deviation shown below.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    )),
                  ]),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.07), borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.fingerprint, color: Colors.amberAccent, size: 14),
                    SizedBox(width: 8),
                    Flexible(child: Text(
                      'X-Ray pitch contour data active. Variance reflects real pitch drift within each note.',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                    )),
                  ]),
                ),
              const SizedBox(height: 10),
              _dossierRow("Avg pitch error", "${avgError.toStringAsFixed(1)} ¢"),
              _dossierRow("Studio-accurate (≤10¢)", "${tunedPct.toStringAsFixed(1)}%"),
              const SizedBox(height: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: tunedPct / 100,
                  backgroundColor: Colors.redAccent.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    tunedPct >= 80 ? Colors.tealAccent
                    : tunedPct >= 50 ? Colors.amberAccent
                    : Colors.redAccent,
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),

              if (worstNotes.isNotEmpty) ...[
                const Text("MOST VARIANCE BY NOTE", style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                ...worstNotes.take(5).map((entry) {
                  double avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
                  Color c = avg <= 10 ? Colors.tealAccent : avg <= 25 ? Colors.amberAccent : Colors.redAccent;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      SizedBox(width: 36, child: Text(entry.key, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                      const SizedBox(width: 8),
                      Expanded(child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (avg / 100).clamp(0.0, 1.0),
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(c),
                          minHeight: 6,
                        ),
                      )),
                      const SizedBox(width: 8),
                      Text('${avg.toStringAsFixed(1)}¢', style: TextStyle(color: c, fontSize: 11)),
                      Text(' ×${entry.value.length}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ]),
                  );
                }),
                const SizedBox(height: 16),
              ],

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: avgError < 15 ? Colors.teal.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: avgError < 15 ? Colors.tealAccent.withOpacity(0.4) : Colors.redAccent.withOpacity(0.4)),
                ),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    children: avgError < 10
                        ? [const TextSpan(text: "VERDICT: Exceptional intonation. Studio-ready performance.", style: TextStyle(color: Colors.tealAccent))]
                        : avgError < 15
                            ? [const TextSpan(text: "VERDICT: Highly accurate. Minor touch-ups may be desired.", style: TextStyle(color: Colors.tealAccent))]
                            : avgError < 25
                                ? [
                                    const TextSpan(text: "VERDICT: Moderate variance detected. Pitch correction and autotune don't appear to have been used! ", style: TextStyle(color: Colors.tealAccent)),
                                    const TextSpan(text: "On flagged notes, the tuning could be improved audibly.", style: TextStyle(color: Colors.redAccent))
                                  ]
                                : [const TextSpan(text: "VERDICT: Significant tuning issues. Review red-flagged notes in the piano roll.", style: TextStyle(color: Colors.redAccent))],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
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
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showSaveConfirmation(String message, {bool isPreview = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: isPreview ? Colors.white : Colors.orange)),
        backgroundColor: isPreview ? Colors.deepPurple[800] : Colors.black,
        duration: Duration(seconds: isPreview ? 6 : 4),
        action: isPreview
            ? SnackBarAction(
                label: 'Play',
                textColor: Colors.deepPurpleAccent,
                onPressed: () => playAllPlayers(),
              )
            : null,
      ),
    );
  }

  void _showStemSelectorTreeDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setTreeState) {
          Widget buildStemCheckbox(String stem) {
            bool isSuggested = suggestedStems.contains(stem);
            return CheckboxListTile(
              dense: true,
              title: Row(
                children: [
                  Text(stem, style: TextStyle(fontSize: 13, color: isSuggested ? Colors.yellowAccent : Colors.white70)),
                  if (isSuggested) 
                    const Padding(
                      padding: EdgeInsets.only(left: 6.0), 
                      child: Text("RECOMMENDED", style: TextStyle(fontSize: 9, color: Colors.yellowAccent, fontWeight: FontWeight.bold))
                    ),
                ],
              ),
              value: targetStemsSelection.contains(stem),
              activeColor: Colors.tealAccent,
              onChanged: (bool? checked) {
                setTreeState(() {
                  if (checked == true) {
                    targetStemsSelection.add(stem);
                  } else {
                    targetStemsSelection.remove(stem);
                  }
                });
                setState(() {});
              },
            );
          }

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text("Stem Extraction Matrix", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Select which stems will be available in the dropdown to generate later.", style: TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 10),
                    const Text("POP & ROCK MODELS", style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ...popStems.map((s) => buildStemCheckbox(s)),
                    const Divider(color: Colors.white24),
                    const Text("ORCHESTRAL MODELS", style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ...orchStems.map((s) => buildStemCheckbox(s)),
                    const Divider(color: Colors.white24),
                    const Text("FORENSIC SUITE", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ...forensicStems.map((s) => buildStemCheckbox(s)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text("Confirm Selection", style: TextStyle(color: Colors.tealAccent))
              )
            ],
          );
        }
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMainMenu() {
    bool canSave = isProjectLoaded && (!hasBeenSaved || dirtyStems.isNotEmpty || undoStack.isNotEmpty);
    bool canSaveAs = isProjectLoaded;

    return [
      const PopupMenuItem(value: 'new_project', child: ListTile(leading: Icon(Icons.insert_drive_file, color: Colors.redAccent), title: Text('New Project'))),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'upload', child: ListTile(leading: Icon(Icons.cloud_upload, color: Colors.tealAccent), title: Text('Upload Audio Mix'))),
      const PopupMenuItem(value: 'import_stem', child: ListTile(leading: Icon(Icons.file_open, color: Colors.tealAccent), title: Text('Import Individual Track'))),
      const PopupMenuItem(value: 'stem_tree', child: ListTile(leading: Icon(Icons.account_tree, color: Colors.purpleAccent), title: Text('Stem Select Tree'))),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'load', child: ListTile(leading: Icon(Icons.folder_open), title: Text('Load Project'))),
      PopupMenuItem(value: 'save', enabled: canSave, child: ListTile(leading: Icon(Icons.save, color: canSave ? Colors.blueAccent : Colors.white38), title: Text('Save Project (Overwrite)', style: TextStyle(color: canSave ? Colors.white : Colors.white38)))),
      PopupMenuItem(value: 'save_as', enabled: canSaveAs, child: ListTile(leading: Icon(Icons.save_as, color: canSaveAs ? Colors.white : Colors.white38), title: Text('Save Project As...', style: TextStyle(color: canSaveAs ? Colors.white : Colors.white38)))),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'processing_mode', 
        child: ListTile(
          leading: Icon(processingMode == 'advanced' ? Icons.auto_awesome : Icons.blur_linear, color: Colors.purpleAccent),
          title: Text(processingMode == 'advanced' ? 'Mode: ADVANCED' : 'Mode: NORMAL', style: const TextStyle(color: Colors.purpleAccent)),
        )
      ),
      const PopupMenuItem(value: 'synth_settings', child: ListTile(leading: Icon(Icons.piano, color: Colors.purpleAccent), title: Text('Synth Audio Settings'))),
      const PopupMenuItem(value: 'show_dossier', child: ListTile(leading: Icon(Icons.assessment, color: Colors.greenAccent), title: Text('View GUI Dossier'))),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'downloads', child: ListTile(leading: Icon(Icons.download, color: Colors.blueAccent), title: Text('Advanced Downloads'))),
      const PopupMenuItem(value: 'export_stems', child: ListTile(leading: Icon(Icons.unarchive, color: Colors.amberAccent), title: Text('Export Stems Archive'))),
      PopupMenuItem(
        value: 'live_mode', 
        child: ListTile(
          leading: Icon(Icons.mic_external_on, color: isLiveModeActive ? Colors.redAccent : Colors.white), 
          title: Text(isLiveModeActive ? 'Disable Live Pedagogy' : 'Enable Live Pedagogy', style: TextStyle(color: isLiveModeActive ? Colors.redAccent : Colors.white))
        )
      ),
      const PopupMenuItem(
        value: 'reprocess', 
        child: ListTile(
          leading: Icon(Icons.sync_problem, color: Colors.orangeAccent), 
          title: Text('Reprocess X-Ray', style: TextStyle(color: Colors.orangeAccent)),
        )
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'test_mode', 
        child: ListTile(
          leading: Icon(Icons.bug_report, color: isTestModeActive ? Colors.redAccent : Colors.white38), 
          title: Text(isTestModeActive ? 'Disable MOCK API Mode' : 'Enable MOCK API Mode', style: TextStyle(color: isTestModeActive ? Colors.redAccent : Colors.white))
        )
      ),
    ];
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'new_project': _newProject(); break;
      case 'upload': _loadFileAndAnalyze(); break;
      case 'import_stem': _importIndividualStem(); break;
      case 'stem_tree': _showStemSelectorTreeDialog(); break;
      case 'load': _loadVoxrayProject(); break;
      case 'save': _saveVoxrayProject(); break;
      case 'save_as': _saveVoxrayProjectAs(); break;
      case 'export_stems': _exportStemsAsZip(); break;
      case 'processing_mode': setState(() => processingMode = processingMode == 'classic' ? 'advanced' : 'classic'); break;
      case 'synth_settings': _showSynthSettingsDialog(); break;
      case 'show_dossier': _showDossier(); break;
      case 'downloads': _showAdvancedDownloadsDialog(); break;
      case 'live_mode': setState(() => isLiveModeActive = !isLiveModeActive); break;
      case 'reprocess': _forceReprocessXray(); break;
      case 'test_mode': setState(() => isTestModeActive = !isTestModeActive); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isCurrentStemGenerated = generatedStems.contains(activeEditableStem);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('voXRAY ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
              child: const Text('PRO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white)),
            ),
            const SizedBox(width: 8),
            const Text('Forensic Daw', style: TextStyle(fontWeight: FontWeight.w300, fontSize: 14, color: Colors.white70)),
          ],
        ),
        actions: [
          if (!isLiveModeActive)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: "Main Menu",
              onSelected: _handleMenuSelection,
              itemBuilder: (context) => _buildMainMenu(),
            ),
        ],
      ),
      body: SafeArea(
        child: isLiveModeActive
            ? LivePedagogyView(
                onExit: () => setState(() => isLiveModeActive = false) 
              )
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.audio_file, size: 14, color: Colors.white54),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                originalFileName != "Unknown File" 
                                    ? "$originalFileName" + (activeEditableStem.isNotEmpty ? "  [STEM: ${activeEditableStem.toUpperCase()}]" : "") 
                                    : "No File Loaded",
                                style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              )
                            ),
                            if (projectName != "Voxray_Session")
                              Text(' [$projectName]', style: const TextStyle(fontSize: 12, color: Colors.white38)),
                          ]
                        ),
                        if (isLoading) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(child: LinearProgressIndicator(value: processingProgress, color: Colors.tealAccent, backgroundColor: Colors.grey[800])),
                              const SizedBox(width: 8),
                              Text(processingMessage, style: const TextStyle(fontSize: 10, color: Colors.tealAccent)),
                            ],
                          )
                        ] else if (isPreviewing || isExporting || isSynthRendering) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(child: LinearProgressIndicator(value: processingProgress, color: Colors.amberAccent, backgroundColor: Colors.grey[800])),
                              const SizedBox(width: 8),
                              Text(exportMessage.isNotEmpty ? exportMessage : synthMessage, style: const TextStyle(fontSize: 10, color: Colors.amberAccent)),
                            ],
                          )
                        ]
                      ],
                    )
                  ),

                  // Integrated Tool Strip
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    color: Colors.black26,
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.start,
                      children: [
                        IconButton(icon: const Icon(Icons.undo), tooltip: 'Undo', onPressed: undoStack.isNotEmpty ? _undo : null),
                        IconButton(icon: const Icon(Icons.redo), tooltip: 'Redo', onPressed: redoStack.isNotEmpty ? _redo : null),
                        
                        Tooltip(
                          message: "Preview pitch/DSP edits",
                          child: IconButton(
                            icon: const Icon(Icons.preview, color: Colors.deepPurpleAccent, size: 24),
                            // Button only active if there are un-previewed changes on the current active stem
                            onPressed: (rawNotes.isNotEmpty && originalAudioBytes != null && !isPreviewing && !isExporting && dirtyStems.contains(activeEditableStem)) ? _renderStemEdits : null,
                          ),
                        ),

                        const SizedBox(width: 8),
                        IconButton(icon: const Icon(Icons.tune, color: Colors.orangeAccent), tooltip: 'Studio Mixer', onPressed: _showStudioMixer),
                        IconButton(icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 26), onPressed: _toggleMasterTransport),
                        
                        if (targetStemsSelection.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: DropdownButton<String>(
                            value: targetStemsSelection.contains(activeEditableStem) && activeEditableStem.isNotEmpty ? activeEditableStem : null,
                            dropdownColor: Colors.grey[900],
                            underline: const SizedBox(),
                            hint: const Text("No Stems Available", style: TextStyle(color: Colors.white38, fontSize: 12)),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.tealAccent),
                            style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 13),
                            items: targetStemsSelection.map((String stemKey) {
                              bool isSuggested = suggestedStems.contains(stemKey);
                              return DropdownMenuItem<String>(
                                value: stemKey,
                                child: Row(
                                  children: [
                                    Text(stemKey.toUpperCase(), style: TextStyle(color: isSuggested ? Colors.yellowAccent : Colors.white)),
                                    if (isSuggested) 
                                       const Padding(padding: EdgeInsets.only(left: 4.0), child: Icon(Icons.star, size: 12, color: Colors.yellowAccent)),
                                    if (!generatedStems.contains(stemKey)) 
                                       const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.hourglass_empty, size: 14, color: Colors.white38))
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newSelection) {
                              if (newSelection != null && newSelection != activeEditableStem) {
                                // FIXED: Evaluate new stem's X-Ray state dynamically when dropdown changes
                                setState(() {
                                    activeEditableStem = newSelection;
                                    isXrayMode = rawNotes.isNotEmpty && rawNotes.any((n) => n.containsKey('contour') && n['contour'] != null);
                                });
                                
                                if (!generatedStems.contains(newSelection) && 
                                    originalAudioBytes != null && 
                                    currentTaskId != null && 
                                    !isLoading) {
                                  _generateStemOnDemand(newSelection);
                                }
                              }
                            },
                          ),
                        ),

                        PopupMenuButton<DragMode>(
                          icon: Icon(Icons.pan_tool, color: currentDragMode != DragMode.off ? Colors.amberAccent : Colors.white38),
                          tooltip: 'Drag Pitch Mode',
                          onSelected: (val) => setState(() => currentDragMode = val),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: DragMode.off, child: Text('Normal (Off)')),
                            PopupMenuItem(value: DragMode.semitone, child: Text('Semitone Drag')),
                            PopupMenuItem(value: DragMode.microTuning, child: Text('Micro-Tuning Drag')),
                          ],
                        ),

                        IconButton(icon: Icon(Icons.touch_app, color: isScrubMode ? Colors.amberAccent : Colors.white38, size: 22), onPressed: () => setState(() => isScrubMode = !isScrubMode)),
                        isXrayProcessing 
                          ? const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent)))
                          : IconButton(icon: Icon(Icons.fingerprint, color: isXrayMode ? Colors.amberAccent : Colors.white38, size: 22), onPressed: isCurrentStemGenerated ? _toggleXrayMode : null),
                        IconButton(icon: Icon(Icons.loop, color: isLoopModeActive ? Colors.tealAccent : Colors.white38, size: 22), onPressed: () => setState(() => isLoopModeActive = !isLoopModeActive)),
                        IconButton(icon: const Icon(Icons.add_location_alt, size: 20, color: Colors.amberAccent), onPressed: addMarkerAtCurrentPlayhead),
                        
                        if (markers.isNotEmpty)
                          PopupMenuButton<double>(
                            icon: const Icon(Icons.location_on, color: Colors.amberAccent, size: 20),
                            tooltip: "Go to Marker",
                            itemBuilder: (context) => markers.map((marker) {
                              int totalSeconds = (marker['time'] as double).round();
                              String timestamp = '${(totalSeconds ~/ 60).toString().padLeft(2, '0')}:${(totalSeconds % 60).toString().padLeft(2, '0')}';
                              return PopupMenuItem<double>(
                                value: marker['time'],
                                child: Row(children: [
                                  const Icon(Icons.location_on, color: Colors.amberAccent, size: 16),
                                  const SizedBox(width: 8),
                                  Text('${marker['label']}  '),
                                  Text(timestamp, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                ]),
                              );
                            }).toList(),
                            onSelected: (time) => jumpToTimelinePosition(time),
                          ),
                        if (markers.length >= 2) ...[
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.settings_overscan, size: 18, color: Colors.blueAccent),
                            tooltip: "Set Loop Region",
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
                        ],
                      ],
                    ),
                  ),
                  
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

                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(width: 46, height: 45, color: Colors.grey[900]), 
                            Expanded(
                              child: SingleChildScrollView(
                                controller: rulerScrollController,
                                scrollDirection: Axis.horizontal,
                                child: TimelineRulerWidget(dawState: this),
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Row(
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
                                          Text("The ${activeEditableStem.isNotEmpty ? activeEditableStem.toUpperCase() : 'selected'} stem has not been extracted yet.", style: const TextStyle(color: Colors.white54)),
                                          const SizedBox(height: 24),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                                            icon: const Icon(Icons.build),
                                            label: Text("Generate & Analyze ${activeEditableStem.isNotEmpty ? activeEditableStem.toUpperCase() : ''}"),
                                            onPressed: isLoading || activeEditableStem.isEmpty ? null : () => _generateStemOnDemand(activeEditableStem),
                                          )
                                        ],
                                      ),
                                    )
                                  : TimelineCanvasWidget(
                                      dawState: this,
                                      horizontalScrollController: horizontalScrollController,
                                      verticalScrollController: verticalScrollController,
                                    ), 
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
