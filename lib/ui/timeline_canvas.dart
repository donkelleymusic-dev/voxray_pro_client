import 'package:flutter/material.dart';
import '../main.dart';
import 'note_inspector.dart';

class TimelineCanvasWidget extends StatefulWidget {
  final VoxrayDAWState dawState;
  const TimelineCanvasWidget({Key? key, required this.dawState}) : super(key: key);
  @override
  State<TimelineCanvasWidget> createState() => _TimelineCanvasWidgetState();
}

class _TimelineCanvasWidgetState extends State<TimelineCanvasWidget> {
  // Define the visible MIDI range (e.g., C2 to C6)
  final int minMidi = 36;
  final int maxMidi = 84;

  @override
  Widget build(BuildContext context) {
    // Total height changes dynamically based on the Zoom Y slider
    double duration = (widget.dawState.songDuration > 0) ? widget.dawState.songDuration : 30.0;
    double zoomX = (widget.dawState.zoomX > 0) ? widget.dawState.zoomX : 100.0;
    double zoomY = (widget.dawState.zoomY > 0) ? widget.dawState.zoomY : 20.0;

    double totalHeight = (maxMidi - minMidi + 1) * zoomY;
    double timelineWidth = duration * zoomX;
    //double totalHeight = (maxMidi - minMidi + 1) * widget.dawState.zoomY;
    //double timelineWidth = widget.dawState.songDuration * widget.dawState.zoomX;
    
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

    // The Master Vertical Scroller keeps the Keys and Grid in sync
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          // 1. STICKY LEFT COLUMN: Piano Keys
          Container(
            width: 60,
            height: totalHeight,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Colors.black, width: 2))
            ),
            child: CustomPaint(
              painter: PianoKeysPainter(minMidi: minMidi, maxMidi: maxMidi, zoomY: widget.dawState.zoomY),
            ),
          ),

          // 2. SCROLLABLE RIGHT COLUMN: The Main Grid
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                onTapDown: (details) {
                  for (int i = 0; i < processedNotes.length; i++) {
                    var pNote = processedNotes[i];
                    if (pNote['isDeleted'] == true) continue;
                    
                    double startX = pNote['start_time'] * widget.dawState.zoomX;
                    double endX = (pNote['start_time'] + ((pNote['end_time'] - pNote['start_time']) * (pNote['time_ratio'] ?? 1.0))) * widget.dawState.zoomX;
                    
                    // Y calculation using Zoom Y instead of screen percentage
                    double yY = (maxMidi - pNote['display_midi']) * widget.dawState.zoomY;
                    
                    // Hitbox vertically centered on the line
                    Rect hitBox = Rect.fromLTRB(startX, yY - (widget.dawState.zoomY / 2), endX, yY + (widget.dawState.zoomY / 2));
                    
                    if (hitBox.contains(details.localPosition)) {
                      NoteInspector.show(context, widget.dawState, i, widget.dawState.rawNotes[i]);
                      break;
                    }
                  }
                },
                child: CustomPaint(
                  size: Size(timelineWidth, totalHeight),
                  painter: AdvancedPianoRollPainter(
                    notes: processedNotes, 
                    zoomX: widget.dawState.zoomX, 
                    zoomY: widget.dawState.zoomY,
                    minMidi: minMidi,
                    maxMidi: maxMidi
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// NEW: Piano Keys Painter
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
      
      // Draw Key Background
      Paint keyPaint = Paint()..color = isBlackKey(i) ? Colors.black87 : Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), keyPaint);
      
      // Draw subtle separator lines between white keys
      if (!isBlackKey(i)) {
        canvas.drawLine(Offset(0, topY + zoomY), Offset(size.width, topY + zoomY), Paint()..color = Colors.grey[400]!);
      }

      // Label C notes
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
// UPDATED: Grid Lines & Dynamic Color Note Painter
// -------------------------------------------------------------
class AdvancedPianoRollPainter extends CustomPainter {
  final List<Map<String, dynamic>> notes;
  final double zoomX;
  final double zoomY;
  final int minMidi;
  final int maxMidi;

  AdvancedPianoRollPainter({required this.notes, required this.zoomX, required this.zoomY, required this.minMidi, required this.maxMidi});

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
    // 1. DRAW BACKGROUND HORIZONTAL GRID LINES
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      // Draw a darker background for black key rows to help guide the eye
      if (isBlackKey(i)) {
        canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), Paint()..color = Colors.white.withOpacity(0.02));
      }
      canvas.drawLine(Offset(0, topY), Offset(size.width, topY), Paint()..color = Colors.white.withOpacity(0.05));
    }

    // 2. DRAW NOTES
    for (var note in notes) {
      if (note['isDeleted'] == true) continue;

      double startX = note['start_time'] * zoomX;
      double endX = (note['start_time'] + ((note['end_time'] - note['start_time']) * (note['time_ratio'] ?? 1.0))) * zoomX;
      
      // Calculate Y based on ZoomY to perfectly match the grid lines
      double topY = (maxMidi - note['display_midi']) * zoomY;
      
      // Dynamic Color Coding based on Cents variance
      int cents = note['display_cents'];
      Color noteColor;
      if (cents.abs() <= 10) {
        noteColor = Colors.tealAccent; // Perfect tune
      } else if (cents.abs() <= 25) {
        noteColor = Colors.amberAccent; // Slightly off
      } else {
        noteColor = Colors.redAccent; // Needs correction
      }
      
      if (note['isMuted'] == true) noteColor = Colors.grey.withOpacity(0.3);

      // Draw the block, scaling its thickness based on ZoomY (with some padding)
      double padding = zoomY * 0.15; 
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(startX, topY + padding, endX, topY + zoomY - padding), const Radius.circular(4)), 
        Paint()..color = noteColor
      );

      // Draw text (Cents + Note Name)
      if (zoomY > 15) { // Only draw text if we are zoomed in enough to see it
        String centsText = cents > 0 ? '+$cents' : '-$cents';
        if (cents == 0) centsText = '0'; 
        
        TextSpan span = TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold),
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