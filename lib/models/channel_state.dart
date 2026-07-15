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
  double compressionThreshold;
  double compressionRatio;
  double eqLowGain;
  double eqMidGain;
  double eqHighGain;

  double compressorThreshold = -24.0; // Default -24 dB
  double compressorRatio = 3.5;       // Default 3.5:1

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
    this.eqCutoff = 20000.0,
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
    // ADDED DSP PARAMETERS HERE:
    'reverbMix': reverbMix,
    'reverbRoomSize': reverbRoomSize,
    'eqCutoff': eqCutoff,
    'compressionThreshold': compressionThreshold,
    'compressionRatio': compressionRatio,
    'eqLowGain': eqLowGain,
    'eqMidGain': eqMidGain,
    'eqHighGain': eqHighGain,
    'compressor_threshold': compressorThreshold,
    'compressor_ratio': compressorRatio,
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
      // ADDED DSP PARAMETERS HERE:
      //: (json[''] ?? 0.0).toDouble(),
      reverbMix: (json['reverbMix'] ?? 0.0).toDouble(),
      reverbRoomSize: (json['reverbRoomSize'] ?? 0.5).toDouble(),
      eqCutoff: (json['eqCutoff'] ?? 20000.0).toDouble(),
      compressionThreshold: (json['compressionThreshold'] ?? 0.0).toDouble(),
      compressionRatio: (json['compressionRatio'] ?? 1.0).toDouble(),
      eqLowGain: (json['eqLowGain'] ?? 0.0).toDouble(),
      eqMidGain: (json['eqMidGain'] ?? 0.0).toDouble(),
      eqHighGain: (json['eqHighGain'] ?? 0.0).toDouble(),
      compressor_threshold: (json['compressorThreshold'] ?? 0.0).toDouble(),
      compressor_ratio: (json['compressorRatio'] ?? 0.0).toDouble(),
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
    double? compressionThreshold,
    double? compressionRatio,
    double? eqLowGain,
    double? eqMidGain,
    double? eqHighGain,
    double? eqCutoff,
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
      compressionThreshold: compressionThreshold ?? this.compressionThreshold,
      compressionRatio: compressionRatio ?? this.compressionRatio,
      eqLowGain: eqLowGain ?? this.eqLowGain,
      eqMidGain: eqMidGain ?? this.eqMidGain,
      eqHighGain: eqHighGain ?? this.eqHighGain,
      eqCutoff: eqCutoff ?? this.eqCutoff,
    );
  }
}
