// ==============================================================================
// vox_synth.dart
// Lightweight pure-Dart synthesis engine for rendering Voxray note data
// (rawNotes) directly to audio, with no server round-trip required.
//
// Notes are the same `Map<String, dynamic>` objects already used throughout
// the app (start_time, end_time, actual_midi, display_midi, cents_shift,
// contour, vibrato_scale, time_ratio, isMuted, isDeleted, ...).
// ==============================================================================

import 'dart:math';
import 'dart:typed_data';

/// Oscillator waveform shapes available to the synth engine.
enum Waveform {
  sine,
  square,
  triangle,
  saw,
}

extension WaveformLabel on Waveform {
  String get label {
    switch (this) {
      case Waveform.sine:
        return 'Sine';
      case Waveform.square:
        return 'Square';
      case Waveform.triangle:
        return 'Triangle';
      case Waveform.saw:
        return 'Saw';
    }
  }
}

/// Attack / Decay / Sustain / Release envelope, all times in seconds
/// (except sustain, which is a 0..1 level).
class ADSR {
  final double attack;
  final double decay;
  final double sustain;
  final double release;

  const ADSR({
    this.attack = 0.01,
    this.decay = 0.05,
    this.sustain = 0.8,
    this.release = 0.08,
  });

  ADSR copyWith({
    double? attack,
    double? decay,
    double? sustain,
    double? release,
  }) {
    return ADSR(
      attack: attack ?? this.attack,
      decay: decay ?? this.decay,
      sustain: sustain ?? this.sustain,
      release: release ?? this.release,
    );
  }
}

/// Bundles every adjustable parameter of the synth engine so it can be
/// passed around and persisted as a single value.
class SynthSettings {
  final Waveform waveform;
  final ADSR adsr;
  final int sampleRate;

  /// Linear gain applied to every voice before mixdown. Polyphony sums
  /// voices, so this is kept conservative by default; final normalization
  /// only ever turns the mix *down* to avoid clipping, never boosts it.
  final double masterGain;

  /// When true and a note has X-Ray `contour` data, the synth follows the
  /// real extracted pitch contour (including any vibrato/cents edits the
  /// user has applied) instead of the static note pitch.
  final bool useXrayContour;

  const SynthSettings({
    this.waveform = Waveform.sine,
    this.adsr = const ADSR(),
    this.sampleRate = 44100,
    this.masterGain = 0.3,
    this.useXrayContour = true,
  });

  SynthSettings copyWith({
    Waveform? waveform,
    ADSR? adsr,
    int? sampleRate,
    double? masterGain,
    bool? useXrayContour,
  }) {
    return SynthSettings(
      waveform: waveform ?? this.waveform,
      adsr: adsr ?? this.adsr,
      sampleRate: sampleRate ?? this.sampleRate,
      masterGain: masterGain ?? this.masterGain,
      useXrayContour: useXrayContour ?? this.useXrayContour,
    );
  }
}

/// Evaluates a single oscillator cycle at the given phase (radians).
/// Square/triangle/saw are derived from a sine-equivalent phase so that
/// all waveforms line up at zero-crossings.
double oscillator(Waveform waveform, double phase) {
  switch (waveform) {
    case Waveform.square:
      return sin(phase) >= 0 ? 1.0 : -1.0;

    case Waveform.triangle:
      return (2 / pi) * asin(sin(phase));

    case Waveform.saw:
      final normalized = phase / (2 * pi);
      return 2 * (normalized - normalized.floor()) - 1;

    case Waveform.sine:
      return sin(phase);
  }
}

/// Converts a (possibly fractional) MIDI note number to frequency in Hz.
double midiToHz(double midi) {
  return 440.0 * pow(2, (midi - 69) / 12);
}

/// Evaluates the ADSR envelope at time [t] seconds into a note of total
/// duration [noteDuration] seconds.
double adsrEnvelope(ADSR adsr, double t, double noteDuration) {
  if (noteDuration <= 0) return 0.0;

  // If the note is shorter than attack+decay, compress the envelope so it
  // still completes within the note rather than clicking or overrunning.
  final double attack = adsr.attack;
  final double decay = adsr.decay;
  final double release = min(adsr.release, noteDuration);
  final double releaseStart = noteDuration - release;

  if (attack + decay >= releaseStart && releaseStart > 0) {
    // Squeeze attack/decay proportionally to fit before release begins.
    final double scale = releaseStart / (attack + decay == 0 ? 1 : attack + decay);
    final double scaledAttack = attack * scale;
    final double scaledDecay = decay * scale;

    if (t < scaledAttack) {
      return scaledAttack > 0 ? t / scaledAttack : 1.0;
    } else if (t < scaledAttack + scaledDecay) {
      final double x = scaledDecay > 0 ? (t - scaledAttack) / scaledDecay : 1.0;
      return 1 - (1 - adsr.sustain) * x;
    }
  } else {
    if (t < attack) {
      return attack > 0 ? t / attack : 1.0;
    } else if (t < attack + decay) {
      final double x = decay > 0 ? (t - attack) / decay : 1.0;
      return 1 - (1 - adsr.sustain) * x;
    }
  }

  if (t >= releaseStart) {
    if (release <= 0) return 0.0;
    final double x = ((t - releaseStart) / release).clamp(0.0, 1.0);
    return adsr.sustain * (1 - x);
  }

  return adsr.sustain;
}

/// Computes the MIDI pitch of [note] at sample offset [i] of [noteSamples]
/// total samples, honoring cents_shift / vibrato_scale, and (optionally)
/// the real X-Ray contour data if present and enabled.
double _pitchForSample({
  required Map note,
  required int i,
  required int noteSamples,
  required bool useXrayContour,
}) {
  final double displayMidi =
      (note['display_midi'] ?? note['actual_midi'] ?? 60.0).toDouble();
  final double actualMidi = (note['actual_midi'] ?? displayMidi).toDouble();
  final double centsShift = (note['cents_shift'] ?? 0).toDouble();
  final double vibrato = (note['vibrato_scale'] ?? 1.0).toDouble();

  final List? contour = useXrayContour ? note['contour'] as List? : null;

  if (contour != null && contour.isNotEmpty) {
    final double posF = contour.length > 1
        ? (i / noteSamples) * (contour.length - 1)
        : 0.0;
    final int j0 = posF.floor().clamp(0, contour.length - 1);
    final int j1 = (j0 + 1).clamp(0, contour.length - 1);
    final double frac = posF - j0;
    final double rawCents = (contour[j0] as num).toDouble() * (1 - frac) +
        (contour[j1] as num).toDouble() * frac;
    final double manipulatedCents = (rawCents * vibrato) + centsShift;
    return displayMidi + manipulatedCents / 100.0;
  }

  return actualMidi + centsShift / 100.0;
}

/// Renders [notes] (the app's `rawNotes` list of maps) into a mono
/// Float32List of raw, *unnormalized* PCM samples spanning [duration]
/// seconds at the sample rate configured in [settings].
///
/// Respects `isDeleted`, `isMuted`, `time_ratio` (stretches note length),
/// `cents_shift`, `vibrato_scale`, and X-Ray `contour` data exactly as the
/// piano-roll grid visualizes them.
Float32List renderNotes({
  required List notes,
  required double duration,
  SynthSettings settings = const SynthSettings(),
}) {
  final int sampleRate = settings.sampleRate;
  final int totalSamples = (duration * sampleRate).ceil();
  final Float32List output = Float32List(max(totalSamples, 0));

  for (final note in notes) {
    if (note['isDeleted'] == true) continue;
    if (note['isMuted'] == true) continue;

    final double startTime = (note['start_time'] ?? 0.0).toDouble();
    final double endTime = (note['end_time'] ?? startTime).toDouble();
    final double timeRatio = (note['time_ratio'] ?? 1.0).toDouble();
    final double effectiveEnd =
        startTime + (endTime - startTime) * timeRatio;

    final int start = (startTime * sampleRate).round();
    final int end = (effectiveEnd * sampleRate).round();
    final int noteSamples = end - start;
    if (noteSamples <= 0) continue;

    double phase = 0.0;

    for (int i = 0; i < noteSamples; i++) {
      final int sampleIndex = start + i;
      if (sampleIndex < 0 || sampleIndex >= totalSamples) continue;

      final double midi = _pitchForSample(
        note: note,
        i: i,
        noteSamples: noteSamples,
        useXrayContour: settings.useXrayContour,
      );
      final double freq = midiToHz(midi);

      final double t = i / sampleRate;
      final double noteDuration = noteSamples / sampleRate;
      final double env = adsrEnvelope(settings.adsr, t, noteDuration);

      phase += 2 * pi * freq / sampleRate;
      if (phase > 2 * pi) {
        phase -= 2 * pi * (phase / (2 * pi)).floorToDouble();
      }

      output[sampleIndex] +=
          oscillator(settings.waveform, phase) * env * settings.masterGain;
    }
  }

  return output;
}

/// Normalizes [audio] in place, but only ever turns the signal *down*
/// (never boosts quiet passages), to prevent clipping from polyphonic
/// summing while preserving the synth's natural dynamics.
void preventClipping(Float32List audio) {
  double peak = 0;
  for (final s in audio) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  if (peak > 1.0) {
    for (int i = 0; i < audio.length; i++) {
      audio[i] /= peak;
    }
  }
}

/// Converts floating point samples in [-1, 1] into little-endian 16-bit
/// signed PCM bytes.
Uint8List floatToPCM16(Float32List input) {
  final bytes = BytesBuilder();
  for (final sample in input) {
    final int s = (sample * 32767).clamp(-32768, 32767).round();
    bytes.addByte(s & 0xFF);
    bytes.addByte((s >> 8) & 0xFF);
  }
  return bytes.toBytes();
}

/// Wraps mono 16-bit PCM [audio] in a standard 44-byte WAV header.
Uint8List encodeWav(
  Float32List audio, {
  int sampleRate = 44100,
  int numChannels = 1,
}) {
  final Uint8List pcm = floatToPCM16(audio);
  const int bitsPerSample = 16;
  final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  final int blockAlign = numChannels * (bitsPerSample ~/ 8);
  final int dataSize = pcm.length;

  final header = BytesBuilder();

  void writeAscii(String s) => header.add(s.codeUnits);
  void writeUint32(int v) => header.add([
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ]);
  void writeUint16(int v) => header.add([v & 0xFF, (v >> 8) & 0xFF]);

  writeAscii('RIFF');
  writeUint32(36 + dataSize);
  writeAscii('WAVE');

  writeAscii('fmt ');
  writeUint32(16); // PCM fmt chunk size
  writeUint16(1); // PCM format
  writeUint16(numChannels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);

  writeAscii('data');
  writeUint32(dataSize);

  final result = BytesBuilder();
  result.add(header.toBytes());
  result.add(pcm);
  return result.toBytes();
}

/// One-shot convenience: renders [notes] to a normalized, ready-to-play or
/// ready-to-save mono WAV byte buffer.
Uint8List renderNotesToWavBytes({
  required List notes,
  required double duration,
  SynthSettings settings = const SynthSettings(),
}) {
  final Float32List audio = renderNotes(
    notes: notes,
    duration: duration,
    settings: settings,
  );
  preventClipping(audio);
  return encodeWav(audio, sampleRate: settings.sampleRate);
}
