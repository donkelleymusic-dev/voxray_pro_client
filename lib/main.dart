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

import 'models/daw_models.dart';
import 'api/voxray_api.dart';
import 'logic/daw_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SoLoud.instance.init();
  runApp(MaterialApp(
    home: const VoxrayDAW(), 
    theme: ThemeData(brightness: Brightness.dark)
  ));
}

class VoxrayDAW extends StatefulWidget {
  const VoxrayDAW({Key? key}) : super(key: key);
  @override
  State<VoxrayDAW> createState() => VoxrayDAWState(); 
}

class VoxrayDAWState extends State<VoxrayDAW> {
  // --- CORE ENGINE ---
  late DawEngine engine;
  
  // --- UI CONTROLLERS ---
  final ScrollController horizontalScrollController = ScrollController();
  final ScrollController verticalScrollController = ScrollController();
  final ScrollController rulerScrollController = ScrollController();

  // ============================================================
  // PROXIES TO DAW ENGINE 
  // (Ensures backward compatibility with TimelineCanvasWidget)
  // ============================================================
  bool get isPlaying => engine.isPlaying;
  double get currentPosition => engine.currentPosition;
  double get songDuration => engine.songDuration;
  double get zoomX => engine.zoomX;
  double get zoomY => engine.zoomY;
  int get maxMidi => engine.maxMidi;
  int get minMidi => engine.minMidi;
  String get activeEditableStem => engine.activeEditableStem;
  List<dynamic> get rawNotes => engine.rawNotes;
  set rawNotes(List<dynamic> val) => engine.rawNotes = val;
  Map<String, List<dynamic>> get allStemsNotes => engine.allStemsNotes;
  Set<String> get generatedStems => engine.generatedStems;
  Set<String> get targetStemsSelection => engine.targetStemsSelection;
  List<Map<String, dynamic>> get markers => engine.markers;
  DragMode get currentDragMode => engine.currentDragMode;
  bool get isScrubMode => engine.isScrubMode;
  bool get isXrayMode => engine.isXrayMode;
  bool get isXrayProcessing => engine.isXrayProcessing;
  bool get isLoopModeActive => engine.isLoopModeActive;
  bool get isLiveModeActive => engine.isLiveModeActive;
  double get loopStartBoundary => engine.loopStartBoundary;
  double get loopEndBoundary => engine.loopEndBoundary;
  List<String> get undoStack => engine.undoStack;
  List<String> get redoStack => engine.redoStack;
  Set<String> get dirtyStems => engine.dirtyStems;
  bool get hasBeenSaved => engine.hasBeenSaved;
  String get projectName => engine.projectName;
  String get originalFileName => engine.originalFileName;
  Uint8List? get originalAudioBytes => engine.originalAudioBytes;
  String? get currentTaskId => engine.currentTaskId;
  String get processingMode => engine.processingMode;
  bool get isOriginalMixAvailable => engine.isOriginalMixAvailable;
  bool get isLoading => engine.isLoading;
  bool get isPreviewing => engine.isPreviewing;
  bool get isExporting => engine.isExporting;
  bool get isSynthRendering => engine.isSynthRendering;
  double get processingProgress => engine.processingProgress;
  String get processingMessage => engine.processingMessage;
  String get exportMessage => engine.exportMessage;
  String get synthMessage => engine.synthMessage;
  Map<String, Uint8List> get cachedStemBytes => engine.cachedStemBytes;
  Map<String, SoundHandle> get stemHandles => engine.stemHandles;
  SoundHandle? get masterHandle => engine.masterHandle;
  SoundHandle? get synthHandle => engine.synthHandle;
  SynthSettings get synthSettings => engine.synthSettings;
  List<String> get suggestedStems => engine.suggestedStems;
  bool get isTestModeActive => engine.isTestModeActive;
  bool get isProjectLoaded => engine.isProjectLoaded;
  Set<String> get activePlaybackSources => engine.activePlaybackSources;

  ChannelState getChannelState(String key) => engine.getChannelState(key);
  void registerUndoSnapshot() => engine.registerUndoSnapshot();

  @override
  void initState() {
    super.initState();
    
    // Initialize MVVM Backend Engine
    engine = DawEngine();
    engine.addListener(_onEngineStateChanged);
    
    // Bind UI callbacks to engine
    engine.onShowMessage = (msg, {bool isPreview = false}) => _showSaveConfirmation(msg, isPreview: isPreview);
    engine.onEngineRecommendation = () => _showEngineRecommendationDialog();

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
  }

  void _onEngineStateChanged() {
    if (!mounted) return;
    setState(() {});

    // Sync playhead auto-scrolling logic driven by the engine's internal position timer
    if (!engine.isUserScrolling && engine.isPlaying) {
      double targetX = (engine.currentPosition * engine.zoomX) - 150.0;
      if (targetX < 0) targetX = 0;
      if (horizontalScrollController.hasClients && horizontalScrollController.position.maxScrollExtent > 0) {
        horizontalScrollController.jumpTo(
          targetX.clamp(0.0, horizontalScrollController.position.maxScrollExtent)
        );
      }

      if (verticalScrollController.hasClients && engine.rawNotes.isNotEmpty) {
        var activeNotes = engine.rawNotes.where((n) {
          if (n['isDeleted'] == true) return false;
          double start = (n['start_time'] ?? 0).toDouble();
          double end = (n['end_time'] ?? 0).toDouble();
          return start <= engine.currentPosition && end >= engine.currentPosition;
        }).toList();

        if (activeNotes.isNotEmpty) {
          List<int> midiValues = activeNotes
              .map<int>((n) => ((n['display_midi'] ?? n['actual_midi'] ?? 60)).round())
              .toList()
            ..sort();
          int medianMidi = midiValues[midiValues.length ~/ 2];

          double viewportHeight = verticalScrollController.position.viewportDimension;
          double targetY = ((engine.maxMidi - medianMidi) * engine.zoomY) + (engine.zoomY / 2) - (viewportHeight / 2);
          targetY = targetY.clamp(0.0, verticalScrollController.position.maxScrollExtent);

          verticalScrollController.animateTo(
            targetY,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    engine.removeListener(_onEngineStateChanged);
    horizontalScrollController.dispose();
    verticalScrollController.dispose();
    rulerScrollController.dispose();
    engine.dispose();
    super.dispose();
  }

  void notifyChanged() {
    setState(() {});
  }

  void jumpToTimelinePosition(double seconds) {
    engine.seekAllPlayers(seconds);
    engine.currentPosition = seconds;

    double targetX = (seconds * engine.zoomX) - 150.0;
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
      engine.updateZoomX(newZoom);
      return;
    }
    
    double oldZoom = engine.zoomX;
    double viewportWidth = horizontalScrollController.position.viewportDimension;
    double currentPixels = horizontalScrollController.position.pixels;
    
    double centerTime = (currentPixels + (viewportWidth / 2)) / oldZoom;
    double newScrollX = (centerTime * newZoom) - (viewportWidth / 2);
    
    engine.updateZoomX(newZoom);
    
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
      engine.updateZoomY(newZoom);
      return;
    }
    
    double oldZoom = engine.zoomY;
    double viewportHeight = verticalScrollController.position.viewportDimension;
    double currentPixels = verticalScrollController.position.pixels;
    
    double centerMidi = engine.maxMidi - ((currentPixels + (viewportHeight / 2) - (oldZoom / 2)) / oldZoom);
    double newScrollY = ((engine.maxMidi - centerMidi) * newZoom) + (newZoom / 2) - (viewportHeight / 2);
    
    engine.updateZoomY(newZoom);
    
    verticalScrollController.jumpTo(math.max(0.0, newScrollY));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (verticalScrollController.hasClients) {
        verticalScrollController.jumpTo(
          newScrollY.clamp(0.0, verticalScrollController.position.maxScrollExtent)
        );
      }
    });
  }

  Future<void> playPreviewTone(double freq) async {
    try {
      final dummyNote = [{
        'start_time': 0.0, 'end_time': 0.5,
        'actual_midi': 69.0 + (12 * math.log(freq / 440.0) / math.ln2),
        'cents_shift': 0, 'volume': 1.0, 'isMuted': false, 'isDeleted': false,
        'time_ratio': 1.0, 'vibrato_scale': 1.0, 'drift_scale': 1.0, 'amplitude': 1.0,
      }];
      final wavBytes = renderNotesToWavBytes(notes: dummyNote, duration: 0.5, settings: engine.synthSettings);
      final previewSrc = await SoLoud.instance.loadMem("preview", wavBytes);
      SoLoud.instance.play(previewSrc, volume: 0.7);
    } catch (e) {
      debugPrint("Preview error: $e");
    }
  }

  Future<void> _requestSnippetSplice(Map<String, dynamic> modifiedNote) async {
    if (engine.activeEditableStem.isEmpty) return;
    try {
      modifiedNote['processing_mode'] = engine.processingMode;
      var data = await VoxrayApi.renderSnippet(
        taskId: engine.currentTaskId!,
        stemName: engine.activeEditableStem,
        editData: modifiedNote,
      );
      
      setState(() {
          modifiedNote['type'] = 'splice';
          modifiedNote['snippet_b64'] = data['snippet_b64'];
          modifiedNote['splice_mode'] = 'replace'; 
      });
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
                        items: [...engine.popStems, ...engine.orchStems, ...engine.forensicStems].map((s) {
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
        content: Text("Acoustic parameters suggest this is a classical or live chamber file. We recommend using the [${engine.selectedEngineProfile.toUpperCase()}] processing engine layout profile to prevent dynamic gating artifacts.", style: const TextStyle(color: Colors.white54)),
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
    
    engine.pauseAllPlayers(); 
    SoLoud.instance.disposeAllSources();
    
    engine.isProjectLoaded = false;
    engine.hasBeenSaved = false;
    engine.dirtyStems.clear();
    engine.allStemsNotes.clear(); 
    engine.generatedStems.clear(); 
    engine.targetStemsSelection.clear(); 
    engine.cachedStemBytes.clear();
    engine.stemHandles.clear(); 
    engine.stemSources.clear(); 
    engine.masterHandle = null; 
    engine.masterSource = null; 
    engine.synthHandle = null; 
    engine.synthSource = null;
    engine.activePlaybackSources.clear(); 
    engine.activeEditableStem = ''; 
    engine.currentTaskId = null; 
    engine.currentJobId = null;
    engine.currentProjectPath = null; 
    engine.originalAudioBytes = null; 
    engine.originalFileName = "Unknown File"; 
    engine.songDuration = 30.0; 
    engine.currentPosition = 0.0;
    engine.markers = [{"id": "mk_start", "time": 0.0, "label": "Start"}, {"id": "mk_end", "time": 30.0, "label": "End"}];
    engine.undoStack.clear();
    engine.redoStack.clear();
    engine.notifyListeners();
    
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
              items: [...engine.popStems, ...engine.orchStems].map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase(), style: const TextStyle(color: Colors.white)))).toList(),
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
    engine.ingestUploadedAudio(bytes, result.files.single.name, 'stem', chosenIdentity);
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

    engine.originalFilePath = result.files.single.path ?? "";
    engine.ingestUploadedAudio(audioBytes, result.files.single.name, uploadOptions['type']!, uploadOptions['stem'] ?? 'none');
  }

  // --- TIMELINE & MARKER UTILS ---

  void addMarkerAtCurrentPlayhead() {
    double visualPlayheadTime = (horizontalScrollController.hasClients
        ? (horizontalScrollController.position.pixels + 150) / engine.zoomX
        : engine.currentPosition);
    
    visualPlayheadTime = visualPlayheadTime.clamp(0.0, engine.songDuration);

    bool tooClose = engine.markers.any((m) => 
        ((m['time'] as double) - visualPlayheadTime).abs() < 0.5);
    if (tooClose) return;

    engine.markers.add({
      "id": "mk_${DateTime.now().millisecondsSinceEpoch}",
      "time": visualPlayheadTime,
      "label": "Marker ${engine.markers.length + 1}"
    });
    engine.notifyListeners();
  }

  void setLoopFromMarkers(double start, double end) {
    engine.loopStartBoundary = start;
    engine.loopEndBoundary = end;
    engine.notifyListeners();
  }

  void deleteMarker(String id) {
    engine.markers.removeWhere((m) => m['id'] == id);
    engine.notifyListeners();
  }

  // --- STUDIO MIXER UI ---

  void _applyMasterPlugins() {
    ChannelState state = engine.getChannelState('master');
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
                ChannelState state = engine.getChannelState(key);
                bool isAudible = engine.activePlaybackSources.contains(key) || (isMaster && engine.activePlaybackSources.isNotEmpty);
                
                double simulatedMeterValue = 0.0;
                if (engine.isPlaying && isAudible) {
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
                             engine.dirtyStems.add(key); engine.hasBeenSaved = false; engine.updateChannelState();
                             if (!isMaster) engine.renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      _pluginDropdown(state.plugin2, highlight, (val) {
                         if(state.plugin2 != val) {
                             setMixerState(() => state.plugin2 = val!);
                             engine.dirtyStems.add(key); engine.hasBeenSaved = false; engine.updateChannelState();
                             if (!isMaster) engine.renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      _pluginDropdown(state.plugin3, highlight, (val) {
                         if(state.plugin3 != val) {
                             setMixerState(() => state.plugin3 = val!);
                             engine.dirtyStems.add(key); engine.hasBeenSaved = false; engine.updateChannelState();
                             if (!isMaster) engine.renderStemPlugins(key);
                             else _applyMasterPlugins();
                         }
                      }),
                      _pluginDropdown(state.plugin4, highlight, (val) {
                         if(state.plugin4 != val) {
                             setMixerState(() => state.plugin4 = val!);
                             engine.dirtyStems.add(key); engine.hasBeenSaved = false; engine.updateChannelState();
                             if (!isMaster) engine.renderStemPlugins(key);
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
                            engine.dirtyStems.add(key); engine.hasBeenSaved = false; engine.updateChannelState();
                            
                            double targetVol = state.isMuted ? 0.0 : state.volume;
                            if (key == 'original') {
                               if (engine.masterHandle != null) SoLoud.instance.setVolume(engine.masterHandle!, targetVol);
                            } else if (key == 'synth') {
                               if (engine.synthHandle != null) SoLoud.instance.setVolume(engine.synthHandle!, targetVol);
                            } else if (engine.stemHandles.containsKey(key)) {
                               SoLoud.instance.setVolume(engine.stemHandles[key]!, targetVol);
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
                                engine.dirtyStems.add(key); engine.hasBeenSaved = false; engine.updateChannelState();
                                if (state.isMuted) return;
                                
                                // Volume Slider Fix
                                if (key == 'master') {
                                  SoLoud.instance.setGlobalVolume(v);
                                } else if (key == 'original') {
                                  if (engine.masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(engine.masterHandle!)) SoLoud.instance.setVolume(engine.masterHandle!, v);
                                } else if (key == 'synth') {
                                  if (engine.synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(engine.synthHandle!)) SoLoud.instance.setVolume(engine.synthHandle!, v);
                                } else if (engine.stemHandles.containsKey(key)) {
                                  if (SoLoud.instance.getIsValidVoiceHandle(engine.stemHandles[key]!)) SoLoud.instance.setVolume(engine.stemHandles[key]!, v);
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
                              engine.dirtyStems.add(key); engine.hasBeenSaved = false; engine.updateChannelState();
                              
                              // Pan Slider Fix
                              if (key == 'master') {
                                if (engine.masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(engine.masterHandle!)) SoLoud.instance.setPan(engine.masterHandle!, v);
                                if (engine.synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(engine.synthHandle!)) SoLoud.instance.setPan(engine.synthHandle!, v);
                                for (var handle in engine.stemHandles.values) {
                                  if (SoLoud.instance.getIsValidVoiceHandle(handle)) SoLoud.instance.setPan(handle, v);
                                }
                              } else if (key == 'original') {
                                if (engine.masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(engine.masterHandle!)) SoLoud.instance.setPan(engine.masterHandle!, v);
                              } else if (key == 'synth') {
                                if (engine.synthHandle != null && SoLoud.instance.getIsValidVoiceHandle(engine.synthHandle!)) SoLoud.instance.setPan(engine.synthHandle!, v);
                              } else if (engine.stemHandles.containsKey(key)) {
                                if (SoLoud.instance.getIsValidVoiceHandle(engine.stemHandles[key]!)) SoLoud.instance.setPan(engine.stemHandles[key]!, v);
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
                          if (engine.isOriginalMixAvailable) buildChannelStrip("MIX", "original", Colors.blueGrey),
                          buildChannelStrip("SYNTH", "synth", Colors.purpleAccent),
                          ...engine.targetStemsSelection.map((stem) => buildChannelStrip(stem.toUpperCase(), stem, Colors.tealAccent)),
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
            setDialogState(() => engine.updateSynthSettings(fn(engine.synthSettings)));
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
                        bool selected = engine.synthSettings.waveform == w;
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
                    _synthSlider('Attack', engine.synthSettings.adsr.attack, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(attack: v)))),
                    _synthSlider('Decay', engine.synthSettings.adsr.decay, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(decay: v)))),
                    _synthSlider('Sustain', engine.synthSettings.adsr.sustain, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(sustain: v)))),
                    _synthSlider('Release', engine.synthSettings.adsr.release, 0.0, 1.0,
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
                          value: engine.synthSettings.useXrayContour,
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
                  if (engine.activePlaybackSources.contains('synth')) engine.loadSynthSource();
                },
                child: const Text('Close', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent.withOpacity(0.2)),
                icon: const Icon(Icons.play_arrow, color: Colors.tealAccent, size: 16),
                label: const Text('Preview Synth', style: TextStyle(color: Colors.tealAccent)),
                onPressed: engine.rawNotes.isEmpty ? null : () async {
                  Navigator.pop(context);
                  await engine.togglePlaybackSource('synth', true);
                  if (!engine.isPlaying) engine.playAllPlayers();
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
    if (engine.rawNotes.isEmpty || engine.originalAudioBytes == null) {
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
                onTap: () { Navigator.pop(context); engine.exportSynthAudio(); }
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.analytics, color: Colors.tealAccent, size: 28),
                title: const Text("Forensic Dossier", style: TextStyle(color: Colors.white)),
                subtitle: const Text("PDF Report", style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () { Navigator.pop(context); engine.downloadDossier(); }
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
                onTap: () { Navigator.pop(context); engine.exportFinalMaster('wav'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.library_music, color: Colors.amberAccent, size: 30),
                title: const Text("FLAC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Lossless / Compressed Size", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); engine.exportFinalMaster('flac'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.music_note, color: Colors.blueAccent, size: 30),
                title: const Text("MP3", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Standard / Web Optimized", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); engine.exportFinalMaster('mp3'); },
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
                onTap: () { Navigator.pop(context); engine.downloadPitchPrint(fullSong: fullSong, format: 'svg'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.photo, color: Colors.amberAccent, size: 30),
                title: const Text("PNG Image", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("High-Resolution Image", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); engine.downloadPitchPrint(fullSong: fullSong, format: 'png'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.blueAccent, size: 30),
                title: const Text("PDF Print", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Print-ready Document", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); engine.downloadPitchPrint(fullSong: fullSong, format: 'pdf'); },
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
    if (engine.rawNotes.isEmpty) return;

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

    bool hasXray = engine.rawNotes.any((n) => n.containsKey('contour') && n['contour'] != null);

    for (var note in engine.rawNotes) {
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
            Text("Dossier: ${engine.activeEditableStem.toUpperCase()}", style: const TextStyle(color: Colors.white)),
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
                onPressed: () => engine.playAllPlayers(),
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
            bool isSuggested = engine.suggestedStems.contains(stem);
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
              value: engine.targetStemsSelection.contains(stem),
              activeColor: Colors.tealAccent,
              onChanged: (bool? checked) {
                setTreeState(() {
                  if (checked == true) {
                    engine.targetStemsSelection.add(stem);
                  } else {
                    engine.targetStemsSelection.remove(stem);
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
                    ...engine.popStems.map((s) => buildStemCheckbox(s)),
                    const Divider(color: Colors.white24),
                    const Text("ORCHESTRAL MODELS", style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ...engine.orchStems.map((s) => buildStemCheckbox(s)),
                    const Divider(color: Colors.white24),
                    const Text("FORENSIC SUITE", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ...engine.forensicStems.map((s) => buildStemCheckbox(s)),
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

  Future<void> _saveVoxrayProject() async {
    if (engine.currentProjectPath == null || kIsWeb || engine.currentProjectPath!.startsWith('content://')) {
      await _saveVoxrayProjectAs();
      return;
    }
    
    final bytes = engine.packageProjectBytes();
    try {
      await File(engine.currentProjectPath!).writeAsBytes(bytes);
      engine.hasBeenSaved = true;
      engine.dirtyStems.clear();
      engine.notifyListeners();
      _showSaveConfirmation("Project file successfully overwritten on disk.");
    } catch (e) { 
      _showSaveConfirmation("Overwrite failed: $e"); 
    }
  }

  Future<void> _saveVoxrayProject_old() async {
    if (engine.currentProjectPath == null || kIsWeb) {
      await _saveVoxrayProjectAs();
      return;
    }
    
    final bytes = engine.packageProjectBytes();
    try {
      await File(engine.currentProjectPath!).writeAsBytes(bytes);
      engine.hasBeenSaved = true;
      engine.dirtyStems.clear();
      engine.notifyListeners();
      _showSaveConfirmation("Project file successfully overwritten on disk.");
    } catch (e) { 
      _showSaveConfirmation("Overwrite failed: $e"); 
    }
  }

  Future<void> _saveVoxrayProjectAs() async {
    final bytes = engine.packageProjectBytes();
    
    String defaultSaveName = engine.originalFileName.contains('.')
        ? engine.originalFileName.substring(0, engine.originalFileName.lastIndexOf('.'))
        : (engine.originalFileName.isNotEmpty ? engine.originalFileName : engine.projectName);

    try {
      String? path = await FileSaver.instance.saveAs(
        name: defaultSaveName,
        bytes: bytes,
        fileExtension: 'vxp',
        mimeType: MimeType.custom,
        customMimeType: 'application/octet-stream',
      );
      if (path != null && path.isNotEmpty) {
        engine.currentProjectPath = path;
        engine.hasBeenSaved = true;
        engine.dirtyStems.clear(); 
        engine.notifyListeners();
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
    
    engine.pauseAllPlayers();

    Uint8List vxpBytes;
    if (result.files.single.bytes != null) {
      vxpBytes = result.files.single.bytes!;
    } else if (result.files.single.path != null) {
      vxpBytes = await File(result.files.single.path!).readAsBytes();
      engine.currentProjectPath = result.files.single.path;
    } else {
      return;
    }

    engine.unpackProjectBytes(vxpBytes);
  }

  List<PopupMenuEntry<String>> _buildMainMenu() {
    bool canSave = engine.isProjectLoaded && (!engine.hasBeenSaved || engine.dirtyStems.isNotEmpty || engine.undoStack.isNotEmpty);
    bool canSaveAs = engine.isProjectLoaded;

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
          leading: Icon(engine.processingMode == 'advanced' ? Icons.auto_awesome : Icons.blur_linear, color: Colors.purpleAccent),
          title: Text(engine.processingMode == 'advanced' ? 'Mode: ADVANCED' : 'Mode: NORMAL', style: const TextStyle(color: Colors.purpleAccent)),
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
          leading: Icon(Icons.mic_external_on, color: engine.isLiveModeActive ? Colors.redAccent : Colors.white), 
          title: Text(engine.isLiveModeActive ? 'Disable Live Pedagogy' : 'Enable Live Pedagogy', style: TextStyle(color: engine.isLiveModeActive ? Colors.redAccent : Colors.white))
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
          leading: Icon(Icons.bug_report, color: engine.isTestModeActive ? Colors.redAccent : Colors.white38), 
          title: Text(engine.isTestModeActive ? 'Disable MOCK API Mode' : 'Enable MOCK API Mode', style: TextStyle(color: engine.isTestModeActive ? Colors.redAccent : Colors.white))
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
      case 'export_stems': engine.exportStemsAsZip(); break;
      case 'processing_mode': engine.toggleProcessingMode(); break;
      case 'synth_settings': _showSynthSettingsDialog(); break;
      case 'show_dossier': _showDossier(); break;
      case 'downloads': _showAdvancedDownloadsDialog(); break;
      case 'live_mode': engine.toggleLiveMode(); break;
      case 'reprocess': engine.forceReprocessXray(); break;
      case 'test_mode': engine.isTestModeActive = !engine.isTestModeActive; engine.notifyListeners(); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isCurrentStemGenerated = engine.generatedStems.contains(engine.activeEditableStem);

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
          if (!engine.isLiveModeActive)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: "Main Menu",
              onSelected: _handleMenuSelection,
              itemBuilder: (context) => _buildMainMenu(),
            ),
        ],
      ),
      body: SafeArea(
        child: engine.isLiveModeActive
            ? LivePedagogyView(
                onExit: () => engine.toggleLiveMode() 
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
                                engine.originalFileName != "Unknown File" 
                                    ? "${engine.originalFileName}" + (engine.activeEditableStem.isNotEmpty ? "  [STEM: ${engine.activeEditableStem.toUpperCase()}]" : "") 
                                    : "No File Loaded",
                                style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              )
                            ),
                            if (engine.projectName != "Voxray_Session")
                              Text(' [${engine.projectName}]', style: const TextStyle(fontSize: 12, color: Colors.white38)),
                          ]
                        ),
                        if (engine.isLoading) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(child: LinearProgressIndicator(value: engine.processingProgress, color: Colors.tealAccent, backgroundColor: Colors.grey[800])),
                              const SizedBox(width: 8),
                              Text(engine.processingMessage, style: const TextStyle(fontSize: 10, color: Colors.tealAccent)),
                            ],
                          )
                        ] else if (engine.isPreviewing || engine.isExporting || engine.isSynthRendering) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(child: LinearProgressIndicator(value: engine.processingProgress, color: Colors.amberAccent, backgroundColor: Colors.grey[800])),
                              const SizedBox(width: 8),
                              Text(engine.exportMessage.isNotEmpty ? engine.exportMessage : engine.synthMessage, style: const TextStyle(fontSize: 10, color: Colors.amberAccent)),
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
                        IconButton(icon: const Icon(Icons.undo), tooltip: 'Undo', onPressed: engine.undoStack.isNotEmpty ? engine.undo : null),
                        IconButton(icon: const Icon(Icons.redo), tooltip: 'Redo', onPressed: engine.redoStack.isNotEmpty ? engine.redo : null),
                        
                        Tooltip(
                          message: "Preview pitch/DSP edits",
                          child: IconButton(
                            icon: const Icon(Icons.preview, color: Colors.deepPurpleAccent, size: 24),
                            // Button only active if there are un-previewed changes on the current active stem
                            onPressed: (engine.rawNotes.isNotEmpty && engine.originalAudioBytes != null && !engine.isPreviewing && !engine.isExporting && engine.dirtyStems.contains(engine.activeEditableStem)) ? engine.renderStemEdits : null,
                          ),
                        ),

                        const SizedBox(width: 8),
                        IconButton(icon: const Icon(Icons.tune, color: Colors.orangeAccent), tooltip: 'Studio Mixer', onPressed: _showStudioMixer),
                        IconButton(icon: Icon(engine.isPlaying ? Icons.pause : Icons.play_arrow, size: 26), onPressed: engine.toggleMasterTransport),
                        
                        if (engine.targetStemsSelection.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: DropdownButton<String>(
                            value: engine.targetStemsSelection.contains(engine.activeEditableStem) && engine.activeEditableStem.isNotEmpty ? engine.activeEditableStem : null,
                            dropdownColor: Colors.grey[900],
                            underline: const SizedBox(),
                            hint: const Text("No Stems Available", style: TextStyle(color: Colors.white38, fontSize: 12)),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.tealAccent),
                            style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 13),
                            items: engine.targetStemsSelection.map((String stemKey) {
                              bool isSuggested = engine.suggestedStems.contains(stemKey);
                              return DropdownMenuItem<String>(
                                value: stemKey,
                                child: Row(
                                  children: [
                                    Text(stemKey.toUpperCase(), style: TextStyle(color: isSuggested ? Colors.yellowAccent : Colors.white)),
                                    if (isSuggested) 
                                       const Padding(padding: EdgeInsets.only(left: 4.0), child: Icon(Icons.star, size: 12, color: Colors.yellowAccent)),
                                    if (!engine.generatedStems.contains(stemKey)) 
                                       const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.hourglass_empty, size: 14, color: Colors.white38))
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newSelection) {
                              if (newSelection != null) {
                                engine.changeActiveEditableStem(newSelection);
                              }
                            },
                          ),
                        ),

                        PopupMenuButton<DragMode>(
                          icon: Icon(Icons.pan_tool, color: engine.currentDragMode != DragMode.off ? Colors.amberAccent : Colors.white38),
                          tooltip: 'Drag Pitch Mode',
                          onSelected: (val) {
                             engine.currentDragMode = val;
                             engine.updateChannelState();
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: DragMode.off, child: Text('Normal (Off)')),
                            PopupMenuItem(value: DragMode.semitone, child: Text('Semitone Drag')),
                            PopupMenuItem(value: DragMode.microTuning, child: Text('Micro-Tuning Drag')),
                          ],
                        ),

                        IconButton(icon: Icon(Icons.touch_app, color: engine.isScrubMode ? Colors.amberAccent : Colors.white38, size: 22), onPressed: () => engine.toggleScrubMode()),
                        engine.isXrayProcessing 
                          ? const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent)))
                          : IconButton(icon: Icon(Icons.fingerprint, color: engine.isXrayMode ? Colors.amberAccent : Colors.white38, size: 22), onPressed: isCurrentStemGenerated ? engine.toggleXrayMode : null),
                        IconButton(icon: Icon(Icons.loop, color: engine.isLoopModeActive ? Colors.tealAccent : Colors.white38, size: 22), onPressed: () => engine.toggleLoopMode()),
                        IconButton(icon: const Icon(Icons.add_location_alt, size: 20, color: Colors.amberAccent), onPressed: addMarkerAtCurrentPlayhead),
                        
                        if (engine.markers.isNotEmpty)
                          PopupMenuButton<double>(
                            icon: const Icon(Icons.location_on, color: Colors.amberAccent, size: 20),
                            tooltip: "Go to Marker",
                            itemBuilder: (context) => engine.markers.map((marker) {
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
                        if (engine.markers.length >= 2) ...[
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.settings_overscan, size: 18, color: Colors.blueAccent),
                            tooltip: "Set Loop Region",
                            itemBuilder: (context) {
                              List<PopupMenuItem<String>> items = [];
                              for (int i = 0; i < engine.markers.length; i++) {
                                for (int j = i + 1; j < engine.markers.length; j++) {
                                  items.add(PopupMenuItem(
                                    value: '${engine.markers[i]['time']}_${engine.markers[j]['time']}',
                                    child: Text('${engine.markers[i]['label']} → ${engine.markers[j]['label']}', style: const TextStyle(fontSize: 12)),
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
                      child: Slider(value: engine.zoomX, min: 20.0, max: 500.0, onChanged: setZoomX),
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
                                      child: Slider(value: engine.zoomY, min: 8.0, max: 60.0, onChanged: setZoomY),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: !isCurrentStemGenerated && engine.originalAudioBytes != null && engine.currentTaskId != null
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.music_note, size: 48, color: Colors.white24),
                                          const SizedBox(height: 16),
                                          Text("The ${engine.activeEditableStem.isNotEmpty ? engine.activeEditableStem.toUpperCase() : 'selected'} stem has not been extracted yet.", style: const TextStyle(color: Colors.white54)),
                                          const SizedBox(height: 24),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                                            icon: const Icon(Icons.build),
                                            label: Text("Generate & Analyze ${engine.activeEditableStem.isNotEmpty ? engine.activeEditableStem.toUpperCase() : ''}"),
                                            onPressed: engine.isLoading || engine.activeEditableStem.isEmpty ? null : () => engine.generateStemOnDemand(engine.activeEditableStem),
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