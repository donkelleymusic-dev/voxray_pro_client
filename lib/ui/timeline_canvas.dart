import 'package:flutter/material.dart';
import '../main.dart';
import 'note_inspector.dart';
import 'package:flutter/rendering.dart'; 
import 'dart:math' as math;
import '../models/channel_state.dart';
// imports for new hardware gaming timer
import 'package:flutter/scheduler.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter/scheduler.dart';

class TimelineCanvasWidget extends StatefulWidget {
  final VoxrayDAWState dawState;
  final ScrollController horizontalScrollController;
  final ScrollController verticalScrollController;

  const TimelineCanvasWidget({
    Key? key, 
    required this.dawState,
    required this.horizontalScrollController,
    required this.verticalScrollController,
  }) : super(key: key);

  @override
  State<TimelineCanvasWidget> createState() => _TimelineCanvasWidgetState();
}

// 1. Add SingleTickerProviderStateMixin for the 60fps Game Loop
class _TimelineCanvasWidgetState extends State<TimelineCanvasWidget> with SingleTickerProviderStateMixin {
  //late Ticker;
  late Ticker _audioSyncTicker;
  final ValueNotifier<double> exactPlayheadTime = ValueNotifier<double>(0.0);

  int? draggingNoteIndex;
  double dragStartY = 0;
  int initialSemitoneShift = 0;
  int initialCentsShift = 0;
  int lastPlayedMidi = -1;

  @override
  void initState() {
    super.initState();
    exactPlayheadTime.value = widget.dawState.currentPosition;
    
    // 2. Initialize the hardware-locked ticker to poll audio time directly
    _audioSyncTicker = createTicker((elapsed) {
      if (widget.dawState.isPlaying) {
        
        // 1. DECLARE the variable so the compiler knows what it is
        double currentTime = widget.dawState.currentPosition;
        bool foundTime = false;
    
        // 2. FETCH the high-res time from the audio engine
        if (widget.dawState.masterHandle != null && SoLoud.instance.getIsValidVoiceHandle(widget.dawState.masterHandle!)) {
          currentTime = SoLoud.instance.getPosition(widget.dawState.masterHandle!).inMilliseconds / 1000.0;
          foundTime = true;
        } else if (widget.dawState.stemHandles.isNotEmpty) {
          for (var handle in widget.dawState.stemHandles.values) {
            if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
              currentTime = SoLoud.instance.getPosition(handle).inMilliseconds / 1000.0;
              foundTime = true;
              break;
            }
          }
        }
        
        //widget.dawState.logToSupabase("DEBUG: timeline_canvas.dart createTicker high-res time fetch. foundTime = ${foundTime}");
    
        // 3. UPDATE the playhead state
        exactPlayheadTime.value = currentTime; // Now it knows what currentTime is!

        // --- UPDATE VU METERS ---
        // 1. Update Synth (Note-Driven)
        widget.dawState.channelLevels['synth']?.value = 
            calculateSynthLevel(currentTime, widget.dawState.rawNotes) * widget.dawState.getChannelState('synth').volume;
            
        // 2. Update Audio Stems (RMS-Driven)
        for (String stemName in widget.dawState.stemSources.keys) {
           var state = widget.dawState.getChannelState(stemName);
           widget.dawState.channelLevels[stemName]?.value = 
               calculateAudioLevel(currentTime, state.stem_rms_data) * state.volume;
          //widget.dawState.logToSupabase("DEBUG: timeline_canvas.dart Update Audio Stem: ${stemName}, value: ${calculateAudioLevel(currentTime, state.stem_rms_data) * state.volume} foundTime");
        }
        // -----------------------------
        
        // 4. SCROLL the canvas synchronously using your math
        if (!widget.dawState.isUserScrolling && widget.horizontalScrollController.hasClients) {
          double anchorOffset = widget.horizontalScrollController.position.viewportDimension * 0.35;
          double targetX = (currentTime * widget.dawState.zoomX) - anchorOffset;
          
          if (targetX < 0) targetX = 0;
          
          if (widget.horizontalScrollController.position.maxScrollExtent > 0) {
            widget.horizontalScrollController.jumpTo(
              targetX.clamp(0.0, widget.horizontalScrollController.position.maxScrollExtent)
            );
          }
        }
    
      } else {
        // Keep things synced if playback is paused but the user is scrubbing
        if (!widget.dawState.isUserScrolling) {
          exactPlayheadTime.value = widget.dawState.currentPosition;
        }
      }
    });
    _audioSyncTicker.start();
    //.start();
  }

  @override
  void dispose() {
    _audioSyncTicker.dispose(); 
    super.dispose();
    //.dispose();
    //exactPlayheadTime.dispose();
    //super.dispose();
  }

  double calculateSynthLevel(double currentPlayheadSeconds, List<dynamic> rawNotes) {
    for (var note in rawNotes) {
      if (note['isDeleted'] == true || note['isMuted'] == true) continue;
      
      double start = note['start_time'];
      double end = start + ((note['end_time'] - start) * (note['time_ratio'] ?? 1.0));
      
      if (currentPlayheadSeconds >= start && currentPlayheadSeconds <= end) {
        return (note['amplitude'] ?? 0.8).toDouble();
      }
    }
    return 0.0;
  }

  double calculateAudioLevel(double currentPlayheadSeconds, List<double> precomputedstem_rms_data) {
    if (precomputedstem_rms_data.isEmpty) {
      return 0.0;
    } else {
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('calculateAudioLevel error stem_rms_data NOT empty'), backgroundColor: Colors.cyan),
      );
    }
    int index = (currentPlayheadSeconds * 10).floor();
    if (index >= 0 && index < precomputedstem_rms_data.length) {
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('calculateAudioLevel precomputedstem_rms_data: $precomputedstem_rms_data[index]'), backgroundColor: Colors.green),
      );
      return precomputedstem_rms_data[index];
    }
    return 0.0;
  }
  
  int get minMidi {
    switch (widget.dawState.activeEditableStem) {
      case 'drums': return 35; // GM Drum Map starts around here
      case 'bass': case 'contrabass': case 'tuba': return 24;
      case 'violin': case 'flute': return 55;
      case 'piano': case 'original': return 21;
      default: return 36;
    }
  }

  int get maxMidi {
    switch (widget.dawState.activeEditableStem) {
      case 'drums': return 59; // Covers up to Crash/Ride cymbals
      case 'bass': case 'contrabass': case 'tuba': return 72;
      case 'violin': case 'flute': return 108;
      case 'piano': case 'original': return 108;
      default: return 84;
    }
  }

  double _midiToFreq(double midi) {
    return 440.0 * math.pow(2.0, (midi - 69.0) / 12.0);
  }

  void _playPitchFeedback(double exactMidi) {
    widget.dawState.playPreviewTone(_midiToFreq(exactMidi));
  }

  @override
  Widget build(BuildContext context) {
    double duration = (widget.dawState.songDuration > 0) ? widget.dawState.songDuration : 30.0;
    double zoomX = (widget.dawState.zoomX > 0) ? widget.dawState.zoomX : 50.0;
    double zoomY = (widget.dawState.zoomY > 0) ? widget.dawState.zoomY : 8.0;

    double totalHeight = (maxMidi - minMidi + 1) * zoomY;
    double timelineWidth = duration * zoomX;
    
    bool isDrums = widget.dawState.activeEditableStem == 'drums';

    // Get current scroll position for the painter's culling logic
    double currentScrollX = widget.horizontalScrollController.hasClients 
        ? widget.horizontalScrollController.position.pixels 
        : 0.0;

    var processedNotes = widget.dawState.rawNotes.map<Map<String, dynamic>>((note) {
      double actualMidi = (note['actual_midi'] ?? 60.0).toDouble();
      int semitoneShift = note['semitone_shift'] ?? 0;
      double shiftCents = (note['cents_shift'] ?? 0).toDouble();
      double effectiveMidi = actualMidi + semitoneShift + (shiftCents / 100.0);
      return <String, dynamic>{...(note as Map<String, dynamic>), "display_midi": effectiveMidi.round()};
    }).toList();

    final ScrollPhysics? scrollPhysics = (widget.dawState.currentDragMode != DragMode.off || draggingNoteIndex != null)
        ? const NeverScrollableScrollPhysics() : null;

    return Stack(
      children: [
        SingleChildScrollView(
          controller: widget.verticalScrollController,
          physics: scrollPhysics,
          scrollDirection: Axis.vertical,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30, height: totalHeight,
                decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 2))),
                child: CustomPaint(
                  painter: PianoKeysPainter(
                    minMidi: minMidi, 
                    maxMidi: maxMidi, 
                    zoomY: widget.dawState.zoomY,
                    isDrumsMode: isDrums,
                  )
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                  if (notification is UserScrollNotification) {
                    widget.dawState.isUserScrolling = notification.direction != ScrollDirection.idle;
                  } else if (notification is ScrollUpdateNotification) {
                    
                    // 3. REMOVED setState() TO STOP LATENCY LOOP
                    
                    if (widget.dawState.isUserScrolling && widget.dawState.isScrubMode) {
                      double viewportWidth = notification.metrics.viewportDimension;
                      double maxScroll = notification.metrics.maxScrollExtent;
                      
                      // Clamp pixels to prevent over-scroll bouncing from breaking the math
                      double pixels = notification.metrics.pixels.clamp(0.0, maxScroll);
                      
                      // The target 25% anchor you requested
                      double anchorOffset = viewportWidth * 0.25; 
                      double dynamicAnchor = anchorOffset;

                      // STATE 1: Smoothly collapse the anchor to 0% as we hit the left edge
                      if (pixels < anchorOffset) {
                        dynamicAnchor = (pixels / anchorOffset) * anchorOffset;
                      } 
                      // STATE 3: Smoothly push the anchor to 100% as we hit the right edge
                      else {
                        double rightZone = viewportWidth * 0.75;
                        if (pixels > maxScroll - rightZone) {
                          double fraction = (pixels - (maxScroll - rightZone)) / rightZone;
                          dynamicAnchor = anchorOffset + (fraction * rightZone);
                        }
                      }
                      
                      double seekTime = (pixels + dynamicAnchor) / widget.dawState.zoomX;
                      double clampedTime = seekTime.clamp(0.0, widget.dawState.songDuration);
                      
                      // Instantly update the visual UI via the fast Notifier
                      exactPlayheadTime.value = clampedTime;
                      
                      // Update the audio engine directly without triggering heavy DAWState rebuilds
                      widget.dawState.seekAllPlayers(clampedTime);
                      
                      // Silently sync the state variable for background processes
                      widget.dawState.currentPosition = clampedTime;
                    }
                  }
                  return false;
                },

                  child: SingleChildScrollView(
                    controller: widget.horizontalScrollController,
                    physics: scrollPhysics,
                    scrollDirection: Axis.horizontal,
                    child: GestureDetector(
                      onTapDown: (details) {
                        print("Tap registered. Current DragMode: ${widget.dawState.currentDragMode}"); // Check the console
                        if (widget.dawState.currentDragMode != DragMode.off) {
                          print("TAP GUARD BLOCKED ACTION");
                          return;
                        }
                        if (widget.dawState.currentDragMode != DragMode.off) return; 
                        const double touchSlop = 24.0; 
                        for (int i = 0; i < processedNotes.length; i++) {
                          var pNote = processedNotes[i];
                          if (pNote['isDeleted'] == true || (pNote['actual_midi'] ?? 60.0).round() == 0 || pNote['type'] == 'xray_line') continue;
                          double startX = pNote['start_time'] * widget.dawState.zoomX;
                          double endX = (pNote['start_time'] + ((pNote['end_time'] - pNote['start_time']) * (pNote['time_ratio'] ?? 1.0))) * widget.dawState.zoomX;
                          double effectiveMidi = (pNote['actual_midi'] ?? 60.0) + (pNote['semitone_shift'] ?? 0) + ((pNote['cents_shift'] ?? 0) / 100.0);
                          double visualY = (maxMidi - effectiveMidi) * widget.dawState.zoomY;
                          if (Rect.fromLTRB(startX, visualY - (widget.dawState.zoomY / 2) - touchSlop, endX, visualY + (widget.dawState.zoomY / 2) + touchSlop).contains(details.localPosition)) {
                            NoteInspector.show(context, widget.dawState, i, widget.dawState.rawNotes[i]);
                            break;
                          }
                        }
                      },
                      onPanStart: widget.dawState.currentDragMode != DragMode.off ? (details) {
                        const double touchSlop = 24.0; 
                        for (int i = 0; i < processedNotes.length; i++) {
                          var pNote = processedNotes[i];
                          if (pNote['isDeleted'] == true || (pNote['actual_midi'] ?? 60.0).round() == 0 || pNote['type'] == 'xray_line') continue;
                          double startX = pNote['start_time'] * widget.dawState.zoomX;
                          double endX = (pNote['start_time'] + ((pNote['end_time'] - pNote['start_time']) * (pNote['time_ratio'] ?? 1.0))) * widget.dawState.zoomX;
                          double effectiveMidi = (pNote['actual_midi'] ?? 60.0) + (pNote['semitone_shift'] ?? 0) + ((pNote['cents_shift'] ?? 0) / 100.0);
                          double visualY = (maxMidi - effectiveMidi) * widget.dawState.zoomY;
                          
                          if (Rect.fromLTRB(startX, visualY - (widget.dawState.zoomY / 2) - touchSlop, endX, visualY + (widget.dawState.zoomY / 2) + touchSlop).contains(details.localPosition)) {
                            widget.dawState.registerUndoSnapshot(); 
                            setState(() {
                              draggingNoteIndex = i;
                              dragStartY = details.localPosition.dy;
                              initialSemitoneShift = widget.dawState.rawNotes[i]['semitone_shift'] ?? 0;
                              initialCentsShift = widget.dawState.rawNotes[i]['cents_shift'] ?? 0;
                            });
                            _playPitchFeedback(effectiveMidi);
                            break;
                          }
                        }
                      } : null,
                      onPanUpdate: widget.dawState.currentDragMode != DragMode.off ? (details) {
                        if (draggingNoteIndex == null) return;
                        double deltaY = details.localPosition.dy - dragStartY;

                        if (widget.dawState.currentDragMode == DragMode.semitone) {
                          int semitoneDelta = -(deltaY / widget.dawState.zoomY).round();
                          int targetShift = initialSemitoneShift + semitoneDelta;
                          if (widget.dawState.rawNotes[draggingNoteIndex!]['semitone_shift'] != targetShift) {
                            widget.dawState.setState(() => widget.dawState.rawNotes[draggingNoteIndex!]['semitone_shift'] = targetShift);
                            double originalMidi = (widget.dawState.rawNotes[draggingNoteIndex!]['actual_midi'] ?? 60.0).toDouble();
                            _playPitchFeedback(originalMidi + targetShift + (initialCentsShift / 100.0));
                          }
                        } else if (widget.dawState.currentDragMode == DragMode.microTuning) {
                          int centsDelta = -(deltaY / widget.dawState.zoomY * 100).round();
                          int targetCents = (initialCentsShift + centsDelta).clamp(-100, 100);
                          if (widget.dawState.rawNotes[draggingNoteIndex!]['cents_shift'] != targetCents) {
                            widget.dawState.setState(() => widget.dawState.rawNotes[draggingNoteIndex!]['cents_shift'] = targetCents);
                            double originalMidi = (widget.dawState.rawNotes[draggingNoteIndex!]['actual_midi'] ?? 60.0).toDouble();
                            _playPitchFeedback(originalMidi + initialSemitoneShift + (targetCents / 100.0));
                          }
                        }
                      } : null,
                      onPanEnd: widget.dawState.currentDragMode != DragMode.off ? (details) { setState(() { draggingNoteIndex = null; lastPlayedMidi = -1; }); } : null,
                      onPanCancel: widget.dawState.currentDragMode != DragMode.off ? () { setState(() { draggingNoteIndex = null; lastPlayedMidi = -1; }); } : null,
                      child: Stack(
                        children: [
                          // 4. Wrap CustomPaint in RepaintBoundary to cache the heavy vector graphics
                          RepaintBoundary(
                            child: CustomPaint(
                              size: Size(timelineWidth, totalHeight),
                              painter: AdvancedPianoRollPainter(
                                notes: processedNotes, 
                                continuousXray: widget.dawState.continuousXray,
                                currentScrollX: currentScrollX,                 
                                zoomX: widget.dawState.zoomX, 
                                zoomY: widget.dawState.zoomY,
                                minMidi: minMidi, maxMidi: maxMidi, 
                                isXrayMode: widget.dawState.isXrayMode,
                                isDrumsMode: isDrums,
                                draggingNoteIndex: draggingNoteIndex, 
                                initialSemitoneShift: initialSemitoneShift,
                              ),
                            ),
                          ),
                          // 5. ValueListenableBuilder explicitly for the lightweight Playhead
                          ValueListenableBuilder<double>(
                            valueListenable: exactPlayheadTime,
                            builder: (context, timeValue, child) {
                              // 1. Calculate the exact pixel position
                              double rawX = timeValue * widget.dawState.zoomX;
                              
                              // 2. QUANTIZATION: Round to the nearest integer pixel. 
                              // This kills the jitter because fluctuations < 0.5 pixels are ignored.
                              double snappedX = rawX.floorToDouble(); 
                          
                              return Positioned(
                                left: snappedX,
                                top: 0,
                                bottom: 0,
                                child: child!,
                              );
                            },
                            child: Container(
                              width: 2,
                              color: Colors.redAccent.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PianoKeysPainter extends CustomPainter {
  final int minMidi; 
  final int maxMidi; 
  final double zoomY;
  final bool isDrumsMode;

  // 1. Define the Map here for clean lookups and easy editing
  static const Map<int, String> drumMap = {
    36: 'KICK',
    38: 'SNARE',
    41: 'TOM',
    42: 'CH HAT',
    43: 'TOM',
    45: 'TOM',
    46: 'OH HAT',
    47: 'TOM',
    49: 'CRASH',
    50: 'TOM',
    51: 'RIDE',
    53: 'RIDE',
    55: 'CRASH',
    57: 'CRASH',
    59: 'RIDE',
  };
  
  PianoKeysPainter({
    required this.minMidi, 
    required this.maxMidi, 
    required this.zoomY, 
    this.isDrumsMode = false
  });

  bool isBlackKey(int midi) { 
    if (isDrumsMode) return false; // Drum tracks just use uniform lanes
    int note = midi % 12; 
    return note == 1 || note == 3 || note == 6 || note == 8 || note == 10; 
  }
  
  String getNoteName(int midi) { 
    if (isDrumsMode) {
      // Returns the label if found, otherwise returns an empty string
      return drumMap[midi] ?? ''; 
    }
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']; 
    return '${noteNames[midi % 12]}${(midi ~/ 12) - 1}'; 
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      
      // Drum mode uses alternating lane colors instead of black/white keys
      Paint keyPaint = Paint()..color = isDrumsMode 
          ? (i % 2 == 0 ? Colors.grey[850]! : Colors.grey[900]!) 
          : (isBlackKey(i) ? Colors.black87 : Colors.white);
          
      canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), keyPaint);
      
      if (!isBlackKey(i) && !isDrumsMode) {
        canvas.drawLine(
          Offset(0, topY + zoomY), 
          Offset(size.width, topY + zoomY), 
          Paint()..color = Colors.grey[400]!
        );
      }
      
      String label = getNoteName(i);
      
      // 2. Only attempt to draw text if the label isn't blank
      if (label.isNotEmpty) {
        double dynamicFontSize = (zoomY * 0.75).clamp(5.0, 10.0);
        if (zoomY >= 5.0) {
          TextPainter tp = TextPainter(
            text: TextSpan(
              text: label, 
              style: TextStyle(
                color: isDrumsMode ? Colors.amberAccent : (isBlackKey(i) ? Colors.white : Colors.black), 
                fontSize: dynamicFontSize, 
                fontWeight: FontWeight.bold
              )
            ), 
            textDirection: TextDirection.ltr
          )..layout();
          
          tp.paint(canvas, Offset(size.width - tp.width - 2, topY + (zoomY / 2) - (tp.height / 2)));
        }
      }
    }
  }
  
  @override 
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class AdvancedPianoRollPainter extends CustomPainter {
  final List<Map<String, dynamic>> notes;
  final List<dynamic> continuousXray;
  final double currentScrollX;
  final double zoomX; final double zoomY;
  final int minMidi; final int maxMidi;
  final bool isXrayMode;
  final bool isDrumsMode;
  final int? draggingNoteIndex;
  final int initialSemitoneShift;

  AdvancedPianoRollPainter({
    required this.notes, 
    required this.continuousXray,
    required this.currentScrollX,
    required this.zoomX, 
    required this.zoomY, 
    required this.minMidi, 
    required this.maxMidi, 
    this.isXrayMode = false, 
    this.isDrumsMode = false,
    this.draggingNoteIndex, 
    this.initialSemitoneShift = 0
  });

  String getNoteName(int midi) { const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']; return '${noteNames[midi % 12]}${(midi ~/ 12) - 1}'; }
  bool isBlackKey(int midi) { int note = midi % 12; return note == 1 || note == 3 || note == 6 || note == 8 || note == 10; }

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      if (isBlackKey(i) && !isDrumsMode) canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), Paint()..color = Colors.white.withOpacity(0.02));
      canvas.drawLine(Offset(0, topY), Offset(size.width, topY), Paint()..color = Colors.white.withOpacity(0.05));
    }

    // =========================================================================
    // LAYER 1: DRAW GLOBAL CONTINUOUS VISUAL X-RAY TRACKING LINE
    // =========================================================================
    if (isXrayMode && continuousXray.isNotEmpty && !isDrumsMode) {
      final xrayPaint = Paint()
        ..color = Colors.tealAccent.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      final Path continuousPath = Path();
      bool isPathStarted = false;
      double lastTime = -1.0;

      for (var point in continuousXray) {
        double time = (point[0] ?? 0.0).toDouble();
        double midiPitch = (point[1] ?? 60.0).toDouble();

        double px = time * zoomX;
        double py = (maxMidi - midiPitch) * zoomY + (zoomY / 2);

        // Culling: Don't draw point artifacts if they clip completely outside viewport bounds
        if (px < currentScrollX - 100 || px > currentScrollX + size.width + 100) {
          isPathStarted = false;
          lastTime = time;
          continue;
        }

        // THE MAGIC GAP DETECTOR
        if (isPathStarted && (time - lastTime) > 0.05) {
          isPathStarted = false;
        }

        if (!isPathStarted) {
          continuousPath.moveTo(px, py);
          isPathStarted = true;
        } else {
          continuousPath.lineTo(px, py);
        }
        
        lastTime = time;
      }
      canvas.drawPath(continuousPath, xrayPaint);
    }

    // =========================================================================
    // LAYER 2: DRAW ANALYTICAL BLOCKS, TRANSIENT BLOBS, AND LOCAL RE-TUNING GUIDES
    // =========================================================================
    for (int i = 0; i < notes.length; i++) {
      var note = notes[i];
      if (note['isDeleted'] == true || (note['actual_midi'] ?? 60.0).round() == 0) continue; 
      
      bool isXrayLine = note['type'] == 'xray_line';
      
      double actualMidi = (note['actual_midi'] ?? 60.0).toDouble();
      double startX = note['start_time'] * zoomX;
      double endX = (note['start_time'] + ((note['end_time'] - note['start_time']) * (note['time_ratio'] ?? 1.0))) * zoomX;
      double padding = zoomY * 0.15; 

      // Calculate the amplitude-based style
      double amplitude = (note['amplitude'] ?? 0.8).toDouble();
      bool isQuiet = amplitude < 0.15; 

      int semitoneShift = note['semitone_shift'] ?? 0;
      double currentShiftCents = (note['cents_shift'] ?? 0).toDouble();
      double effectiveMidi = actualMidi + semitoneShift + (currentShiftCents / 100.0);
      double visualY = (maxMidi - effectiveMidi) * zoomY;

      // ==========================================
      // THE DRUM BLOB INTERCEPTOR
      // ==========================================
      bool isDrumHit = note['type'] == 'drum_hit' || isDrumsMode;

      if (isDrumHit) {
        double amplitude = (note['amplitude'] ?? 0.8).toDouble();
        Color drumColor = Colors.deepOrangeAccent.withOpacity((0.3 + (amplitude * 0.7)).clamp(0.0, 1.0));
        
        double blobRadius = zoomY * 0.45; 
        
        canvas.drawCircle(
          Offset(startX + blobRadius, visualY + (zoomY / 2)),
          blobRadius,
          Paint()..color = drumColor
        );
        
        continue; 
      }

      // Only process Ghost Rectangles and Solid Blocks for real pitched notes
      if (!isXrayLine) {
        if (i == draggingNoteIndex) {
          double ghostEffectiveMidi = actualMidi + initialSemitoneShift + (currentShiftCents / 100.0);
          double ghostVisualY = (maxMidi - ghostEffectiveMidi) * zoomY;
          Rect ghostRect = Rect.fromLTRB(startX, ghostVisualY + padding, endX, ghostVisualY + zoomY - padding);
          canvas.drawRRect(RRect.fromRectAndRadius(ghostRect, const Radius.circular(4)), Paint()..color = Colors.white.withOpacity(0.15)..style = PaintingStyle.fill);
          canvas.drawRRect(RRect.fromRectAndRadius(ghostRect, const Radius.circular(4)), Paint()..color = Colors.white.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 1.0);
        }

        double baseFraction = note['xray_cents'] != null ? (note['xray_cents'] / 100.0) : (actualMidi - actualMidi.round());
        double exactCurrentMidi = actualMidi.round() + baseFraction + semitoneShift + (currentShiftCents / 100.0);
        int deviationFromDisplay = ((exactCurrentMidi - note['display_midi']) * 100).round();

        Color noteColor = deviationFromDisplay.abs() <= 10 ? Colors.blueAccent : deviationFromDisplay.abs() <= 25 ? Colors.amberAccent : Colors.redAccent;
        if (note['isMuted'] == true) noteColor = Colors.grey.withOpacity(0.3);
        if (i == draggingNoteIndex) noteColor = noteColor.withOpacity(0.7);

        Color finalNoteColor = noteColor;
        if (isQuiet) {
            finalNoteColor = noteColor.withOpacity(0.15);
        } else if (isXrayMode && i != draggingNoteIndex) {
            finalNoteColor = noteColor.withOpacity(0.4);
        }

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(startX, visualY + padding, endX, visualY + zoomY - padding), 
            const Radius.circular(4)
          ), 
          Paint()
            ..color = finalNoteColor
            ..style = PaintingStyle.fill 
        );

        String labelText = '${getNoteName(note['display_midi'])} ${deviationFromDisplay > 0 ? '+$deviationFromDisplay¢' : (deviationFromDisplay == 0 ? '±0¢' : '$deviationFromDisplay¢')}';
        
        // ==========================================
        // NEW TEXT RENDERING (DYNAMIC RESIZE & OUTLINE)
        // ==========================================
        
        double maxFontSize = (zoomY * 0.6).clamp(6.0, 14.0); 
        double availableWidth = (endX - startX) - 6.0; 

        if (availableWidth > 10 && zoomY > 10) { 
          TextPainter measureTp = TextPainter(
            text: TextSpan(text: labelText, style: TextStyle(fontSize: maxFontSize, fontWeight: FontWeight.bold)),
            textDirection: TextDirection.ltr
          )..layout();

          double finalFontSize = maxFontSize;
          if (measureTp.width > availableWidth) {
            finalFontSize = maxFontSize * (availableWidth / measureTp.width);
          }

          if (finalFontSize >= 4.5) {
            Color outlineColor = isQuiet ? Colors.white.withOpacity(0.25) : Colors.white;
            Color fillColor = isQuiet ? Colors.black.withOpacity(0.25) : Colors.black;

            TextPainter tpOutline = TextPainter(
              text: TextSpan(
                text: labelText,
                style: TextStyle(
                  fontSize: finalFontSize,
                  fontWeight: FontWeight.w900,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 2.0 
                    ..color = outlineColor,
                )
              ),
              textDirection: TextDirection.ltr
            )..layout();

            TextPainter tpFill = TextPainter(
              text: TextSpan(
                text: labelText,
                style: TextStyle(
                  fontSize: finalFontSize,
                  fontWeight: FontWeight.w900,
                  color: fillColor,
                )
              ),
              textDirection: TextDirection.ltr
            )..layout();

            Offset textOffset = Offset(startX + 3, visualY + (zoomY / 2) - (tpFill.height / 2));
            tpOutline.paint(canvas, textOffset);
            tpFill.paint(canvas, textOffset);
          }
        }
      }

      double latencyOffset = 0.045;
      
      if (isXrayMode && note['contour'] != null && (note['contour'] as List).isNotEmpty) {
        Path contourPath = Path();
        List<dynamic> contour = note['contour'];
        double stepX = (endX - startX) / (contour.length > 1 ? contour.length - 1 : 1);
        double vibrato = (note['vibrato_scale'] ?? 1.0).toDouble();
        for (int j = 0; j < contour.length; j++) {
          double px = (startX - latencyOffset) + (j * stepX);
          double pointMidi = actualMidi.round().toDouble() + semitoneShift + ((contour[j].toDouble() * vibrato) + currentShiftCents) / 100.0;
          double py = (maxMidi - pointMidi) * zoomY + (zoomY / 2);
          if (j == 0) contourPath.moveTo(px, py); else contourPath.lineTo(px, py);
        }
        
        Color lineColor = isXrayLine ? Colors.white.withOpacity(0.3) : Colors.white;
        canvas.drawPath(contourPath, Paint()..color = lineColor..style = PaintingStyle.stroke..strokeWidth = 2.0..strokeCap = StrokeCap.round);
      }
    }
  }
  
  @override 
  bool shouldRepaint(covariant AdvancedPianoRollPainter oldDelegate) {
    return oldDelegate.zoomX != zoomX ||
           oldDelegate.zoomY != zoomY ||
           oldDelegate.currentScrollX != currentScrollX ||
           oldDelegate.draggingNoteIndex != draggingNoteIndex ||
           oldDelegate.isXrayMode != isXrayMode ||
           oldDelegate.isDrumsMode != isDrumsMode ||
           oldDelegate.notes != notes; 
  }
}
