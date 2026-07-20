// ==============================================================================
// COPYRIGHT AND OWNERSHIP DECLARATION
// ==============================================================================
// Copyright (c) 2026 Donald Bayard Kelley. All Rights Reserved.
// voXRAY Enterprise DSP & Roformer Engine — PROPRIETARY AND CONFIDENTIAL
// ==============================================================================

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math; 
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:io' show Platform, File;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/channel_state.dart';
import '../audio/vox_synth.dart';
import '../services/supabase_service.dart';
import '../main.dart'; // Gives access to VoxrayDAWStateBase

/// Drop this mixin onto VoxrayDAWState.
mixin DawApiService on VoxrayDAWStateBase {
  
  // ── Sibling Dependencies ─────────────────────────────────────────────────
  // These are handled by DawAudioController, so we declare them abstractly 
  // here so this API mixin can successfully call them.
  void pauseAllPlayers();
  void playAllPlayers();
  void seekAllPlayers(double seconds);
  Future<void> loadStemPlayerSource(String stemName, String apiBase, String taskId);
  Future<void> loadSynthSource();

  //String getPlatformString() {
  //  if (kIsWeb) return 'flutter_web';
  //  return 'flutter_${Platform.operatingSystem}';
  //}

  // =========================================================================
  // CONTEXT ENRICHMENT
  // =========================================================================

  List<Map<String, dynamic>> enrichManifestWithPolyphonicContext(List<dynamic> targetNotesList) {
    List<Map<String, dynamic>> enrichedList = [];
    for (var entry in targetNotesList) {
      Map<String, dynamic> note = Map<String, dynamic>.from(entry);
      double start = (note['start_time'] ?? 0.0).toDouble();
      double end   = (note['end_time']   ?? 0.0).toDouble();

      double actualMidi    = (note['actual_midi']    ?? 60.0).toDouble();
      int    semitoneShift =  note['semitone_shift'] ?? 0;
      double centsShift    = (note['cents_shift']    ?? 0).toDouble();
      double effectiveMidi = actualMidi + semitoneShift + (centsShift / 100.0);

      var overlaps = targetNotesList.where((alt) {
        if (alt['isDeleted'] == true) return false;
        double altStart = (alt['start_time'] ?? 0.0).toDouble();
        double altEnd   = (alt['end_time']   ?? 0.0).toDouble();
        double overlapStart = start > altStart ? start : altStart;
        double overlapEnd   = end   < altEnd   ? end   : altEnd;
        return (overlapEnd - overlapStart) > 0.08;
      }).toList();

      note['is_poly']         = overlaps.length > 1;
      note['target_freq']     = 440.0 * math.pow(2.0, (effectiveMidi - 69.0) / 12.0);
      note['component_count'] = overlaps.length;
      enrichedList.add(note);
    }
    return enrichedList;
  }

  // =========================================================================
  // UPLOAD & ANALYSIS
  // =========================================================================

  Future<void> testUploadSpeed(Uint8List bytes, String filename) async {
    
    logToSupabase('STARTING HTTPBIN UPLOAD TEST...');
    processingMessage = '🧪 STARTING HTTPBIN UPLOAD TEST...';
    
    final stopwatch = Stopwatch()..start();
    
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://httpbin.org/post'))
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
        
      var response = await request.send();
      stopwatch.stop();
      
      logToSupabase('TEST COMPLETE! STATUS: ${response.statusCode}, TIME: ${stopwatch.elapsedMilliseconds} ms (${stopwatch.elapsed.inSeconds} seconds)');
      processingMessage = '🧪 TEST COMPLETE!';
      processingMessage = '🧪 Status Code: ${response.statusCode}';
      processingMessage = '🧪 Total Time: ${stopwatch.elapsedMilliseconds} ms (${stopwatch.elapsed.inSeconds} seconds)';
      
    } catch (e) {
      stopwatch.stop();
      logToSupabase('TEST CRASHED after ${stopwatch.elapsed.inSeconds} seconds: $e');
      processingMessage = '🧪 TEST CRASHED after ${stopwatch.elapsed.inSeconds} seconds: $e';
    }
  }
  
  Future<Map<String, String>?> showUploadTypeDialog(BuildContext context) {
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String selectedType = 'mix';
        String selectedStem = 'vocals';
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Audio Upload Type',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioListTile<String>(
                  title: const Text('Full Mix', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Contains multiple instruments.',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: 'mix', groupValue: selectedType,
                  activeColor: Colors.tealAccent,
                  onChanged: (val) => setDialogState(() => selectedType = val!),
                ),
                RadioListTile<String>(
                  title: const Text('Single Stem', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Already isolated instrument.',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: 'stem', groupValue: selectedType,
                  activeColor: Colors.tealAccent,
                  onChanged: (val) => setDialogState(() => selectedType = val!),
                ),
                if (selectedType == 'stem') ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0, bottom: 8.0, left: 16.0),
                    child: Text('Identify this stem:',
                        style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: Colors.grey[850],
                      value: selectedStem,
                      items: [...popStems, ...orchStems, ...forensicStems].map((s) =>
                          DropdownMenuItem(value: s,
                              child: Text(s.toUpperCase(),
                                  style: const TextStyle(color: Colors.white)))).toList(),
                      onChanged: (val) => setDialogState(() => selectedStem = val!),
                    ),
                  ),
                ]
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () => Navigator.pop(
                    context, {'type': selectedType, 'stem': selectedStem}),
                child: const Text('Proceed'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _showAcousticProfileDialog() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String selectedProfile = 'standard';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text("Select Acoustic Profile", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<String>(
                    title: const Text("Standard / Pop / Modern", style: TextStyle(color: Colors.white)),
                    subtitle: const Text("Optimized for Vocals, Drums, Guitars, Bass, Keys...", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    value: 'standard',
                    groupValue: selectedProfile,
                    activeColor: Colors.tealAccent,
                    onChanged: (val) => setDialogState(() => selectedProfile = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text("Classical / Orchestral", style: TextStyle(color: Colors.white)),
                    subtitle: const Text("Optimized for Piano WITH Strings, Woodwinds, Brass", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    value: 'classical',
                    groupValue: selectedProfile,
                    activeColor: Colors.tealAccent,
                    onChanged: (val) => setDialogState(() => selectedProfile = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null), 
                  child: const Text("Cancel", style: TextStyle(color: Colors.white54))
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () => Navigator.pop(context, selectedProfile), 
                  child: const Text("Process Audio")
                ),
              ],
            );
          }
        );
      }
    );
  }
  

  Future<void> loadFileAndAnalyze(BuildContext context) async {
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.audio, withData: true);
    if (result == null) return;

    var uploadOptions = await showUploadTypeDialog(context);
    if (uploadOptions == null) return;

    // --- NEW: Ask for the acoustic profile if it's a full mix ---
    String acousticProfile = 'standard';
    if (uploadOptions['type'] == 'mix') {
      String? profile = await _showAcousticProfileDialog();
      if (profile == null) return; // User cancelled
      acousticProfile = profile;
    }

    Uint8List? audioBytes;
    if (result.files.single.bytes != null) {
      audioBytes = result.files.single.bytes!;
    } else if (result.files.single.path != null) {
      audioBytes = await File(result.files.single.path!).readAsBytes();
    } else return;

    // --- TEMPORARY INJECTION ---
    //await testUploadSpeed(audioBytes, result.files.single.name);
    //return; // Stop here, don't run the rest of the DAW logic yet
    // ---------------------------
    
    setState(() {
      isLoading          = true;
      processingProgress = 0.0;
      originalAudioBytes = audioBytes;
      originalFileName   = result.files.single.name;
      originalFilePath   = result.files.single.path ?? '';
      isProjectLoaded    = true;
      hasBeenSaved       = false;
      isXrayMode = false;
      dirtyStems.clear();
      cachedStemPaths.clear();
      cachedStemBytes.clear();
      for (var h in stemHandles.values) SoLoud.instance.stop(h);
      stemHandles.clear();
      stemSources.clear();
      activePlaybackSources.clear();
      allStemsNotes.clear();
      generatedStems.clear();
      targetStemsSelection.clear(); // Cleared out so the API can populate them
      currentTaskId  = null;
      currentJobId   = null;
      suggestedStems.clear();
      allStemsContinuousXray.clear();

      if (uploadOptions['type'] == 'mix') {
        isOriginalMixAvailable = true;
        activePlaybackSources.add('original');
        processingMessage = 'Analyzing and extracting all stems... Please keep app open.';
      } else {
        isOriginalMixAvailable   = false;
        activeEditableStem       = uploadOptions['stem']!;
        activePlaybackSources.add(activeEditableStem);
        targetStemsSelection.add(activeEditableStem);
        processingMessage = 'Uploading ${activeEditableStem.toUpperCase()} stem... Please keep app open.';
      }
    });

    if (synthHandle  != null) SoLoud.instance.stop(synthHandle!);
    if (masterHandle != null) SoLoud.instance.stop(masterHandle!);

    try {
      masterSource = await SoLoud.instance.loadMem('master', originalAudioBytes!);
      masterHandle = SoLoud.instance.play(masterSource!, paused: true);
      SoLoud.instance.setPause(masterHandle!, true);
      final origState = getChannelState('original');
      SoLoud.instance.setVolume(masterHandle!, origState.isMuted ? 0.0 : origState.volume);
      SoLoud.instance.setPan(masterHandle!, origState.pan);
    } catch (e) {
      logToSupabase('Audio preview setup failed (non-fatal): $e');
    }

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
        ..fields['instruments_json']  = jsonEncode(targetStemsSelection.toList())
        ..fields['upload_type']       = uploadOptions['type']!
        ..fields['stem_target']       = uploadOptions['type'] == 'stem' ? uploadOptions['stem']! : 'none'
        ..fields['acoustic_profile']  = acousticProfile 
        ..fields['is_test_mode']      = isTestModeActive.toString()
        ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!,
            filename: result.files.single.name));
      
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        request.fields['access_token'] = session.accessToken;
      }
      
      // =========================================================
      // 1. FREE THE EVENT LOOP: Pause the 60fps UI ticker
      // =========================================================
      setState(() { isUploading = true; });

      var response = await request.send().timeout(const Duration(seconds: 240), onTimeout: () {
        throw TimeoutException('File upload timed out (4 min max). The server took too long to respond.');
      });
      
      // =========================================================
      // 2. RESTORE THE EVENT LOOP: The upload finished safely
      // =========================================================
      setState(() { isUploading = false; });

      if (response.statusCode != 200) throw Exception('Server rejected file upload');

      var data = json.decode(await response.stream.bytesToString());
      currentTaskId = data['task_id'];
      currentJobId = data['job_id'];

      String targetToPoll = uploadOptions['type'] == 'stem' ? uploadOptions['stem']! : 'mix';
      await registerActiveJob(currentJobId!, currentTaskId!, 'INITIAL_STEM_ANALYSIS', targetToPoll);
      pollForStemData(currentJobId!, targetToPoll);

    } catch (e) {
      logToSupabase('Initialization Failed: $e');
      
      // =========================================================
      // 3. FAILSAFE: Always restore the loop if the upload crashes
      // =========================================================
      setState(() { 
        isUploading = false; 
        isLoading = false; 
        processingMessage = 'Failed to start.'; 
      });
      
      showSaveConfirmation('Initialization Failed: $e');
    }
  }

  Future<void> importIndividualStem(BuildContext context) async {
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.audio, withData: true);
    if (result == null) return;

    Uint8List bytes = result.files.single.bytes ?? await File(result.files.single.path!).readAsBytes();

    String? chosenIdentity = await showDialog<String>(
      context: context, barrierDismissible: false,
      builder: (ctx) {
        String selected = 'vocals';
        return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Identify Imported Track', style: TextStyle(color: Colors.white)),
          content: DropdownButton<String>(
            isExpanded: true, dropdownColor: Colors.grey[850], value: selected,
            items: [...popStems, ...orchStems].map((s) =>
                DropdownMenuItem(value: s,
                    child: Text(s.toUpperCase(), style: const TextStyle(color: Colors.white)))).toList(),
            onChanged: (v) => setDialogState(() => selected = v!),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent),
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Import', style: TextStyle(color: Colors.black))),
          ],
        ));
      },
    );
    if (chosenIdentity == null) return;

    setState(() {
      originalAudioBytes = bytes;
      originalFileName   = result.files.single.name;
      isLoading          = true;
      processingMessage  = 'Ingesting stem and generating tracking matrices...';
      targetStemsSelection.add(chosenIdentity);
      activeEditableStem = chosenIdentity;
    });

    try {
      var req = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
        ..fields['upload_type']      = 'stem'
        ..fields['stem_target']      = chosenIdentity
        ..fields['instruments_json'] = jsonEncode([chosenIdentity])
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: result.files.single.name));

      // =========================================================
      // 1. FREE THE EVENT LOOP
      // =========================================================
      setState(() { isUploading = true; });

      var res  = await req.send();
      
      // =========================================================
      // 2. RESTORE THE EVENT LOOP
      // =========================================================
      setState(() { isUploading = false; });

      var data = jsonDecode(await res.stream.bytesToString());
      currentTaskId = data['task_id'];
      currentJobId  = data['job_id'];
      pollForStemData(currentJobId!, chosenIdentity);
    } catch (e) {
      
      // =========================================================
      // 3. FAILSAFE RESTORE
      // =========================================================
      setState(() { 
        isUploading = false; 
        isLoading = false; 
      });
      showSaveConfirmation('Import matrix generation crashed: $e');
    }
  }

  // =========================================================================
  // POLLING LOOPS
  // =========================================================================

  void pollForStemData(String jobId, String targetStem) {
    pollingTimer?.cancel();
    pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        var statusRes = await http.get(Uri.parse('$apiBase/get-task-status?task_id=$jobId'));
        if (statusRes.statusCode == 200) {
          var statusData = json.decode(statusRes.body);
          setState(() {
            processingProgress = (statusData['progress'] ?? 0).toDouble() / 100.0;
            processingMessage  = statusData['message'] ?? 'Processing...';
          });

          if (statusData['status'] == 'complete') {
            timer.cancel();
            final result = statusData['result'];
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('active_job_id');
            await prefs.remove('active_target_stem');

            setState(() {
              if (result['valid_stems'] != null) {
                List<String> returnedStems = List<String>.from(result['valid_stems']);
                targetStemsSelection = returnedStems.toSet();
                generatedStems = returnedStems.toSet();
                
                // Ensure activeEditableStem does not default to 'instrumental'
                if (targetStem == 'mix' && returnedStems.isNotEmpty) {
                    activeEditableStem = returnedStems.firstWhere(
                      (s) => s != 'instrumental', 
                      orElse: () => returnedStems.first
                    );
                }
              }

              if (targetStem != 'mix') {
                 final allStemsMap = result['all_stems_notes'];
                 List<dynamic> stemNotes = [];
                 if (allStemsMap != null && allStemsMap[targetStem] != null) {
                   stemNotes = json.decode(json.encode(allStemsMap[targetStem]));
                 } else {
                   stemNotes = json.decode(json.encode(result['notes'] ?? []));
                 }
                 allStemsNotes[targetStem] = stemNotes;
                 generatedStems.add(targetStem);
                 
                 // Exclude instrumental from active playback sources
                 if (targetStem != 'instrumental') {
                   activePlaybackSources.add(targetStem);
                 }
                 processingMessage = 'Downloading audio for ${targetStem.toUpperCase()}...';
              } else {
                 if (result['all_stems_notes'] != null) {
                     allStemsNotes = Map<String, List<dynamic>>.from(result['all_stems_notes']);
                 }
                 for (var s in generatedStems) {
                     // Exclude instrumental so audio isn't doubled
                     if (s != 'instrumental') {
                       activePlaybackSources.add(s);
                     }
                 }
                 processingMessage = 'Downloading audio stems...';
              }

              // --- DEFAULT MUTING ---
              // Mute instrumental (remains cached for .vxp archives, but muted & hidden in UI)
              getChannelState('instrumental').isMuted = true;
              
              // Mute synth channel by default for newly processed audio
              getChannelState('synth').isMuted = true;

              if (result['stem_rms_data'] != null) {
                Map<String, dynamic> envelopes = result['stem_rms_data'];
                logToSupabase("DEBUG: Envelope dictionary received with ${envelopes.length} stems.");
                
                for (String stemName in envelopes.keys) {
                   var state = getChannelState(stemName);
                   state.rmsEnvelope = (envelopes[stemName] as List).map<double>((e) => (e as num).toDouble()).toList();
                   logToSupabase("DEBUG: Successfully assigned ${state.rmsEnvelope.length} RMS frames to track: $stemName");
                }
              } else {
                logToSupabase("DEBUG: CRITICAL: No stem_rms_data found in server response.");
              }
              
              double newDuration = (result['duration'] ?? songDuration).toDouble();
              if (newDuration > 0) {
                songDuration    = newDuration;
                loopEndBoundary = songDuration;
                int endIdx = markers.indexWhere((m) => m['id'] == 'mk_end');
                if (endIdx != -1) markers[endIdx]['time'] = songDuration;
              }
            });

            // --- AWAIT THE DOWNLOADS FIRST ---
            if (targetStem != 'mix') {
              await loadStemPlayerSource(targetStem, apiBase, currentTaskId!);
            } else {
              for (var s in generatedStems) {
                  await loadStemPlayerSource(s, apiBase, currentTaskId!);
              }
            }
            
            if (mounted) setState(() { isLoading = false; processingMessage = ''; });
            
            // --- NOW TRIGGER AUTOSAVE ---
            // The audio is downloaded, cachedStemPaths is fully populated!
            triggerAutoSave(); 
          }
        } else {
          timer.cancel();
          setState(() {
            isLoading = false;
            processingMessage = 'Error: Server returned ${statusRes.statusCode}';
            activePlaybackSources.remove(targetStem);
          });
          showSaveConfirmation('Processing Error: Server returned ${statusRes.statusCode}');
        }
      } catch (e) {
        logToSupabase('Polling network blink (app likely backgrounded): $e');
        if (mounted) setState(() => processingMessage = 'Reconnecting to server...');
      }
    });
  }

  void pollForXrayReprocess(String jobId, String targetStem) {
    pollingTimer?.cancel();
    pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        var statusRes = await http.get(Uri.parse('$apiBase/get-task-status?task_id=$jobId'));
        if (statusRes.statusCode == 200) {
          var statusData = json.decode(statusRes.body);
          if (mounted) setState(() => processingMessage = statusData['message'] ?? 'Processing X-Ray...');

          if (statusData['status'] == 'complete') {
            timer.cancel();
            await clearActiveJob();
            final result = statusData['result'];
            if (mounted) {
              setState(() {
                processingMessage = '';
                allStemsNotes[targetStem] = result['notes'];
                if (result['continuous_xray'] != null) {
                  allStemsContinuousXray[targetStem] = result['continuous_xray'];
                }
                isXrayProcessing = false;
                isXrayMode       = true;
                registerUndoSnapshot();
              });
              showSaveConfirmation('X-Ray high-resolution tracking complete.');
            }
          } else if (statusData['status'] == 'error') {
            timer.cancel();
            await clearActiveJob();
            if (mounted) {
              setState(() => isXrayProcessing = false);
              showSaveConfirmation('X-Ray Processing Error: ${statusData['message']}');
            }
          }
        }
      } catch (e) {
        logToSupabase('X-Ray polling network blink: $e');
      }
    });
  }

  // =========================================================================
  // STEM ON-DEMAND GENERATION
  // =========================================================================

  Future<void> generateStemOnDemand(String targetToGenerate) async {
    if (currentTaskId == null) return;
    if (generatedStems.contains(targetToGenerate)) return;

    await BackendService.logEvent(
      platform: getPlatformString(),
      severity: 'INFO',
      message: 'User initiated stem generation for $targetToGenerate',
    );

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('You must be logged in.');

    setState(() {
      isLoading          = true;
      processingProgress = 0.0;
      processingMessage  = 'Isolating $targetToGenerate & extracting notes...';
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/generate-stem-on-demand'))
        ..fields['task_id']      = currentTaskId!
        ..fields['target_stem']  = targetToGenerate
        ..fields['access_token'] = session.accessToken;

      var res = await request.send();
      if (res.statusCode == 200) {
        final resData = json.decode(await res.stream.bytesToString());
        final String jobId = resData['job_id'];
        currentJobId = jobId;
        await registerActiveJob(jobId, currentTaskId!, 'STEM_GENERATION', targetToGenerate);
        pollForStemData(jobId, targetToGenerate);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_job_id', jobId);
        await prefs.setString('active_target_stem', targetToGenerate);

        await BackendService.logEvent(
          platform: 'flutter', severity: 'INFO',
          message: 'Successfully generated stem $targetToGenerate',
        );
      } else if (res.statusCode == 402) {
        throw Exception('Insufficient DSP tokens. Please open your Wallet to top up.');
      } else {
        throw Exception('API Error: ${res.statusCode}');
      }
    } catch (e) {
      setState(() {
        isLoading         = false;
        processingMessage = '';
        activePlaybackSources.remove(targetToGenerate);
        if (generatedStems.isNotEmpty && !generatedStems.contains(activeEditableStem)) {
          activeEditableStem = generatedStems.first;
        }
      });
      await BackendService.logEvent(
        platform: 'flutter', severity: 'ERROR',
        message: 'Stem generation failed: $e',
      );
      showSaveConfirmation('Failed to generate ${targetToGenerate.toUpperCase()} stem: $e');
    }
  }

  // =========================================================================
  // X-RAY
  // =========================================================================

  Future<void> forceReprocessXray(BuildContext context) async {
    if (rawNotes.isEmpty) return;

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
          SizedBox(width: 8),
          Text('Force Reprocess', style: TextStyle(color: Colors.white)),
        ]),
        content: Text(
          'This will re-run the heavy X-Ray pitch extraction on the server for the current '
          '[${activeEditableStem.toUpperCase()}] stem and overwrite your current pitch contours. Proceed?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent[700]),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    bool cachedTransportState = isPlaying; 
    pauseAllPlayers();
    setState(() { isXrayProcessing = true; isXrayMode = true; });

    try {
      if (currentTaskId == null) {
        if (!cachedStemPaths.containsKey(activeEditableStem)) {
          throw Exception('Audio data not found in cache.');
        }
        showSaveConfirmation('Establishing new server session for Reprocess...');
        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type']      = 'stem'
          ..fields['stem_target']      = activeEditableStem
          ..fields['instruments_json'] = jsonEncode([activeEditableStem])
          ..files.add(await http.MultipartFile.fromPath('file', cachedStemPaths[activeEditableStem]!));

        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          registerUndoSnapshot();
          currentTaskId = jsonDecode(await sessionRes.stream.bytesToString())['task_id'];
        } else {
          throw Exception('Could not establish background server session.');
        }
      }

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-xray'))
        ..fields['task_id']         = currentTaskId!
        ..fields['stem_target']     = activeEditableStem
        ..fields['notes_manifest']  = jsonEncode(enrichManifestWithPolyphonicContext(rawNotes));

      var response = await request.send();
      if (response.statusCode == 200) {
        var data  = jsonDecode(await response.stream.bytesToString());
        String jobId = data['job_id'];
        await registerActiveJob(jobId, currentTaskId!, 'XRAY_REPROCESS', activeEditableStem);
        pollForXrayReprocess(jobId, activeEditableStem);
      } else {
        throw Exception('Server rejected X-Ray request.');
      }
    } catch (e) {
      logToSupabase('XRAY Reprocess error: $e');
      showSaveConfirmation('Reprocess failed: $e');
      setState(() => isXrayProcessing = false);
    } finally {
      if (cachedTransportState) playAllPlayers(); else pauseAllPlayers();
    }
  }

  Future<void> toggleXrayMode() async {
    if (rawNotes.isEmpty) return;
    if (isXrayMode || rawNotes.any((n) => n.containsKey('contour'))) {
      setState(() => isXrayMode = !isXrayMode);
      return;
    }

    pauseAllPlayers();
    setState(() { isXrayProcessing = true; isXrayMode = true; });

    try {
      if (currentTaskId == null) {
        String lookupKey = activeEditableStem.toLowerCase().trim();
        bool found = cachedStemPaths.keys.any((k) {
          if (k.toLowerCase().trim() == lookupKey) {
            activeEditableStem = k;
            return true;
          }
          return false;
        });

        if (!found) {
          showSaveConfirmation('Missing audio data. Available keys: ${cachedStemPaths.keys.toList()}');
          setState(() { isXrayProcessing = false; isXrayMode = false; });
          return;
        }

        showSaveConfirmation('Establishing new server session for X-Ray...');
        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type']      = 'stem'
          ..fields['stem_target']      = activeEditableStem
          ..fields['instruments_json'] = jsonEncode([activeEditableStem])
          ..files.add(await http.MultipartFile.fromPath('file', cachedStemPaths[activeEditableStem]!));

        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          registerUndoSnapshot();
          currentTaskId = jsonDecode(await sessionRes.stream.bytesToString())['task_id'];
        } else {
          throw Exception('Could not establish background server session.');
        }
      }

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-xray'))
        ..fields['task_id']        = currentTaskId!
        ..fields['stem_target']     = activeEditableStem
        ..fields['notes_manifest'] = jsonEncode(enrichManifestWithPolyphonicContext(rawNotes));

      var response = await request.send();
      if (response.statusCode == 200) {
        registerUndoSnapshot();
        var data  = jsonDecode(await response.stream.bytesToString());
        String jobId = data['job_id'];
        await registerActiveJob(jobId, currentTaskId!, 'XRAY_REPROCESS', activeEditableStem);
        pollForXrayReprocess(jobId, activeEditableStem);
      } else {
        throw Exception('Server rejected X-Ray request.');
      }
    } catch (e) {
      logToSupabase('XRAY error: $e');
      showSaveConfirmation('Connection error: $e');
      setState(() { isXrayMode = false; isXrayProcessing = false; });
    } finally {
      //playAllPlayers(); // why was it playing after xray completed?
    }
  }

  // =========================================================================
  // RENDER JOBS
  // =========================================================================

  // =========================================================================
  // RENDER JOBS
  // =========================================================================

  // FIX 1: Change return type from Uint8List? to Map<String, dynamic>?
  Future<Map<String, dynamic>?> pollRenderJob(String jobId) async {
    int retryCount = 0;
    const int maxRetries = 100;
    while (retryCount < maxRetries) {
      try {
        final res = await http.get(Uri.parse('$apiBase/get-task-status?task_id=$jobId'));
        if (res.statusCode == 200) {
          final taskData = jsonDecode(res.body);
          setState(() {
            processingProgress = (taskData['progress'] ?? 0).toDouble() / 100.0;
            if (isPreviewing || isExporting) exportMessage = taskData['message'] ?? 'Processing...';
          });
          if (taskData['status'] == 'complete') {
            // FIX 2: Return the JSON dictionary directly! No Base64!
            return taskData['result']; 
          } else if (taskData['status'] == 'error') {
            throw Exception(taskData['message']);
          }
        } else if (res.statusCode == 404) {
          throw Exception('Task expired or crashed on server');
        }
      } catch (e) {
        logToSupabase('Polling network blink: $e');
      }
      await Future.delayed(const Duration(seconds: 3));
      retryCount++;
    }
    throw Exception('Polling timed out after 5 minutes.');
  }

  Future<void> renderStemEdits(String activeStem) async {
    if (originalAudioBytes == null || activeStem.isEmpty) return;
    logToSupabase('renderStemEdits UI for stem: $activeStem');
    setState(() { isPreviewing = true; exportMessage = 'Queueing edits via Server...'; processingProgress = 0.0; });

    try {
      if (currentTaskId == null) {
        
      logToSupabase('renderStemEdits UI "currentTaskId == null" for stem: $activeStem');
        String lookupStem = activeEditableStem.isNotEmpty ? activeEditableStem
            : (cachedStemPaths.isNotEmpty ? cachedStemPaths.keys.first : '');
        if (lookupStem.isEmpty || !cachedStemPaths.containsKey(lookupStem)) {
          
          logToSupabase('renderStemEdits UI "No valid track state found in cache." for stem: $activeStem');
          throw Exception('No valid track state found in cache.');
        }
        showSaveConfirmation('Establishing server architecture link for Master Mix...');
        
        logToSupabase('renderStemEdits UI "posting to analyze-advanced" for stem: $activeStem, stem_target: $lookupStem, acoustic_profile: "standard"');
        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type']      = 'stem'
          ..fields['stem_target']      = lookupStem
          ..fields['instruments_json'] = jsonEncode([lookupStem])
          ..fields['acoustic_profile']  = 'standard' 
          ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'master.wav'));
          
        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          currentTaskId = jsonDecode(await sessionRes.stream.bytesToString())['task_id'];
        } else {
          
          logToSupabase('renderStemEdits UI "posting to analyze-advanced" failed: sessionRes.statusCode = $sessionRes.statusCode');
          throw Exception('Could not build a backend framework pipeline target session.');
        }
      }

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['task_id']      = currentTaskId!
        ..fields['is_test_mode'] = isTestModeActive.toString()
        ..files.add(http.MultipartFile.fromString(
          'render_data_file',
          jsonEncode({
            'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
            'edits': enrichManifestWithPolyphonicContext(rawNotes),
            'solo_stem': activeStem,
            'processing_mode': processingMode,
          }),
          filename: 'render_data.json',
        )); // <-- SEMICOLON CLOSES THE CASCADE

      // Attach ALL cached stems directly from the device
      // Attach ONLY the active stem directly from the device
      if (cachedStemPaths.containsKey(activeStem)) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'audio_stems', 
            cachedStemPaths[activeStem]!, 
            filename: 'stems_${currentTaskId}_$activeStem.ogg'
          )
        );
        logToSupabase('renderStemEdits UI "Attach ALL cached stems directly from the device" request.files.add filename: "stems_${currentTaskId}_$activeStem.ogg"');
      }

      var response = await request.send().timeout(const Duration(seconds: 120), onTimeout: () {
        
        logToSupabase('renderStemEdits UI "Attach ALL cached stems" Upload timed out. Connection is too slow.');
        throw TimeoutException('Upload timed out. Connection is too slow.');
      });
      var responseData = await http.Response.fromStream(response);
      if (responseData.statusCode != 200) {
        
        logToSupabase('renderStemEdits UI "Attach ALL cached stems" responseData.statusCode: ${responseData.statusCode}: ${responseData.body}');
        throw Exception('Server error ${responseData.statusCode}: ${responseData.body}');
      }

      var result = jsonDecode(responseData.body);
      if (result['status'] == 'success') {
        String jobId = result['job_id'];
        
        final renderResult = await pollRenderJob(jobId);
        if (renderResult == null) throw Exception('Render polling failed.');
        
        logToSupabase('renderStemEdits UI "Attach ALL cached stems" success: Downloading preview audio...');
        setState(() => exportMessage = 'Downloading preview audio...');
        String fileId = renderResult['file_id'];
        String rFormat = renderResult['format'];
        
        var dlRes = await http.get(Uri.parse('$apiBase/api/download-mix/$fileId?format=$rFormat')).timeout(const Duration(seconds: 60));
        if (dlRes.statusCode != 200) {
          
          logToSupabase('renderStemEdits UI statusCode: $dlRes.statusCode for http.get("$apiBase/api/download-mix/$fileId?format=$rFormat")');
          throw Exception('Failed to download preview audio.');
        }
        
        Uint8List previewBytes = dlRes.bodyBytes;

        if (stemHandles.containsKey(activeStem) &&
            SoLoud.instance.getIsValidVoiceHandle(stemHandles[activeStem]!)) {
          SoLoud.instance.stop(stemHandles[activeStem]!);
        }

        stemSources[activeStem] = await SoLoud.instance.loadMem('stem_${activeStem}_edited', previewBytes);
        stemHandles[activeStem] = SoLoud.instance.play(stemSources[activeStem]!, paused: true);
        SoLoud.instance.setVolume(stemHandles[activeStem]!, getChannelState(activeStem).volume);
        SoLoud.instance.setPan(stemHandles[activeStem]!, getChannelState(activeStem).pan);
        seekAllPlayers(currentPosition);

        if (!activePlaybackSources.contains(activeStem)) {
          setState(() { activePlaybackSources.add(activeStem); });
        }
        setState(() => dirtyStems.remove(activeStem));
        
        logToSupabase('renderStemEdits UI "Stem updated — tap Play to hear edits."');
        showSaveConfirmation('Stem updated — tap Play to hear edits.', isPreview: true);
      } else {
        
        logToSupabase('renderStemEdits UI "Render failed"');
        showSaveConfirmation('Render failed: ${result['message'] ?? 'unknown error'}');
      }
    } catch (e) {
      logToSupabase('Stem render failed: $e');
      showSaveConfirmation('Render failed: $e');
    } finally {
      setState(() { isPreviewing = false; exportMessage = ''; processingProgress = 0.0; });
    }
  }

  Future<void> renderStemPlugins(String stem) async {
    if (originalAudioBytes == null) return;
    setState(() { isPreviewing = true; exportMessage = 'Rendering plugins for $stem...'; processingProgress = 0.0; });

    try {
      if (currentTaskId == null) {
        String lookupStem = activeEditableStem.isNotEmpty ? activeEditableStem
            : (cachedStemPaths.isNotEmpty ? cachedStemPaths.keys.first : '');
        if (lookupStem.isEmpty || !cachedStemPaths.containsKey(lookupStem)) {
          throw Exception('No valid track state found in cache.');
        }
        showSaveConfirmation('Establishing server architecture link for Master Mix...');
        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type']      = 'stem'
          ..fields['stem_target']      = lookupStem
          ..fields['instruments_json'] = jsonEncode([lookupStem])
          ..fields['acoustic_profile']  = 'standard' 
          ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'master.wav'));
          
        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          currentTaskId = jsonDecode(await sessionRes.stream.bytesToString())['task_id'];
        } else {
          throw Exception('Could not build a backend framework pipeline target session.');
        }
      }

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['task_id']      = currentTaskId!
        ..fields['is_test_mode'] = isTestModeActive.toString()
        ..files.add(http.MultipartFile.fromString(
          'render_data_file',
          jsonEncode({
            'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
            'edits': enrichManifestWithPolyphonicContext(allStemsNotes[stem] ?? []),
            'solo_stem': stem,
            'processing_mode': processingMode,
          }),
          filename: 'render_data.json',
        )); // <-- SEMICOLON CLOSES THE CASCADE

      // Attach ALL cached stems directly from the device
      if (cachedStemPaths.containsKey(stem)) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'audio_stems', 
            cachedStemPaths[stem]!, 
            filename: 'stems_${currentTaskId}_$stem.ogg'
          )
        );
      }

      var response = await request.send().timeout(const Duration(seconds: 120));
      var responseData = await http.Response.fromStream(response);
      if (responseData.statusCode == 200) {
        var result = jsonDecode(responseData.body);
        if (result['status'] == 'success') {
          String jobId = result['job_id'];
          
          final renderResult = await pollRenderJob(jobId);
          if (renderResult == null) throw Exception('Render polling failed.');
          
          setState(() => exportMessage = 'Downloading plugin audio...');
          String fileId = renderResult['file_id'];
          String rFormat = renderResult['format'];
          
          var dlRes = await http.get(Uri.parse('$apiBase/api/download-mix/$fileId?format=$rFormat')).timeout(const Duration(seconds: 60));
          if (dlRes.statusCode != 200) throw Exception('Failed to download plugin audio.');
          
          Uint8List previewBytes = dlRes.bodyBytes;

          if (stemHandles.containsKey(stem) && SoLoud.instance.getIsValidVoiceHandle(stemHandles[stem]!)) {
            SoLoud.instance.stop(stemHandles[stem]!);
          }
          stemSources[stem] = await SoLoud.instance.loadMem('stem_${stem}_edited', previewBytes);
          stemHandles[stem] = SoLoud.instance.play(stemSources[stem]!, paused: true);
          SoLoud.instance.setVolume(stemHandles[stem]!, getChannelState(stem).volume);
          SoLoud.instance.setPan(stemHandles[stem]!, getChannelState(stem).pan);
          seekAllPlayers(currentPosition);
          setState(() => dirtyStems.remove(stem));
        }
      }
    } catch (e) {
      logToSupabase('Plugin render failed: $e');
      showSaveConfirmation('Plugin render failed: $e');
    } finally {
      setState(() { isPreviewing = false; exportMessage = ''; processingProgress = 0.0; });
    }
  }

  // =========================================================================
  // EXPORT
  // =========================================================================

  Future<void> exportFinalMaster(String format) async {
    if (originalAudioBytes == null) return;
    setState(() { isExporting = true; exportMessage = 'Queuing $format Master...'; processingProgress = 0.0; });

    Map<String, dynamic> enrichedStemsNotesMap = {};
    allStemsNotes.forEach((k, v) => enrichedStemsNotesMap[k] = enrichManifestWithPolyphonicContext(v));

    try {
      if (currentTaskId == null) {
        String lookupStem = activeEditableStem.isNotEmpty ? activeEditableStem
            : (cachedStemPaths.isNotEmpty ? cachedStemPaths.keys.first : '');
        if (lookupStem.isEmpty || !cachedStemPaths.containsKey(lookupStem)) {
          throw Exception('No valid track state found in cache.');
        }
        showSaveConfirmation('Establishing server architecture link for Master Mix...');
        var sessionReq = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-advanced'))
          ..fields['upload_type']      = 'stem'
          ..fields['stem_target']      = lookupStem
          ..fields['instruments_json'] = jsonEncode([lookupStem])
          ..fields['acoustic_profile']  = 'standard' 
          ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'master.wav'));
          
        var sessionRes = await sessionReq.send();
        if (sessionRes.statusCode == 200) {
          currentTaskId = jsonDecode(await sessionRes.stream.bytesToString())['task_id'];
        } else {
          throw Exception('Could not build a backend framework pipeline target session.');
        }
      }

      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['task_id']       = currentTaskId!
        ..fields['export_format'] = format
        ..fields['is_test_mode']  = isTestModeActive.toString()
        ..files.add(http.MultipartFile.fromString(
          'render_data_file',
          jsonEncode({
            'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
            'all_stems_notes': enrichedStemsNotesMap,
            'processing_mode': processingMode,
          }),
          filename: 'render_data.json',
        )); // <-- SEMICOLON CLOSES THE CASCADE

      // Attach ALL cached stems directly from the device
      for (var entry in cachedStemPaths.entries) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'audio_stems', 
            entry.value, 
            filename: 'stems_${currentTaskId}_${entry.key}.ogg'
          )
        );
      }

      var response = await request.send().timeout(const Duration(seconds: 120));
      var responseData = await http.Response.fromStream(response);
      if (responseData.statusCode != 200) {
        throw Exception('Server error ${responseData.statusCode}: ${responseData.body}');
      }

      var data = jsonDecode(responseData.body);
      if (data['status'] == 'success') {
        
        final renderResult = await pollRenderJob(data['job_id']);
        if (renderResult == null) throw Exception('Master render polling failed.');
        
        setState(() => exportMessage = 'Downloading final master...');
        String fileId = renderResult['file_id'];
        String rFormat = renderResult['format'];
        
        var dlRes = await http.get(Uri.parse('$apiBase/api/download-mix/$fileId?format=$rFormat')).timeout(const Duration(seconds: 120));
        if (dlRes.statusCode != 200) throw Exception('Failed to download final master audio.');
        
        final Uint8List bytes = dlRes.bodyBytes;

        final mimeMap = {'wav': 'audio/wav', 'mp3': 'audio/mpeg', 'flac': 'audio/flac', 'opus': 'audio/ogg'};
        final fileExt = format == 'opus' ? 'ogg' : format;
        String defaultName = originalFileName.contains('.')
            ? '${originalFileName.substring(0, originalFileName.lastIndexOf('.'))}_voxray_master'
            : '${originalFileName}_voxray_master';

        String? path = await FileSaver.instance.saveAs(
          name: defaultName, bytes: bytes, fileExtension: fileExt,
          mimeType: MimeType.custom, customMimeType: mimeMap[format] ?? 'audio/wav');
        showSaveConfirmation(path != null && path.isNotEmpty
            ? 'Master mix saved as ${format.toUpperCase()}.' : 'Export cancelled.');
      } else {
        showSaveConfirmation('Export failed: ${data['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      showSaveConfirmation('Export failed: $e');
    } finally {
      setState(() { isExporting = false; exportMessage = ''; processingProgress = 0.0; });
    }
  }

  Future<void> exportSynthAudio(String stem) async {
    if (rawNotes.isEmpty) return;
    setState(() { isSynthRendering = true; synthMessage = 'Rendering synth audio...'; });
    try {
      final Uint8List wavBytes = renderNotesToWavBytes(
          notes: rawNotes, duration: songDuration, settings: synthSettings);

      String defaultName = originalFileName.contains('.')
          ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
          : (originalFileName.isNotEmpty ? originalFileName : projectName);
      defaultName = '${defaultName}_synth';

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: defaultName, bytes: wavBytes, fileExtension: 'wav',
          mimeType: MimeType.custom, customMimeType: 'audio/wav');
        showSaveConfirmation('Synth audio exported as WAV.');
      } else {
        String? path = await FileSaver.instance.saveAs(
          name: defaultName, bytes: wavBytes, fileExtension: 'wav',
          mimeType: MimeType.custom, customMimeType: 'audio/wav');
        showSaveConfirmation(path != null && path.isNotEmpty
            ? 'Synth audio exported as WAV.' : 'Export cancelled.');
      }
    } catch (e) {
      showSaveConfirmation('Synth export failed: $e');
    } finally {
      setState(() { isSynthRendering = false; synthMessage = ''; });
    }
  }
  
  Future<void> exportStemsAsZip() async {
    if (cachedStemPaths.isEmpty) {
      showSaveConfirmation('No extracted audio stems available to export.');
      return;
    }
    setState(() { isExporting = true; exportMessage = 'Packing unmixed multi-track stems archive...'; });
    
    try {
      Archive arch = Archive();
      for (var entry in cachedStemPaths.entries) {
        final bytes = await File(entry.value).readAsBytes();
        
        // FIX 1: Dynamically grab the actual file extension (.wav or .ogg)
        String actualExtension = entry.value.split('.').last;
        
        arch.addFile(ArchiveFile('${projectName}_stem_${entry.key}.$actualExtension', bytes.length, bytes));
      }
      
      Uint8List zip = Uint8List.fromList(ZipEncoder().encode(arch)!);
      await FileSaver.instance.saveAs(
          name: '${projectName}_stems', bytes: zip,
          fileExtension: 'zip', mimeType: MimeType.zip);
          
      showSaveConfirmation('All tracks exported successfully as unmixed multi-track stems.');
    } catch (e) {
      showSaveConfirmation('Stem tree generation failed: $e');
    } finally {
      // FIX 2: Clear the export message!
      setState(() { isExporting = false; exportMessage = ''; });
    }
  }

  Future<void> downloadDossier() async {
    if (rawNotes.isEmpty) return;
    setState(() { isExporting = true; exportMessage = 'Generating dossier PDF...'; });
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/generate-dossier'))
        ..fields['task_id']       = currentTaskId ?? ''
        ..fields['notes_manifest'] = jsonEncode(enrichManifestWithPolyphonicContext(rawNotes))
        ..fields['session_meta']  = jsonEncode({
          'filename': originalFileName, 'duration': songDuration,
          'stem_target': activeEditableStem,
          'xray_enabled': rawNotes.any((n) => n.containsKey('contour')),
          'version': '1.5.0',
        });

      var response     = await request.send();
      var responseData = await http.Response.fromStream(response);
      if (responseData.statusCode != 200) throw Exception('Server error ${responseData.statusCode}');

      var result = jsonDecode(responseData.body);
      if (result['status'] == 'success') {
        final Uint8List bytes = base64Decode(result['pdf_b64']);
        String saveName = originalFileName.contains('.')
            ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
            : originalFileName;

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: '${saveName}_dossier', bytes: bytes,
            fileExtension: 'pdf', mimeType: MimeType.custom, customMimeType: 'application/pdf');
        } else {
          String? path = await FileSaver.instance.saveAs(
            name: '${saveName}_dossier', bytes: bytes,
            fileExtension: 'pdf', mimeType: MimeType.custom, customMimeType: 'application/pdf');
          showSaveConfirmation(path != null && path.isNotEmpty
              ? 'Dossier saved successfully.' : 'Save cancelled.');
        }
      }
    } catch (e) {
      showSaveConfirmation('Dossier generation failed: $e');
    } finally {
      setState(() { isExporting = false; exportMessage = ''; });
    }
  }

  Future<void> downloadPitchPrint({
    required bool fullSong,
    required String format,
    required double visibleStart,
    required double visibleEnd,
  }) async {
    if (rawNotes.isEmpty) return;
    setState(() { isExporting = true; exportMessage = 'Generating PitchPrint™...'; });
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/generate-pitchprint'))
        ..fields['task_id']        = currentTaskId ?? ''
        ..fields['notes_manifest'] = jsonEncode(enrichManifestWithPolyphonicContext(rawNotes))
        ..fields['full_song']      = fullSong.toString()
        ..fields['visible_start']  = visibleStart.toString()
        ..fields['visible_end']    = visibleEnd.toString()
        ..fields['song_duration']  = songDuration.toString();

      var response     = await request.send();
      var responseData = await http.Response.fromStream(response);
      if (responseData.statusCode != 200) throw Exception('Server error ${responseData.statusCode}');

      var result = jsonDecode(responseData.body);
      if (result['status'] == 'success') {
        final Uint8List bytes = base64Decode(result['svg_b64']);
        String saveName = originalFileName.contains('.')
            ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
            : originalFileName;

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: '${saveName}_pitchprint', bytes: bytes,
            fileExtension: 'svg', mimeType: MimeType.custom, customMimeType: 'image/svg+xml');
        } else {
          String? path = await FileSaver.instance.saveAs(
            name: '${saveName}_pitchprint', bytes: bytes,
            fileExtension: 'svg', mimeType: MimeType.custom, customMimeType: 'image/svg+xml');
          showSaveConfirmation(path != null && path.isNotEmpty
              ? 'PitchPrint™ saved successfully.' : 'Save cancelled.');
        }
      }
    } catch (e) {
      showSaveConfirmation('PitchPrint™ generation failed: $e');
    } finally {
      setState(() { isExporting = false; exportMessage = ''; });
    }
  }

  // =========================================================================
  // PROJECT PACKAGE / SAVE / LOAD
  // =========================================================================

  Future<Uint8List> packageProjectBytes() async {
    Map<String, dynamic> projectData = {
      'voxray_version': '1.5.0',
      'project_name': projectName,
      'original_file': originalFileName,
      'original_file_path': originalFilePath,
      'song_duration': songDuration,
      'is_original_mix_available': isOriginalMixAvailable,
      'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
      'target_stems_selection': targetStemsSelection.toList(),
      'generated_stems': generatedStems.toList(),
      'all_stems_notes': allStemsNotes,
      'all_stems_continuous_xray': allStemsContinuousXray,
      'active_editable_stem': activeEditableStem,
      'history': {'undo_stack': undoStack, 'redo_stack': redoStack},
      'markers': markers,
    };

    List<int> jsonBytes = utf8.encode(json.encode(projectData));
    Archive archive     = Archive();
    archive.addFile(ArchiveFile('project.json', jsonBytes.length, jsonBytes));

    if (originalAudioBytes != null) {
      archive.addFile(ArchiveFile(
          'original_audio.dat', originalAudioBytes!.length, originalAudioBytes));
    }

    // 1. Pack from RAM (Always works on Web, and works for fresh downloads on Android)
    for (var entry in cachedStemBytes.entries) {
      archive.addFile(ArchiveFile('${entry.key}.ogg', entry.value.length, entry.value));
    }

    // 2. Pack from Disk (Fallback for Android if it streamed from an offline save)
    if (!kIsWeb) {
      for (var entry in cachedStemPaths.entries) {
        // Only pack from disk if we didn't already pack it from RAM!
        if (!cachedStemBytes.containsKey(entry.key)) {
          try {
            final bytes = await File(entry.value).readAsBytes();
            archive.addFile(ArchiveFile('${entry.key}.ogg', bytes.length, bytes));
          } catch (e) {
            logToSupabase('Skipping missing file for package: ${entry.key}');
          }
        }
      }
    }

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  Future<void> saveVoxrayProjectAs() async {
    final bytes = await packageProjectBytes();
    String defaultSaveName = originalFileName.contains('.')
        ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
        : (originalFileName.isNotEmpty ? originalFileName : projectName);
  
    try {
      // 1. Correct v11 API: Direct call on FilePicker, no '.platform', no 'bytes' passed
      String? path = await FilePicker.saveFile(
        dialogTitle: 'Save VoxRay Project',
        fileName: '$defaultSaveName.vxp', 
        type: FileType.custom,
        allowedExtensions: ['vxp'],
      );
  
      if (path != null && path.isNotEmpty) {
        // 2. Write natively via Dart I/O to avoid the C++ plugin stack overflow
        final file = File(path);
        await file.writeAsBytes(bytes);
  
        setState(() { 
          currentProjectPath = path; 
          hasBeenSaved = true; 
          dirtyStems.clear(); 
        });
        showSaveConfirmation('Project saved successfully as offline .vxp archive.');
      } else {
        showSaveConfirmation('Save cancelled.');
      }
    } catch (e) {
      showSaveConfirmation('Save failed: $e');
    }
  }

  
  Future<void> saveVoxrayProject_crossplatform_problems() async {
    logToSupabase('client saveVoxrayProject()');
    if (currentProjectPath == null || kIsWeb || currentProjectPath!.startsWith('content://')) {
      
      logToSupabase('client saveVoxrayProject - currentProjectPath: ${currentProjectPath}, kIsWeb: ${kIsWeb}, currentProjectPath-startWith"content://" = ${currentProjectPath?.startsWith("content://")}');
      return; // Bails out safely on mobile cached URIs
    }
    final bytes = await packageProjectBytes();
    try {
      logToSupabase('client saveVoxrayProject - try(await File(path.writeAsBytes({$bytes}))');
      
      await File(currentProjectPath!).writeAsBytes(bytes);
      setState(() { hasBeenSaved = true; dirtyStems.clear(); });
      showSaveConfirmation('Project file successfully overwritten on disk.');
    } catch (e) {
      
      logToSupabase('client saveVoxrayProject - Overwrite failed: $e');
      showSaveConfirmation('Overwrite failed: $e');
    }
  }

  Future<void> saveVoxrayProjectAs() async {
    final bytes = await packageProjectBytes();
  
    // 1. Clean base name (strip any existing .zip or .vxp extensions)
    String baseName = originalFileName;
    if (baseName.endsWith('.zip')) {
      baseName = baseName.substring(0, baseName.length - 4);
    }
    if (baseName.endsWith('.vxp')) {
      baseName = baseName.substring(0, baseName.length - 4);
    }
    if (baseName.contains('.')) {
      baseName = baseName.substring(0, baseName.lastIndexOf('.'));
    }
    if (baseName.isEmpty) {
      baseName = projectName.isNotEmpty ? projectName : 'UntitledProject';
    }
  
    final String targetFileName = '$baseName.vxp';
  
    try {
      String? path;
  
      // 2. MOBILE & WEB
      if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
        path = await FilePicker.saveFile(
          dialogTitle: 'Save VoxRay Project',
          fileName: targetFileName,
          type: FileType.any, // FileType.any prevents OS/browser from enforcing application/zip extension
          bytes: bytes,
        );
  
        if (path != null || kIsWeb) {
          setState(() {
            if (path != null) {
              // Guarantee .zip is removed if the OS appended it
              currentProjectPath = path.endsWith('.zip')
                  ? path.substring(0, path.length - 4)
                  : path;
            }
            hasBeenSaved = true;
            dirtyStems.clear();
          });
          showSaveConfirmation('Project saved successfully.');
        } else {
          showSaveConfirmation('Save cancelled.');
        }
      } 
      // 3. DESKTOP (Windows/Mac/Linux)
      else {
        path = await FilePicker.saveFile(
          dialogTitle: 'Save VoxRay Project',
          fileName: targetFileName,
          type: FileType.any, // Prevents OS dialog from forcing MIME extensions
        );
  
        if (path != null && path.isNotEmpty) {
          // Strip trailing .zip if added by OS file dialog
          if (path.endsWith('.zip')) {
            path = path.substring(0, path.length - 4);
          }
          if (!path.endsWith('.vxp')) {
            path = '$path.vxp';
          }
  
          final file = File(path);
          await file.writeAsBytes(bytes);
  
          setState(() {
            currentProjectPath = path;
            hasBeenSaved = true;
            dirtyStems.clear();
          });
          showSaveConfirmation('Project saved successfully as offline .vxp archive.');
        } else {
          showSaveConfirmation('Save cancelled.');
        }
      }
    } catch (e) {
      showSaveConfirmation('Save failed: $e');
    }
  }

  Future<void> loadVoxrayProject(BuildContext context) async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom, allowedExtensions: ['vxp'], withData: true);
    if (result == null) return;

    String fileName = result.files.single.name.toLowerCase();
    if (!fileName.endsWith('.vxp')) {
      showSaveConfirmation('Invalid format: Please select a valid Voxray (.vxp) project archive.');
      return;
    }

    pauseAllPlayers();

    Uint8List vxpBytes;
    if (result.files.single.bytes != null) {
      vxpBytes = result.files.single.bytes!;
    } else if (result.files.single.path != null) {
      vxpBytes          = await File(result.files.single.path!).readAsBytes();
      currentProjectPath = result.files.single.path;
    } else return;

    setState(() {
      isProjectLoaded = true;
      hasBeenSaved    = true;
      dirtyStems.clear();
      cachedStemPaths.clear();
      cachedStemBytes.clear();
      for (var h in stemHandles.values) SoLoud.instance.stop(h);
      stemHandles.clear();
      stemSources.clear();
      activePlaybackSources.clear();
      allStemsNotes.clear();
      generatedStems.clear();
      if (masterHandle != null) SoLoud.instance.stop(masterHandle!);
      if (synthHandle  != null) SoLoud.instance.stop(synthHandle!);
      isLoading         = true;
      processingMessage = 'Unpacking .vxp archive and loading offline files...';
    });

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(vxpBytes);
    } catch (e) {
      setState(() { isLoading = false; processingMessage = ''; });
      showSaveConfirmation('Failed to parse .vxp archive.');
      return;
    }

    Map<String, dynamic> projectData = {};

    // 1. Safely grab the temp directory path ONLY if we are not on the web.
    String? tempDirPath;
    if (!kIsWeb) {
      final tDir = await getTemporaryDirectory();
      tempDirPath = tDir.path;
    }

    // 2. Unpack the archive
    for (ArchiveFile file in archive) {
      if (file.name == 'project.json') {
        projectData = json.decode(utf8.decode(file.content as List<int>));
      } else if (file.name == 'original_audio.dat') {
        originalAudioBytes = file.content as Uint8List;
      } else if (file.name.endsWith('.ogg')) {
        String stemName = file.name.replaceAll('.ogg', '');
        
        // WEB & MOBILE: Always load into RAM for instant playback
        cachedStemBytes[stemName] = file.content as Uint8List;
        
        // MOBILE ONLY: Write to disk to save RAM
        if (!kIsWeb && tempDirPath != null) {
          String extractPath = '$tempDirPath/imported_$stemName.ogg';
          await File(extractPath).writeAsBytes(file.content as List<int>);
          cachedStemPaths[stemName] = extractPath;
        }
      }
    }

    if (projectData.isEmpty) {
      setState(() { isLoading = false; processingMessage = ''; });
      showSaveConfirmation('Invalid project format: missing JSON configuration.');
      return;
    }

    setState(() {
      projectName           = projectData['project_name'] ?? 'Voxray_Session';
      originalFileName      = projectData['original_file'] ?? 'Unknown File';
      originalFilePath      = projectData['original_file_path'] ?? '';
      isOriginalMixAvailable = projectData['is_original_mix_available'] ?? true;

      if (projectData.containsKey('song_duration')) {
        songDuration = (projectData['song_duration'] as num).toDouble();
      } else {
        double maxTime = 30.0;
        if (projectData['all_stems_notes'] != null) {
          (projectData['all_stems_notes'] as Map).forEach((_, notesList) {
            for (var note in notesList) {
              double endTime = (note['end_time'] ?? 0.0).toDouble();
              if (endTime > maxTime) maxTime = endTime;
            }
          });
        }
        songDuration = maxTime;
      }

      // 1. Load the markers from the file first! (Fixed variable name)
      if (projectData['markers'] != null) {
        markers.clear();
        // Safely cast the JSON list back into your Dart List<Map> structure
        markers.addAll(List<Map<String, dynamic>>.from(
            projectData['markers'].map((m) => Map<String, dynamic>.from(m))
        ));
      }

      // 2. Now adjust the loop boundary based on the loaded markers/duration
      loopEndBoundary = songDuration;
      int endIdx = markers.indexWhere((m) => m['id'] == 'mk_end');
      if (endIdx != -1) markers[endIdx]['time'] = songDuration;
      
      if (projectData['mixer_state'] != null) {
        Map<String, dynamic> ms = projectData['mixer_state'];
        mixerState
          ..clear()
          ..addAll(ms.map((k, v) => MapEntry(k, ChannelState.fromJson(v))));
      }

      if (projectData['target_stems_selection'] != null) {
        targetStemsSelection
          ..clear()
          ..addAll(Set<String>.from(projectData['target_stems_selection']));
      }
      if (projectData['generated_stems'] != null) {
        generatedStems
          ..clear()
          ..addAll(Set<String>.from(projectData['generated_stems']));
      }
      if (projectData['all_stems_notes'] != null) {
        allStemsNotes = Map<String, List<dynamic>>.from(projectData['all_stems_notes']);
      }
      if (projectData['all_stems_continuous_xray'] != null) {
        allStemsContinuousXray = Map<String, List<dynamic>>.from(projectData['all_stems_continuous_xray']);
      }
      activeEditableStem = projectData['active_editable_stem'] ?? '';

      if (projectData['history'] != null) {
        undoStack           = List<String>.from(projectData['history']['undo_stack']);
        redoStack           = List<String>.from(projectData['history']['redo_stack']);
        undoStackContinuous = List<String>.from(projectData['history']['undo_stack_continuous'] ?? []);
        redoStackContinuous = List<String>.from(projectData['history']['redo_stack_continuous'] ?? []);
      }
      if (rawNotes.isNotEmpty && rawNotes.first.containsKey('contour')) isXrayMode = true;
    });

    if (originalAudioBytes != null && isOriginalMixAvailable) {
      activePlaybackSources.add('original');
      try {
        masterSource = await SoLoud.instance.loadMem('master', originalAudioBytes!);
        masterHandle = SoLoud.instance.play(masterSource!, paused: true);
        final origState = getChannelState('original');
        SoLoud.instance.setVolume(masterHandle!, origState.isMuted ? 0.0 : origState.volume);
        SoLoud.instance.setPan(masterHandle!, origState.pan);
      } catch (e) {
        logToSupabase('Offline master preview load failed: $e');
        showSaveConfirmation('Warning: Original mix format unsupported by local player. Muted.');
      }
    }

    for (String stem in generatedStems) {
      // FIX: Check if the audio exists on Disk OR in RAM!
      if (cachedStemPaths.containsKey(stem) || cachedStemBytes.containsKey(stem)) {
        activePlaybackSources.add(stem);
        await loadStemPlayerSource(stem, apiBase, currentTaskId ?? '');
        
        applyStemPlugins(stem); 
      }
    }

    if (rawNotes.isNotEmpty && rawNotes.first.containsKey('contour')) {
      await loadSynthSource();
    }

    // Inside your project load function, after stems are loaded into SoLoud:
    for (String stem in stemSources.keys) {
      // This forces the audio engine to read the newly loaded JSON state 
      // and apply the correct EQ, Reverb, and Compressor settings instantly!
      applyStemPlugins(stem); 
    }

    seekAllPlayers(0.0);
    setState(() { currentPosition = 0.0; isLoading = false; processingMessage = ''; });
    showSaveConfirmation('Project fully restored from offline archive.');
  }

  // =========================================================================
  // AUTO-SAVE & SESSION RESTORE
  // =========================================================================

  void triggerAutoSave() {
    if (currentTaskId == null || isRestoringState || kIsWeb) return; // ADD kIsWeb
    autoSaveTimer?.cancel();
    autoSaveTimer = Timer(const Duration(seconds: 2), _performAutoSave);
  }

  Future<void> _performAutoSave() async {
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/voxray_autosave.json');
      final data = {
        'timestamp': DateTime.now().toIso8601String(),
        'task_id': currentTaskId, 'job_id': currentJobId,
        'project_name': projectName, 'original_file': originalFileName,
        'song_duration': songDuration,
        'mixer_state': mixerState.map((k, v) => MapEntry(k, v.toJson())),
        'target_stems_selection': targetStemsSelection.toList(),
        'generated_stems': generatedStems.toList(),
        'all_stems_notes': allStemsNotes,
        'all_stems_continuous_xray': allStemsContinuousXray,
        'active_editable_stem': activeEditableStem,
        'cached_stem_paths': cachedStemPaths,
        'zoom_x': zoomX, 'zoom_y': zoomY,
        'markers': markers,
      };
      await file.writeAsString(jsonEncode(data));
      logToSupabase('Auto-saved to disk silently.');
    } catch (e) {
      logToSupabase('Auto-save failed silently: $e');
    }
  }

  Future<void> restoreAutoSaveOnStartup() async {
    if (kIsWeb) return;
    try {
      setState(() => isRestoringState = true);
      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/voxray_autosave.json');

      if (!await file.exists()) {
        setState(() => isRestoringState = false);
        return;
      }

      final data      = jsonDecode(await file.readAsString());
      final savedTime = DateTime.parse(data['timestamp']);
      if (DateTime.now().difference(savedTime).inHours > 24) {
        await file.delete();
        setState(() => isRestoringState = false);
        return;
      }

      // 1. RECONSTRUCT DYNAMIC PATHS (Fixes the OS Sandbox Bug)
      final tempDir = await getTemporaryDirectory();
      Map<String, String> repairedPaths = {};
      
      (data['cached_stem_paths'] as Map<String, dynamic>? ?? {}).forEach((key, val) {
        // Grab just the filename from the saved absolute path (e.g., "song_vocals.ogg")
        String fileName = val.toString().split('/').last;
        // Rebuild it using today's valid OS Temporary Directory
        repairedPaths[key] = '${tempDir.path}/$fileName';
      });

      setState(() {
        isLoading          = true;
        processingMessage  = 'Restoring previous session...';
        
        // Ensure variables aren't null so the UI menus wake up
        currentTaskId      = data['task_id'] ?? 'recovered_task_id';
        currentJobId       = data['job_id'];
        projectName        = data['project_name'] ?? 'Recovered Session';
        originalFileName   = data['original_file'] ?? 'Recovered Audio';
        
        songDuration       = data['song_duration'];
        zoomX              = data['zoom_x'] ?? 50.0;
        zoomY              = data['zoom_y'] ?? 8.0;

        // WAKE UP THE MENUS
        hasBeenSaved = false; 
        isProjectLoaded = true;

        if (data['markers'] != null) {
          markers.clear();
          // Safely cast the JSON list back into your Dart List<Map> structure
          markers.addAll(List<Map<String, dynamic>>.from(
              data['markers'].map((m) => Map<String, dynamic>.from(m))
          ));
        }
        
        isOriginalMixAvailable = data['original_file'] != null; // Optional: helps wake up export menus

        if (data['mixer_state'] != null) {
          final ms = data['mixer_state'] as Map<String, dynamic>;
          mixerState
            ..clear()
            ..addAll(ms.map((k, v) => MapEntry(k, ChannelState.fromJson(v))));
        }

        targetStemsSelection
          ..clear()
          ..addAll(Set<String>.from(data['target_stems_selection']));
        generatedStems
          ..clear()
          ..addAll(Set<String>.from(data['generated_stems']));
          
        allStemsNotes           = Map<String, List<dynamic>>.from(data['all_stems_notes']);
        allStemsContinuousXray  = Map<String, List<dynamic>>.from(data['all_stems_continuous_xray']);
        activeEditableStem      = data['active_editable_stem'];

        // Assign our repaired paths so the audio engine can actually find the files
        cachedStemPaths.clear();
        cachedStemPaths.addAll(repairedPaths);
      });

      // 2. LOAD AUDIO AND SYNC DSP MIXER
      for (String stem in generatedStems) {
        if (cachedStemPaths.containsKey(stem)) {
          activePlaybackSources.add(stem);
          
          // Wait for the track to load into memory...
          await loadStemPlayerSource(stem, apiBase, currentTaskId ?? '');
          
          // --- FIX THE MIXER BUG ---
          // Now that it is loaded, instantly force the C++ engine to turn the Reverb/Comp back on!
          applyStemPlugins(stem); 
        }
      }

      if (currentJobId != null && activeEditableStem.isNotEmpty) {
        pollForStemData(currentJobId!, activeEditableStem);
      } else {
        setState(() { isLoading = false; processingMessage = ''; });
      }

      showSaveConfirmation('Recovered previous unsaved session.');
    } catch (e) {
      logToSupabase('Failed to restore autosave: $e');
    } finally {
      setState(() => isRestoringState = false);
    }
  }

  // =========================================================================
  // JOB REGISTRATION & RECOVERY
  // =========================================================================

  Future<void> registerActiveJob(
      String jobId, String taskId, String jobType, String target) async {
    final prefs   = await SharedPreferences.getInstance();
    await prefs.setString('pending_backend_job', jsonEncode({
      'job_id': jobId, 'task_id': taskId, 'job_type': jobType, 'target': target,
    }));
    setState(() { currentJobId = jobId; currentTaskId = taskId; isLoading = true; });
  }

  Future<void> clearActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_backend_job');
    setState(() => currentJobId = null);
  }

  Future<void> resumeInterruptedJobsOnStartup() async {
    final prefs     = await SharedPreferences.getInstance();
    final jobString = prefs.getString('pending_backend_job');
    if (jobString == null) return;

    final jobData = jsonDecode(jobString);
    final jobId   = jobData['job_id']   as String;
    final taskId  = jobData['task_id']  as String;
    final jobType = jobData['job_type'] as String;
    final target  = jobData['target']   as String;

    setState(() {
      currentJobId      = jobId;
      currentTaskId     = taskId;
      isLoading         = true;
      processingMessage = 'Reconnecting to server...';
    });

    switch (jobType) {
      case 'STEM_GENERATION':
      case 'INITIAL_STEM_ANALYSIS':
        activeEditableStem = target;
        pollForStemData(jobId, target);
        break;
      case 'XRAY_REPROCESS':
        activeEditableStem = target;
        pollForXrayReprocess(jobId, target);
        break;
      case 'MASTER_RENDER':
      case 'STEM_EDIT_PREVIEW':
        setState(() { isPreviewing = true; exportMessage = 'Reconnecting to render engine...'; });
        pollRenderJob(jobId);
        break;
      default:
        await clearActiveJob();
        setState(() => isLoading = false);
    }
  }
}
