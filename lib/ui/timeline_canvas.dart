import 'package:flutter/material.dart';
import '../main.dart';
import 'note_inspector.dart';

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

  // --- DRAG STATE TRACKING ---
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
          // Disable vertical canvas scrolling if we are actively dragging a note up/down
          physics: draggingNoteIndex != null ? const NeverScrollableScrollPhysics() : null,
          scrollDirection: Axis.vertical,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Piano keys column
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
              // NotificationListener wraps the ONE horizontal scroll view
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      widget.dawState.isUserScrolling = true;
                    } else if (notification is ScrollEndNotification) {
                      widget.dawState.isUserScrolling = false;
                    } else if (notification is ScrollUpdateNotification &&
                               notification.dragDetails != null &&
                               widget.dawState.isScrubMode &&
                               widget.dawState.isUserScrolling) {
                      double seekTime = (notification.metrics.pixels + 150) /
                          widget.dawState.zoomX;
                      seekTime = seekTime.clamp(0.0, widget.dawState.songDuration);
                      widget.dawState.jumpToTimelinePosition(seekTime);
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: widget.horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: GestureDetector(
                      // --- TAP: NOTE INSPECTOR ---
                      onTapDown: (details) {
                        // Ignore taps if drag tool is active (requires isDragMode in main.dart)
                        if (widget.dawState.isDragMode) return; 

                        for (int i = 0; i < processedNotes.length; i++) {
                          var pNote = processedNotes[i];
                          if (pNote['isDeleted'] == true) continue;
                          
                          double startX = pNote['start_time'] * widget.dawState.zoomX;
                          double endX = (pNote['start_time'] + ((pNote['end_time'] - pNote['start_time']) * (pNote['time_ratio'] ?? 1.0))) * widget.dawState.zoomX;
                          double yY = (maxMidi - pNote['display_midi']) * widget.dawState.zoomY;
                          
                          // Account for visual cents shift so hit box matches what they see
                          double visualY = yY - ((pNote['display_cents'] / 100.0) * widget.dawState.zoomY);
                          Rect hitBox = Rect.fromLTRB(startX, visualY - (widget.dawState.zoomY / 2), endX, visualY + (widget.dawState.zoomY / 2));
                          
                          if (hitBox.contains(details.localPosition)) {
                            NoteInspector.show(context, widget.dawState, i, widget.dawState.rawNotes[i]);
                            break;
                          }
                        }
                      },
                      
                      // --- PAN: DRAG TO TUNE ---
                      onPanStart: (details) {
                        if (!widget.dawState.isDragMode) return;

                        for (int i = 0; i < processedNotes.length; i++) {
                          var pNote = processedNotes[i];
                          if (pNote['isDeleted'] == true) continue;
                          
                          double startX = pNote['start_time'] * widget.dawState.zoomX;
                          double endX = (pNote['start_time'] + ((pNote['end_time'] - pNote['start_time']) * (pNote['time_ratio'] ?? 1.0))) * widget.dawState.zoomX;
                          double yY = (maxMidi - pNote['display_midi']) * widget.dawState.zoomY;
                          double visualY = yY - ((pNote['display_cents'] / 100.0) * widget.dawState.zoomY);
                          
                          Rect hitBox = Rect.fromLTRB(startX, visualY - (widget.dawState.zoomY / 2), endX, visualY + (widget.dawState.zoomY / 2));
                          
                          if (hitBox.contains(details.localPosition)) {
                            widget.dawState.registerUndoSnapshot(); 
                            setState(() {
                              draggingNoteIndex = i;
                              dragStartY = details.localPosition.dy;
                              // Store the base pitch instead of the micro-cents
                              initialActualMidi = (widget.dawState.rawNotes[i]['actual_midi'] ?? 60.0).toDouble();
                            });
                            break;
                          }
                        }
                      },
                      onPanUpdate: (details) {
                        if (!widget.dawState.isDragMode || draggingNoteIndex == null) return;

                        double deltaY = details.localPosition.dy - dragStartY;
                        
                        // 1 zoomY height = exactly 1 MIDI semitone.
                        // Moving UP (negative deltaY) increases pitch.
                        double midiDelta = -(deltaY / widget.dawState.zoomY);

                        widget.dawState.setState(() {
                          // Apply macro shift and clamp it so it doesn't drag off the screen
                          widget.dawState.rawNotes[draggingNoteIndex!]['actual_midi'] = 
                            (initialActualMidi + midiDelta).clamp(minMidi.toDouble(), maxMidi.toDouble());
                        });
                      },
                      onPanEnd: (details) {
                        setState(() { draggingNoteIndex = null; });
                      },
                      onPanCancel: () {
                        setState(() { draggingNoteIndex = null; });
                      },

                      child: CustomPaint(
                        size: Size(timelineWidth, totalHeight),
                        painter: AdvancedPianoRollPainter(
                          notes: processedNotes,
                          zoomX: widget.dawState.zoomX,
                          zoomY: widget.dawState.zoomY,
                          minMidi: minMidi,
                          maxMidi: maxMidi,
                          isXrayMode: widget.dawState.isXrayMode,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Stationary playhead line
        Positioned(
          left: 60 + 150,
          top: 0,
          bottom: 0,
          child: Container(
            width: 2,
            color: Colors.redAccent.withOpacity(0.8),
          ),
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
        canvas.drawLine(
          Offset(0, topY + zoomY),
          Offset(size.width, topY + zoomY),
          Paint()..color = Colors.grey[400]!
        );
      }

      if (i % 12 == 0) {
        TextPainter tp = TextPainter(
          text: TextSpan(
            text: getNoteName(i),
            style: TextStyle(
              color: isBlackKey(i) ? Colors.white : Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.bold
            )
          ),
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

  AdvancedPianoRollPainter({
    required this.notes,
    required this.zoomX,
    required this.zoomY,
    required this.minMidi,
    required this.maxMidi,
    this.isXrayMode = false,
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
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      if (isBlackKey(i)) {
        canvas.drawRect(
          Rect.fromLTWH(0, topY, size.width, zoomY),
          Paint()..color = Colors.white.withOpacity(0.02)
        );
      }
      canvas.drawLine(
        Offset(0, topY),
        Offset(size.width, topY),
        Paint()..color = Colors.white.withOpacity(0.05)
      );
    }

    for (var note in notes) {
      if (note['isDeleted'] == true) continue;

      double startX = note['start_time'] * zoomX;
      double endX = (note['start_time'] + ((note['end_time'] - note['start_time']) * (note['time_ratio'] ?? 1.0))) * zoomX;
      double topY = (maxMidi - note['display_midi']) * zoomY;
      
      // If we have deep XRAY data, use the true average cents. Otherwise, fall back to basic midi mapping.
      int baselineCents = note['xray_cents']?.round() ?? note['display_cents'];
      int totalCents = baselineCents + (note['cents_shift'] ?? 0) as int;
      
      Color noteColor;
      if (totalCents.abs() <= 10) {
        noteColor = Colors.tealAccent;
      } else if (totalCents.abs() <= 25) {
        noteColor = Colors.amberAccent;
      } else {
        noteColor = Colors.redAccent;
      }
      
      if (note['isMuted'] == true) noteColor = Colors.grey.withOpacity(0.3);

      double padding = zoomY * 0.15; 
      Rect noteRect = Rect.fromLTRB(startX, topY + padding, endX, topY + zoomY - padding);
      
      // Draw the block (make it slightly transparent if XRAY is on so lines pop)
     canvas.drawRRect(
        RRect.fromRectAndRadius(noteRect, const Radius.circular(4)), 
        Paint()..color = isXrayMode ? noteColor.withOpacity(0.4) : noteColor
      );

// --- XRAY FORENSIC PITCH RENDERING ---
      if (isXrayMode && note['contour'] != null) {
        List<dynamic> contour = note['contour'];
        if (contour.isNotEmpty) {
          Path contourPath = Path();
          double stepX = (endX - startX) / (contour.length > 1 ? contour.length - 1 : 1);
          
          double shift = (note['cents_shift'] ?? 0).toDouble();
          double vibrato = (note['vibrato_scale'] ?? 1.0).toDouble();

          for (int j = 0; j < contour.length; j++) {
            // APPLY REAL-TIME SCALAR MATH (No backend needed for edits!)
            double rawCents = contour[j].toDouble();
            double manipulatedCents = (rawCents * vibrato) + shift;
            
            double px = startX + (j * stepX);
            // Calculate Y. 100 cents = exactly 1 zoomY height (1 semitone)
            // Center of the block is perfect pitch. 
            double py = topY + (zoomY / 2) - ((manipulatedCents / 100.0) * zoomY);
            
            if (j == 0) contourPath.moveTo(px, py);
            else contourPath.lineTo(px, py);
          }
          
          // Draw the high-contrast pitch line
          canvas.drawPath(
            contourPath, 
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..strokeCap = StrokeCap.round
          );
        }
      }

      // Draw the text label
      if (zoomY > 15) {
        String centsText = totalCents > 0 ? '+$totalCents' : (totalCents == 0 ? '0' : '$totalCents');
        TextSpan span = TextSpan(
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          text: ' ${getNoteName(note['display_midi'])} $centsText',
        );
        
        TextPainter tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
        if (endX - startX > tp.width + 4) {
          tp.paint(canvas, Offset(startX, topY + (zoomY / 2) - (tp.height / 2)));
        }
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}