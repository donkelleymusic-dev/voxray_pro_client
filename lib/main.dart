// ==============================================================================
// COPYRIGHT AND OWNERSHIP DECLARATION
// ==============================================================================
// Copyright (c) 2026 Donald Bayard Kelley. All Rights Reserved.
// 
// voXRAY Enterprise DSP & Roformer Engine
// 
// PROPRIETARY AND CONFIDENTIAL
// This source code, algorithms, binaries, and related documentation are the 
// exclusive intellectual property of Donald Bayard Kelley. 
//
// Unauthorized copying, reproduction, distribution, modification, reverse 
// engineering, or use of this file, via any medium, is strictly prohibited 
// without the express written consent of the copyright holder. This software 
// contains trade secrets and proprietary methodologies protected by Canadian 
// and International intellectual property laws.
// 
// AUTHOR AND CONTACT INFORMATION:
// Developer / Owner: Donald Bayard Kelley
// Jurisdiction: British Columbia, Canada
// Direct Inquiries: donkelleymusic@gmail.com
// YouTube: @don-music
// Instagram: @donmusicyt
//
// By accessing this codebase, you acknowledge and agree to respect the 
// proprietary nature of this software.
// ==============================================================================

import 'dart:io';
import 'package:flutter/foundation.dart'; // for kIsWeb
import 'package:path_provider/path_provider.dart'; // for getTemporaryDirectory
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; 
//import 'dart:html' as html;
import 'package:file_saver/file_saver.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:typed_data';

import 'ui/timeline_canvas.dart';
import 'pedagogy/live_analyzer.dart';

void main() => runApp(MaterialApp(
  home: const VoxrayDAW(), 
  theme: ThemeData(brightness: Brightness.dark)
));

class VoxrayDAW extends StatefulWidget {
  const VoxrayDAW({Key? key}) : super(key: key);
  @override
  State<VoxrayDAW> createState() => VoxrayDAWState(); 
}

class VoxrayDAWState extends State<VoxrayDAW> {
  final AudioPlayer masterPlayer = AudioPlayer();
  
  // Viewport Scrollers
  final ScrollController horizontalScrollController = ScrollController();
  final ScrollController verticalScrollController = ScrollController();
  
  List<dynamic> rawNotes = [];
  List<Map<String, dynamic>> markers = [];
  List<String> undoStack = [];
  List<String> redoStack = [];
  
  bool isLoading = false;
  double processingProgress = 0.0; 
  String processingMessage = "";   
  Timer? pollingTimer;             

  bool isMixerOpen = false;
  double songDuration = 30.0;
  double currentPosition = 0.0;
  double zoomX = 150.0;
  double zoomY = 24.0;
  
  // Global DAW Bounds
  final int minMidi = 36;
  final int maxMidi = 84;
  
  String projectName = "Voxray_Session";
  Uint8List? originalAudioBytes;

  double targetVolume = 0.85;
  double accompVolume = 1.0;
  bool applyDenoise = false;
  String temperament = 'Equal';
  int rootKeyMidi = 60;
  
  bool isLiveModeActive = false;
  bool isLoopModeActive = false;
  double loopStartBoundary = 2.0;
  double loopEndBoundary = 8.0;

  final String apiBase = 'https://donkelleymusic--voxray-pro-api-api.modal.run';

  @override
  void initState() {
    super.initState();
    masterPlayer.playerStateStream.listen((state) {
      debugPrint("Player state: ${state.processingState} playing:${state.playing} isLoading:$isLoading");
    });
    masterPlayer.positionStream.listen((pos) {
      if (!mounted) return;
      double currentT = pos.inMilliseconds / 1000.0;
      
      if (isLoopModeActive && currentT >= loopEndBoundary) {
        masterPlayer.seek(Duration(milliseconds: (loopStartBoundary * 1000).round()));
        currentT = loopStartBoundary;
      }
      
      setState(() => currentPosition = currentT);

      // --- NEW: Viewport Tracking Engine ---
      if (masterPlayer.playing) {
        // 1. Horizontal Scroll (Stationary Playhead at ~150px offset)
        double targetX = (currentT * zoomX) - 150.0;
        if (targetX < 0) targetX = 0;
        if (horizontalScrollController.hasClients) {
          horizontalScrollController.jumpTo(targetX);
        }

        // 2. Vertical Glide (Center active pitch)
        var activeNotes = rawNotes.where((n) => 
            n['isDeleted'] != true && 
            n['start_time'] <= currentT && 
            n['end_time'] >= currentT
        ).toList();

        if (activeNotes.isNotEmpty && verticalScrollController.hasClients) {
          // Track highest pitched active note
          activeNotes.sort((a, b) => (b['display_midi'] ?? 0).compareTo(a['display_midi'] ?? 0));
          int targetMidi = activeNotes.first['display_midi'] ?? 60;
          
          double viewportCenter = verticalScrollController.position.viewportDimension / 2;
          double targetY = ((maxMidi - targetMidi) * zoomY) - viewportCenter;
          
          if (targetY < 0) targetY = 0;
          if (targetY > verticalScrollController.position.maxScrollExtent) {
            targetY = verticalScrollController.position.maxScrollExtent;
          }
          
          verticalScrollController.animateTo(
            targetY, 
            duration: const Duration(milliseconds: 200), 
            curve: Curves.easeOut
          );
        }
      }
    });
  }

  @override
  void dispose() {
    pollingTimer?.cancel();
    horizontalScrollController.dispose();
    verticalScrollController.dispose();
    super.dispose();
  }

  void registerUndoSnapshot() {
    setState(() {
      undoStack.add(json.encode(rawNotes));
      redoStack.clear();
    });
  }

  void jumpToTimelinePosition(double seconds) {
    masterPlayer.seek(Duration(milliseconds: (seconds * 1000).round()));
    setState(() => currentPosition = seconds);
  }

  void addMarkerAtCurrentPlayhead() {
    setState(() {
      markers.add({
        "id": "mk_${DateTime.now().millisecondsSinceEpoch}",
        "time": currentPosition,
        "label": "Marker ${markers.length + 1}"
      });
    });
  }

  void _undo() {
    if (undoStack.isNotEmpty) {
      setState(() {
        redoStack.add(json.encode(rawNotes));
        rawNotes = json.decode(undoStack.removeLast());
      });
    }
  }

  void _redo() {
    if (redoStack.isNotEmpty) {
      setState(() {
        undoStack.add(json.encode(rawNotes));
        rawNotes = json.decode(redoStack.removeLast());
      });
    }
  }

  Future<void> _saveVoxrayProject() async {
    Map<String, dynamic> projectData = {
      "voxray_version": "1.2.0",
      "project_name": projectName,
      "track_settings": {"target_volume": targetVolume, "accomp_volume": accompVolume, "apply_denoise": applyDenoise},
      "edits": rawNotes,
      "history": {"undo_stack": undoStack, "redo_stack": redoStack}
    };

    // Convert JSON to bytes for saving
    String jsonString = json.encode(projectData);
    Uint8List bytes = Uint8List.fromList(utf8.encode(jsonString));

    await FileSaver.instance.saveFile(
      name: projectName,
      bytes: bytes,
      fileExtension: 'vxr',
      mimeType: MimeType.json,
    );
  }

  Future<void> _loadVoxrayProject() async {
    //FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['vxr']);
    //if (result == null || result.files.single.bytes == null) return;

    //String jsonString = utf8.decode(result.files.single.bytes!);

    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom, 
      allowedExtensions: ['vxr'],
      withData: true,
    );
    if (result == null) return;

    String jsonString;
    if (result.files.single.bytes != null) {
      jsonString = utf8.decode(result.files.single.bytes!);
    } else if (result.files.single.path != null) {
      jsonString = await File(result.files.single.path!).readAsString();
    } else {
      return;
    }
    Map<String, dynamic> projectData = json.decode(jsonString);
    
    setState(() {
      targetVolume = projectData['track_settings']['target_volume'] ?? 0.85;
      accompVolume = projectData['track_settings']['accomp_volume'] ?? 1.0;
      applyDenoise = projectData['track_settings']['apply_denoise'] ?? false;
      rawNotes = projectData['edits'];
      if (projectData['history'] != null) {
        undoStack = List<String>.from(projectData['history']['undo_stack']);
        redoStack = List<String>.from(projectData['history']['redo_stack']);
      }
    });
  }
  _loadFileAndAnalyze() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.audio, withData: true);
    if (result == null) return;

    Uint8List? audioBytes;
    if (result.files.single.bytes != null) {
      audioBytes = result.files.single.bytes!;
    } else if (result.files.single.path != null) {
      audioBytes = await File(result.files.single.path!).readAsBytes();
    } else return;

    setState(() {
      isLoading = true;
      processingProgress = 0.0;
      processingMessage = "Uploading file...";
      originalAudioBytes = audioBytes;
    });

    // Audio setup in its own try/catch — don't let it abort the upload
    try {
      if (kIsWeb) {
        await masterPlayer.setAudioSource(MyCustomBytesSource(originalAudioBytes!));
      } else {
        // On Android/desktop, write to a temp file and load from path
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/preview_audio.wav');
        await tempFile.writeAsBytes(originalAudioBytes!);
        await masterPlayer.setFilePath(tempFile.path);
      }
    } catch (e) {
      debugPrint("Audio preview setup failed (non-fatal): $e");
    }

    // API upload continues regardless
    try {
      var request = http.MultipartRequest(
          'POST', Uri.parse('$apiBase/analyze-advanced'))
        ..fields['stem_target'] = "vocals"
        ..files.add(http.MultipartFile.fromBytes(
            'file', originalAudioBytes!,
            filename: result.files.single.name));
  
      var response = await request.send();
      if (response.statusCode != 200) {
        throw Exception("Server rejected file upload");
      }
      
      var data = json.decode(await response.stream.bytesToString());
      String taskId = data['task_id'];

      pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        try {
          var statusRes = await http.get(Uri.parse('$apiBase/get-task-status?task_id=$taskId'));
          if (statusRes.statusCode == 200) {
            var statusData = json.decode(statusRes.body);
            
            setState(() {
              processingProgress = (statusData['progress'] ?? 0).toDouble() / 100.0;
              processingMessage = statusData['message'] ?? "Processing...";
            });

            if (statusData['status'] == 'complete') {
              timer.cancel();
              setState(() {
                rawNotes = statusData['result']['notes'];
                songDuration = statusData['result']['duration'].toDouble();
                isLoading = false;
              });
            } else if (statusData['status'] == 'error') {
              timer.cancel();
              debugPrint("Server Error: ${statusData['message']}");
              setState(() { 
                isLoading = false; 
                processingMessage = "Error: ${statusData['message']}"; 
              });
            }
          }
        } catch (e) {
          debugPrint("Polling error (retrying): $e");
        }
      });

    } catch (e) {
      debugPrint("Initialization Failed: $e");
      setState(() { isLoading = false; processingMessage = "Failed to start."; });
    }
  }

  Future<void> _exportFinalMaster() async {
    if (originalAudioBytes == null) return;
    setState(() => isLoading = true);

    var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
      ..fields['edit_manifest'] = json.encode({
        "track_settings": {"target_volume": targetVolume, "accomp_volume": accompVolume, "apply_denoise": applyDenoise},
        "edits": rawNotes
      })
      ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'master.wav'));

    var res = await request.send();
    if (res.statusCode == 200) {
      var data = json.decode(await res.stream.bytesToString());
      final Uint8List bytes = base64.decode(data['master_mix_b64']);
      
      await FileSaver.instance.saveFile(
        name: 'voxray_master',
        bytes: bytes,
        fileExtension: 'wav', 
        mimeType: MimeType.custom,               // <--- Use custom
        customMimeType: 'audio/wav',             // <--- Specify WAV format here
      );
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isLiveModeActive ? 'Voxray: Live Pedagogy' : 'Voxray: Forensic DAW'),
        actions: [
          Row(
            children: [
              const Icon(Icons.mic_external_on, size: 16, color: Colors.redAccent),
              const SizedBox(width: 8),
              const Text("Live Mode", style: TextStyle(fontWeight: FontWeight.bold)),
              Switch(
                value: isLiveModeActive,
                onChanged: (val) => setState(() => isLiveModeActive = val),
                activeColor: Colors.redAccent,
              ),
            ],
          ),
          if (!isLiveModeActive) ...[
            // Always visible
            IconButton(icon: const Icon(Icons.undo), onPressed: undoStack.isEmpty ? null : _undo),
            IconButton(icon: const Icon(Icons.redo), onPressed: redoStack.isEmpty ? null : _redo),
            // Landscape: show remaining buttons inline
            if (MediaQuery.of(context).size.width > 600) ...[
              IconButton(icon: const Icon(Icons.folder_open), tooltip: "Load .vxr", onPressed: _loadVoxrayProject),
              IconButton(icon: const Icon(Icons.save), tooltip: "Save .vxr", onPressed: _saveVoxrayProject),
              IconButton(icon: const Icon(Icons.download), tooltip: "Export Master", onPressed: rawNotes.isEmpty ? null : _exportFinalMaster),
            ] else
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'load': _loadVoxrayProject(); break;
                    case 'save': _saveVoxrayProject(); break;
                    case 'export': _exportFinalMaster(); break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'load',
                    child: ListTile(leading: Icon(Icons.folder_open), title: Text('Load .vxr')),
                  ),
                  const PopupMenuItem(
                    value: 'save',
                    child: ListTile(leading: Icon(Icons.save), title: Text('Save .vxr')),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    enabled: rawNotes.isNotEmpty,
                    child: const ListTile(leading: Icon(Icons.download), title: Text('Export Master')),
                  ),
                ],
              ),
          ],
        ],
      ),
      body: isLiveModeActive 
          ? const LivePedagogyView() 
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    spacing: 16, crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (isLoading)
                        SizedBox(
                          width: 200,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(processingMessage, style: const TextStyle(fontSize: 12, color: Colors.tealAccent)),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: processingProgress,
                                backgroundColor: Colors.grey[800],
                                color: Colors.tealAccent,
                                minHeight: 8,
                              ),
                            ],
                          ),
                        )
                      else
                        ElevatedButton(
                          onPressed: _loadFileAndAnalyze, 
                          child: const Text('Upload Audio')
                        ),
                      Wrap(
                        spacing: 15.0, 
                        runSpacing: 10.0, 
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          //const Text("De-Hiss", style: TextStyle(fontSize: 12)),
                          //Switch(value: applyDenoise, onChanged: (val) => setState(() => applyDenoise = val), activeColor: Colors.amberAccent),
                          
                          const Text("Zoom X", style: TextStyle(fontSize: 12)),
                          SizedBox(
                            width: 100,
                            child: Slider(
                              value: zoomX, min: 50.0, max: 400.0,
                              onChanged: (v) => setState(() => zoomX = v),
                            ),
                          ),
                          
                          const Text("Zoom Y", style: TextStyle(fontSize: 12)),
                          SizedBox(
                            width: 100,
                            child: Slider(
                              value: zoomY, min: 10.0, max: 60.0,
                              onChanged: (v) => setState(() => zoomY = v),
                            ),
                          ),

                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
                            icon: const Icon(Icons.analytics, size: 16),
                            label: const Text("Dossier"),
                            onPressed: _showDossier,
                          )
                        ],
                      ),
                      IconButton(
                        icon: Icon(masterPlayer.playing ? Icons.pause : Icons.play_arrow),
                        onPressed: () => masterPlayer.playing ? masterPlayer.pause() : masterPlayer.play(),
                      ),
                      IconButton(icon: const Icon(Icons.tune), onPressed: () => setState(() => isMixerOpen = !isMixerOpen)),
                    ],
                  ),
                ),
                // MIXER POPUP
              if (isMixerOpen && !isLiveModeActive)
                Container(
                  color: Colors.grey[900],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text("Vocal Vol", style: TextStyle(fontSize: 12, color: Colors.white70))),
                          Expanded(
                            child: Slider(
                              value: targetVolume, min: 0.0, max: 2.0,
                              activeColor: Colors.tealAccent,
                              onChanged: (v) => setState(() => targetVolume = v),
                            ),
                          ),
                          SizedBox(width: 36, child: Text("${(targetVolume * 100).round()}%", style: const TextStyle(fontSize: 11, color: Colors.white54))),
                        ],
                      ),
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text("Accomp Vol", style: TextStyle(fontSize: 12, color: Colors.white70))),
                          Expanded(
                            child: Slider(
                              value: accompVolume, min: 0.0, max: 2.0,
                              activeColor: Colors.amberAccent,
                              onChanged: (v) => setState(() => accompVolume = v),
                            ),
                          ),
                          SizedBox(width: 36, child: Text("${(accompVolume * 100).round()}%", style: const TextStyle(fontSize: 11, color: Colors.white54))),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const SizedBox(width: 80, child: Text("De-Hiss", style: TextStyle(fontSize: 12, color: Colors.white70))),
                          Switch(value: applyDenoise, onChanged: (val) => setState(() => applyDenoise = val), activeColor: Colors.amberAccent),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(child: TimelineCanvasWidget(dawState: this)),
              ],
            ),
    );
  }

  void _showDossier() {
    if (rawNotes.isEmpty) return;
    int totalNotes = 0;
    double totalError = 0;
    int perfectlyTuned = 0;

    for (var note in rawNotes) {
      if (note['isDeleted'] == true) continue;
      totalNotes++;
      double baseMidi = note['actual_midi'] ?? 0;
      int nearest = baseMidi.round();
      double cents = ((baseMidi - nearest) * 100).abs();
      totalError += cents;
      if (cents <= 10) perfectlyTuned++;
    }

    double avgError = totalNotes > 0 ? totalError / totalNotes : 0;
    double tunedPercentage = totalNotes > 0 ? (perfectlyTuned / totalNotes) * 100 : 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Performance Dossier", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Active Notes Analyzed: $totalNotes", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            Text("Global Average Error: ${avgError.toStringAsFixed(1)} cents", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            Text("Studio Tolerance (<10c): ${tunedPercentage.toStringAsFixed(1)}%", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            Text(
              avgError < 15 ? "VERDICT: Highly accurate performance. Minor touch-ups needed." 
              : "VERDICT: Significant tuning variance detected. Pitch correction recommended.",
              style: TextStyle(color: avgError < 15 ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))
        ],
      ),
    );
  }
}

class MyCustomBytesSource extends StreamAudioSource {
  final List<int> bytes;
  MyCustomBytesSource(this.bytes);
  @override Future<StreamAudioResponse> request([int? start, int? end]) async => StreamAudioResponse(
    sourceLength: bytes.length, contentLength: (end ?? bytes.length) - (start ?? 0), offset: start ?? 0,
    stream: Stream.value(bytes.sublist(start ?? 0, end ?? bytes.length)), contentType: 'audio/wav',
  );
}