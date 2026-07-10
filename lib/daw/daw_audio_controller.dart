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
/// Requires the consuming State to have the fields declared in VoxrayDAWState.
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

/// Drop this mixin onto VoxrayDAWState.
/// All methods call [setState] via the mixin's inherited binding.
mixin DawAudioController<T extends StatefulWidget> on State<T> {

  // ── Fields that must exist on the host State ──────────────────────────────
  // (Declared here as abstract getters/setters so the analyser is happy,
  //  but the host State provides the actual storage.)

  double get songDuration;
  set songDuration(double value);
  
  bool get isLoading;
  set isLoading(bool value);
  
  AudioSource? get masterSource;
  set masterSource(AudioSource? v);
  SoundHandle? get masterHandle;
  set masterHandle(SoundHandle? v);

  AudioSource? get synthSource;
  set synthSource(AudioSource? v);
  SoundHandle? get synthHandle;
  set synthHandle(SoundHandle? v);

  Map<String, AudioSource> get stemSources;
  Map<String, SoundHandle> get stemHandles;

  bool get isPlaying;
  set isPlaying(bool v);

  double get currentPosition;
  set currentPosition(double v);

  Set<String> get activePlaybackSources;
  Set<String> get stemsCurrentlyFetching;
  bool get isFetchingStems;
  set isFetchingStems(bool v);

  Map<String, String> get cachedStemPaths;
  Map<String, ChannelState> get mixerState;

  SynthSettings get synthSettings;
  bool get isSynthRendering;
  set isSynthRendering(bool v);
  String get synthMessage;
  set synthMessage(String v);

  List<dynamic> get rawNotes;
  //double get songDuration;
  String get currentTaskId_nullable; // expose nullable task id
  String get activeEditableStem;

  // ── Channel state helper ──────────────────────────────────────────────────

  ChannelState getChannelState(String key) {
    if (!mixerState.containsKey(key)) {
      mixerState[key] = ChannelState();
    }
    return mixerState[key]!;
  }

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
      final dir = await getTemporaryDirectory();
      final String filePath = '${dir.path}/${taskId}_$stemName.ogg';

      if (!cachedStemPaths.containsKey(stemName) || !await File(filePath).exists()) {
        final bytes = await fetchStemBytes(stemName, apiBase, taskId);
        await File(filePath).writeAsBytes(bytes);
        cachedStemPaths[stemName] = filePath;
      }

      if (stemHandles.containsKey(stemName)) {
        SoLoud.instance.stop(stemHandles[stemName]!);
      }

      // 1. Load the source
      stemSources[stemName] = await SoLoud.instance.loadFile(cachedStemPaths[stemName]!);
      
      // 2. NEW: Extract duration and update the global DAW state
      //final duration = SoLoud.instance.getLength(stemSources[stemName]!);
      //if (duration > songDuration) {
      //  setState(() {
      //    songDuration = duration;
      //  });
      //}
      // 1. Get the source length
      final duration = SoLoud.instance.getLength(stemSources[stemName]!);
      
      // 2. Set the global duration via the setter
      songDuration = duration; 
      
      // 3. Force UI rebuild
      setState(() {});

      // 3. Setup playback
      stemHandles[stemName] = SoLoud.instance.play(stemSources[stemName]!, paused: true);
      SoLoud.instance.setPause(stemHandles[stemName]!, true);

      final state = getChannelState(stemName);
      SoLoud.instance.setVolume(stemHandles[stemName]!, state.isMuted ? 0.0 : state.volume);
      SoLoud.instance.setPan(stemHandles[stemName]!, state.pan);

    } catch (e) {
      debugPrint('Stem track layer $stemName build failed: $e');
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
      debugPrint('Synth layer load failed: $e');
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
  //Future<void> playPreviewTone(double freq, SynthSettings settings) async {
  Future<void> playPreviewTone(double freq, [dynamic settings]) async {
    try {
      final dummyNote = [{
        'start_time': 0.0, 'end_time': 0.5,
        'actual_midi': 69.0 + (12 * math.log(freq / 440.0) / math.ln2),
        'cents_shift': 0, 'volume': 1.0, 'isMuted': false, 'isDeleted': false,
        'time_ratio': 1.0, 'vibrato_scale': 1.0, 'drift_scale': 1.0, 'amplitude': 1.0,
      }];
      final wavBytes = renderNotesToWavBytes(notes: dummyNote, duration: 0.5, settings: settings);
      final previewSrc = await SoLoud.instance.loadMem('preview', wavBytes);
      SoLoud.instance.play(previewSrc, volume: 0.7);
    } catch (e) {
      debugPrint('Preview error: $e');
    }
  }
}
