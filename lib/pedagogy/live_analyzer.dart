import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'dart:typed_data';
import 'dart:math';

import 'live_canvas.dart';

class LivePedagogyView extends StatefulWidget {
  const LivePedagogyView({Key? key}) : super(key: key);
  @override State<LivePedagogyView> createState() => _LivePedagogyViewState();
}

class _LivePedagogyViewState extends State<LivePedagogyView> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  PitchDetector? _pitchDetector;
  List<double?> _pitchHistory = []; 
  final int _maxFrames = 150; 
  final double _sampleRate = 44100;

  @override
  void initState() {
    super.initState();
    _pitchDetector = PitchDetector(audioSampleRate: _sampleRate.toDouble(), bufferSize: 2048);
    _startLiveTracking();
  }

  Future<void> _startLiveTracking() async {
    if (await _audioRecorder.hasPermission()) {
      final stream = await _audioRecorder.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 44100, numChannels: 1));
      stream.listen((Uint8List data) async { // <--- ADD async HERE
        Int16List intData = data.buffer.asInt16List();
        List<double> doubleData = intData.map((e) => e.toDouble()).toList();
        
        // The library returns a Future, so we await it
        final result = await _pitchDetector?.getPitchFromFloatBuffer(doubleData); 
        
        if (!mounted) return;
        
        setState(() {
          // Now 'result' is a PitchDetectorResult, and properties are accessible
          if (result != null && result.pitched && result.probability > 0.8) {
            double midiValue = 69 + 12 * (log(result.pitch / 440.0) / ln2);
            _pitchHistory.add(midiValue);
          } else {
            _pitchHistory.add(null); 
          }
          
          if (_pitchHistory.length > _maxFrames) _pitchHistory.removeAt(0);
        });
      });
    }
  }

  @override void dispose() { _audioRecorder.dispose(); super.dispose(); }

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
    int octave = (midi / 12).floor() - 1;
    return "${notes[midi % 12]}$octave";
  }
}