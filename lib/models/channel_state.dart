// ==============================================================================
// COPYRIGHT AND OWNERSHIP DECLARATION
// ==============================================================================
// Copyright (c) 2026 Donald Bayard Kelley. All Rights Reserved.
// voXRAY Enterprise DSP & Roformer Engine — PROPRIETARY AND CONFIDENTIAL
// ==============================================================================

/// Mixer channel state model and related enums.
/// This file has no Flutter or audio dependencies — safe to unit-test in isolation.

// --- DRAG MODE ---

enum DragMode { off, semitone, microTuning }

// --- MIXER CHANNEL STATE MODEL ---

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
  double reverbRoomSize;
  double eqCutoff;
  double eqLowGain;
  double eqMidGain;
  double eqHighGain;

  // Clean, unified compressor parameters (Defaulting to professional standards)
  double compressorThreshold; // e.g. -24.0 dBFS
  double compressorRatio;     // e.g. 3.5:1

  // Pre-calculated envelope for the VU meter
  List<double> stem_rms_data;

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
    this.reverbRoomSize = 0.5,
    this.eqCutoff = 1.0,
    this.eqLowGain = 0.0,
    this.eqMidGain = 0.0,
    this.eqHighGain = 0.0,
    this.compressorThreshold = -24.0,
    this.compressorRatio = 3.5,
    this.stem_rms_data = const [],
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
    'reverbMix': reverbMix,
    'reverbRoomSize': reverbRoomSize,
    'eqCutoff': eqCutoff,
    'eqLowGain': eqLowGain,
    'eqMidGain': eqMidGain,
    'eqHighGain': eqHighGain,
    // Consistent camelCase for UI <-> Python JSON payload maps
    'compressorThreshold': compressorThreshold,
    'compressorRatio': compressorRatio,
    'stem_rms_data': stem_rms_data,
  };

  factory ChannelState.fromJson(Map<String, dynamic> json) {
    double loadedEq = (json['eqCutoff'] ?? 1.0).toDouble();
    if (loadedEq > 1.0) loadedEq = 1.0;
    return ChannelState(
      volume: (json['volume'] ?? 1.0).toDouble(),
      pan: (json['pan'] ?? 0.0).toDouble(),
      isMuted: json['isMuted'] ?? false,
      isSoloed: json['isSoloed'] ?? false,
      plugin1: json['plugin1'] ?? 'None',
      plugin2: json['plugin2'] ?? 'None',
      plugin3: json['plugin3'] ?? 'None',
      plugin4: json['plugin4'] ?? 'None',
      reverbMix: (json['reverbMix'] ?? 0.0).toDouble(),
      reverbRoomSize: (json['reverbRoomSize'] ?? 0.5).toDouble(),
      eqCutoff: loadedEq,
      eqLowGain: (json['eqLowGain'] ?? 0.0).toDouble(),
      eqMidGain: (json['eqMidGain'] ?? 0.0).toDouble(),
      eqHighGain: (json['eqHighGain'] ?? 0.0).toDouble(),
      // Handle fallback keys gracefully in case older offline projects are loaded
      compressorThreshold: (json['compressorThreshold'] ?? json['compressor_threshold'] ?? -24.0).toDouble(),
      compressorRatio: (json['compressorRatio'] ?? json['compressor_ratio'] ?? 3.5).toDouble(),
      //rmsEnvelope: (json['rmsEnvelope'] as List<dynamic>?)?.map((e) => e.toDouble()).toList() ?? [],
      stem_rms_data: (json['stem_rms_data'] as List<dynamic>?)?.map<double>((e) => (e as num).toDouble()).toList() ?? <double>[],
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
    double? reverbMix,
    double? reverbRoomSize,
    double? eqCutoff,
    double? eqLowGain,
    double? eqMidGain,
    double? eqHighGain,
    double? compressorThreshold,
    double? compressorRatio,
    List<double>? stem_rms_data,
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
      reverbMix: reverbMix ?? this.reverbMix,
      reverbRoomSize: reverbRoomSize ?? this.reverbRoomSize,
      eqCutoff: eqCutoff ?? this.eqCutoff,
      eqLowGain: eqLowGain ?? this.eqLowGain,
      eqMidGain: eqMidGain ?? this.eqMidGain,
      eqHighGain: eqHighGain ?? this.eqHighGain,
      compressorThreshold: compressorThreshold ?? this.compressorThreshold,
      compressorRatio: compressorRatio ?? this.compressorRatio,
      stem_rms_data: stem_rms_data ?? this.stem_rms_data,
    );
  }
}
