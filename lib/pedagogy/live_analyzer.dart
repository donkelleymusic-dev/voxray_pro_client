import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'live_canvas.dart';

class LivePedagogyView extends StatefulWidget {
  const LivePedagogyView({Key? key}) : super(key: key);
  @override State<LivePedagogyView> createState() => _LivePedagogyViewState();
}

class _LivePedagogyViewState extends State<LivePedagogyView> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  PitchDetector? _pitchDetector;
  final List<double?> _pitchHistory = []; 
  final int _maxFrames = 150; 
  final double _sampleRate = 44100;
  
  // Accumulator buffer to ensure we only process exactly 2048 samples at a time
  final List<double> _audioBuffer = [];
  final int _targetBufferSize = 2048;

  @override
  void initState() {
    super.initState();
    _pitchDetector = PitchDetector(audioSampleRate: _sampleRate, bufferSize: _targetBufferSize);
    _startLiveTracking();
  }

  Future<void> _startLiveTracking() async {
    bool hasPermission = await _audioRecorder.hasPermission();
    
    if (!hasPermission) {
      String errorMsg = kIsWeb 
          ? "Browser blocked mic access. Ensure you are using HTTPS/localhost and check the URL bar icon to allow access."
          : "Microphone permission denied. Check native OS settings.";
          
      debugPrint("❌ $errorMsg");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg), 
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    final stream = await _audioRecorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 44100, numChannels: 1)
    );
    
    stream.listen((Uint8List data) async { 
      ByteData byteData = ByteData.sublistView(data);
      List<double> normalizedData = List<double>.generate(
        byteData.lengthInBytes ~/ 2, 
        (i) => byteData.getInt16(i * 2, Endian.little) / 32768.0
      );
      
      _audioBuffer.addAll(normalizedData);

      while (_audioBuffer.length >= _targetBufferSize) {
        List<double> processBuffer = _audioBuffer.sublist(0, _targetBufferSize);
        _audioBuffer.removeRange(0, _targetBufferSize);

        // --- FILTER 1: RMS NOISE GATE ---
        // Calculate the root mean square (volume) of the buffer.
        // Kills background rustling, distant talking, and quiet handling noise.
        double sumSquares = 0.0;
        for (double s in processBuffer) {
          sumSquares += s * s;
        }
        double rms = sqrt(sumSquares / processBuffer.length);
        
        // 0.01 is a solid baseline threshold for a -1.0 to 1.0 normalized buffer.
        if (rms < 0.01) { 
          if (mounted) {
            setState(() {
              _pitchHistory.add(null);
              if (_pitchHistory.length > _maxFrames) _pitchHistory.removeAt(0);
            });
          }
          continue;
        }

        final result = await _pitchDetector?.getPitchFromFloatBuffer(processBuffer); 
        
        if (!mounted) return;
        
        setState(() {
          bool validPitch = false;

          // Require a relatively confident pitch (0.65)
          if (result != null && result.pitched && result.probability > 0.65) {
            double hz = result.pitch;
            
            // --- FILTER 2: FREQUENCY BOUNDS ---
            // Your canvas draws MIDI 36 (65.4 Hz) to MIDI 84 (1046.5 Hz).
            // Foot taps register as < 40Hz. Bow squeaks register > 2000Hz.
            // Bounding the detection to 60Hz - 1100Hz kills the extremes cleanly.
            if (hz > 60.0 && hz < 1100.0) {
              double midiValue = 69 + 12 * (log(hz / 440.0) / ln2);
              
              // --- FILTER 3: TRANSIENT SPIKE REJECTION ---
              // If the pitch jumps by more than an octave+ (14 semitones) in a single 
              // 46ms frame, it is almost certainly a mechanical transient (click/bang).
              bool isSpike = false;
              for (int i = _pitchHistory.length - 1; i >= 0 && i >= _pitchHistory.length - 3; i--) {
                 if (_pitchHistory[i] != null) {
                    if ((midiValue - _pitchHistory[i]!).abs() > 14.0) {
                       isSpike = true;
                    }
                    break;
                 }
              }

              if (!isSpike) {
                _pitchHistory.add(midiValue);
                validPitch = true;
              }
            }
          }
          
          if (!validPitch) {
            _pitchHistory.add(null); 
          }
          
          if (_pitchHistory.length > _maxFrames) _pitchHistory.removeAt(0);
        });
      }
    });
  }

    final stream = await _audioRecorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 44100, numChannels: 1)
    );
    
    stream.listen((Uint8List data) async { 
      // Safely read only the exact valid bytes as Little-Endian PCM
      ByteData byteData = ByteData.sublistView(data);
      List<double> normalizedData = List<double>.generate(
        byteData.lengthInBytes ~/ 2, 
        (i) => byteData.getInt16(i * 2, Endian.little) / 32768.0
      );
      
      // Accumulate the data
      _audioBuffer.addAll(normalizedData);

      //Int16List intData = data.buffer.asInt16List();
      
      // Normalize 16-bit PCM to -1.0 to 1.0 floats
      //List<double> normalizedData = intData.map((e) => e / 32768.0).toList();
      
      // Accumulate the data
      //_audioBuffer.addAll(normalizedData);

      // Only process when we have enough data for the algorithm
      while (_audioBuffer.length >= _targetBufferSize) {
        List<double> processBuffer = _audioBuffer.sublist(0, _targetBufferSize);
        _audioBuffer.removeRange(0, _targetBufferSize);

        final result = await _pitchDetector?.getPitchFromFloatBuffer(processBuffer); 
        
        if (!mounted) return;
        
        setState(() {
          // The human voice (especially humming) contains a lot of breathiness and unpitched overtones. 
          // A threshold of 0.8 is quite strict for a live phone microphone.  try 0.6 or 0.7:
          if (result != null && result.pitched && result.probability > 0.6) {
            double midiValue = 69 + 12 * (log(result.pitch / 440.0) / ln2);
            _pitchHistory.add(midiValue);
          } else {
            _pitchHistory.add(null); 
          }
          
          if (_pitchHistory.length > _maxFrames) _pitchHistory.removeAt(0);
        });
      }
    });
  }

  @override 
  void dispose() { 
    _audioRecorder.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[950],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16), color: Colors.black45,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("LIVE INTONATION TRACKER", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                Text(
                  _pitchHistory.isNotEmpty && _pitchHistory.last != null ? "Target: ${_midiToNoteName(_pitchHistory.last!.round())}" : "Listening...",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                )
              ],
            ),
          ),
          Expanded(child: LiveScrollingCanvas(pitchHistory: _pitchHistory, maxFrames: _maxFrames)),
        ],
      ),
    );
  }

  String _midiToNoteName(int midi) {
    List<String> notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    int octave = (midi ~/ 12) - 1; // Used integer division (~/) for safety
    return "${notes[midi % 12]}$octave";
  }
}
