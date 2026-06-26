import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;
import 'package:just_audio/just_audio.dart';
import 'dart:typed_data';

void main() => runApp(MaterialApp(
  home: const VoxrayDAW(), 
  theme: ThemeData(brightness: Brightness.dark)
));

class VoxrayDAW extends StatefulWidget {
  const VoxrayDAW({Key? key}) : super(key: key);
  @override
  State<VoxrayDAW> createState() => _VoxrayDAWState();
}

class _VoxrayDAWState extends State<VoxrayDAW> {
  final AudioPlayer _masterPlayer = AudioPlayer();
  
  // State
  List<dynamic> _rawNotes = [];
  List<dynamic> _chords = [];
  List<String> _undoStack = [];
  List<String> _redoStack = [];
  
  bool _isLoading = false;
  bool _isMixerOpen = false;
  double _songDuration = 1.0;
  double _currentPosition = 0.0;
  double _zoomX = 150.0;
  String _projectName = "Voxray_Session";
  Uint8List? _originalAudioBytes;

  // Track Mix
  double _targetVolume = 0.85;
  double _accompVolume = 1.0;

  // Settings
  String _temperament = 'Equal';
  int _rootKeyMidi = 60;
  int? _draggingNoteIndex;
  double _dragOffsetY = 0.0;

  final List<String> _noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

  @override
  void initState() {
    super.initState();
    _masterPlayer.positionStream.listen((pos) {
      setState(() => _currentPosition = pos.inMilliseconds / 1000.0);
    });
  }

  // --- UNDO / REDO ---
  void _registerUndoSnapshot() {
    setState(() {
      _undoStack.add(json.encode(_rawNotes));
      _redoStack.clear();
    });
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      setState(() {
        _redoStack.add(json.encode(_rawNotes));
        _rawNotes = json.decode(_undoStack.removeLast());
      });
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      setState(() {
        _undoStack.add(json.encode(_rawNotes));
        _rawNotes = json.decode(_redoStack.removeLast());
      });
    }
  }

  // --- PROJECT MANAGEMENT ---
  void _saveVoxrayProject() {
    Map<String, dynamic> projectData = {
      "voxray_version": "1.1.0",
      "project_name": _projectName,
      "track_settings": {"target_volume": _targetVolume, "accomp_volume": _accompVolume},
      "edits": _rawNotes,
      "history": {"undo_stack": _undoStack, "redo_stack": _redoStack}
    };

    final blob = html.Blob([json.encode(projectData)], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", "$_projectName.vxr")
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _loadVoxrayProject() async {
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['vxr']);
    if (result == null || result.files.single.bytes == null) return;

    String jsonString = utf8.decode(result.files.single.bytes!);
    Map<String, dynamic> projectData = json.decode(jsonString);
    
    setState(() {
      _targetVolume = projectData['track_settings']['target_volume'];
      _accompVolume = projectData['track_settings']['accomp_volume'];
      _rawNotes = projectData['edits'];
      if (projectData['history'] != null) {
        _undoStack = List<String>.from(projectData['history']['undo_stack']);
        _redoStack = List<String>.from(projectData['history']['redo_stack']);
      }
    });
  }

  // --- API CALLS ---
  Future<void> _loadFileAndAnalyze() async {
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.audio, withData: true);
    if (result == null || result.files.single.bytes == null) return;

    setState(() { _isLoading = true; _originalAudioBytes = result.files.single.bytes; });
    await _masterPlayer.setAudioSource(MyCustomBytesSource(_originalAudioBytes!));

    var request = http.MultipartRequest('POST', Uri.parse('https://donkelleymusic--voxray-pro-api-analyze-advanced.modal.run'))
      ..fields['stem_target'] = "vocals" 
      ..files.add(http.MultipartFile.fromBytes('file', _originalAudioBytes!, filename: result.files.single.name));

    var res = await request.send();
    if (res.statusCode == 200) {
      var data = json.decode(await res.stream.bytesToString());
      setState(() {
        _rawNotes = data['notes'];
        _chords = data['chords'];
        _songDuration = data['duration'].toDouble();
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _exportFinalMaster() async {
    if (_originalAudioBytes == null) return;
    setState(() => _isLoading = true);

    var request = http.MultipartRequest('POST', Uri.parse('YOUR_MODAL_ENDPOINT/batch_render_and_mix'))
      ..fields['edit_manifest'] = json.encode({
        "track_settings": {"target_volume": _targetVolume, "accomp_volume": _accompVolume},
        "edits": _rawNotes
      })
      ..files.add(http.MultipartFile.fromBytes('file', _originalAudioBytes!, filename: 'master.wav'));

    var res = await request.send();
    if (res.statusCode == 200) {
      var data = json.decode(await res.stream.bytesToString());
      final bytes = base64.decode(data['master_mix_b64']);
      final blob = html.Blob([bytes], 'audio/wav');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", "voxray_master.wav")
        ..click();
      html.Url.revokeObjectUrl(url);
    }
    setState(() => _isLoading = false);
  }

  // --- INSPECTOR UI ---
  void _showNoteInspector(int noteIndex, Map<String, dynamic> note) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Edit Note", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Divider(color: Colors.white24),
                  
                  const Text("Pitch Shift (Cents)", style: TextStyle(color: Colors.white70)),
                  Slider(
                    value: (note['cents_shift'] ?? 0).toDouble(),
                    min: -50, max: 50, activeColor: Colors.amberAccent,
                    onChangeStart: (_) => _registerUndoSnapshot(),
                    onChanged: (val) {
                      setModalState(() => note['cents_shift'] = val.round());
                      setState(() {}); 
                    },
                  ),

                  const Text("Note Velocity", style: TextStyle(color: Colors.white70)),
                  Slider(
                    value: note['volume'] ?? 1.0,
                    min: 0.0, max: 1.5, activeColor: Colors.greenAccent,
                    onChangeStart: (_) => _registerUndoSnapshot(),
                    onChanged: (val) {
                      setModalState(() => note['volume'] = val);
                      setState(() {});
                    },
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: note['isMuted'] ? Colors.orange : Colors.grey[800]),
                        icon: Icon(note['isMuted'] ? Icons.volume_off : Icons.volume_up),
                        label: Text(note['isMuted'] ? "Muted" : "Mute"),
                        onPressed: () {
                          _registerUndoSnapshot();
                          setModalState(() => note['isMuted'] = !note['isMuted']);
                          setState(() {});
                        },
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: note['isDeleted'] ? Colors.redAccent : Colors.grey[800]),
                        icon: Icon(note['isDeleted'] ? Icons.restore : Icons.delete),
                        label: Text(note['isDeleted'] ? "Restore" : "Delete"),
                        onPressed: () {
                          _registerUndoSnapshot();
                          setModalState(() => note['isDeleted'] = !note['isDeleted']);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double timelineWidth = _songDuration * _zoomX;
    
    // Dynamic Temperament Recalculation
    var processedNotes = _rawNotes.map((note) {
      double baseMidi = note['actual_midi'];
      int nearest = baseMidi.round();
      double dynamicCents = (baseMidi - nearest) * 100 + (note['cents_shift'] ?? 0);
      return {...note, "display_midi": nearest, "display_cents": dynamicCents.round()};
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voxray DAW'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _undoStack.isEmpty ? null : _undo),
          IconButton(icon: const Icon(Icons.redo), onPressed: _redoStack.isEmpty ? null : _redo),
          IconButton(icon: const Icon(Icons.folder_open), tooltip: "Load .vxr", onPressed: _loadVoxrayProject),
          IconButton(icon: const Icon(Icons.save), tooltip: "Save .vxr", onPressed: _saveVoxrayProject),
          IconButton(icon: const Icon(Icons.download), tooltip: "Export Master", onPressed: _rawNotes.isEmpty ? null : _exportFinalMaster),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 16,
              children: [
                ElevatedButton(onPressed: _isLoading ? null : _loadFileAndAnalyze, child: Text(_isLoading ? 'Processing...' : 'Upload Source Audio')),
                DropdownButton<String>(
                  value: _temperament,
                  items: const [DropdownMenuItem(value: 'Equal', child: Text('Equal Temperament')), DropdownMenuItem(value: 'Just', child: Text('Just Intonation'))],
                  onChanged: (val) => setState(() => _temperament = val!),
                ),
                IconButton(
                  icon: Icon(_masterPlayer.playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () => _masterPlayer.playing ? _masterPlayer.pause() : _masterPlayer.play(),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: Stack(
              children: [
                // 1. TIMELINE CANVAS
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: GestureDetector(
                    onPanDown: (details) {
                      double tapX = details.localPosition.dx;
                      double tapY = details.localPosition.dy;
                      
                      for (int i = 0; i < processedNotes.length; i++) {
                        var note = processedNotes[i];
                        if (note['isDeleted'] == true) continue;
                        
                        double startX = note['start_time'] * _zoomX;
                        double endX = note['end_time'] * _zoomX;
                        double noteY = MediaQuery.of(context).size.height - (((note['display_midi'] - 36) / 60) * MediaQuery.of(context).size.height);

                        if (tapX >= startX && tapX <= endX && (tapY - noteY).abs() < 20) {
                          _registerUndoSnapshot(); // Snapshot before drag begins
                          setState(() { _draggingNoteIndex = i; _dragOffsetY = 0.0; });
                          break;
                        }
                      }
                    },
                    onPanUpdate: (details) {
                      if (_draggingNoteIndex != null) setState(() => _dragOffsetY += details.delta.dy);
                    },
                    onPanEnd: (details) {
                      if (_draggingNoteIndex != null) {
                        int shift = -(_dragOffsetY / 5).round(); 
                        if (shift == 0) {
                           // If tapped but not dragged, open inspector
                          _showNoteInspector(_draggingNoteIndex!, _rawNotes[_draggingNoteIndex!]);
                        } else {
                          setState(() {
                            _rawNotes[_draggingNoteIndex!]['cents_shift'] += shift;
                            _draggingNoteIndex = null;
                          });
                        }
                      }
                    },
                    child: Container(
                      width: timelineWidth,
                      color: Colors.grey[950],
                      child: CustomPaint(
                        painter: AdvancedPianoRollPainter(notes: processedNotes.map((e) => Map<String, dynamic>.from(e as Map)).toList(), zoomX: _zoomX, currentPosition: _currentPosition),
                      ),
                    ),
                  ),
                ),

                // 2. PLAYHEAD
                Positioned(left: _currentPosition * _zoomX, top: 0, bottom: 0, child: Container(width: 2, color: Colors.amber)),

                // 3. MIXER PANEL
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  top: 10, right: _isMixerOpen ? 10 : -220,
                  child: Container(
                    width: 200, padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("MASTER BUS", style: TextStyle(color: Colors.white)),
                            IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _isMixerOpen = false))
                          ],
                        ),
                        Text("Target Stem", style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                        Slider(value: _targetVolume, onChanged: (v) => setState(() => _targetVolume = v)),
                        Text("Accompaniment", style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                        Slider(value: _accompVolume, onChanged: (v) => setState(() => _accompVolume = v)),
                      ],
                    ),
                  ),
                ),
                
                if (!_isMixerOpen)
                  Positioned(top: 10, right: 10, child: FloatingActionButton.small(backgroundColor: Colors.grey[850], child: const Icon(Icons.tune), onPressed: () => setState(() => _isMixerOpen = true))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdvancedPianoRollPainter extends CustomPainter {
  final List<Map<String, dynamic>> notes;
  final double zoomX;
  final double currentPosition;

  AdvancedPianoRollPainter({required this.notes, required this.zoomX, required this.currentPosition});

  @override
  void paint(Canvas canvas, Size size) {
    for (var note in notes) {
      if (note['isDeleted'] == true) continue;

      double startX = note['start_time'] * zoomX;
      double endX = note['end_time'] * zoomX;
      double yY = size.height - (((note['display_midi'] - 36) / 60) * size.height);

      Color noteColor = Colors.greenAccent.withOpacity(note['volume'].clamp(0.2, 1.0));
      if (note['isMuted'] == true) noteColor = Colors.grey.withOpacity(0.3);
      else if (note['display_cents'].abs() > 15) noteColor = Colors.redAccent;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(startX, yY - 4, endX, yY + 4), const Radius.circular(4)), 
        Paint()..color = noteColor
      );
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class MyCustomBytesSource extends StreamAudioSource {
  final List<int> bytes;
  MyCustomBytesSource(this.bytes);
  @override Future<StreamAudioResponse> request([int? start, int? end]) async => StreamAudioResponse(
    sourceLength: bytes.length, contentLength: (end ?? bytes.length) - (start ?? 0), offset: start ?? 0,
    stream: Stream.value(bytes.sublist(start ?? 0, end ?? bytes.length)), contentType: 'audio/wav',
  );
}