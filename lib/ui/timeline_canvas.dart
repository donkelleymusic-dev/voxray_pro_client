import 'package:flutter/material.dart';
import '../main.dart';
import 'note_inspector.dart';
import 'package:flutter/rendering.dart'; 
import 'dart:math' as math;

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

class _TimelineCanvasWidgetState extends State<TimelineCanvasWidget> {
  int? draggingNoteIndex;
  double dragStartY = 0;
  int initialSemitoneShift = 0;
  int initialCentsShift = 0;
  int lastPlayedMidi = -1;

  int get minMidi {
    switch (widget.dawState.activeEditableStem) {
      case 'bass': case 'contrabass': case 'tuba': return 24;
      case 'violin': case 'flute': return 55;
      case 'piano': case 'original': return 21;
      default: return 36;
    }
  }

  int get maxMidi {
    switch (widget.dawState.activeEditableStem) {
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
                child: CustomPaint(painter: PianoKeysPainter(minMidi: minMidi, maxMidi: maxMidi, zoomY: widget.dawState.zoomY)),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification) {
                      widget.dawState.isUserScrolling = notification.direction != ScrollDirection.idle;
                      if (!widget.dawState.isUserScrolling && widget.dawState.isScrubMode) {
                        double seekTime = (notification.metrics.pixels + 150) / widget.dawState.zoomX;
                        widget.dawState.seekAllPlayers(seekTime.clamp(0.0, widget.dawState.songDuration));
                      }
                    } else if (notification is ScrollUpdateNotification) {
                      // Trigger a rebuild so the Painter gets the new currentScrollX for culling
                      setState(() {}); 
                      
                      if (widget.dawState.isUserScrolling && widget.dawState.isScrubMode) {
                        double seekTime = (notification.metrics.pixels + 150) / widget.dawState.zoomX;
                        widget.dawState.setState(() => widget.dawState.currentPosition = seekTime.clamp(0.0, widget.dawState.songDuration));
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
                          CustomPaint(
                            size: Size(timelineWidth, totalHeight),
                            painter: AdvancedPianoRollPainter(
                              notes: processedNotes, 
                              continuousXray: widget.dawState.continuousXray, // Passed via constructor
                              currentScrollX: currentScrollX,                 // Passed via constructor
                              zoomX: widget.dawState.zoomX, 
                              zoomY: widget.dawState.zoomY,
                              minMidi: minMidi, maxMidi: maxMidi, 
                              isXrayMode: widget.dawState.isXrayMode,
                              draggingNoteIndex: draggingNoteIndex, 
                              initialSemitoneShift: initialSemitoneShift,
                            ),
                          ),
                          // Moving Vertical Playhead
                          Positioned(
                            left: widget.dawState.currentPosition * widget.dawState.zoomX,
                            top: 0,
                            bottom: 0,
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
  final int minMidi; final int maxMidi; final double zoomY;
  PianoKeysPainter({required this.minMidi, required this.maxMidi, required this.zoomY});

  bool isBlackKey(int midi) { int note = midi % 12; return note == 1 || note == 3 || note == 6 || note == 8 || note == 10; }
  String getNoteName(int midi) { const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']; return '${noteNames[midi % 12]}${(midi ~/ 12) - 1}'; }

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      Paint keyPaint = Paint()..color = isBlackKey(i) ? Colors.black87 : Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), keyPaint);
      if (!isBlackKey(i)) canvas.drawLine(Offset(0, topY + zoomY), Offset(size.width, topY + zoomY), Paint()..color = Colors.grey[400]!);
      if (i % 12 == 0 && zoomY > 10) {
        TextPainter tp = TextPainter(text: TextSpan(text: getNoteName(i), style: TextStyle(color: isBlackKey(i) ? Colors.white : Colors.black, fontSize: 8, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(size.width - tp.width - 2, topY + (zoomY / 2) - (tp.height / 2)));
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class AdvancedPianoRollPainter extends CustomPainter {
  final List<Map<String, dynamic>> notes;
  final List<dynamic> continuousXray;
  final double currentScrollX;
  final double zoomX; final double zoomY;
  final int minMidi; final int maxMidi;
  final bool isXrayMode;
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
    this.draggingNoteIndex, 
    this.initialSemitoneShift = 0
  });

  String getNoteName(int midi) { const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']; return '${noteNames[midi % 12]}${(midi ~/ 12) - 1}'; }
  bool isBlackKey(int midi) { int note = midi % 12; return note == 1 || note == 3 || note == 6 || note == 8 || note == 10; }

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      if (isBlackKey(i)) canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), Paint()..color = Colors.white.withOpacity(0.02));
      canvas.drawLine(Offset(0, topY), Offset(size.width, topY), Paint()..color = Colors.white.withOpacity(0.05));
    }

    // =========================================================================
    // LAYER 1: DRAW GLOBAL CONTINUOUS VISUAL X-RAY TRACKING LINE
    // =========================================================================
    if (isXrayMode && continuousXray.isNotEmpty) {
      final xrayPaint = Paint()
        ..color = Colors.tealAccent.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      final Path continuousPath = Path();
      bool isPathStarted = false;

      for (var point in continuousXray) {
        // Python API returns [time, pitch] array to save data
        double time = (point[0] ?? 0.0).toDouble();
        double midiPitch = (point[1] ?? 60.0).toDouble();

        // Map time and pitch directly to structural UI canvas coordinates
        double px = time * zoomX;
        double py = (maxMidi - midiPitch) * zoomY + (zoomY / 2);

        // Don't draw point artifacts if they clip completely outside horizontal viewport bounds
        if (px < currentScrollX - 100 || px > currentScrollX + size.width + 100) {
          isPathStarted = false; // Break the path so it doesn't draw a giant line across culling bounds
          continue;
        }

        if (!isPathStarted) {
          continuousPath.moveTo(px, py);
          isPathStarted = true;
        } else {
          continuousPath.lineTo(px, py);
        }
      }
      canvas.drawPath(continuousPath, xrayPaint);
    }

    // =========================================================================
    // LAYER 2: DRAW ANALYTICAL BLOCKS AND LOCAL RE-TUNING GUIDES
    // =========================================================================
    for (int i = 0; i < notes.length; i++) {
      var note = notes[i];
      if (note['isDeleted'] == true || (note['actual_midi'] ?? 60.0).round() == 0) continue; 
      
      bool isXrayLine = note['type'] == 'xray_line';
      
      double actualMidi = (note['actual_midi'] ?? 60.0).toDouble();
      double startX = note['start_time'] * zoomX;
      double endX = (note['start_time'] + ((note['end_time'] - note['start_time']) * (note['time_ratio'] ?? 1.0))) * zoomX;
      double padding = zoomY * 0.15; 

      int semitoneShift = note['semitone_shift'] ?? 0;
      double currentShiftCents = (note['cents_shift'] ?? 0).toDouble();
      double effectiveMidi = actualMidi + semitoneShift + (currentShiftCents / 100.0);
      double visualY = (maxMidi - effectiveMidi) * zoomY;

      // Only process Ghost Rectangles and Solid Blocks for real notes
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

        Color noteColor = deviationFromDisplay.abs() <= 10 ? Colors.tealAccent : deviationFromDisplay.abs() <= 25 ? Colors.amberAccent : Colors.redAccent;
        if (note['isMuted'] == true) noteColor = Colors.grey.withOpacity(0.3);
        if (i == draggingNoteIndex) noteColor = noteColor.withOpacity(0.7);

        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(startX, visualY + padding, endX, visualY + zoomY - padding), const Radius.circular(4)), Paint()..color = isXrayMode && i != draggingNoteIndex ? noteColor.withOpacity(0.4) : noteColor);

        String labelText = '${getNoteName(note['display_midi'])} ${deviationFromDisplay > 0 ? '+$deviationFromDisplay¢' : (deviationFromDisplay == 0 ? '±0¢' : '$deviationFromDisplay¢')}';
        TextPainter tp = TextPainter(text: TextSpan(text: labelText, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
        if ((endX - startX) >= tp.width + 6 && zoomY > 14) {
          tp.paint(canvas, Offset(startX + 3, visualY + (zoomY / 2) - (tp.height / 2)));
        }
      }

      // Draw the squiggly contour line for ALL objects (Real notes AND Continuous X-Ray lines)
      if (isXrayMode && note['contour'] != null && (note['contour'] as List).isNotEmpty) {
        Path contourPath = Path();
        List<dynamic> contour = note['contour'];
        double stepX = (endX - startX) / (contour.length > 1 ? contour.length - 1 : 1);
        double vibrato = (note['vibrato_scale'] ?? 1.0).toDouble();
        for (int j = 0; j < contour.length; j++) {
          double px = startX + (j * stepX);
          double pointMidi = actualMidi.round().toDouble() + semitoneShift + ((contour[j].toDouble() * vibrato) + currentShiftCents) / 100.0;
          double py = (maxMidi - pointMidi) * zoomY + (zoomY / 2);
          if (j == 0) contourPath.moveTo(px, py); else contourPath.lineTo(px, py);
        }
        
        // Dim the background lines slightly so the real notes pop
        Color lineColor = isXrayLine ? Colors.white.withOpacity(0.3) : Colors.white;
        canvas.drawPath(contourPath, Paint()..color = lineColor..style = PaintingStyle.stroke..strokeWidth = 2.0..strokeCap = StrokeCap.round);
      }
    }
  }
  
  @override 
  bool shouldRepaint(covariant AdvancedPianoRollPainter oldDelegate) {
    // Only repaint if zooming, scrolling, or dragging changes
    return oldDelegate.zoomX != zoomX ||
           oldDelegate.zoomY != zoomY ||
           oldDelegate.currentScrollX != currentScrollX ||
           oldDelegate.draggingNoteIndex != draggingNoteIndex ||
           oldDelegate.isXrayMode != isXrayMode;
  }
}
