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
enum Waveform { sine, square, triangle, saw }

extension WaveformLabel on Waveform {
  String get label {
    switch (this) { 
      case Waveform.sine: return 'Sine'; 
      case Waveform.square: return 'Square'; 
      case Waveform.triangle: return 'Triangle'; 
      case Waveform.saw: return 'Saw'; 
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
    this.release = 0.15
  });
  
  ADSR copyWith({double? attack, double? decay, double? sustain, double? release}) { 
    return ADSR(
      attack: attack ?? this.attack, 
      decay: decay ?? this.decay, 
      sustain: sustain ?? this.sustain, 
      release: release ?? this.release
    ); 
  }
}

/// Bundles every adjustable parameter of the synth engine so it can be
/// passed around and persisted as a single value.
class SynthSettings {
  final Waveform waveform; 
  final ADSR adsr; 
  final int sampleRate; 
  final double masterGain; 
  final bool useXrayContour;
  final double vibratoRate; 
  final double vibratoDepth; 
  final double lpfCutoffMultiplier;
  
  const SynthSettings({
    this.waveform = Waveform.saw, 
    this.adsr = const ADSR(), 
    this.sampleRate = 44100, 
    this.masterGain = 0.25, 
    this.useXrayContour = true,
    this.vibratoRate = 5.0, 
    this.vibratoDepth = 0.0, 
    this.lpfCutoffMultiplier = 4.0,
  });

  SynthSettings copyWith({Waveform? waveform, ADSR? adsr, int? sampleRate, double? masterGain, bool? useXrayContour}) {
    return SynthSettings(
      waveform: waveform ?? this.waveform, 
      adsr: adsr ?? this.adsr, 
      sampleRate: sampleRate ?? this.sampleRate, 
      masterGain: masterGain ?? this.masterGain, 
      useXrayContour: useXrayContour ?? this.useXrayContour
    );
  }
}

/// Evaluates a single oscillator cycle at the given phase (radians).
double oscillator(Waveform waveform, double phase) {
  switch (waveform) {
    case Waveform.square: return sin(phase) >= 0 ? 1.0 : -1.0;
    case Waveform.triangle: return (2 / pi) * asin(sin(phase));
    case Waveform.saw: final normalized = phase / (2 * pi); return 2 * (normalized - normalized.floor()) - 1;
    case Waveform.sine: return sin(phase);
  }
}

/// Converts a (possibly fractional) MIDI note number to frequency in Hz.
double midiToHz(double midi) => 440.0 * pow(2, (midi - 69) / 12);

/// Evaluates the ADSR envelope at time [t] seconds into a note.
double adsrEnvelope(ADSR adsr, double t, double noteDuration) {
  if (t < adsr.attack) return adsr.attack > 0 ? t / adsr.attack : 1.0;
  else if (t < adsr.attack + adsr.decay) return 1 - (1 - adsr.sustain) * (adsr.decay > 0 ? (t - adsr.attack) / adsr.decay : 1.0);
  if (t >= noteDuration) return max(0.0, adsr.sustain * (1 - ((t - noteDuration) / adsr.release)));
  return adsr.sustain;
}

/// Computes the MIDI pitch of [note] at sample offset [i], honoring cents_shift / 
/// vibrato_scale, real X-Ray contour data, and synthesized vibrato settings.
double _pitchForSample({required Map note, required int i, required int noteSamples, required bool useXrayContour, required double t, required SynthSettings settings}) {
  final double displayMidi = (note['display_midi'] ?? note['actual_midi'] ?? 60.0).toDouble();
  final double actualMidi = (note['actual_midi'] ?? displayMidi).toDouble();
  final double centsShift = (note['cents_shift'] ?? 0).toDouble();
  final double vibrato = (note['vibrato_scale'] ?? 1.0).toDouble();
  final List? contour = useXrayContour ? note['contour'] as List? : null;

  double midi = actualMidi + centsShift / 100.0;
  if (contour != null && contour.isNotEmpty) {
    final double posF = contour.length > 1 ? (i / noteSamples) * (contour.length - 1) : 0.0;
    final int j0 = posF.floor().clamp(0, contour.length - 1);
    final int j1 = (j0 + 1).clamp(0, contour.length - 1);
    final double rawCents = (contour[j0] as num).toDouble() * (1 - (posF - j0)) + (contour[j1] as num).toDouble() * (posF - j0);
    midi = displayMidi + ((rawCents * vibrato) + centsShift) / 100.0;
  }
  
  if (settings.vibratoDepth > 0) midi += (sin(2 * pi * settings.vibratoRate * t) * settings.vibratoDepth) / 100.0;
  return midi;
}

/// Renders notes into a mono Float32List of raw, unnormalized PCM samples.
Float32List renderNotes({required List notes, required double duration, SynthSettings settings = const SynthSettings()}) {
  final int totalSamples = (duration * settings.sampleRate).ceil();
  final Float32List output = Float32List(max(totalSamples, 0));

  for (final note in notes) {
    if (note['isDeleted'] == true || note['isMuted'] == true) continue;
    final double startTime = (note['start_time'] ?? 0.0).toDouble();
    final double noteDuration = ((note['end_time'] ?? startTime).toDouble() - startTime) * (note['time_ratio'] ?? 1.0).toDouble();
    final double totalLength = noteDuration + settings.adsr.release; 
    
    final int start = (startTime * settings.sampleRate).round();
    final int noteSamples = (noteDuration * settings.sampleRate).round();
    final int renderSamples = (totalLength * settings.sampleRate).round();
    if (renderSamples <= 0) continue;

    double phase = 0.0;
    double lastOut = 0.0; 
    
    for (int i = 0; i < renderSamples; i++) {
      final int sampleIndex = start + i;
      if (sampleIndex < 0 || sampleIndex >= totalSamples) continue;

      final double t = i / settings.sampleRate;
      final double env = adsrEnvelope(settings.adsr, t, noteDuration);
      if (env <= 0) continue;

      final double midi = _pitchForSample(note: note, i: i, noteSamples: noteSamples, useXrayContour: settings.useXrayContour, t: t, settings: settings);
      final double freq = midiToHz(midi);

      phase += 2 * pi * freq / settings.sampleRate;
      if (phase > 2 * pi) phase -= 2 * pi;

      double rawOsc = oscillator(settings.waveform, phase) * env;
      
      // Pitch-tracking Low Pass Filter tied to envelope
      double cutoffFreq = freq * settings.lpfCutoffMultiplier * env; 
      double alpha = (2 * pi * cutoffFreq) / (2 * pi * cutoffFreq + settings.sampleRate);
      double filteredOut = lastOut + alpha * (rawOsc - lastOut);
      lastOut = filteredOut;

      output[sampleIndex] += filteredOut * settings.masterGain;
    }
  }
  return output;
}

/// Normalizes audio in place to prevent clipping from polyphonic summing.
void preventClipping(Float32List audio) {
  double peak = 0;
  for (final s in audio) { if (s.abs() > peak) peak = s.abs(); }
  if (peak > 1.0) { for (int i = 0; i < audio.length; i++) audio[i] /= peak; }
}

/// Converts floating point samples into little-endian 16-bit signed PCM bytes.
Uint8List floatToPCM16(Float32List input) {
  final bytes = BytesBuilder();
  for (final sample in input) {
    final int s = (sample * 32767).clamp(-32768, 32767).round();
    bytes.addByte(s & 0xFF); bytes.addByte((s >> 8) & 0xFF);
  }
  return bytes.toBytes();
}

/// Wraps mono 16-bit PCM audio in a standard WAV header.
Uint8List encodeWav(Float32List audio, {int sampleRate = 44100, int numChannels = 1}) {
  final pcm = floatToPCM16(audio);
  final header = BytesBuilder();
  header.add('RIFF'.codeUnits);
  header.add([ (36 + pcm.length) & 0xFF, ((36 + pcm.length) >> 8) & 0xFF, ((36 + pcm.length) >> 16) & 0xFF, ((36 + pcm.length) >> 24) & 0xFF ]);
  header.add('WAVEfmt '.codeUnits);
  header.add([ 16, 0, 0, 0, 1, 0, numChannels, 0 ]);
  header.add([ sampleRate & 0xFF, (sampleRate >> 8) & 0xFF, (sampleRate >> 16) & 0xFF, (sampleRate >> 24) & 0xFF ]);
  int byteRate = sampleRate * numChannels * 2;
  header.add([ byteRate & 0xFF, (byteRate >> 8) & 0xFF, (byteRate >> 16) & 0xFF, (byteRate >> 24) & 0xFF ]);
  header.add([ numChannels * 2, 0, 16, 0 ]);
  header.add('data'.codeUnits);
  header.add([ pcm.length & 0xFF, (pcm.length >> 8) & 0xFF, (pcm.length >> 16) & 0xFF, (pcm.length >> 24) & 0xFF ]);
  return (BytesBuilder()..add(header.toBytes())..add(pcm)).toBytes();
}

/// One-shot convenience: renders notes to a normalized, ready-to-play WAV byte buffer.
Uint8List renderNotesToWavBytes({required List notes, required double duration, SynthSettings settings = const SynthSettings()}) {
  final audio = renderNotes(notes: notes, duration: duration, settings: settings);
  preventClipping(audio);
  return encodeWav(audio, sampleRate: settings.sampleRate);
}

/// Client-Side DSP Processing Engine for Pitch Shifting and Crossfading
class ClientSideDSP {
  
  /// Applies local pitch shifting and crossfades to raw PCM/WAV byte arrays
  /// based on the user's `rawNotes` timeline edits using a Granular approach.
  static Future<Uint8List> applyPitchEditsAndCrossfades({
    required Uint8List audioBytes,
    required List<dynamic> notes,
    required int sampleRate,
  }) async {
    // Basic validation for WAV header (44 bytes)
    if (audioBytes.length < 44) return audioBytes;

    // Isolate PCM data, assuming 16-bit Mono (based on previous encodeWav implementation)
    final int dataSize = audioBytes.length - 44;
    final ByteData pcmData = ByteData.sublistView(audioBytes, 44);
    
    // Convert Int16 bytes to Float32 array for DSP mathematics
    Float32List audioBuffer = Float32List(dataSize ~/ 2);
    for (int i = 0; i < audioBuffer.length; i++) {
      audioBuffer[i] = pcmData.getInt16(i * 2, Endian.little) / 32768.0;
    }

    final int crossfadeSamples = (0.01 * sampleRate).round(); // 10ms Hanning crossfade

    for (var note in notes) {
      if (note['isDeleted'] == true || note['isMuted'] == true) continue;
      
      // Do not attempt to pitch shift silence blocks (MIDI 36)
      if ((note['actual_midi'] ?? 60.0).round() == 36) continue;

      int semitoneShift = note['semitone_shift'] ?? 0;
      double centsShift = (note['cents_shift'] ?? 0).toDouble();

      if (semitoneShift == 0 && centsShift == 0) continue; // No shift required

      double totalCents = (semitoneShift * 100) + centsShift;
      double pitchRatio = pow(2.0, totalCents / 1200.0).toDouble();

      double startTime = (note['start_time'] ?? 0.0).toDouble();
      double endTime = (note['end_time'] ?? startTime).toDouble();

      int startSample = (startTime * sampleRate).round();
      int endSample = (endTime * sampleRate).round();

      if (startSample >= audioBuffer.length || startSample >= endSample) continue;
      endSample = min(endSample, audioBuffer.length);

      // Extract the original phrase
      Float32List segment = audioBuffer.sublist(startSample, endSample);

      // Apply Time-Domain Granular Pitch Shift
      Float32List shiftedSegment = _granularPitchShift(segment, pitchRatio, sampleRate);
      
      // Truncate or zero-pad the shifted segment to fit the original exact timeline boundary 
      // (This prevents desyncing the rest of the stem over time)
      Float32List fittedSegment = Float32List(endSample - startSample);
      for(int i = 0; i < fittedSegment.length; i++) {
        if (i < shiftedSegment.length) {
          fittedSegment[i] = shiftedSegment[i];
        } else {
          fittedSegment[i] = 0.0;
        }
      }

      // Apply Hanning Window Crossfade at boundaries to eliminate zero-crossing clicks
      _applyCrossfade(fittedSegment, crossfadeSamples);

      // Splice back into main buffer
      for (int i = 0; i < fittedSegment.length; i++) {
        audioBuffer[startSample + i] = fittedSegment[i];
      }
    }

    // Anti-clip Normalization
    preventClipping(audioBuffer);

    // Re-encode back to WAV format 
    return encodeWav(audioBuffer, sampleRate: sampleRate);
  }

  /// Granular Overlap-Add algorithm for time-domain pitch shifting.
  /// Bypasses the heavy computational cost of a pure-Dart Phase Vocoder / FFT.
  static Float32List _granularPitchShift(Float32List input, double pitchRatio, int sampleRate) {
    if (pitchRatio == 1.0) return input;

    // Grain size: 30ms. Overlap: 50%
    int grainSize = (0.03 * sampleRate).round(); 
    int hopSize = grainSize ~/ 2; 

    // Output length will roughly match input length (time-preserving)
    Float32List output = Float32List(input.length);
    
    // We resample the input array based on the pitch ratio
    int resampledLength = (input.length / pitchRatio).round();
    Float32List resampledInput = Float32List(resampledLength);
    
    for (int i = 0; i < resampledLength; i++) {
      double mappedIndex = i * pitchRatio;
      int idx1 = mappedIndex.floor();
      int idx2 = min(idx1 + 1, input.length - 1);
      double frac = mappedIndex - idx1;
      
      if (idx1 >= 0 && idx1 < input.length) {
        // Linear interpolation
        resampledInput[i] = (input[idx1] * (1.0 - frac)) + (input[idx2] * frac);
      }
    }

    // Granular overlap-add to correct the time domain duration
    for (int outPos = 0; outPos < output.length - grainSize; outPos += hopSize) {
      // Map the output position to the corresponding position in the resampled array
      int inPos = (outPos * pitchRatio).round();
      if (inPos > resampledInput.length - grainSize) {
         inPos = resampledInput.length - grainSize;
      }
      if (inPos < 0) continue;

      for (int i = 0; i < grainSize; i++) {
        // Hanning Window for the grain
        double window = 0.5 * (1.0 - cos(2 * pi * i / (grainSize - 1)));
        output[outPos + i] += resampledInput[inPos + i] * window;
      }
    }

    return output;
  }

  static void _applyCrossfade(Float32List segment, int crossfadeLengthSamples) {
    if (segment.length <= crossfadeLengthSamples * 2) return;
    for (int i = 0; i < crossfadeLengthSamples; i++) {
      double fade = 0.5 * (1.0 - cos(pi * i / crossfadeLengthSamples));
      segment[i] *= fade; 
      segment[segment.length - 1 - i] *= fade; 
    }
  }
}
