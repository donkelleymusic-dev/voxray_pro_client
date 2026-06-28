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
      
      // Actually show the user the error in the UI
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
      Int16List intData = data.buffer.asInt16List();
      
      // Normalize 16-bit PCM to -1.0 to 1.0 floats
      List<double> normalizedData = intData.map((e) => e / 32768.0).toList();
      
      // Accumulate the data
      _audioBuffer.addAll(normalizedData);

      // Only process when we have enough data for the algorithm
      while (_audioBuffer.length >= _targetBufferSize) {
        List<double> processBuffer = _audioBuffer.sublist(0, _targetBufferSize);
        _audioBuffer.removeRange(0, _targetBufferSize);

        final result = await _pitchDetector?.getPitchFromFloatBuffer(processBuffer); 
        
        if (!mounted) return;
        
        setState(() {
          if (result != null && result.pitched && result.probability > 0.8) {
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