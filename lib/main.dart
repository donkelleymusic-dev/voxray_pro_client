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
import 'ui/timeline_ruler.dart';
import 'synth/vox_synth.dart';

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
  final AudioPlayer synthPlayer = AudioPlayer();

  // --- Note-data synth engine ---
  SynthSettings synthSettings = const SynthSettings();
  bool isSynthRendering = false;
  String synthMessage = '';
  
  // Viewport Scrollers
  final ScrollController horizontalScrollController = ScrollController();
  final ScrollController verticalScrollController = ScrollController();
  final ScrollController rulerScrollController = ScrollController();
  
  List<dynamic> rawNotes = [];
  List<Map<String, dynamic>> markers = [];
  List<String> undoStack = [];
  List<String> redoStack = [];
  
  bool isLoading = false;
  double processingProgress = 0.0; 
  String processingMessage = "";   
  Timer? pollingTimer;     
  String? currentTaskId;       

  // xray mode (polyphonic pitch analysis)
  bool isXrayMode = false;
  bool isXrayProcessing = false;
  String originalFileName = "Unknown File"; 
  String originalFilePath = "";

  bool isMixerOpen = false;
  double songDuration = 30.0;
  double currentPosition = 0.0;
  double zoomX = 150.0;
  double zoomY = 24.0;
  
  
  // Global DAW Bounds
  final int minMidi = 36;
  final int maxMidi = 84;

  bool isScrubMode = true;
  bool isDragMode = false;
  
  String projectName = "Voxray_Session";
  Uint8List? originalAudioBytes;

  double targetVolume = 0.85;
  double accompVolume = 1.0;
  bool applyDenoise = false;
  String temperament = 'Equal';
  int rootKeyMidi = 60;
  
  bool isLiveModeActive = false;
  bool isLoopModeActive = false;
  double loopStartBoundary = 0.0;
  double loopEndBoundary = 20.0;

  bool isUserScrolling = false;
  bool isExporting = false;
  bool isPreviewing = false;
  String exportMessage = '';

  final String apiBase = 'https://donkelleymusic--voxray-pro-api-api.modal.run';

  @override
  void initState() {
    super.initState();
    horizontalScrollController.addListener(() {
      if (rulerScrollController.hasClients &&
          rulerScrollController.position.pixels != horizontalScrollController.position.pixels) {
        rulerScrollController.jumpTo(horizontalScrollController.position.pixels);
      }
    });
    // In initState, also add the reverse mirror:
    rulerScrollController.addListener(() {
      if (horizontalScrollController.hasClients &&
          horizontalScrollController.position.pixels != rulerScrollController.position.pixels) {
        horizontalScrollController.jumpTo(rulerScrollController.position.pixels);
      }
    });
    masterPlayer.playerStateStream.listen((state) {
      debugPrint("Player state: ${state.processingState} playing:${state.playing} isLoading:$isLoading");
    });
    synthPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() {});
    });
    masterPlayer.positionStream.listen((pos) {
      if (!mounted) return;
      double currentT = pos.inMilliseconds / 1000.0;

      if (isLoopModeActive && 
          loopEndBoundary > loopStartBoundary && 
          loopEndBoundary > 0.0 &&
          currentT >= loopEndBoundary) {
        masterPlayer.seek(Duration(milliseconds: (loopStartBoundary * 1000).round()));
        currentT = loopStartBoundary;
      }

      setState(() => currentPosition = currentT);

      if (masterPlayer.playing) {
        // Horizontal: keep playhead stationary at 150px from left
        double targetX = (currentT * zoomX) - 150.0;
        if (targetX < 0) targetX = 0;
        if (horizontalScrollController.hasClients) {
          horizontalScrollController.jumpTo(
            targetX.clamp(0.0, horizontalScrollController.position.maxScrollExtent)
          );
        }

        // Vertical: follow highest active note
        if (verticalScrollController.hasClients && rawNotes.isNotEmpty) {
          var activeNotes = rawNotes.where((n) {
            if (n['isDeleted'] == true) return false;
            double start = (n['start_time'] ?? 0).toDouble();
            double end = (n['end_time'] ?? 0).toDouble();
            return start <= currentT && end >= currentT;
          }).toList();

          if (activeNotes.isNotEmpty) {
            // Find the median pitch of active notes (better than highest for polyphony)
            List<int> midiValues = activeNotes
                .map<int>((n) => ((n['display_midi'] ?? n['actual_midi'] ?? 60)).round())
                .toList()
              ..sort();
            int medianMidi = midiValues[midiValues.length ~/ 2];

            double viewportHeight = verticalScrollController.position.viewportDimension;
            double targetY = ((maxMidi - medianMidi) * zoomY) - (viewportHeight / 2);
            targetY = targetY.clamp(0.0, verticalScrollController.position.maxScrollExtent);

            verticalScrollController.animateTo(
              targetY,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    pollingTimer?.cancel();
    horizontalScrollController.dispose();
    verticalScrollController.dispose();
    rulerScrollController.dispose();
    synthPlayer.dispose();
    super.dispose();
  }

  void notifyChanged() {
    setState(() {});
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

    // Scroll grid so the jumped-to position appears at the stationary playhead (150px offset)
    double targetX = (seconds * zoomX) - 150.0;
    if (targetX < 0) targetX = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (horizontalScrollController.hasClients &&
          horizontalScrollController.positions.length == 1) {
        horizontalScrollController.jumpTo(
          targetX.clamp(0.0, horizontalScrollController.position.maxScrollExtent)
        );
      }
      if (rulerScrollController.hasClients &&
          rulerScrollController.positions.length == 1) {
        rulerScrollController.jumpTo(
          targetX.clamp(0.0, rulerScrollController.position.maxScrollExtent)
        );
      }
    });
  }

  Future<void> _forceReprocessXray() async {
    if (rawNotes.isEmpty || currentTaskId == null) return;

    // 1. The Fail-Safe Confirmation Dialog
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
          SizedBox(width: 8),
          Text("Force Reprocess", style: TextStyle(color: Colors.white)),
        ]),
        content: const Text(
          "This will re-run the heavy X-Ray pitch extraction on the server and overwrite your current pitch contours. This might take a moment. Proceed?",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text("Cancel", style: TextStyle(color: Colors.white54))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent[700]),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Proceed"),
          ),
        ],
      )
    );

    if (confirm != true) return;

    // 2. The Reprocess Execution
    setState(() { 
      isXrayProcessing = true; 
      isXrayMode = true; // Ensure the UI draws it once done
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-xray'))
        ..fields['task_id'] = currentTaskId!
        ..fields['notes_manifest'] = jsonEncode(rawNotes); // Send current state

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);
      
      if (responseData.statusCode == 200) {
        var data = jsonDecode(responseData.body);
        if (data['status'] == 'success') {
          setState(() {
            rawNotes = data['notes']; // Overwrite with fresh contours
            registerUndoSnapshot();
          });
          _showSaveConfirmation('X-Ray data successfully reprocessed.');
        } else {
          _showSaveConfirmation('Reprocess failed: ${data['message']}');
        }
      }
    } catch (e) {
      debugPrint("XRAY Reprocess error: $e");
      _showSaveConfirmation('Reprocess failed: $e');
    } finally {
      setState(() => isXrayProcessing = false);
    }
  }

  Future<void> _downloadDossier() async {
    if (rawNotes.isEmpty) return;
    setState(() { isExporting = true; exportMessage = "Generating dossier PDF..."; });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/generate-dossier'))
        ..fields['task_id'] = currentTaskId ?? ''
        ..fields['notes_manifest'] = jsonEncode(rawNotes)
        ..fields['session_meta'] = jsonEncode({
          'filename': originalFileName,
          'duration': songDuration,
          'stem_target': 'vocals',
          'xray_enabled': rawNotes.any((n) => n.containsKey('contour')),
          'version': '1.3.0',
        });

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);

      if (responseData.statusCode != 200) {
        throw Exception("Server error ${responseData.statusCode}");
      }

      var result = jsonDecode(responseData.body);
      if (result['status'] == 'success') {
        final Uint8List bytes = base64Decode(result['pdf_b64']);

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: '${projectName}_dossier', bytes: bytes,
            fileExtension: 'pdf', mimeType: MimeType.custom, customMimeType: 'application/pdf',
          );
        } else {
          String? path = await FileSaver.instance.saveAs(
            name: '${projectName}_dossier',
            bytes: bytes,
            fileExtension: 'pdf',
            mimeType: MimeType.custom,
            customMimeType: 'application/pdf',
          );
          if (path != null && path.isNotEmpty) {
            _showSaveConfirmation('Dossier saved successfully.');
          } else {
            _showSaveConfirmation('Save cancelled.');
          }
        }
      }
    } catch (e) {
      _showSaveConfirmation('Dossier generation failed: $e');
    } finally {
      setState(() { isExporting = false; exportMessage = ''; });
    }
  }

  Future<void> _downloadPitchPrint({required bool fullSong}) async {
    if (rawNotes.isEmpty) return;
    setState(() { isExporting = true; exportMessage = "Generating PitchPrint™..."; });

    // Calculate visible region from scroll position
    double visibleStart = horizontalScrollController.hasClients
        ? horizontalScrollController.position.pixels / zoomX
        : 0.0;
    double visibleEnd = horizontalScrollController.hasClients
        ? (horizontalScrollController.position.pixels + horizontalScrollController.position.viewportDimension) / zoomX
        : songDuration;

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/generate-pitchprint'))
        ..fields['task_id'] = currentTaskId ?? ''
        ..fields['notes_manifest'] = jsonEncode(rawNotes)
        ..fields['full_song'] = fullSong.toString()
        ..fields['visible_start'] = visibleStart.toString()
        ..fields['visible_end'] = visibleEnd.toString()
        ..fields['song_duration'] = songDuration.toString();

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);

      if (responseData.statusCode != 200) {
        throw Exception("Server error ${responseData.statusCode}");
      }

      var result = jsonDecode(responseData.body);
      if (result['status'] == 'success') {
        final Uint8List bytes = base64Decode(result['svg_b64']);

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: '${projectName}_pitchprint', bytes: bytes,
            fileExtension: 'svg', mimeType: MimeType.custom, customMimeType: 'image/svg+xml',
          );
        } else {
          String? path = await FileSaver.instance.saveAs(
            name: '${projectName}_pitchprint',
            bytes: bytes,
            fileExtension: 'svg',
            mimeType: MimeType.custom,
            customMimeType: 'image/svg+xml',
          );
          if (path != null && path.isNotEmpty) {
            _showSaveConfirmation('PitchPrint™ saved successfully.');
          } else {
            _showSaveConfirmation('Save cancelled.');
          }
        }
      }
    } catch (e) {
      _showSaveConfirmation('PitchPrint™ generation failed: $e');
    } finally {
      setState(() { isExporting = false; exportMessage = ''; });
    }
  }

  Future<void> _toggleXrayMode() async {
    if (rawNotes.isEmpty || currentTaskId == null) return;
    
    // If turning off, or if data already exists, just toggle the UI state
    if (isXrayMode || rawNotes.any((n) => n.containsKey('contour'))) {
      setState(() => isXrayMode = !isXrayMode);
      return;
    }

    // First time turning it on: Fetch deep data
    setState(() { isXrayProcessing = true; isXrayMode = true; });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/analyze-xray'))
        ..fields['task_id'] = currentTaskId!
        ..fields['notes_manifest'] = jsonEncode(rawNotes);

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);
      
      if (responseData.statusCode == 200) {
        var data = jsonDecode(responseData.body);
        if (data['status'] == 'success') {
          setState(() {
            rawNotes = data['notes'];
            registerUndoSnapshot(); // Save the new rich data to history
          });
        } else {
          _showSaveConfirmation('XRAY failed: ${data['message']}');
          setState(() => isXrayMode = false);
        }
      }
    } catch (e) {
      debugPrint("XRAY error: $e");
      setState(() => isXrayMode = false);
    } finally {
      setState(() => isXrayProcessing = false);
    }
  }

  void addMarkerAtCurrentPlayhead() {
    // Calculate actual time at the stationary playhead line (150px offset from scroll)
    double visualPlayheadTime = (horizontalScrollController.hasClients
        ? (horizontalScrollController.position.pixels + 150) / zoomX
        : currentPosition);
    
    // Clamp to song duration
    visualPlayheadTime = visualPlayheadTime.clamp(0.0, songDuration);

    // Check for nearby existing markers (within 0.5 seconds)
    bool tooClose = markers.any((m) => 
        ((m['time'] as double) - visualPlayheadTime).abs() < 0.5);
    if (tooClose) {
      debugPrint("Marker too close to existing one, skipping");
      return;
    }

    setState(() {
      markers.add({
        "id": "mk_${DateTime.now().millisecondsSinceEpoch}",
        "time": visualPlayheadTime,
        "label": "Marker ${markers.length + 1}"
      });
    });
    debugPrint("Marker added at $visualPlayheadTime, total: ${markers.length}");
  }

  void setLoopFromMarkers(double start, double end) {
    setState(() {
      loopStartBoundary = start;
      loopEndBoundary = end;
    });
  }

  void deleteMarker(String id) {
    setState(() {
      markers.removeWhere((m) => m['id'] == id);
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

  Future<void> _previewWithEdits() async {
    if (originalAudioBytes == null) return;
    
    bool wasPlaying = masterPlayer.playing;
    double resumePosition = currentPosition;
    if (wasPlaying) await masterPlayer.pause();
    
    setState(() { isPreviewing = true; exportMessage = "Rendering preview mix..."; });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['edit_manifest'] = jsonEncode({
          'track_settings': {'target_volume': targetVolume, 'accomp_volume': accompVolume, 'apply_denoise': applyDenoise},
          'edits': rawNotes,
        })
        ..fields['task_id'] = currentTaskId ?? ''  
        ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'audio.wav'));

      // YOUR response handling — buffers full response before parsing
      var response = await request.send();
      var responseData = await http.Response.fromStream(response);
      
      if (responseData.statusCode != 200) {
        throw Exception("Server error ${responseData.statusCode}: ${responseData.body}");
      }

      var result = jsonDecode(responseData.body);

      if (result['status'] == 'success') {
        Uint8List previewBytes = base64Decode(result['master_mix_b64']);

        if (kIsWeb) {
          await masterPlayer.setAudioSource(MyCustomBytesSource(previewBytes));
        } else {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/preview_mix.wav');
          await tempFile.writeAsBytes(previewBytes);
          await masterPlayer.setFilePath(tempFile.path);
        }

        await masterPlayer.seek(Duration(milliseconds: (resumePosition * 1000).round()));
        
        if (wasPlaying) {
          await masterPlayer.play();
          _showSaveConfirmation('Preview ready — resuming with edits applied.', isPreview: true);
        } else {
          _showSaveConfirmation('Preview ready — tap Play to hear your edits.', isPreview: true);
        }
      } else {
        if (wasPlaying) await masterPlayer.play();
        _showSaveConfirmation('Preview failed: ${result['message'] ?? 'unknown error'}');
      }
    } catch (e) {
      if (wasPlaying) await masterPlayer.play();
      debugPrint("Preview render failed: $e");
      _showSaveConfirmation('Preview failed: $e');
    } finally {
      setState(() { isPreviewing = false; exportMessage = ''; });
    }
  }
  
  Future<void> _saveVoxrayProject() async {
    Map<String, dynamic> projectData = {
        "voxray_version": "1.3.0",
        "project_name": projectName,
        "original_file": originalFileName, // SAVE FILENAME
        "original_file_path": originalFilePath, 
        "track_settings": {"target_volume": targetVolume, "accomp_volume": accompVolume, "apply_denoise": applyDenoise},
        "edits": rawNotes, // This now automatically includes the 'contour' arrays
        "history": {"undo_stack": undoStack, "redo_stack": redoStack}
      };

    String jsonString = json.encode(projectData);
    Uint8List bytes = Uint8List.fromList(utf8.encode(jsonString));

    try {
      // Using FileSaver.saveAs forces the native file requester on Android, iOS, and Desktop
      String? path = await FileSaver.instance.saveAs(
        name: projectName,
        bytes: bytes,
        fileExtension: 'vxr',
        mimeType: MimeType.custom,
        customMimeType: 'application/json'
      );
      
      if (path != null && path.isNotEmpty) {
        _showSaveConfirmation('Project saved successfully.');
      } else {
        _showSaveConfirmation('Save cancelled.');
      }
    } catch (e) {
      debugPrint("Save error: $e");
      _showSaveConfirmation('Save failed: $e');
    }
  }

  Future<void> _loadVoxrayProject() async {
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
      projectName = projectData['project_name'] ?? "Voxray_Session";
      originalFileName = projectData['original_file'] ?? "Unknown File";
      originalFilePath = projectData['original_file_path'] ?? "";
      targetVolume = projectData['track_settings']['target_volume'] ?? 0.85;
      accompVolume = projectData['track_settings']['accomp_volume'] ?? 1.0;
      applyDenoise = projectData['track_settings']['apply_denoise'] ?? false;
      rawNotes = projectData['edits'];
      if (projectData['history'] != null) {
        undoStack = List<String>.from(projectData['history']['undo_stack']);
        redoStack = List<String>.from(projectData['history']['redo_stack']);
      }
      if (rawNotes.isNotEmpty && rawNotes.first.containsKey('contour')) {
        isXrayMode = true;
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

    /* setState(() {
      isLoading = true;
      processingProgress = 0.0;
      processingMessage = "Uploading file...";
      originalAudioBytes = audioBytes;
      originalFileName = result.files.single.name;
    }); */

    setState(() {
      isLoading = true;
      processingProgress = 0.0;
      processingMessage = "Uploading file...";
      originalAudioBytes = audioBytes;
      originalFileName = result.files.single.name; // SAVE THE FILENAME
      originalFilePath = result.files.single.path ?? "";
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
                loopEndBoundary = songDuration; // keep loop end in sync
                currentTaskId = taskId;
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

  void _showExportDialog() {
    if (rawNotes.isEmpty || originalAudioBytes == null) return;
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Export Master Mix", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.audio_file, color: Colors.tealAccent, size: 30),
                title: const Text("WAV", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Lossless / Studio Quality", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); _exportFinalMaster('wav'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.library_music, color: Colors.amberAccent, size: 30),
                title: const Text("FLAC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Lossless / Compressed Size", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); _exportFinalMaster('flac'); },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.music_note, color: Colors.blueAccent, size: 30),
                title: const Text("MP3", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Standard / Web Optimized", style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () { Navigator.pop(context); _exportFinalMaster('mp3'); },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text("Cancel", style: TextStyle(color: Colors.white54))
            )
          ],
        );
      }
    );
  }

  Future<void> _exportFinalMaster(String format) async {
    if (originalAudioBytes == null) return;
    setState(() { isExporting = true; exportMessage = "Rendering $format..."; });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiBase/batch-render-and-mix'))
        ..fields['edit_manifest'] = json.encode({
          "track_settings": {"target_volume": targetVolume, "accomp_volume": accompVolume, "apply_denoise": applyDenoise},
          "edits": rawNotes
        })
        ..fields['task_id'] = currentTaskId ?? '' 
        ..fields['export_format'] = format // <--- SEND FORMAT TO API
        ..files.add(http.MultipartFile.fromBytes('file', originalAudioBytes!, filename: 'master.wav'));

      var response = await request.send();
      var responseData = await http.Response.fromStream(response);
      
      if (responseData.statusCode != 200) {
        throw Exception("Server error ${responseData.statusCode}: ${responseData.body}");
      }
      
      var data = jsonDecode(responseData.body);

      if (data['status'] == 'success') {
        final Uint8List bytes = base64.decode(data['master_mix_b64']);

        // Determine correct mime type for saving
        String mimeType = 'audio/wav';
        if (format == 'mp3') mimeType = 'audio/mpeg';
        if (format == 'flac') mimeType = 'audio/flac';

        // Derive default save folder from original file path
        String defaultName = originalFileName.contains('.')
            ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
            : originalFileName;
        defaultName = '${defaultName}_voxray_master';

        // If we know the original folder, default the save name to include it
        // FileSaver.saveAs doesn't support a starting directory, but the name
        // gives the user a clear reference
        String? path = await FileSaver.instance.saveAs(
          name: defaultName,
          bytes: bytes,
          fileExtension: format,
          mimeType: MimeType.custom,
          customMimeType: mimeType,
        );
        
        if (path != null && path.isNotEmpty) {
          _showSaveConfirmation('Master mix saved as ${format.toUpperCase()}.');
        } else {
          _showSaveConfirmation('Export cancelled.');
        }
      } else {
        _showSaveConfirmation('Export failed: ${data['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      debugPrint("Export error: $e");
      _showSaveConfirmation('Export failed: $e');
    } finally {
      setState(() { isExporting = false; exportMessage = ''; });
    }
  }

  // ============================================================
  // SYNTH PLAYBACK / EXPORT (note-data sonification, no server)
  // ============================================================

  Future<void> _playSynthPreview() async {
    if (rawNotes.isEmpty) return;
    setState(() { isSynthRendering = true; synthMessage = "Synthesizing note data..."; });

    try {
      await synthPlayer.stop();

      final Uint8List wavBytes = renderNotesToWavBytes(
        notes: rawNotes,
        duration: songDuration,
        settings: synthSettings,
      );

      if (kIsWeb) {
        await synthPlayer.setAudioSource(MyCustomBytesSource(wavBytes));
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/voxray_synth_preview.wav');
        await tempFile.writeAsBytes(wavBytes);
        await synthPlayer.setFilePath(tempFile.path);
      }

      await synthPlayer.seek(Duration(milliseconds: (currentPosition * 1000).round()));
      await synthPlayer.play();
    } catch (e) {
      debugPrint("Synth preview failed: $e");
      _showSaveConfirmation('Synth preview failed: $e');
    } finally {
      setState(() { isSynthRendering = false; synthMessage = ''; });
    }
  }

  Future<void> _stopSynthPreview() async {
    await synthPlayer.stop();
  }

  Future<void> _exportSynthAudio() async {
    if (rawNotes.isEmpty) return;
    setState(() { isSynthRendering = true; synthMessage = "Rendering synth audio..."; });

    try {
      final Uint8List wavBytes = renderNotesToWavBytes(
        notes: rawNotes,
        duration: songDuration,
        settings: synthSettings,
      );

      String defaultName = originalFileName.contains('.')
          ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
          : (originalFileName.isNotEmpty ? originalFileName : projectName);
      defaultName = '${defaultName}_synth';

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: defaultName,
          bytes: wavBytes,
          fileExtension: 'wav',
          mimeType: MimeType.custom,
          customMimeType: 'audio/wav',
        );
        _showSaveConfirmation('Synth audio exported as WAV.');
      } else {
        String? path = await FileSaver.instance.saveAs(
          name: defaultName,
          bytes: wavBytes,
          fileExtension: 'wav',
          mimeType: MimeType.custom,
          customMimeType: 'audio/wav',
        );
        if (path != null && path.isNotEmpty) {
          _showSaveConfirmation('Synth audio exported as WAV.');
        } else {
          _showSaveConfirmation('Export cancelled.');
        }
      }
    } catch (e) {
      debugPrint("Synth export failed: $e");
      _showSaveConfirmation('Synth export failed: $e');
    } finally {
      setState(() { isSynthRendering = false; synthMessage = ''; });
    }
  }

  void _showSynthSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void update(SynthSettings Function(SynthSettings) fn) {
            setDialogState(() => synthSettings = fn(synthSettings));
            setState(() {});
          }

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Row(children: [
              Icon(Icons.graphic_eq, color: Colors.tealAccent, size: 20),
              SizedBox(width: 8),
              Text('Synth Settings', style: TextStyle(color: Colors.white)),
            ]),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Plays back the note grid's pitch data directly — "
                        "useful for verifying detected pitches independent of the original recording.",
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 16),
                    const Text('Waveform', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.0)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: Waveform.values.map((w) {
                        bool selected = synthSettings.waveform == w;
                        return ChoiceChip(
                          label: Text(w.label, style: TextStyle(fontSize: 12, color: selected ? Colors.black : Colors.white70)),
                          selected: selected,
                          selectedColor: Colors.tealAccent,
                          backgroundColor: Colors.white10,
                          onSelected: (_) => update((s) => s.copyWith(waveform: w)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Envelope (ADSR)', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    _synthSlider('Attack', synthSettings.adsr.attack, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(attack: v)))),
                    _synthSlider('Decay', synthSettings.adsr.decay, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(decay: v)))),
                    _synthSlider('Sustain', synthSettings.adsr.sustain, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(sustain: v)))),
                    _synthSlider('Release', synthSettings.adsr.release, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(adsr: s.adsr.copyWith(release: v)))),
                    const SizedBox(height: 8),
                    _synthSlider('Gain', synthSettings.masterGain, 0.0, 1.0,
                        (v) => update((s) => s.copyWith(masterGain: v))),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Text("Follow X-Ray contour", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                        Switch(
                          value: synthSettings.useXrayContour,
                          activeColor: Colors.amberAccent,
                          onChanged: (v) => update((s) => s.copyWith(useXrayContour: v)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent.withOpacity(0.2)),
                icon: const Icon(Icons.play_arrow, color: Colors.tealAccent, size: 16),
                label: const Text('Preview', style: TextStyle(color: Colors.tealAccent)),
                onPressed: rawNotes.isEmpty ? null : () {
                  Navigator.pop(context);
                  _playSynthPreview();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _synthSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))),
        Expanded(child: Slider(value: value, min: min, max: max, activeColor: Colors.tealAccent, onChanged: onChanged)),
        SizedBox(width: 36, child: Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.white54, fontSize: 10))),
      ],
    );
  }

  void _showSaveConfirmation(String message, {bool isPreview = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isPreview ? Colors.deepPurple[800] : Colors.grey[800],
        duration: Duration(seconds: isPreview ? 6 : 4),
        action: isPreview
            ? SnackBarAction(
                label: 'Play',
                textColor: Colors.deepPurpleAccent,
                onPressed: () => masterPlayer.play(),
              )
            : null,
      ),
    );
  }

  void _showPitchPrintOptions() {
    bool fullSong = true; // default

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Row(children: [
            Icon(Icons.fingerprint, color: Colors.amberAccent, size: 20),
            SizedBox(width: 8),
            Text('PitchPrint™', style: TextStyle(color: Colors.white)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Generate a high-resolution pitch analysis graph.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              // Range selector
              Container(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      value: true,
                      groupValue: fullSong,
                      activeColor: Colors.amberAccent,
                      title: const Text('Full Song', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Complete performance analysis', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      onChanged: (v) => setDialogState(() => fullSong = v!),
                    ),
                    RadioListTile<bool>(
                      value: false,
                      groupValue: fullSong,
                      activeColor: Colors.amberAccent,
                      title: const Text('Visible Region', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Current timeline view only', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      onChanged: (v) => setDialogState(() => fullSong = v!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Format selector
              const Text('Format', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _formatChip('SVG', 'Vector', Colors.tealAccent),
                  _formatChip('PNG', 'High-Res', Colors.amberAccent),
                  _formatChip('PDF', 'Print', Colors.blueAccent),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent.withOpacity(0.2)),
              icon: const Icon(Icons.fingerprint, color: Colors.amberAccent, size: 16),
              label: const Text('Generate', style: TextStyle(color: Colors.amberAccent)),
              onPressed: () {
                Navigator.pop(context);
                _downloadPitchPrint(fullSong: fullSong);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatChip(String format, String label, Color color) {
    // For now just visual — wire up selection state when you want multiple format options
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(format, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
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
              const Text("Live", style: TextStyle(fontWeight: FontWeight.bold)),
              Switch(
                value: isLiveModeActive,
                onChanged: (val) => setState(() => isLiveModeActive = val),
                activeColor: Colors.redAccent,
              ),
            ],
          ),
          if (!isLiveModeActive) ...[
            IconButton(icon: const Icon(Icons.undo), onPressed: undoStack.isEmpty ? null : _undo),
            IconButton(icon: const Icon(Icons.redo), onPressed: redoStack.isEmpty ? null : _redo),
            if (MediaQuery.of(context).size.width > 600) ...[
              IconButton(icon: const Icon(Icons.folder_open), tooltip: "Load .vxr", onPressed: _loadVoxrayProject),
              IconButton(icon: const Icon(Icons.save), tooltip: "Save .vxr", onPressed: _saveVoxrayProject),
              IconButton(icon: const Icon(Icons.sync_problem), tooltip: "Reprocess X-Ray", onPressed: _forceReprocessXray),
            ] else
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'load': _loadVoxrayProject(); break;
                    case 'save': _saveVoxrayProject(); break;
                    case 'export': _showExportDialog(); break;
                    case 'reprocess': _forceReprocessXray(); break; // <--- NEW ACTION
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'load', child: ListTile(leading: Icon(Icons.folder_open), title: Text('Load .vxr'))),
                  const PopupMenuItem(value: 'save', child: ListTile(leading: Icon(Icons.save), title: Text('Save .vxr'))),
                  const PopupMenuDivider(),
                  // --- NEW ADVANCED MENU ITEM ---
                  const PopupMenuItem(
                    value: 'reprocess', 
                    child: ListTile(
                      leading: Icon(Icons.sync_problem, color: Colors.orangeAccent), 
                      title: Text('Reprocess X-Ray', style: TextStyle(color: Colors.orangeAccent)),
                      subtitle: Text('Force server recalculation', style: TextStyle(fontSize: 10, color: Colors.white38)),
                    )
                  ),
                ],
              ),
          ],
        ],
      ),
      // --- ADDED SAFEAREA TO RESPECT ANDROID/IOS SYSTEM UI BOUNDARIES ---
      body: SafeArea(
        child: isLiveModeActive
            ? const LivePedagogyView()
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    color: Colors.black26,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (isLoading)
                            SizedBox(
                              width: 150,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(processingMessage, style: const TextStyle(fontSize: 10, color: Colors.tealAccent), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  LinearProgressIndicator(value: processingProgress, backgroundColor: Colors.grey[800], color: Colors.tealAccent, minHeight: 4),
                                ],
                              ),
                            )
                          else
                            ElevatedButton(
                              onPressed: _loadFileAndAnalyze,
                              style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
                              child: const Text('Upload')
                            ),
                          
                          const SizedBox(width: 16),
                          const Text("Zoom X", style: TextStyle(fontSize: 12)),
                          SizedBox(width: 80, child: Slider(value: zoomX, min: 50.0, max: 400.0, onChanged: (v) => setState(() => zoomX = v))),
                          
                          const Text("Zoom Y", style: TextStyle(fontSize: 12)),
                          SizedBox(width: 80, child: Slider(value: zoomY, min: 10.0, max: 60.0, onChanged: (v) => setState(() => zoomY = v))),
                          
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800], visualDensity: VisualDensity.compact),
                            icon: const Icon(Icons.analytics, size: 14), label: const Text("Dossier"),
                            onPressed: _showDossier,
                          ),
                          
                          const SizedBox(width: 8),
                          if (rawNotes.isNotEmpty && originalAudioBytes != null)
                            isPreviewing
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurpleAccent)),
                                    const SizedBox(width: 6),
                                    Text(exportMessage, style: const TextStyle(fontSize: 11, color: Colors.deepPurpleAccent)),
                                  ],
                                )
                              : ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple[700], visualDensity: VisualDensity.compact),
                                  icon: const Icon(Icons.play_circle, size: 14), label: const Text("Preview Mix"),
                                  onPressed: _previewWithEdits,
                                ),

                          const SizedBox(width: 8),
                          isExporting
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent)),
                                  const SizedBox(width: 6),
                                  Text(exportMessage, style: const TextStyle(fontSize: 11, color: Colors.tealAccent)),
                                ],
                              )
                            : IconButton(icon: const Icon(Icons.download, size: 20), tooltip: "Export Master", onPressed: rawNotes.isEmpty ? null : _showExportDialog),
                            
                          Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                          // download dossier (with advanced forensics or pitchprint graph) via a popup menu:
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.download, size: 20),
                            tooltip: "Download Report",
                            onSelected: (value) {
                              switch (value) {
                                case 'dossier': _downloadDossier(); break;
                                case 'pitchprint': _showPitchPrintOptions(); break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'dossier',
                                child: ListTile(
                                  leading: Icon(Icons.description, color: Colors.tealAccent),
                                  title: Text('Pro Dossier'),
                                  subtitle: Text('Full forensic PDF report', style: TextStyle(fontSize: 11)),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'pitchprint',
                                child: ListTile(
                                  leading: Icon(Icons.fingerprint, color: Colors.amberAccent),
                                  title: Text('PitchPrint™'),
                                  subtitle: Text('Visual pitch analysis graph', style: TextStyle(fontSize: 11)),
                                ),
                              ),
                            ],
                          ),
                          IconButton(icon: Icon(masterPlayer.playing ? Icons.pause : Icons.play_arrow, size: 24), onPressed: () => masterPlayer.playing ? masterPlayer.pause() : masterPlayer.play()),
                          IconButton(
                            icon: Icon(Icons.touch_app, color: isScrubMode ? Colors.amberAccent : Colors.white38, size: 20),
                            tooltip: "Scrub Mode", onPressed: () => setState(() => isScrubMode = !isScrubMode),
                          ),
                          IconButton(
                            icon: Icon(Icons.pan_tool, color: isDragMode ? Colors.amberAccent : Colors.white38, size: 20),
                            tooltip: "Drag Pitch Mode", onPressed: () => setState(() => isDragMode = !isDragMode),
                          ),
                          // Toggle and launch xray mode (polyphonic pitch analysis) — if already processing, show a spinner instead of the button:
                          isXrayProcessing 
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12.0),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent)),
                              )
                            : IconButton(
                                icon: Icon(Icons.fingerprint, color: isXrayMode ? Colors.amberAccent : Colors.white38, size: 20),
                                tooltip: "X-ray Pitch Analysis", 
                                onPressed: _toggleXrayMode, // <--- Actually calls the function!
                              ),
                          IconButton(icon: Icon(Icons.tune, color: isMixerOpen ? Colors.tealAccent : Colors.white70, size: 20), onPressed: () => setState(() => isMixerOpen = !isMixerOpen)),
                          IconButton(icon: const Icon(Icons.add_location_alt, size: 20, color: Colors.amberAccent), tooltip: "Add Marker", onPressed: addMarkerAtCurrentPlayhead),

                          Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                          // --- SYNTH PLAYBACK OF NOTE DATA ---
                          isSynthRendering
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12.0),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent)),
                              )
                            : IconButton(
                                icon: Icon(synthPlayer.playing ? Icons.stop_circle : Icons.graphic_eq, color: Colors.tealAccent, size: 20),
                                tooltip: synthPlayer.playing ? "Stop Synth Playback" : "Play Synth (Note Data)",
                                onPressed: rawNotes.isEmpty ? null : (synthPlayer.playing ? _stopSynthPreview : _playSynthPreview),
                              ),
                          IconButton(
                            icon: const Icon(Icons.tune_outlined, size: 18, color: Colors.white70),
                            tooltip: "Synth Settings",
                            onPressed: _showSynthSettingsDialog,
                          ),
                          IconButton(
                            icon: const Icon(Icons.save_alt, size: 18, color: Colors.tealAccent),
                            tooltip: "Export Synth Audio (.wav)",
                            onPressed: rawNotes.isEmpty ? null : _exportSynthAudio,
                          ),
                          
                          if (markers.length >= 2) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.repeat, size: 16, color: Colors.blueAccent),
                                const SizedBox(width: 8),
                                Switch(value: isLoopModeActive, onChanged: (val) => setState(() => isLoopModeActive = val), activeColor: Colors.blueAccent),
                              ],
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.settings_overscan, size: 18, color: Colors.blueAccent),
                              tooltip: "Set Loop Region",
                              itemBuilder: (context) {
                                List<PopupMenuItem<String>> items = [];
                                for (int i = 0; i < markers.length; i++) {
                                  for (int j = i + 1; j < markers.length; j++) {
                                    items.add(PopupMenuItem(
                                      value: '${markers[i]['time']}_${markers[j]['time']}',
                                      child: Text('${markers[i]['label']} → ${markers[j]['label']}', style: const TextStyle(fontSize: 12)),
                                    ));
                                  }
                                }
                                return items;
                              },
                              onSelected: (val) {
                                final parts = val.split('_');
                                setLoopFromMarkers(double.parse(parts[0]), double.parse(parts[1]));
                              },
                            ),
                          ] else ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.repeat, size: 16, color: Colors.blueAccent),
                                const SizedBox(width: 8),
                                Switch(value: isLoopModeActive, onChanged: (val) => setState(() => isLoopModeActive = val), activeColor: Colors.blueAccent),
                              ],
                            ),
                          ],
                          
                          if (markers.isNotEmpty)
                            PopupMenuButton<double>(
                              icon: const Icon(Icons.location_on, color: Colors.amberAccent, size: 20),
                              tooltip: "Jump to Marker",
                              itemBuilder: (context) => markers.map((marker) {
                                int totalSeconds = (marker['time'] as double).round();
                                String timestamp = '${(totalSeconds ~/ 60).toString().padLeft(2, '0')}:${(totalSeconds % 60).toString().padLeft(2, '0')}';
                                return PopupMenuItem<double>(
                                  value: marker['time'],
                                  child: Row(children: [
                                    const Icon(Icons.location_on, color: Colors.amberAccent, size: 16),
                                    const SizedBox(width: 8),
                                    Text('${marker['label']}  '),
                                    Text(timestamp, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  ]),
                                );
                              }).toList(),
                              onSelected: (time) => jumpToTimelinePosition(time),
                            ),
                        ],
                      ),
                    ),
                  ),

                  if (isMixerOpen)
                    Container(
                      width: double.infinity,
                      color: Colors.grey[900],
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 250,
                            child: Row(
                              children: [
                                const SizedBox(width: 65, child: Text("Vocal Vol", style: TextStyle(fontSize: 11, color: Colors.white70))),
                                Expanded(child: Slider(value: targetVolume, min: 0.0, max: 2.0, activeColor: Colors.tealAccent, onChanged: (v) => setState(() => targetVolume = v))),
                                SizedBox(width: 32, child: Text("${(targetVolume * 100).round()}%", style: const TextStyle(fontSize: 10, color: Colors.white54))),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 250,
                            child: Row(
                              children: [
                                const SizedBox(width: 65, child: Text("Accomp Vol", style: TextStyle(fontSize: 11, color: Colors.white70))),
                                Expanded(child: Slider(value: accompVolume, min: 0.0, max: 2.0, activeColor: Colors.amberAccent, onChanged: (v) => setState(() => accompVolume = v))),
                                SizedBox(width: 32, child: Text("${(accompVolume * 100).round()}%", style: const TextStyle(fontSize: 10, color: Colors.white54))),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("De-Hiss", style: TextStyle(fontSize: 11, color: Colors.white70)),
                                Switch(value: applyDenoise, onChanged: (val) => setState(() => applyDenoise = val), activeColor: Colors.amberAccent),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Filename banner — in Column, not in Row
                  if (originalFileName != "Unknown File" && !isLiveModeActive)
                    SizedBox(
                      height: 18,
                      child: Row(
                        children: [
                          const Icon(Icons.audio_file, size: 11, color: Colors.white24),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              originalFileName.isNotEmpty ? originalFileName : "Unknown File",
                              //originalFilePath.isNotEmpty ? originalFilePath : originalFileName,
                              style: const TextStyle(fontSize: 10, color: Colors.white30),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (projectName != "Voxray_Session") ...[
                            const SizedBox(width: 8),
                            Text('[$projectName]', style: const TextStyle(fontSize: 10, color: Colors.white24)),
                          ],
                        ],
                      ),
                    ),

                  // Ruler row — clean, no banner inside it
                  Row(
                    children: [
                      Container(width: 60, height: 35, color: Colors.grey[900]),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: rulerScrollController,
                          scrollDirection: Axis.horizontal,
                          child: TimelineRulerWidget(dawState: this),
                        ),
                      ),
                    ],
                  ),

                  Expanded(
                    child: TimelineCanvasWidget(
                      dawState: this,
                      horizontalScrollController: horizontalScrollController,
                      verticalScrollController: verticalScrollController,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showDossier() {
    if (rawNotes.isEmpty) return;

    // Helper
    String midiToName(num midi) {
      const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
      int m = midi.round();
      return '${noteNames[m % 12]}${(m ~/ 12) - 1}';
    }

    int totalNotes = 0;
    double totalError = 0;
    int perfectlyTuned = 0;
    int mutedCount = 0;
    int deletedCount = 0;

    // Per-note-name error accumulation for worst-offender report
    Map<String, List<double>> noteErrors = {};

    bool hasXray = rawNotes.any((n) => n.containsKey('contour') && n['contour'] != null);

    for (var note in rawNotes) {
      if (note['isDeleted'] == true) { deletedCount++; continue; }
      if (note['isMuted'] == true) mutedCount++;
      totalNotes++;

      double effectiveCents;

      // If xray contour exists, use actual pitch drift average from contour
      if (note['contour'] != null && (note['contour'] as List).isNotEmpty) {
        List<dynamic> contour = note['contour'];
        double avgDrift = contour.map((c) => (c as num).toDouble().abs()).reduce((a, b) => a + b) / contour.length;
        effectiveCents = avgDrift;
      } else {
        // Fall back to actual_midi fractional cents + any user shift
        double baseMidi = (note['actual_midi'] ?? 60.0).toDouble();
        double rawCents = (baseMidi - baseMidi.round()) * 100;
        double shiftCents = (note['cents_shift'] ?? 0).toDouble();
        effectiveCents = (rawCents + shiftCents).abs();
      }

      totalError += effectiveCents;
      if (effectiveCents <= 10) perfectlyTuned++;

      // Use actual midi for note name grouping
      double baseMidi = (note['actual_midi'] ?? 60.0).toDouble();
      String name = midiToName(baseMidi.round());
      noteErrors.putIfAbsent(name, () => []);
      noteErrors[name]!.add(effectiveCents);
    }

    double avgError = totalNotes > 0 ? totalError / totalNotes : 0;
    double tunedPct = totalNotes > 0 ? (perfectlyTuned / totalNotes) * 100 : 0;

    // Find worst 3 offenders by average error per note name
    var worstNotes = noteErrors.entries.toList()
      ..sort((a, b) {
        double aAvg = a.value.reduce((x, y) => x + y) / a.value.length;
        double bAvg = b.value.reduce((x, y) => x + y) / b.value.length;
        return bAvg.compareTo(aAvg);
      });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Row(
          children: [
            const Text("Performance Dossier", style: TextStyle(color: Colors.white)),
            const Spacer(),
            if (hasXray)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.fingerprint, color: Colors.amberAccent, size: 14),
                  SizedBox(width: 4),
                  Text('X-Ray', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                ]),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                child: const Text('X-Ray not enabled', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SUMMARY ---
              const Text("SUMMARY", style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              _dossierRow("Notes analyzed", "$totalNotes"),
              _dossierRow("Muted notes", "$mutedCount"),
              _dossierRow("Deleted notes", "$deletedCount"),
              const SizedBox(height: 10),

              // --- PITCH ACCURACY ---
              const Text("PITCH ACCURACY", style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              if (!hasXray)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.info_outline, color: Colors.white38, size: 14),
                    SizedBox(width: 8),
                    Flexible(child: Text(
                      'Enable X-Ray mode for detailed pitch contour analysis. '
                      'Basic MIDI deviation shown below.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    )),
                  ]),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.07), borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.fingerprint, color: Colors.amberAccent, size: 14),
                    SizedBox(width: 8),
                    Flexible(child: Text(
                      'X-Ray pitch contour data active. Variance reflects real pitch drift within each note.',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                    )),
                  ]),
                ),
              const SizedBox(height: 10),
              _dossierRow("Avg pitch error", "${avgError.toStringAsFixed(1)} ¢"),
              _dossierRow("Studio-accurate (≤10¢)", "${tunedPct.toStringAsFixed(1)}%"),
              const SizedBox(height: 10),

              // Color-coded accuracy bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: tunedPct / 100,
                  backgroundColor: Colors.redAccent.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    tunedPct >= 80 ? Colors.tealAccent
                    : tunedPct >= 50 ? Colors.amberAccent
                    : Colors.redAccent,
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),

              // --- WORST OFFENDERS ---
              if (worstNotes.isNotEmpty) ...[
                const Text("MOST VARIANCE BY NOTE", style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                ...worstNotes.take(5).map((entry) {
                  double avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
                  Color c = avg <= 10 ? Colors.tealAccent : avg <= 25 ? Colors.amberAccent : Colors.redAccent;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      SizedBox(width: 36, child: Text(entry.key, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                      const SizedBox(width: 8),
                      Expanded(child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (avg / 100).clamp(0.0, 1.0),
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(c),
                          minHeight: 6,
                        ),
                      )),
                      const SizedBox(width: 8),
                      Text('${avg.toStringAsFixed(1)}¢', style: TextStyle(color: c, fontSize: 11)),
                      Text(' ×${entry.value.length}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ]),
                  );
                }),
                const SizedBox(height: 16),
              ],

              // --- VERDICT ---
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: avgError < 15 ? Colors.teal.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: avgError < 15 ? Colors.tealAccent.withOpacity(0.4) : Colors.redAccent.withOpacity(0.4)),
                ),
                child: Text(
                  avgError < 10
                    ? "VERDICT: Exceptional intonation. Studio-ready performance."
                    : avgError < 15
                      ? "VERDICT: Highly accurate. Minor touch-ups may be desired."
                      : avgError < 25
                        ? "VERDICT: Moderate variance detected. Pitch correction recommended on flagged notes."
                        : "VERDICT: Significant tuning issues. Review red-flagged notes in the piano roll.",
                  style: TextStyle(
                    color: avgError < 15 ? Colors.tealAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  // Helper widget for dossier rows
  Widget _dossierRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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