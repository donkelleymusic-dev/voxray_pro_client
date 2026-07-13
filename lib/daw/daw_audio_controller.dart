// ==============================================================================
// COPYRIGHT AND OWNERSHIP DECLARATION
// ==============================================================================
// Copyright (c) 2026 Donald Bayard Kelley. All Rights Reserved.
// voXRAY Enterprise DSP & Roformer Engine — PROPRIETARY AND CONFIDENTIAL
// ==============================================================================

/// DAW Audio Controller
///
/// Mixin for VoxrayDAWState that owns all SoLoud playback operations:
///   - play / pause / seek across all active sources
///   - stem source loading from disk
///   - synth WAV rendering and loading
///   - preview tone generation
///
/// Requires the consuming State to have the fields declared in VoxrayDAWStateBase.
/// No UI dialogs live here — only audio engine logic.

import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/channel_state.dart';
import '../audio/vox_synth.dart';
import '../main.dart'; // Gives access to VoxrayDAWStateBase

/// Drop this mixin onto VoxrayDAWState.
/// All methods call [setState] via the mixin's inherited binding.
mixin DawAudioController on VoxrayDAWStateBase {

  // ── Transport ─────────────────────────────────────────────────────────────

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
    // If that prints FALSE or NULL even though you just loaded a file, you have a disconnected State. issue.
    logToSupabase("DEBUG: MasterHandle valid? ${masterHandle != null ? SoLoud.instance.getIsValidVoiceHandle(masterHandle!) : 'NULL'}");
    setState(() => isPlaying = true);

    SoundHandle? revive(SoundHandle? handle, AudioSource? source, String key) {
      if (source == null) return handle;
      if (handle != null && SoLoud.instance.getIsValidVoiceHandle(handle)) {
        SoLoud.instance.setPause(handle, false);
        return handle;
      } else {
        final newHandle = SoLoud.instance.play(source, paused: true);
        final state = getChannelState(key);
        SoLoud.instance.setVolume(newHandle, state.isMuted ? 0.0 : state.volume);
        SoLoud.instance.setPan(newHandle, state.pan);
        SoLoud.instance.seek(newHandle, Duration(milliseconds: (currentPosition * 1000).round()));
        SoLoud.instance.setPause(newHandle, false);
        return newHandle;
      }
    }

    masterHandle = revive(masterHandle, masterSource, 'original');
    synthHandle  = revive(synthHandle,  synthSource,  'synth');
    for (String key in stemSources.keys) {
      stemHandles[key] = revive(stemHandles[key], stemSources[key], key)!;
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

  // ── Stem source loading ───────────────────────────────────────────────────

  Future<Uint8List> fetchStemBytes(String stemName, String apiBase, String taskId) async {
    final stemRes = await http.get(Uri.parse('$apiBase/api/stem/$taskId/$stemName?format=ogg'));
    if (stemRes.statusCode == 200) return stemRes.bodyBytes;
    throw Exception('Stem fetch error ${stemRes.statusCode}');
  }

  Future<void> loadStemPlayerSource(String stemName, String apiBase, String taskId) async {
    if (stemsCurrentlyFetching.contains(stemName)) return;

    setState(() {
      stemsCurrentlyFetching.add(stemName);
      isFetchingStems = true;
    });

    bool wasPlaying = isPlaying;
    if (wasPlaying) pauseAllPlayers();

    try {
      bool localFileExists = false;
      String? targetPath = cachedStemPaths[stemName];

      // 1. If the project loader or autosave registered a path, check if it's physically on disk
      if (targetPath != null && targetPath.isNotEmpty) {
        if (await File(targetPath).exists()) {
          localFileExists = true;
        }
      }

      // 2. Only download from the server if we lack a valid offline file path
      if (!localFileExists) {
        if (taskId.isEmpty) {
          throw Exception('Cannot fetch stem: no valid server Task ID or offline cache path available.');
        }
        final dir = await getTemporaryDirectory();
        final String networkFilePath = '${dir.path}/${taskId}_$stemName.ogg';
        
        logToSupabase("Local cache missing for track [$stemName]. Streaming from remote node deployment...");
        final bytes = await fetchStemBytes(stemName, apiBase, taskId);
        await File(networkFilePath).writeAsBytes(bytes);
        cachedStemPaths[stemName] = networkFilePath;
      } else {
        logToSupabase("Cache verified. Streaming [$stemName] directly from storage path: ${cachedStemPaths[stemName]}");
      }

      // Force clear the old voice handle before creating a new one to avoid dead engine pointers
      if (stemHandles.containsKey(stemName)) {
        if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[stemName]!)) {
          SoLoud.instance.stop(stemHandles[stemName]!);
        }
        stemHandles.remove(stemName);
      }

      // Read audio dynamically from disk (Streaming, not loading into RAM):
      final newSource = await SoLoud.instance.loadFile(
        cachedStemPaths[stemName]!,
        mode: LoadMode.disk, // <--- THIS PREVENTS RAM CRASHES!
      );

      // =======================================================================
      // 🎛️ ZERO-WET ARCHITECTURE: Pre-load and bypass DSP plugins
      // =======================================================================
      try {
        // 1. Activate the filters on this specific isolated audio source
        newSource.filters.freeverbFilter.activate();
        newSource.filters.compressorFilter.activate();
        
        // 2. Immediately bypass them (set wet mix to 0.0)
        // Note: Adjust parameter access based on your specific flutter_soloud version
        newSource.filters.freeverbFilter.setWet(0.0);
        
        // For compressors, bypass usually means 0 wetness, or a 1:1 ratio
        // newSource.filters.compressorFilter.setWet(0.0); 
        
        logToSupabase("DSP Graph compiled & bypassed successfully for track [$stemName]");
      } catch (fxError) {
        // If a filter fails, we log it but don't crash the track loading
        logToSupabase("Warning: Could not pre-load filters for [$stemName]: $fxError");
      }
      // =======================================================================

      // Assign the fully prepped source to your state map
      stemSources[stemName] = newSource;

      // Setup playback parameters
      stemHandles[stemName] = SoLoud.instance.play(stemSources[stemName]!, paused: true);
      SoLoud.instance.setPause(stemHandles[stemName]!, true);

      final state = getChannelState(stemName);
      logToSupabase("DSP Configuration: Channel track [$stemName] initialized with volume level: ${state.volume}");
      SoLoud.instance.setVolume(stemHandles[stemName]!, state.isMuted ? 0.0 : state.volume);
      SoLoud.instance.setPan(stemHandles[stemName]!, state.pan);

    } catch (e) {
      logToSupabase('Audio Layer Processing Failure [Track: $stemName]: $e', severity: 'ERROR');
      setState(() => activePlaybackSources.remove(stemName));
    } finally {
      setState(() {
        stemsCurrentlyFetching.remove(stemName);
        isFetchingStems = false;
      });
      seekAllPlayers(currentPosition);
      if (wasPlaying) playAllPlayers(); else pauseAllPlayers();
    }
  }
  
  Future<void> loadStemPlayerSource_old(String stemName, String apiBase, String taskId) async {
    if (stemsCurrentlyFetching.contains(stemName)) return;

    setState(() {
      stemsCurrentlyFetching.add(stemName);
      isFetchingStems = true;
    });

    bool wasPlaying = isPlaying;
    if (wasPlaying) pauseAllPlayers();

    try {
      bool localFileExists = false;
      String? targetPath = cachedStemPaths[stemName];

      // 1. If the project loader or autosave registered a path, check if it's physically on disk
      if (targetPath != null && targetPath.isNotEmpty) {
        if (await File(targetPath).exists()) {
          localFileExists = true;
        }
      }

      // 2. Only download from the server if we lack a valid offline file path
      if (!localFileExists) {
        if (taskId.isEmpty) {
          throw Exception('Cannot fetch stem: no valid server Task ID or offline cache path available.');
        }
        final dir = await getTemporaryDirectory();
        final String networkFilePath = '${dir.path}/${taskId}_$stemName.ogg';
        
        logToSupabase("Local cache missing for track [$stemName]. Streaming from remote node deployment...");
        final bytes = await fetchStemBytes(stemName, apiBase, taskId);
        await File(networkFilePath).writeAsBytes(bytes);
        cachedStemPaths[stemName] = networkFilePath;
      } else {
        logToSupabase("Cache verified. Streaming [$stemName] directly from storage path: ${cachedStemPaths[stemName]}");
      }

      // Force clear the old voice handle before creating a new one to avoid dead engine pointers
      if (stemHandles.containsKey(stemName)) {
        if (SoLoud.instance.getIsValidVoiceHandle(stemHandles[stemName]!)) {
          SoLoud.instance.stop(stemHandles[stemName]!);
        }
        stemHandles.remove(stemName);
      }

      // Read audio dynamically from disk (Streaming, not loading into RAM):
      stemSources[stemName] = await SoLoud.instance.loadFile(
        cachedStemPaths[stemName]!,
        mode: LoadMode.disk, // <--- THIS PREVENTS RAM CRASHES!
      );
      // Read audio into RAM and then play:
      //stemSources[stemName] = await SoLoud.instance.loadFile(cachedStemPaths[stemName]!);

      // Setup playback parameters
      stemHandles[stemName] = SoLoud.instance.play(stemSources[stemName]!, paused: true);
      SoLoud.instance.setPause(stemHandles[stemName]!, true);

      final state = getChannelState(stemName);
      logToSupabase("DSP Configuration: Channel track [$stemName] initialized with volume level: ${state.volume}");
      SoLoud.instance.setVolume(stemHandles[stemName]!, state.isMuted ? 0.0 : state.volume);
      SoLoud.instance.setPan(stemHandles[stemName]!, state.pan);

    } catch (e) {
      logToSupabase('Audio Layer Processing Failure [Track: $stemName]: $e', severity: 'ERROR');
      setState(() => activePlaybackSources.remove(stemName));
    } finally {
      setState(() {
        stemsCurrentlyFetching.remove(stemName);
        isFetchingStems = false;
      });
      seekAllPlayers(currentPosition);
      if (wasPlaying) playAllPlayers(); else pauseAllPlayers();
    }
  }

  // ── Synth layer ───────────────────────────────────────────────────────────

  Future<void> loadSynthSource() async {
    if (rawNotes.isEmpty) return;
    setState(() { isSynthRendering = true; synthMessage = 'Synthesizing note data...'; });

    bool wasPlaying = isPlaying;
    if (wasPlaying) pauseAllPlayers();

    try {
      final Uint8List wavBytes = renderNotesToWavBytes(
        notes: rawNotes,
        duration: songDuration,
        settings: synthSettings,
      );

      if (synthHandle != null) SoLoud.instance.stop(synthHandle!);
      synthSource = await SoLoud.instance.loadMem('synth_layer', wavBytes);
      synthHandle = SoLoud.instance.play(synthSource!, paused: true);
      SoLoud.instance.setPause(synthHandle!, true);

      final state = getChannelState('synth');
      SoLoud.instance.setVolume(synthHandle!, state.isMuted ? 0.0 : state.volume);
      SoLoud.instance.setPan(synthHandle!, state.pan);
    } catch (e) {
      logToSupabase('Synth layer load failed: $e');
      setState(() => activePlaybackSources.remove('synth'));
    } finally {
      setState(() { isSynthRendering = false; synthMessage = ''; });
      seekAllPlayers(currentPosition);
      if (wasPlaying) playAllPlayers(); else pauseAllPlayers();
    }
  }

  Future<void> refreshSynthLayerIfActive() async {
    if (activePlaybackSources.contains('synth')) {
      await loadSynthSource();
    }
  }

  // ── Preview tone ──────────────────────────────────────────────────────────
  
  Future<void> playPreviewTone(double freq, [dynamic settings]) async {
    try {
      final dummyNote = [{
        'start_time': 0.0, 'end_time': 0.5,
        'actual_midi': 69.0 + (12 * math.log(freq / 440.0) / math.ln2),
        'cents_shift': 0, 'volume': 1.0, 'isMuted': false, 'isDeleted': false,
        'time_ratio': 1.0, 'vibrato_scale': 1.0, 'drift_scale': 1.0, 'amplitude': 1.0,
      }];
      final wavBytes = renderNotesToWavBytes(
        notes: dummyNote, 
        duration: 0.5, 
        // Fallback to DAW's synthSettings if none are explicitly passed
        settings: settings ?? synthSettings
      );
      final previewSrc = await SoLoud.instance.loadMem('preview', wavBytes);
      SoLoud.instance.play(previewSrc, volume: 0.7);
    } catch (e) {
      logToSupabase('Preview error: $e');
    }
  }
  // Drop this into your main State class
  void updateStemDSP(String stemName, String pluginName, bool isEnabled) {
    // 1. Get the currently playing voice handle for this stem
    final handle = stemHandles[stemName];
    
    if (handle == null || !SoLoud.instance.getIsValidVoiceHandle(handle)) {
      // If the track isn't loaded or playing, we don't need to do anything. 
      // The Zero-Wet default will apply next time it loads!
      return; 
    }
  
    // 2. Route the UI interaction to the correct SoLoud Filter parameter
    try {
      switch (pluginName) {
        case 'Reverb':
          // If enabled, push Wet mix to 1.0 (or whatever your preferred max is)
          // If disabled, drop it to 0.0 (Bypassed)
          final targetWetness = isEnabled ? 0.8 : 0.0;
          
          // Note: Check your specific flutter_soloud version for the exact syntax.
          // It is typically accessed via the filter itself or the setFilterParameter method:
          SoLoud.instance.filters.freeverbFilter.setFilterParameter(
            handle, 
            0, // 0 is usually the attribute ID for 'Wet' in Freeverb
            targetWetness
          );
          break;
  
        case 'Compressor':
          // A bypassed compressor usually has a ratio of 1:1 and a high threshold
          final targetRatio = isEnabled ? 4.0 : 1.0; 
          
          SoLoud.instance.filters.compressorFilter.setFilterParameter(
            handle, 
            2, // Example attribute ID for Ratio
            targetRatio
          );
          break;
          
        // Add other DSPs like EQ, Delay, etc., here!
      }
      
      logToSupabase("DSP Real-Time Update: [$stemName] -> $pluginName (Enabled: $isEnabled)");
      
    } catch (e) {
      logToSupabase("Failed to update DSP on the fly for [$stemName]: $e");
    }
  }
}
