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
  
  Map<String, List<dynamic>> allStemsNotes = {
    'vocals': []
  };
  String activeEditableStem = 'vocals'; 

  Set<String> targetStemsSelection = {'vocals', 'instrumental'};
  Set<String> generatedStems = {}; 
  List<String> suggestedStems = []; 
  
  // State flags for project management
  bool isOriginalMixAvailable = false; 
  bool isTestModeActive = false; 
  bool isProjectLoaded = false;
  bool hasBeenSaved = false;
  Set<String> dirtyStems = {}; 

  List<dynamic> get rawNotes => allStemsNotes[activeEditableStem] ?? [];
  set rawNotes(List<dynamic> updatedNotes) {
    allStemsNotes[activeEditableStem] = updatedNotes;
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
  
  final int minMidi = 36;
  final int maxMidi = 84;

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
            double targetY = ((maxMidi - medianMidi) * zoomY) - (viewportHeight / 2);
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
    setState(() {
      undoStack.add(json.encode(allStemsNotes));
      redoStack.clear();
      cachedStemBytes.remove(activeEditableStem);
      dirtyStems.add(activeEditableStem); 
    });
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
    double viewportCenterX = horizontalScrollController.position.pixels + (horizontalScrollController.position.viewportDimension / 2);
    double centerTime = viewportCenterX / zoomX;
    
    setState(() => zoomX = newZoom);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      double newScrollX = (centerTime * zoomX) - (horizontalScrollController.position.viewportDimension / 2);
      horizontalScrollController.jumpTo(newScrollX.clamp(0.0, horizontalScrollController.position.maxScrollExtent));
    });
  }

  void setZoomY(double newZoom) {
    if (!verticalScrollController.hasClients) {
      setState(() => zoomY = newZoom);
      return;
    }
    double viewportCenterY = verticalScrollController.position.pixels + (verticalScrollController.position.viewportDimension / 2);
    double centerMidi = maxMidi - (viewportCenterY / zoomY);
    
    setState(() => zoomY = newZoom);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      double newScrollY = ((maxMidi - centerMidi) * zoomY) - (verticalScrollController.position.viewportDimension / 2);
      verticalScrollController.jumpTo(newScrollY.clamp(0.0, verticalScrollController.position.maxScrollExtent));
    });
  }

  // ============================================================
  // MULTI-SOURCE NATIVE PLAYBACK MIXER (SoLoud)
  // ============================================================

  void seekAllPlayers(double seconds) {
    final time = Duration(milliseconds: (seconds * 1000).round());
    if (masterHandle != null) SoLoud.instance.seek(masterHandle!, time);
    if (synthHandle != null) SoLoud.instance.seek(synthHandle!, time);
    for (var handle in stemHandles.values) {
      SoLoud.instance.seek(handle, time);
    }
  }

  void playAllPlayers() {
    setState(() => isPlaying = true);
    if (masterHandle != null) SoLoud.instance.setPause(masterHandle!, false);
    if (synthHandle != null) SoLoud.instance.setPause(synthHandle!, false);
    for (var handle in stemHandles.values) {
      SoLoud.instance.setPause(handle, false);
    }
  }

  void pauseAllPlayers() {
    setState(() => isPlaying = false);
    if (masterHandle != null) SoLoud.instance.setPause(masterHandle!, true);
    if (synthHandle != null) SoLoud.instance.setPause(synthHandle!, true);
    for (var handle in stemHandles.values) {
      SoLoud.instance.setPause(handle, true);
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

  void _newProject() {
    setState(() {
      isProjectLoaded = false;
      hasBeenSaved = false;
      dirtyStems.clear();
      
      originalAudioBytes = null;
      originalFileName = "Unknown File";
      originalFilePath = "";
      projectName = "Voxray_Session";
      
      cachedStemBytes.clear();
      for(var h in stemHandles.values) SoLoud.instance.stop(h);
      stemHandles.clear();
      stemSources.clear();
      activePlaybackSources.clear();
      allStemsNotes.clear();
      generatedStems.clear();
      undoStack.clear();
      redoStack.clear();
      
      if (masterHandle != null) SoLoud.instance.stop(masterHandle!);
      if (synthHandle != null) SoLoud.instance.stop(synthHandle!);
      masterHandle = null;
      masterSource = null;
      synthHandle = null;
      synthSource = null;
      
      currentTaskId = null;
      currentJobId = null;
      suggestedStems.clear();
    });
  }

  Future<void> _requestSnippetSplice(Map<String, dynamic> modifiedNote) async {
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
        processingMessage = "Caching Full Mix & Extracting Forensic ID...";
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

      if (uploadOptions['type'] == 'mix') {
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

            final allStemsMap = result['all_stems_notes'];
            if (allStemsMap != null) {
              allStemsMap.forEach((key, value) {
                allStemsNotes[key] = json.decode(json.encode(value));
                generatedStems.add(key);
              });
            } else {
              allStemsNotes[targetStem] = json.decode(json.encode(result['notes'] ?? []));
              generatedStems.add(targetStem);
            }

            setState(() {
              if (!activePlaybackSources.contains(targetStem)) {
                activePlaybackSources.add(targetStem); 
              }
              
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
    if (rawNotes.isEmpty || currentTaskId == null) return;

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

    setState(() { 
      isXrayProcessing = true; 
      isXrayMode = true; 
    });

    try {
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
    }
  }

  Future<void> _toggleXrayMode() async {
    if (rawNotes.isEmpty || currentTaskId == null) return;
    
    if (isXrayMode || rawNotes.any((n) => n.containsKey('contour'))) {
      setState(() => isXrayMode = !isXrayMode);
      return;
    }

    setState(() { isXrayProcessing = true; isXrayMode = true; });

    try {
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
      setState(() => isXrayMode = false);
    } finally {
      setState(() { isXrayProcessing = false; });
    }
  }

  Future<Uint8List> _fetchStemBytes(String stemName) async {
    if (currentTaskId == null) throw Exception("No active session");
    final stemRes = await http.get(Uri.parse('$apiBase/api/stem/$currentTaskId/$stemName?format=ogg'));
    if (stemRes.statusCode == 200) return stemRes.bodyBytes;
    throw Exception("Stem fetch error ${stemRes.statusCode}");
  }

  Future<void> _loadStemPlayerSource(String stemName) async {
    if (originalAudioBytes == null) return;
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
        // slight delay allows memory buffers to settle
        await Future.delayed(const Duration(milliseconds: 50));
        playAllPlayers();
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
      
      SoLoud.instance.setVolume(synthHandle!, getChannelState('synth').volume);
      SoLoud.instance.setPan(synthHandle!, getChannelState('synth').pan); 
    } catch (e) {
      debugPrint("Synth layer load failed: $e");
      _showSaveConfirmation('Synth layer failed: $e');
      setState(() => activePlaybackSources.remove('synth'));
    } finally {
      setState(() { isSynthRendering = false; synthMessage = ''; });
      seekAllPlayers(currentPosition);
      if (wasPlaying) playAllPlayers();
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
        SoLoud.instance.setVolume(masterHandle!, enabled ? getChannelState('original').volume : 0.0);
        SoLoud.instance.setPan(masterHandle!, getChannelState('original').pan);
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
    if (originalAudioBytes == null) return;
    
    bool wasPlaying = isPlaying;
    double resumePosition = currentPosition;
    if (wasPlaying) pauseAllPlayers();
    
    setState(() { isPreviewing = true; exportMessage = "Queueing edits via Server..."; processingProgress = 0.0; });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['edit_manifest'] = jsonEncode({
          'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
          'edits': _enrichManifestWithPolyphonicContext(rawNotes),
          'solo_stem': activeEditableStem,
          'processing_mode': processingMode
        })
        ..fields['task_id'] = currentTaskId ?? ''
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

        if (stemHandles.containsKey(activeEditableStem)) {
          SoLoud.instance.stop(stemHandles[activeEditableStem]!);
        }

        stemSources[activeEditableStem] = await SoLoud.instance.loadMem("stem_${activeEditableStem}_edited", previewBytes);
        stemHandles[activeEditableStem] = SoLoud.instance.play(stemSources[activeEditableStem]!, paused: true);
        
        SoLoud.instance.setVolume(stemHandles[activeEditableStem]!, getChannelState(activeEditableStem).volume);
        SoLoud.instance.setPan(stemHandles[activeEditableStem]!, getChannelState(activeEditableStem).pan);
        seekAllPlayers(resumePosition);
        
        if (!activePlaybackSources.contains(activeEditableStem)) {
           setState(() { activePlaybackSources.add(activeEditableStem); });
        }

        setState(() {
          dirtyStems.remove(activeEditableStem); 
        });

        if (wasPlaying) {
          playAllPlayers();
          _showSaveConfirmation('Edits applied to ${activeEditableStem.toUpperCase()} stem.', isPreview: true);
        } else {
          _showSaveConfirmation('Stem updated — tap Play to hear edits.', isPreview: true);
        }
      } else {
        if (wasPlaying) playAllPlayers();
        _showSaveConfirmation('Render failed: ${result['message'] ?? 'unknown error'}');
      }
    } catch (e) {
      if (wasPlaying) playAllPlayers();
      debugPrint("Stem render failed: $e");
      _showSaveConfirmation('Render failed: $e');
    } finally {
      setState(() { isPreviewing = false; exportMessage = ''; processingProgress = 0.0; });
    }
  }

  Future<void> _renderStemPlugins(String stem) async {
    if (originalAudioBytes == null) return;
    
    bool wasPlaying = isPlaying;
    double resumePosition = currentPosition;
    
    setState(() { isPreviewing = true; exportMessage = "Rendering plugins for $stem..."; processingProgress = 0.0; });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['edit_manifest'] = jsonEncode({
          'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
          'edits': _enrichManifestWithPolyphonicContext(allStemsNotes[stem] ?? []),
          'solo_stem': stem,
          'processing_mode': processingMode
        })
        ..fields['task_id'] = currentTaskId ?? ''
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

          if (stemHandles.containsKey(stem)) {
             SoLoud.instance.stop(stemHandles[stem]!);
          }

          stemSources[stem] = await SoLoud.instance.loadMem("stem_${stem}_edited", previewBytes);
          stemHandles[stem] = SoLoud.instance.play(stemSources[stem]!, paused: !wasPlaying);
          
          SoLoud.instance.setVolume(stemHandles[stem]!, getChannelState(stem).volume);
          SoLoud.instance.setPan(stemHandles[stem]!, getChannelState(stem).pan);
          seekAllPlayers(resumePosition);
          
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
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['edit_manifest'] = json.encode({
          "mixer_state": mixerState.map((k, v) => MapEntry(k, v.toJson())),
          "all_stems_notes": enrichedStemsNotesMap,
          "processing_mode": processingMode
        })
        ..fields['task_id'] = currentTaskId ?? '' 
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
          'version': '1.4.0',
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
  
  Future<void> _saveVoxrayProject() async {
    Map<String, dynamic> projectData = {
      "voxray_version": "1.4.1", 
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

    List<int>? zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      _showSaveConfirmation('Archive encoding failed.');
      return;
    }
    Uint8List vxpBytes = Uint8List.fromList(zipData);

    String defaultSaveName = originalFileName.contains('.')
        ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
        : (originalFileName.isNotEmpty ? originalFileName : projectName);

    try {
      String? path = await FileSaver.instance.saveAs(
        name: defaultSaveName,
        bytes: vxpBytes,
        fileExtension: 'vxp',
        mimeType: MimeType.zip,
      );
      
      if (path != null && path.isNotEmpty) {
        setState(() {
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

    Uint8List vxpBytes;
    if (result.files.single.bytes != null) {
      vxpBytes = result.files.single.bytes!;
    } else if (result.files.single.path != null) {
      vxpBytes = await File(result.files.single.path!).readAsBytes();
    } else {
      return;
    }

    setState(() {
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
      activeEditableStem = projectData['active_editable_stem'] ?? 'vocals';
      
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
       masterSource = await SoLoud.instance.loadMem("master", originalAudioBytes!);
       masterHandle = SoLoud.instance.play(masterSource!, paused: true);
    }

    for (String stem in generatedStems) {
       if (cachedStemBytes.containsKey(stem)) {
          await _loadStemPlayerSource(stem);
       }
    }

    if (rawNotes.isNotEmpty && rawNotes.first.containsKey('contour')) {
       await _loadSynthSource();
    }

    setState(() { isLoading = false; processingMessage = ""; });
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
                             dirtyStems.add(key); 
                             if (!isMaster) _renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      _pluginDropdown(state.plugin2, highlight, (val) {
                         if(state.plugin2 != val) {
                             setMixerState(() => state.plugin2 = val!);
                             dirtyStems.add(key);
                             if (!isMaster) _renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      _pluginDropdown(state.plugin3, highlight, (val) {
                         if(state.plugin3 != val) {
                             setMixerState(() => state.plugin3 = val!);
                             dirtyStems.add(key);
                             if (!isMaster) _renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      _pluginDropdown(state.plugin4, highlight, (val) {
                         if(state.plugin4 != val) {
                             setMixerState(() => state.plugin4 = val!);
                             dirtyStems.add(key);
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
                            dirtyStems.add(key);
                            
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
                                dirtyStems.add(key);
                                if (state.isMuted) return;
                                
                                if (key == 'master') {
                                  SoLoud.instance.setGlobalVolume(v);
                                } else if (key == 'original') {
                                  if (masterHandle != null) SoLoud.instance.setVolume(masterHandle!, v);
                                } else if (key == 'synth') {
                                  if (synthHandle != null) SoLoud.instance.setVolume(synthHandle!, v);
                                } else if (stemHandles.containsKey(key)) {
                                  SoLoud.instance.setVolume(stemHandles[key]!, v);
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
                              dirtyStems.add(key);
                              
                              if (key == 'master') {
                                // Pan applied to all active stems when adjusting Master track pan
                                if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, v);
                                if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, v);
                                for (var handle in stemHandles.values) {
                                  SoLoud.instance.setPan(handle, v);
                                }
                              } else if (key == 'original') {
                                if (masterHandle != null) SoLoud.instance.setPan(masterHandle!, v);
                              } else if (key == 'synth') {
                                if (synthHandle != null) SoLoud.instance.setPan(synthHandle!, v);
                              } else if (stemHandles.containsKey(key)) {
                                SoLoud.instance.setPan(stemHandles[key]!, v);
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
                subtitle: const Text("Lossless / Studio Quality", style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () { Navigator.pop(context); _exportFinalMaster('wav'); }
              ),
              // (More formats and methods can follow) ...
            ]
          ),
        );
      }
    );
  }
}
