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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import '../models/daw_models.dart';
import '../api/voxray_api.dart';
import '../audio/vox_synth.dart';

class DawEngine extends ChangeNotifier {
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

  Map<String, List<dynamic>> allStemsNotes = {};
  String activeEditableStem = ''; 

  Set<String> targetStemsSelection = {};
  Set<String> generatedStems = {}; 
  List<String> suggestedStems = []; 

  final List<String> popStems = ['vocals', 'instrumental', 'drums', 'bass', 'guitar', 'piano', 'other'];
  final List<String> orchStems = ['violin', 'cello', 'contrabass', 'flute', 'oboe', 'bassoon', 'trumpet', 'trombone', 'tuba', 'percussion', 'orchestral'];
  final List<String> forensicStems = ['forensic_id'];
  
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
      notifyListeners();
    }
  }

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

  Function(String message, {bool isPreview})? onShowMessage;
  Function()? onEngineRecommendation;

  DawEngine() {
    _initPositionTimer();
  }

  void _initPositionTimer() {
    positionTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!isPlaying) return;
      
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

      currentPosition = currentT;
      notifyListeners();
    });
  }

  void updateZoomX(double val) { zoomX = val; notifyListeners(); }
  void updateZoomY(double val) { zoomY = val; notifyListeners(); }
  void toggleScrubMode() { isScrubMode = !isScrubMode; notifyListeners(); }
  void toggleLoopMode() { isLoopModeActive = !isLoopModeActive; notifyListeners(); }
  void setDragMode(DragMode mode) { currentDragMode = mode; notifyListeners(); }
  void toggleLiveMode() { isLiveModeActive = !isLiveModeActive; notifyListeners(); }
  void toggleProcessingMode() { processingMode = processingMode == 'classic' ? 'advanced' : 'classic'; notifyListeners(); }
  void updateSynthSettings(SynthSettings settings) { synthSettings = settings; notifyListeners(); }

  void registerUndoSnapshot() {
    if (activeEditableStem.isNotEmpty) {
      undoStack.add(json.encode(allStemsNotes));
      redoStack.clear();
      dirtyStems.add(activeEditableStem); 
      hasBeenSaved = false; 
      notifyListeners();
    }
  }

  void undo() {
    if (undoStack.isNotEmpty) {
      redoStack.add(json.encode(allStemsNotes));
      allStemsNotes = Map<String, List<dynamic>>.from(json.decode(undoStack.removeLast()));
      notifyListeners();
    }
  }

  void redo() {
    if (redoStack.isNotEmpty) {
      undoStack.add(json.encode(allStemsNotes));
      allStemsNotes = Map<String, List<dynamic>>.from(json.decode(redoStack.removeLast()));
      notifyListeners();
    }
  }

  ChannelState getChannelState(String key) {
    if (!mixerState.containsKey(key)) {
      mixerState[key] = ChannelState();
    }
    return mixerState[key]!;
  }

  void updateChannelState() {
    notifyListeners();
  }

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
    isPlaying = true;
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
    notifyListeners();
  }

  void pauseAllPlayers() {
    isPlaying = false;
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
    notifyListeners();
  }

  void toggleMasterTransport() {
    if (isPlaying) pauseAllPlayers(); else playAllPlayers();
  }

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

  // --- API INTEGRATION CORE EXECUTION ---
  
  Future<void> ingestUploadedAudio(Uint8List bytes, String name, String uploadType, String stemTarget) async {
    isLoading = true; processingProgress = 0.0;
    originalAudioBytes = bytes; originalFileName = name;
    isProjectLoaded = true; hasBeenSaved = false;
    dirtyStems.clear(); cachedStemBytes.clear();
    allStemsNotes.clear(); generatedStems.clear();
    currentTaskId = null; currentJobId = null; suggestedStems.clear();

    if (uploadType == 'mix') {
      isOriginalMixAvailable = true; activePlaybackSources.add('original');
      processingMessage = "Analyzing profile and dynamic parameters...";
    } else {
      isOriginalMixAvailable = false; activeEditableStem = stemTarget;
      activePlaybackSources.add(stemTarget); targetStemsSelection.add(stemTarget);
      processingMessage = "Analyzing ${stemTarget.toUpperCase()} stem notes...";
    }
    notifyListeners();

    if (synthHandle != null) SoLoud.instance.stop(synthHandle!);
    if (masterHandle != null) SoLoud.instance.stop(masterHandle!);

    try {
      masterSource = await SoLoud.instance.loadMem("master", originalAudioBytes!);
      masterHandle = SoLoud.instance.play(masterSource!, paused: true);
      SoLoud.instance.setPause(masterHandle!, true);
      SoLoud.instance.setVolume(masterHandle!, getChannelState('original').volume);
    } catch (e) {
      debugPrint("Audio preview setup failed: $e");
    }

    try {
      var data = await VoxrayApi.analyzeAdvanced(
        audioBytes: originalAudioBytes!,
        filename: name,
        uploadType: uploadType,
        stemTarget: uploadType == 'stem' ? stemTarget : 'none',
        instruments: targetStemsSelection.toList(),
        isTestMode: isTestModeActive,
      );
      
      currentTaskId = data['task_id']; 
      if (data['detected_instruments'] != null) suggestedStems = List<String>.from(data['detected_instruments']);
      if (data['recommended_engine'] != null) selectedEngineProfile = data['recommended_engine'];

      if (uploadType == 'mix') {
        if (selectedEngineProfile != 'studio' && onEngineRecommendation != null) onEngineRecommendation!();
        isLoading = false;
        songDuration = (data['duration'] ?? 30.0).toDouble(); 
        loopEndBoundary = songDuration;
        int endIdx = markers.indexWhere((m) => m['id'] == 'mk_end');
        if (endIdx != -1) markers[endIdx]['time'] = songDuration;
        notifyListeners();
        return;
      }

      currentJobId = data['job_id']; 
      pollForStemData(currentJobId!, stemTarget);
    } catch (e) {
      isLoading = false; processingMessage = "Failed to start.";
      notifyListeners();
      if (onShowMessage != null) onShowMessage!('Initialization Failed: $e');
    }
  }

  void pollForStemData(String jobId, String targetStem) {
    pollingTimer?.cancel();
    pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        var statusData = await VoxrayApi.getTaskStatus(jobId);
        processingProgress = (statusData['progress'] ?? 0).toDouble() / 100.0;
        processingMessage = statusData['message'] ?? "Processing...";
        notifyListeners();

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
          isLoading = false; processingMessage = '';
          loadStemPlayerSource(targetStem);
        } else if (statusData['status'] == 'error') {
          timer.cancel(); isLoading = false; activePlaybackSources.remove(targetStem);
          notifyListeners();
          if (onShowMessage != null) onShowMessage!('Processing Error: ${statusData['message']}');
        }
      } catch (e) {
        timer.cancel(); isLoading = false; activePlaybackSources.remove(targetStem);
        notifyListeners();
        if (onShowMessage != null) onShowMessage!('Connection error during polling: $e');
      }
    });
  }

  Future<void> generateStemOnDemand(String targetToGenerate) async {
    if (currentTaskId == null) return;
    if (generatedStems.contains(targetToGenerate)) return;

    isLoading = true; processingProgress = 0.0;
    processingMessage = "Isolating $targetToGenerate & extracting notes...";
    notifyListeners();

    try {
      var resData = await VoxrayApi.generateStemOnDemand(taskId: currentTaskId!, targetStem: targetToGenerate);
      final String jobId = resData['job_id'];
      currentJobId = jobId;
      pollForStemData(jobId, targetToGenerate);
    } catch (e) {
      isLoading = false; processingMessage = "";
      activePlaybackSources.remove(targetToGenerate);
      if (generatedStems.isNotEmpty && !generatedStems.contains(activeEditableStem)) {
         activeEditableStem = generatedStems.first;
      }
      notifyListeners();
      if (onShowMessage != null) onShowMessage!("Failed to generate ${targetToGenerate.toUpperCase()} stem: $e");
    }
  }

  Future<void> changeActiveEditableStem(String newSelection) async {
    if (newSelection != activeEditableStem) {
      activeEditableStem = newSelection;
      isXrayMode = rawNotes.isNotEmpty && rawNotes.any((n) => n.containsKey('contour') && n['contour'] != null);
      notifyListeners();
      if (!generatedStems.contains(newSelection) && originalAudioBytes != null && currentTaskId != null && !isLoading) {
        await generateStemOnDemand(newSelection);
      }
    }
  }

  Future<void> forceReprocessXray() async {
    if (rawNotes.isEmpty) return;
    bool cachedTransportState = isPlaying;
    pauseAllPlayers();
    isXrayProcessing = true; isXrayMode = true; notifyListeners();

    try {
      if (currentTaskId == null) {
        if (!cachedStemBytes.containsKey(activeEditableStem)) throw Exception("Audio data not found in cache.");
        var sessionData = await VoxrayApi.analyzeAdvanced(
          audioBytes: cachedStemBytes[activeEditableStem]!,
          filename: '${activeEditableStem}_offline.ogg',
          uploadType: 'stem',
          stemTarget: activeEditableStem,
          instruments: [activeEditableStem],
        );
        currentTaskId = sessionData['task_id'];
      }

      var data = await VoxrayApi.analyzeXray(taskId: currentTaskId!, enrichedNotes: _enrichManifestWithPolyphonicContext(rawNotes));
      if (data['status'] == 'success') {
        rawNotes = data['notes']; registerUndoSnapshot();
        if (onShowMessage != null) onShowMessage!('X-Ray data successfully reprocessed.');
      }
    } catch (e) {
      if (onShowMessage != null) onShowMessage!('Reprocess failed: $e');
    } finally {
      isXrayProcessing = false; notifyListeners();
      if (cachedTransportState) playAllPlayers();
    }
  }

  Future<void> toggleXrayMode() async {
    if (rawNotes.isEmpty) return;
    bool cachedTransportState = isPlaying;
    if (isXrayMode || rawNotes.any((n) => n.containsKey('contour'))) {
      isXrayMode = !isXrayMode; notifyListeners(); return;
    }
    pauseAllPlayers();
    isXrayProcessing = true; isXrayMode = true; notifyListeners();

    try {
      if (currentTaskId == null) {
        String lookupKey = activeEditableStem.toLowerCase().trim();
        String matchedKey = cachedStemBytes.keys.firstWhere((k) => k.toLowerCase().trim() == lookupKey, orElse: () => '');
        if (matchedKey.isEmpty) throw Exception("Audio tracks match layout failure.");

        var sessionData = await VoxrayApi.analyzeAdvanced(
          audioBytes: cachedStemBytes[matchedKey]!,
          filename: '${matchedKey}_offline.ogg',
          uploadType: 'stem',
          stemTarget: matchedKey,
          instruments: [matchedKey],
        );
        currentTaskId = sessionData['task_id'];
      }

      var data = await VoxrayApi.analyzeXray(taskId: currentTaskId!, enrichedNotes: _enrichManifestWithPolyphonicContext(rawNotes));
      if (data['status'] == 'success') {
        rawNotes = data['notes']; registerUndoSnapshot();
      } else {
        isXrayMode = false;
      }
    } catch (e) {
      isXrayMode = false;
    } finally {
      isXrayProcessing = false; notifyListeners();
      if (cachedTransportState) playAllPlayers();
    }
  }

  Future<void> loadStemPlayerSource(String stemName) async {
    isFetchingStems = true; notifyListeners();
    bool wasPlaying = isPlaying;
    if (wasPlaying) pauseAllPlayers(); 

    try {
      final Uint8List bytes = cachedStemBytes[stemName] ?? await VoxrayApi.fetchStemBytes(currentTaskId!, stemName);
      cachedStemBytes[stemName] = bytes;

      if (stemHandles.containsKey(stemName)) SoLoud.instance.stop(stemHandles[stemName]!);

      stemSources[stemName] = await SoLoud.instance.loadMem("stem_$stemName", bytes);
      stemHandles[stemName] = SoLoud.instance.play(stemSources[stemName]!, paused: true);
      SoLoud.instance.setPause(stemHandles[stemName]!, true); 

      ChannelState state = getChannelState(stemName);
      SoLoud.instance.setVolume(stemHandles[stemName]!, state.isMuted ? 0.0 : state.volume);
      SoLoud.instance.setPan(stemHandles[stemName]!, state.pan); 
    } catch (e) {
      activePlaybackSources.remove(stemName);
    } finally {
      isFetchingStems = false; notifyListeners();
      seekAllPlayers(currentPosition); 
      if (wasPlaying) {
        await Future.delayed(const Duration(milliseconds: 50)); playAllPlayers();
      }
    }
  }

  Future<void> loadSynthSource() async {
    if (rawNotes.isEmpty) return;
    isSynthRendering = true; synthMessage = "Synthesizing note data..."; notifyListeners();
    bool wasPlaying = isPlaying;
    if (wasPlaying) pauseAllPlayers();

    try {
      final Uint8List wavBytes = renderNotesToWavBytes(notes: rawNotes, duration: songDuration, settings: synthSettings);
      if (synthHandle != null) SoLoud.instance.stop(synthHandle!);
      synthSource = await SoLoud.instance.loadMem("synth_layer", wavBytes);
      synthHandle = SoLoud.instance.play(synthSource!, paused: true);
      SoLoud.instance.setPause(synthHandle!, true);
      
      ChannelState state = getChannelState('synth');
      SoLoud.instance.setVolume(synthHandle!, state.isMuted ? 0.0 : state.volume);
      SoLoud.instance.setPan(synthHandle!, state.pan); 
    } catch (e) {
      activePlaybackSources.remove('synth');
    } finally {
      isSynthRendering = false; synthMessage = ''; notifyListeners();
      seekAllPlayers(currentPosition);
      if (wasPlaying) playAllPlayers();
    }
  }

  Future<void> togglePlaybackSource(String key, bool enabled) async {
    if (enabled) activePlaybackSources.add(key); else activePlaybackSources.remove(key);
    notifyListeners();

    if (key == 'original') {
      if (masterHandle != null) {
        SoLoud.instance.setVolume(masterHandle!, enabled ? (getChannelState('original').isMuted ? 0.0 : getChannelState('original').volume) : 0.0);
      }
    } else if (key == 'synth') {
      if (enabled) await loadSynthSource(); else if (synthHandle != null) SoLoud.instance.setVolume(synthHandle!, 0.0);
    } else {
      if (enabled) {
        if (!generatedStems.contains(key)) await generateStemOnDemand(key);
        else await loadStemPlayerSource(key);
      } else if (stemHandles.containsKey(key)) {
        SoLoud.instance.setVolume(stemHandles[key]!, 0.0);
      }
    }
  }

  Future<Uint8List?> pollRenderJob(String jobId) async {
    bool isComplete = false;
    int retryCount = 0;
    const int maxRetries = 100; 
    
    while (!isComplete && retryCount < maxRetries) {
      try {
        final taskData = await VoxrayApi.getTaskStatus(jobId);
        final status = taskData['status'];
        
        processingProgress = (taskData['progress'] ?? 0).toDouble() / 100.0;
        if (isPreviewing) exportMessage = taskData['message'] ?? 'Processing...';
        notifyListeners();

        if (status == 'complete') {
          return base64Decode(taskData['result']['master_mix_b64']);
        } else if (status == 'error') {
          throw Exception(taskData['message']);
        }
      } catch (e) {
        debugPrint('Polling network blink: $e');
      }
      await Future.delayed(const Duration(seconds: 3));
      retryCount++;
    }
    throw Exception('Polling timed out after 5 minutes.');
  }

  Future<void> renderStemEdits() async {
    if (originalAudioBytes == null || activeEditableStem.isEmpty) return;
    isPreviewing = true; exportMessage = "Queueing edits via Server..."; processingProgress = 0.0; notifyListeners();

    try {
      if (currentTaskId == null) {
        var sessionData = await VoxrayApi.analyzeAdvanced(
          audioBytes: cachedStemBytes[activeEditableStem]!,
          filename: '${activeEditableStem}_offline.ogg',
          uploadType: 'stem',
          stemTarget: activeEditableStem,
          instruments: [activeEditableStem],
        );
        currentTaskId = sessionData['task_id'];
      }

      var result = await VoxrayApi.batchRenderAndMix(
        taskId: currentTaskId!,
        audioBytes: originalAudioBytes!,
        editManifest: {
          'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
          'edits': _enrichManifestWithPolyphonicContext(rawNotes),
          'solo_stem': activeEditableStem,
          'processing_mode': processingMode
        },
        isTestMode: isTestModeActive,
      );

      if (result['status'] == 'success') {
        Uint8List previewBytes = await pollRenderJob(result['job_id']) ?? Uint8List(0);
        cachedStemBytes[activeEditableStem] = previewBytes;
        if (stemHandles.containsKey(activeEditableStem)) SoLoud.instance.stop(stemHandles[activeEditableStem]!);

        stemSources[activeEditableStem] = await SoLoud.instance.loadMem("stem_${activeEditableStem}_edited", previewBytes);
        stemHandles[activeEditableStem] = SoLoud.instance.play(stemSources[activeEditableStem]!, paused: true);
        
        SoLoud.instance.setVolume(stemHandles[activeEditableStem]!, getChannelState(activeEditableStem).volume);
        seekAllPlayers(currentPosition);
        if (isPlaying) SoLoud.instance.setPause(stemHandles[activeEditableStem]!, false);
        if (!activePlaybackSources.contains(activeEditableStem)) activePlaybackSources.add(activeEditableStem);
        dirtyStems.remove(activeEditableStem); 

        if (onShowMessage != null) onShowMessage!('Edits applied to ${activeEditableStem.toUpperCase()} stem.', isPreview: true);
      }
    } catch (e) {
      if (onShowMessage != null) onShowMessage!('Render failed: $e');
    } finally {
      isPreviewing = false; exportMessage = ''; notifyListeners();
    }
  }

  Future<void> renderStemPlugins(String stem) async {
    if (originalAudioBytes == null) return;
    isPreviewing = true; exportMessage = "Rendering plugins for $stem..."; processingProgress = 0.0; notifyListeners();

    try {
      if (currentTaskId == null) {
        var sessionData = await VoxrayApi.analyzeAdvanced(audioBytes: cachedStemBytes[stem]!, filename: '${stem}_offline.ogg', uploadType: 'stem', stemTarget: stem, instruments: [stem]);
        currentTaskId = sessionData['task_id'];
      }

      var result = await VoxrayApi.batchRenderAndMix(
        taskId: currentTaskId!,
        audioBytes: originalAudioBytes!,
        editManifest: {
          'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
          'edits': _enrichManifestWithPolyphonicContext(allStemsNotes[stem] ?? []),
          'solo_stem': stem,
          'processing_mode': processingMode
        },
      );

      if (result['status'] == 'success') {
        Uint8List previewBytes = await pollRenderJob(result['job_id']) ?? Uint8List(0);
        cachedStemBytes[stem] = previewBytes;
        if (stemHandles.containsKey(stem)) SoLoud.instance.stop(stemHandles[stem]!);
        stemSources[stem] = await SoLoud.instance.loadMem("stem_${stem}_edited", previewBytes);
        stemHandles[stem] = SoLoud.instance.play(stemSources[stem]!, paused: true);
        SoLoud.instance.setVolume(stemHandles[stem]!, getChannelState(stem).volume);
        seekAllPlayers(currentPosition);
        if (isPlaying) SoLoud.instance.setPause(stemHandles[stem]!, false);
        dirtyStems.remove(stem); 
      }
    } catch (e) {
      if (onShowMessage != null) onShowMessage!('Plugin render failed: $e');
    } finally {
      isPreviewing = false; exportMessage = ''; notifyListeners();
    }
  }

  Future<void> exportFinalMaster(String format) async {
    if (originalAudioBytes == null) return;
    isExporting = true; exportMessage = "Queuing $format Master..."; processingProgress = 0.0; notifyListeners();

    Map<String, dynamic> enrichedStemsNotesMap = {};
    allStemsNotes.forEach((k, v) => enrichedStemsNotesMap[k] = _enrichManifestWithPolyphonicContext(v));

    try {
      if (currentTaskId == null) {
        String lookupStem = activeEditableStem.isNotEmpty ? activeEditableStem : (cachedStemBytes.isNotEmpty ? cachedStemBytes.keys.first : '');
        var sessionData = await VoxrayApi.analyzeAdvanced(audioBytes: cachedStemBytes[lookupStem]!, filename: '${lookupStem}_offline.ogg', uploadType: 'stem', stemTarget: lookupStem, instruments: [lookupStem]);
        currentTaskId = sessionData['task_id'];
      }

      var data = await VoxrayApi.batchRenderAndMix(
        taskId: currentTaskId!,
        audioBytes: originalAudioBytes!,
        editManifest: {"mixer_state": mixerState.map((k, v) => MapEntry(k, v.toJson())), "all_stems_notes": enrichedStemsNotesMap, "processing_mode": processingMode},
        isTestMode: isTestModeActive,
        exportFormat: format,
      );

      if (data['status'] == 'success') {
        final Uint8List bytes = await pollRenderJob(data['job_id']) ?? Uint8List(0);
        String mimeType = format == 'mp3' ? 'audio/mpeg' : (format == 'flac' ? 'audio/flac' : 'audio/wav');
        String defaultName = '${originalFileName.split('.').first}_voxray_master';

        await FileSaver.instance.saveAs(name: defaultName, bytes: bytes, fileExtension: format, mimeType: MimeType.custom, customMimeType: mimeType);
        if (onShowMessage != null) onShowMessage!('Master mix saved successfully.');
      }
    } catch (e) {
      if (onShowMessage != null) onShowMessage!('Export failed: $e');
    } finally {
      isExporting = false; exportMessage = ''; notifyListeners();
    }
  }

  Future<void> exportStemsAsZip() async {
    if (cachedStemBytes.isEmpty) { 
      if (onShowMessage != null) onShowMessage!("No extracted audio stems available to export."); 
      return; 
    }
    isExporting = true; exportMessage = "Packing unmixed multi-track stems archive..."; notifyListeners();
    try {
      Archive arch = Archive();
      cachedStemBytes.forEach((k, v) => arch.addFile(ArchiveFile('${projectName}_stem_$k.ogg', v.length, v)));
      Uint8List zip = Uint8List.fromList(ZipEncoder().encode(arch)!);
      await FileSaver.instance.saveAs(name: "${projectName}_stems", bytes: zip, fileExtension: 'zip', mimeType: MimeType.zip);
      if (onShowMessage != null) onShowMessage!("All tracks exported successfully as unmixed multi-track stems.");
    } catch (e) { 
      if (onShowMessage != null) onShowMessage!("Stem tree generation failed: $e"); 
    } finally {
      isExporting = false; notifyListeners();
    }
  }

  Future<void> exportSynthAudio() async {
    if (rawNotes.isEmpty) return;
    isSynthRendering = true; synthMessage = "Rendering synth audio..."; notifyListeners();

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
        await FileSaver.instance.saveFile(name: defaultName, bytes: wavBytes, fileExtension: 'wav', mimeType: MimeType.custom, customMimeType: 'audio/wav');
        if (onShowMessage != null) onShowMessage!('Synth audio exported as WAV.');
      } else {
        String? path = await FileSaver.instance.saveAs(name: defaultName, bytes: wavBytes, fileExtension: 'wav', mimeType: MimeType.custom, customMimeType: 'audio/wav');
        if (path != null && path.isNotEmpty) {
          if (onShowMessage != null) onShowMessage!('Synth audio exported as WAV.');
        } else {
          if (onShowMessage != null) onShowMessage!('Export cancelled.');
        }
      }
    } catch (e) {
      if (onShowMessage != null) onShowMessage!('Synth export failed: $e');
    } finally {
      isSynthRendering = false; synthMessage = ''; notifyListeners();
    }
  }

  Future<void> downloadDossier() async {
    if (rawNotes.isEmpty) return;
    isExporting = true; exportMessage = "Generating dossier PDF..."; notifyListeners();

    try {
      var result = await VoxrayApi.generateDossier(
        taskId: currentTaskId ?? '',
        enrichedNotes: _enrichManifestWithPolyphonicContext(rawNotes),
        sessionMeta: {
          'filename': originalFileName,
          'duration': songDuration,
          'stem_target': activeEditableStem,
          'xray_enabled': rawNotes.any((n) => n.containsKey('contour')),
          'version': '1.5.0',
        },
      );

      if (result['status'] == 'success') {
        final Uint8List bytes = base64Decode(result['pdf_b64']);
        String saveName = originalFileName.contains('.')
            ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
            : originalFileName;

        if (kIsWeb) {
          await FileSaver.instance.saveFile(name: '${saveName}_dossier', bytes: bytes, fileExtension: 'pdf', mimeType: MimeType.custom, customMimeType: 'application/pdf');
        } else {
          String? path = await FileSaver.instance.saveAs(name: '${saveName}_dossier', bytes: bytes, fileExtension: 'pdf', mimeType: MimeType.custom, customMimeType: 'application/pdf');
          if (path != null && path.isNotEmpty) {
            if (onShowMessage != null) onShowMessage!('Dossier saved successfully.');
          } else {
            if (onShowMessage != null) onShowMessage!('Save cancelled.');
          }
        }
      }
    } catch (e) {
      if (onShowMessage != null) onShowMessage!('Dossier generation failed: $e');
    } finally {
      isExporting = false; exportMessage = ''; notifyListeners();
    }
  }

  Future<void> downloadPitchPrint({required bool fullSong, required String format}) async {
    if (rawNotes.isEmpty) return;
    isExporting = true; exportMessage = "Generating PitchPrint™..."; notifyListeners();

    double visibleStart = 0.0;
    double visibleEnd = songDuration;

    try {
      var result = await VoxrayApi.generatePitchPrint(
        taskId: currentTaskId ?? '',
        enrichedNotes: _enrichManifestWithPolyphonicContext(rawNotes),
        fullSong: fullSong,
        visibleStart: visibleStart,
        visibleEnd: visibleEnd,
        songDuration: songDuration,
      );

      if (result['status'] == 'success') {
        final Uint8List bytes = base64Decode(result['svg_b64']);
        String saveName = originalFileName.contains('.')
            ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
            : originalFileName;

        if (kIsWeb) {
          await FileSaver.instance.saveFile(name: '${saveName}_pitchprint', bytes: bytes, fileExtension: 'svg', mimeType: MimeType.custom, customMimeType: 'image/svg+xml');
        } else {
          String? path = await FileSaver.instance.saveAs(name: '${saveName}_pitchprint', bytes: bytes, fileExtension: 'svg', mimeType: MimeType.custom, customMimeType: 'image/svg+xml');
          if (path != null && path.isNotEmpty) {
            if (onShowMessage != null) onShowMessage!('PitchPrint™ saved successfully.');
          } else {
            if (onShowMessage != null) onShowMessage!('Save cancelled.');
          }
        }
      }
    } catch (e) {
      if (onShowMessage != null) onShowMessage!('PitchPrint™ generation failed: $e');
    } finally {
      isExporting = false; exportMessage = ''; notifyListeners();
    }
  }

  Uint8List packageProjectBytes() {
    Map<String, dynamic> projectData = {
      "voxray_version": "1.5.0", "project_name": projectName, "original_file": originalFileName, "original_file_path": originalFilePath, "song_duration": songDuration,
      "is_original_mix_available": isOriginalMixAvailable, "mixer_state": mixerState.map((k, v) => MapEntry(k, v.toJson())), "target_stems_selection": targetStemsSelection.toList(),
      "generated_stems": generatedStems.toList(), "all_stems_notes": allStemsNotes, "active_editable_stem": activeEditableStem, "history": {"undo_stack": undoStack, "redo_stack": redoStack}
    };
    Archive archive = Archive();
    archive.addFile(ArchiveFile('project.json', utf8.encode(json.encode(projectData)).length, utf8.encode(json.encode(projectData))));
    if (originalAudioBytes != null) archive.addFile(ArchiveFile('original_audio.dat', originalAudioBytes!.length, originalAudioBytes));
    cachedStemBytes.forEach((k, v) => archive.addFile(ArchiveFile('$k.ogg', v.length, v)));
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  void unpackProjectBytes(Uint8List vxpBytes) {
    Archive archive = ZipDecoder().decodeBytes(vxpBytes);
    Map<String, dynamic> projectData = {};
    for (ArchiveFile file in archive) {
      if (file.name == 'project.json') projectData = json.decode(utf8.decode(file.content as List<int>));
      else if (file.name == 'original_audio.dat') originalAudioBytes = file.content as Uint8List;
      else if (file.name.endsWith('.ogg')) cachedStemBytes[file.name.replaceAll('.ogg', '')] = file.content as Uint8List;
    }

    projectName = projectData['project_name'] ?? "Voxray_Session";
    originalFileName = projectData['original_file'] ?? "Unknown File";
    songDuration = (projectData['song_duration'] as num).toDouble();
    isOriginalMixAvailable = projectData['is_original_mix_available'] ?? true;
    mixerState = (projectData['mixer_state'] as Map).map((k, v) => MapEntry(k.toString(), ChannelState.fromJson(v)));
    targetStemsSelection = Set<String>.from(projectData['target_stems_selection']);
    generatedStems = Set<String>.from(projectData['generated_stems']);
    allStemsNotes = Map<String, List<dynamic>>.from(projectData['all_stems_notes']);
    activeEditableStem = projectData['active_editable_stem'] ?? '';
    undoStack = List<String>.from(projectData['history']['undo_stack']);
    redoStack = List<String>.from(projectData['history']['redo_stack']);
    isProjectLoaded = true; hasBeenSaved = true; isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    positionTimer?.cancel();
    pollingTimer?.cancel();
    super.dispose();
  }
}