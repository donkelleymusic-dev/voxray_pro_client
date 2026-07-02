import 'package:flutter/material.dart';
import '../main.dart';
import 'note_inspector.dart';
import 'package:flutter/rendering.dart'; 

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
  final int minMidi = 36;
  final int maxMidi = 84;

  int? draggingNoteIndex;
  double dragStartY = 0;
  double initialCentsShift = 0;

  @override
  Widget build(BuildContext context) {
    double duration = (widget.dawState.songDuration > 0) ? widget.dawState.songDuration : 30.0;
    double zoomX = (widget.dawState.zoomX > 0) ? widget.dawState.zoomX : 50.0;
    double zoomY = (widget.dawState.zoomY > 0) ? widget.dawState.zoomY : 8.0;

    double totalHeight = (maxMidi - minMidi + 1) * zoomY;
    double timelineWidth = duration * zoomX;

    var processedNotes = widget.dawState.rawNotes.map<Map<String, dynamic>>((note) {
      double actualMidi = (note['actual_midi'] ?? 60.0).toDouble();
      double shiftCents = (note['cents_shift'] ?? 0).toDouble();
      
      // Calculate effective position with original microtonal shift preserved
      double effectiveMidi = actualMidi + (shiftCents / 100.0);
      int nearest = effectiveMidi.round();
      
      return <String, dynamic>{
        ...(note as Map<String, dynamic>), 
        "display_midi": nearest,
      };
    }).toList();

    return Stack(
      children: [
        SingleChildScrollView(
          controller: widget.verticalScrollController,
          physics: draggingNoteIndex != null ? const NeverScrollableScrollPhysics() : null,
          scrollDirection: Axis.vertical,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: totalHeight,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.black, width: 2))
                ),
                child: CustomPaint(
                  painter: PianoKeysPainter(
                    minMidi: minMidi, 
                    maxMidi: maxMidi, 
                    zoomY: widget.dawState.zoomY
                  ),
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification) {
                      if (notification.direction != ScrollDirection.idle) {
                        widget.dawState.isUserScrolling = true;
                      } else {
                        widget.dawState.isUserScrolling = false;

                        if (widget.dawState.isScrubMode) {
                          double seekTime = (notification.metrics.pixels + 150) / widget.dawState.zoomX;
                          seekTime = seekTime.clamp(0.0, widget.dawState.songDuration);
                          widget.dawState.masterPlayer.seek(Duration(milliseconds: (seekTime * 1000).round()));
                        }
                      }
                    } 
                    else if (notification is ScrollUpdateNotification) {
                      if (widget.dawState.isUserScrolling && widget.dawState.isScrubMode) {
                        double seekTime = (notification.metrics.pixels + 150) / widget.dawState.zoomX;
                        seekTime = seekTime.clamp(0.0, widget.dawState.songDuration);
                        widget.dawState.setState(() {
                          widget.dawState.currentPosition = seekTime;
                        });
                      }
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: widget.horizontalScrollController,
                    physics: draggingNoteIndex != null ? const NeverScrollableScrollPhysics() : null,
                    scrollDirection: Axis.horizontal,
                    child: GestureDetector(
                      onTapDown: (details) {
                        if (widget.dawState.isDragMode) return; 
                        const double touchSlop = 24.0; 
                        
                        for (int i = 0; i < processedNotes.length; i++) {
                          var pNote = processedNotes[i];
                          if (pNote['isDeleted'] == true) continue;
                          
                          double startX = pNote['start_time'] * widget.dawState.zoomX;
                          double endX = (pNote['start_time'] + ((pNote['end_time'] - pNote['start_time']) * (pNote['time_ratio'] ?? 1.0))) * widget.dawState.zoomX;
                          
                          double effectiveMidi = (pNote['actual_midi'] ?? 60.0) + ((pNote['cents_shift'] ?? 0) / 100.0);
                          double visualY = (maxMidi - effectiveMidi) * widget.dawState.zoomY;
                          
                          Rect hitBox = Rect.fromLTRB(startX, visualY - (widget.dawState.zoomY / 2) - touchSlop, endX, visualY + (widget.dawState.zoomY / 2) + touchSlop);
                          if (hitBox.contains(details.localPosition)) {
                            NoteInspector.show(context, widget.dawState, i, widget.dawState.rawNotes[i]);
                            break;
                          }
                        }
                      },
                      onPanStart: widget.dawState.isDragMode ? (details) {
                        const double touchSlop = 24.0; 
                        
                        for (int i = 0; i < processedNotes.length; i++) {
                          var pNote = processedNotes[i];
                          if (pNote['isDeleted'] == true) continue;
                          
                          double startX = pNote['start_time'] * widget.dawState.zoomX;
                          double endX = (pNote['start_time'] + ((pNote['end_time'] - pNote['start_time']) * (pNote['time_ratio'] ?? 1.0))) * widget.dawState.zoomX;
                          
                          double effectiveMidi = (pNote['actual_midi'] ?? 60.0) + ((pNote['cents_shift'] ?? 0) / 100.0);
                          double visualY = (maxMidi - effectiveMidi) * widget.dawState.zoomY;
                          
                          Rect hitBox = Rect.fromLTRB(startX, visualY - (widget.dawState.zoomY / 2) - touchSlop, endX, visualY + (widget.dawState.zoomY / 2) + touchSlop);
                          
                          if (hitBox.contains(details.localPosition)) {
                            widget.dawState.registerUndoSnapshot(); 
                            setState(() {
                              draggingNoteIndex = i;
                              dragStartY = details.localPosition.dy;
                              initialCentsShift = (widget.dawState.rawNotes[i]['cents_shift'] ?? 0).toDouble();
                            });
                            break;
                          }
                        }
                      } : null,
                      onPanUpdate: widget.dawState.isDragMode ? (details) {
                        if (draggingNoteIndex == null) return;
                        
                        double deltaY = details.localPosition.dy - dragStartY;
                        int semitoneDelta = -(deltaY / widget.dawState.zoomY).round();
                        
                        // Increment by exact 100-cent steps to preserve original microtonal shift
                        widget.dawState.setState(() {
                          widget.dawState.rawNotes[draggingNoteIndex!]['cents_shift'] = 
                            initialCentsShift + (semitoneDelta * 100);
                        });
                      } : null,
                      onPanEnd: widget.dawState.isDragMode 
                        ? (details) { setState(() { draggingNoteIndex = null; }); } 
                        : null,
                      onPanCancel: widget.dawState.isDragMode 
                        ? () { setState(() { draggingNoteIndex = null; }); } 
                        : null,
                      child: CustomPaint(
                        size: Size(timelineWidth, totalHeight),
                        painter: AdvancedPianoRollPainter(
                          notes: processedNotes,
                          zoomX: widget.dawState.zoomX,
                          zoomY: widget.dawState.zoomY,
                          minMidi: minMidi,
                          maxMidi: maxMidi,
                          isXrayMode: widget.dawState.isXrayMode,
                          draggingNoteIndex: draggingNoteIndex,
                          initialCentsShift: initialCentsShift,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 30 + 150,
          top: 0,
          bottom: 0,
          child: Container(width: 2, color: Colors.redAccent.withOpacity(0.8)),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------
// Piano Keys Painter
// -------------------------------------------------------------
class PianoKeysPainter extends CustomPainter {
  final int minMidi;
  final int maxMidi;
  final double zoomY;

  PianoKeysPainter({required this.minMidi, required this.maxMidi, required this.zoomY});

  bool isBlackKey(int midi) {
    int note = midi % 12;
    return note == 1 || note == 3 || note == 6 || note == 8 || note == 10;
  }

  String getNoteName(int midi) {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    int octave = (midi ~/ 12) - 1;
    return '${noteNames[midi % 12]}$octave';
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      Paint keyPaint = Paint()..color = isBlackKey(i) ? Colors.black87 : Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), keyPaint);
      if (!isBlackKey(i)) {
        canvas.drawLine(Offset(0, topY + zoomY), Offset(size.width, topY + zoomY), Paint()..color = Colors.grey[400]!);
      }
      if (i % 12 == 0 && zoomY > 10) {
        TextPainter tp = TextPainter(
          text: TextSpan(text: getNoteName(i), style: TextStyle(color: isBlackKey(i) ? Colors.white : Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width - 2, topY + (zoomY / 2) - (tp.height / 2)));
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// -------------------------------------------------------------
// Grid Lines & Dynamic Color Note Painter
// -------------------------------------------------------------
class AdvancedPianoRollPainter extends CustomPainter {
  final List<Map<String, dynamic>> notes;
  final double zoomX;
  final double zoomY;
  final int minMidi;
  final int maxMidi;
  final bool isXrayMode;
  final int? draggingNoteIndex;
  final double initialCentsShift;

  AdvancedPianoRollPainter({
    required this.notes,
    required this.zoomX,
    required this.zoomY,
    required this.minMidi,
    required this.maxMidi,
    this.isXrayMode = false,
    this.draggingNoteIndex,
    this.initialCentsShift = 0.0,
  });

  String getNoteName(int midi) {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return '${noteNames[midi % 12]}${(midi ~/ 12) - 1}';
  }

  bool isBlackKey(int midi) {
    int note = midi % 12;
    return note == 1 || note == 3 || note == 6 || note == 8 || note == 10;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Grid lines
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      if (isBlackKey(i)) {
        canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), Paint()..color = Colors.white.withOpacity(0.02));
      }
      canvas.drawLine(Offset(0, topY), Offset(size.width, topY), Paint()..color = Colors.white.withOpacity(0.05));
    }

    for (int i = 0; i < notes.length; i++) {
      var note = notes[i];
      if (note['isDeleted'] == true) continue;

      double startX = note['start_time'] * zoomX;
      double endX = (note['start_time'] + ((note['end_time'] - note['start_time']) * (note['time_ratio'] ?? 1.0))) * zoomX;
      double noteWidth = endX - startX;
      double padding = zoomY * 0.15; 

      // Calculate absolute effective positioning
      double actualMidi = (note['actual_midi'] ?? 60.0).toDouble();
      double currentShiftCents = (note['cents_shift'] ?? 0).toDouble();
      double effectiveMidi = actualMidi + (currentShiftCents / 100.0);
      double visualY = (maxMidi - effectiveMidi) * zoomY;

      // --- PAINT GHOST NOTE IF DRAGGING ---
      if (i == draggingNoteIndex) {
        double ghostEffectiveMidi = actualMidi + (initialCentsShift / 100.0);
        double ghostVisualY = (maxMidi - ghostEffectiveMidi) * zoomY;
        
        Rect ghostRect = Rect.fromLTRB(startX, ghostVisualY + padding, endX, ghostVisualY + zoomY - padding);
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(ghostRect, const Radius.circular(4)), 
          Paint()
            ..color = Colors.white.withOpacity(0.15)
            ..style = PaintingStyle.fill
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(ghostRect, const Radius.circular(4)), 
          Paint()
            ..color = Colors.white.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
        );
      }

      double baseFraction = note['xray_cents'] != null 
          ? (note['xray_cents'] / 100.0)
          : (actualMidi - actualMidi.round());
      double exactCurrentMidi = actualMidi.round() + baseFraction + (currentShiftCents / 100.0);
      int deviationFromDisplay = ((exactCurrentMidi - note['display_midi']) * 100).round();

      Color noteColor;
      if (deviationFromDisplay.abs() <= 10) {
        noteColor = Colors.tealAccent;
      } else if (deviationFromDisplay.abs() <= 25) {
        noteColor = Colors.amberAccent;
      } else {
        noteColor = Colors.redAccent;
      }
      if (note['isMuted'] == true) noteColor = Colors.grey.withOpacity(0.3);
      if (i == draggingNoteIndex) noteColor = noteColor.withOpacity(0.7);

      Rect noteRect = Rect.fromLTRB(startX, visualY + padding, endX, visualY + zoomY - padding);
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(noteRect, const Radius.circular(4)), 
        Paint()..color = isXrayMode && i != draggingNoteIndex ? noteColor.withOpacity(0.4) : noteColor
      );

      // Xray contour line mapped cleanly against true grid midi space
      if (isXrayMode && note['contour'] != null) {
        List<dynamic> contour = note['contour'];
        if (contour.isNotEmpty) {
          Path contourPath = Path();
          double stepX = (endX - startX) / (contour.length > 1 ? contour.length - 1 : 1);
          double vibrato = (note['vibrato_scale'] ?? 1.0).toDouble();
          double baseMidiForContour = actualMidi.round().toDouble();
          
          for (int j = 0; j < contour.length; j++) {
            double rawCents = contour[j].toDouble();
            double pointMidi = baseMidiForContour + ((rawCents * vibrato) + currentShiftCents) / 100.0;
            double px = startX + (j * stepX);
            double py = (maxMidi - pointMidi) * zoomY + (zoomY / 2);
            if (j == 0) contourPath.moveTo(px, py);
            else contourPath.lineTo(px, py);
          }
          canvas.drawPath(contourPath, Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round);
        }
      }

      // --- NOTE LABEL ---
      String noteName = getNoteName(note['display_midi']);
      String centsText = deviationFromDisplay > 0 ? '+$deviationFromDisplay¢' : (deviationFromDisplay == 0 ? '±0¢' : '$deviationFromDisplay¢');
      String labelText = '$noteName $centsText';

      TextPainter tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      if (noteWidth >= tp.width + 6 && zoomY > 14) {
        tp.paint(canvas, Offset(startX + 3, visualY + (zoomY / 2) - (tp.height / 2)));
      } else if (noteWidth >= 4) {
        double labelX = startX;
        double labelY = visualY - tp.height - 3;
        if (labelY < 0) labelY = visualY + zoomY + 2;

        Rect bgRect = Rect.fromLTWH(labelX - 2, labelY - 1, tp.width + 4, tp.height + 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
          Paint()..color = Colors.black.withOpacity(0.65),
        );
        tp.paint(canvas, Offset(labelX, labelY));
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}import 'package:flutter/material.dart';
import '../main.dart';
import 'note_inspector.dart';
import 'package:flutter/rendering.dart'; 

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
  final int minMidi = 36;
  final int maxMidi = 84;

  int? draggingNoteIndex;
  double dragStartY = 0;
  double initialActualMidi = 60.0;
  double initialCentsShift = 0;

  @override
  Widget build(BuildContext context) {
    double duration = (widget.dawState.songDuration > 0) ? widget.dawState.songDuration : 30.0;
    double zoomX = (widget.dawState.zoomX > 0) ? widget.dawState.zoomX : 100.0;
    double zoomY = (widget.dawState.zoomY > 0) ? widget.dawState.zoomY : 20.0;

    double totalHeight = (maxMidi - minMidi + 1) * zoomY;
    double timelineWidth = duration * zoomX;

    var processedNotes = widget.dawState.rawNotes.map<Map<String, dynamic>>((note) {
      double baseMidi = (note['actual_midi'] ?? 60.0).toDouble();
      int nearest = baseMidi.round();
      double dynamicCents = (baseMidi - nearest) * 100 + (note['cents_shift'] ?? 0);
      return <String, dynamic>{
        ...(note as Map<String, dynamic>), 
        "display_midi": nearest,
        "display_cents": dynamicCents.round()
      };
    }).toList();

    return Stack(
      children: [
        SingleChildScrollView(
          controller: widget.verticalScrollController,
          physics: draggingNoteIndex != null ? const NeverScrollableScrollPhysics() : null,
          scrollDirection: Axis.vertical,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: totalHeight,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.black, width: 2))
                ),
                child: CustomPaint(
                  painter: PianoKeysPainter(
                    minMidi: minMidi, 
                    maxMidi: maxMidi, 
                    zoomY: widget.dawState.zoomY
                  ),
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification) {
                      if (notification.direction != ScrollDirection.idle) {
                        widget.dawState.isUserScrolling = true;
                      } else {
                        widget.dawState.isUserScrolling = false;

                        if (widget.dawState.isScrubMode) {
                          double seekTime = (notification.metrics.pixels + 150) / widget.dawState.zoomX;
                          seekTime = seekTime.clamp(0.0, widget.dawState.songDuration);
                          widget.dawState.masterPlayer.seek(Duration(milliseconds: (seekTime * 1000).round()));
                        }
                      }
                    } 
                    else if (notification is ScrollUpdateNotification) {
                      if (widget.dawState.isUserScrolling && widget.dawState.isScrubMode) {
                        double seekTime = (notification.metrics.pixels + 150) / widget.dawState.zoomX;
                        seekTime = seekTime.clamp(0.0, widget.dawState.songDuration);
                        widget.dawState.setState(() {
                          widget.dawState.currentPosition = seekTime;
                        });
                      }
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: widget.horizontalScrollController,
                    physics: draggingNoteIndex != null ? const NeverScrollableScrollPhysics() : null,
                    scrollDirection: Axis.horizontal,
                    child: GestureDetector(
                      onTapDown: (details) {
                        if (widget.dawState.isDragMode) return; 
                        const double touchSlop = 24.0; // Expanded hit area
                        
                        for (int i = 0; i < processedNotes.length; i++) {
                          var pNote = processedNotes[i];
                          if (pNote['isDeleted'] == true) continue;
                          
                          double startX = pNote['start_time'] * widget.dawState.zoomX;
                          double endX = (pNote['start_time'] + ((pNote['end_time'] - pNote['start_time']) * (pNote['time_ratio'] ?? 1.0))) * widget.dawState.zoomX;
                          double yY = (maxMidi - pNote['display_midi']) * widget.dawState.zoomY;
                          double visualY = yY - ((pNote['display_cents'] / 100.0) * widget.dawState.zoomY);
                          
                          Rect hitBox = Rect.fromLTRB(startX, visualY - (widget.dawState.zoomY / 2) - touchSlop, endX, visualY + (widget.dawState.zoomY / 2) + touchSlop);
                          if (hitBox.contains(details.localPosition)) {
                            NoteInspector.show(context, widget.dawState, i, widget.dawState.rawNotes[i]);
                            break;
                          }
                        }
                      },
                      onPanStart: widget.dawState.isDragMode ? (details) {
                        const double touchSlop = 24.0; // Expanded hit area
                        
                        for (int i = 0; i < processedNotes.length; i++) {
                          var pNote = processedNotes[i];
                          if (pNote['isDeleted'] == true) continue;
                          
                          double startX = pNote['start_time'] * widget.dawState.zoomX;
                          double endX = (pNote['start_time'] + ((pNote['end_time'] - pNote['start_time']) * (pNote['time_ratio'] ?? 1.0))) * widget.dawState.zoomX;
                          double yY = (maxMidi - pNote['display_midi']) * widget.dawState.zoomY;
                          double visualY = yY - ((pNote['display_cents'] / 100.0) * widget.dawState.zoomY);
                          
                          Rect hitBox = Rect.fromLTRB(startX, visualY - (widget.dawState.zoomY / 2) - touchSlop, endX, visualY + (widget.dawState.zoomY / 2) + touchSlop);
                          
                          if (hitBox.contains(details.localPosition)) {
                            widget.dawState.registerUndoSnapshot(); 
                            setState(() {
                              draggingNoteIndex = i;
                              dragStartY = details.localPosition.dy;
                              initialActualMidi = (widget.dawState.rawNotes[i]['actual_midi'] ?? 60.0).toDouble();
                            });
                            break;
                          }
                        }
                      } : null,
                      onPanUpdate: widget.dawState.isDragMode ? (details) {
                        if (draggingNoteIndex == null) return;
                        
                        double deltaY = details.localPosition.dy - dragStartY;
                        double midiDelta = -(deltaY / widget.dawState.zoomY);
                        
                        widget.dawState.setState(() {
                          widget.dawState.rawNotes[draggingNoteIndex!]['actual_midi'] = 
                            (initialActualMidi + midiDelta).clamp(minMidi.toDouble(), maxMidi.toDouble());
                        });
                      } : null,
                      onPanEnd: widget.dawState.isDragMode 
                        ? (details) { setState(() { draggingNoteIndex = null; }); } 
                        : null,
                      onPanCancel: widget.dawState.isDragMode 
                        ? () { setState(() { draggingNoteIndex = null; }); } 
                        : null,
                      child: CustomPaint(
                        size: Size(timelineWidth, totalHeight),
                        painter: AdvancedPianoRollPainter(
                          notes: processedNotes,
                          zoomX: widget.dawState.zoomX,
                          zoomY: widget.dawState.zoomY,
                          minMidi: minMidi,
                          maxMidi: maxMidi,
                          isXrayMode: widget.dawState.isXrayMode,
                          draggingNoteIndex: draggingNoteIndex,
                          initialActualMidi: initialActualMidi,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 60 + 150,
          top: 0,
          bottom: 0,
          child: Container(width: 2, color: Colors.redAccent.withOpacity(0.8)),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------
// Piano Keys Painter
// -------------------------------------------------------------
class PianoKeysPainter extends CustomPainter {
  final int minMidi;
  final int maxMidi;
  final double zoomY;

  PianoKeysPainter({required this.minMidi, required this.maxMidi, required this.zoomY});

  bool isBlackKey(int midi) {
    int note = midi % 12;
    return note == 1 || note == 3 || note == 6 || note == 8 || note == 10;
  }

  String getNoteName(int midi) {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    int octave = (midi ~/ 12) - 1;
    return '${noteNames[midi % 12]}$octave';
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      Paint keyPaint = Paint()..color = isBlackKey(i) ? Colors.black87 : Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), keyPaint);
      if (!isBlackKey(i)) {
        canvas.drawLine(Offset(0, topY + zoomY), Offset(size.width, topY + zoomY), Paint()..color = Colors.grey[400]!);
      }
      if (i % 12 == 0) {
        TextPainter tp = TextPainter(
          text: TextSpan(text: getNoteName(i), style: TextStyle(color: isBlackKey(i) ? Colors.white : Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width - 5, topY + (zoomY / 2) - (tp.height / 2)));
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// -------------------------------------------------------------
// Grid Lines & Dynamic Color Note Painter
// -------------------------------------------------------------
class AdvancedPianoRollPainter extends CustomPainter {
  final List<Map<String, dynamic>> notes;
  final double zoomX;
  final double zoomY;
  final int minMidi;
  final int maxMidi;
  final bool isXrayMode;
  final int? draggingNoteIndex;
  final double? initialActualMidi;

  AdvancedPianoRollPainter({
    required this.notes,
    required this.zoomX,
    required this.zoomY,
    required this.minMidi,
    required this.maxMidi,
    this.isXrayMode = false,
    this.draggingNoteIndex,
    this.initialActualMidi,
  });

  String getNoteName(int midi) {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return '${noteNames[midi % 12]}${(midi ~/ 12) - 1}';
  }

  bool isBlackKey(int midi) {
    int note = midi % 12;
    return note == 1 || note == 3 || note == 6 || note == 8 || note == 10;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Grid lines
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      if (isBlackKey(i)) {
        canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), Paint()..color = Colors.white.withOpacity(0.02));
      }
      canvas.drawLine(Offset(0, topY), Offset(size.width, topY), Paint()..color = Colors.white.withOpacity(0.05));
    }

    for (int i = 0; i < notes.length; i++) {
      var note = notes[i];
      if (note['isDeleted'] == true) continue;

      double startX = note['start_time'] * zoomX;
      double endX = (note['start_time'] + ((note['end_time'] - note['start_time']) * (note['time_ratio'] ?? 1.0))) * zoomX;
      double topY = (maxMidi - note['display_midi']) * zoomY;
      double noteWidth = endX - startX;
      double padding = zoomY * 0.15; 

      // --- PAINT GHOST NOTE IF DRAGGING ---
      if (i == draggingNoteIndex && initialActualMidi != null) {
        int initialNearest = initialActualMidi!.round();
        double initialCents = (initialActualMidi! - initialNearest) * 100 + (note['cents_shift'] ?? 0);
        
        double ghostTopY = (maxMidi - initialNearest) * zoomY;
        double ghostVisualY = ghostTopY - ((initialCents / 100.0) * zoomY);
        
        Rect ghostRect = Rect.fromLTRB(startX, ghostVisualY + padding, endX, ghostVisualY + zoomY - padding);
        
        // Draw the translucent outline of where the note started
        canvas.drawRRect(
          RRect.fromRectAndRadius(ghostRect, const Radius.circular(4)), 
          Paint()
            ..color = Colors.white.withOpacity(0.15)
            ..style = PaintingStyle.fill
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(ghostRect, const Radius.circular(4)), 
          Paint()
            ..color = Colors.white.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
        );
      }

      int baselineCents = note['xray_cents']?.round() ?? note['display_cents'];
      int totalCents = (baselineCents + (note['cents_shift'] ?? 0)) as int;

      Color noteColor;
      if (totalCents.abs() <= 10) {
        noteColor = Colors.tealAccent;
      } else if (totalCents.abs() <= 25) {
        noteColor = Colors.amberAccent;
      } else {
        noteColor = Colors.redAccent;
      }
      if (note['isMuted'] == true) noteColor = Colors.grey.withOpacity(0.3);
      
      // Make the active dragging note slightly transparent so you can see the grid behind it
      if (i == draggingNoteIndex) noteColor = noteColor.withOpacity(0.7);

      double visualY = topY - ((note['display_cents'] / 100.0) * zoomY);
      Rect noteRect = Rect.fromLTRB(startX, visualY + padding, endX, visualY + zoomY - padding);
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(noteRect, const Radius.circular(4)), 
        Paint()..color = isXrayMode && i != draggingNoteIndex ? noteColor.withOpacity(0.4) : noteColor
      );

      // Xray contour line
      if (isXrayMode && note['contour'] != null) {
        List<dynamic> contour = note['contour'];
        if (contour.isNotEmpty) {
          Path contourPath = Path();
          double stepX = (endX - startX) / (contour.length > 1 ? contour.length - 1 : 1);
          double shift = (note['cents_shift'] ?? 0).toDouble();
          double vibrato = (note['vibrato_scale'] ?? 1.0).toDouble();
          for (int j = 0; j < contour.length; j++) {
            double rawCents = contour[j].toDouble();
            double manipulatedCents = (rawCents * vibrato) + shift;
            double px = startX + (j * stepX);
            double py = visualY + (zoomY / 2) - ((manipulatedCents / 100.0) * zoomY);
            if (j == 0) contourPath.moveTo(px, py);
            else contourPath.lineTo(px, py);
          }
          canvas.drawPath(contourPath, Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round);
        }
      }

      // --- NOTE LABEL ---
      String noteName = getNoteName(note['display_midi']);
      String centsText = totalCents > 0 ? '+$totalCents¢' : (totalCents == 0 ? '±0¢' : '$totalCents¢');
      String labelText = '$noteName $centsText';

      TextPainter tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      if (noteWidth >= tp.width + 6 && zoomY > 14) {
        tp.paint(canvas, Offset(startX + 3, visualY + (zoomY / 2) - (tp.height / 2)));
      } else if (noteWidth >= 4) {
        double labelX = startX;
        double labelY = visualY - tp.height - 3;
        if (labelY < 0) labelY = visualY + zoomY + 2;

        Rect bgRect = Rect.fromLTWH(labelX - 2, labelY - 1, tp.width + 4, tp.height + 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
          Paint()..color = Colors.black.withOpacity(0.65),
        );
        tp.paint(canvas, Offset(labelX, labelY));
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
