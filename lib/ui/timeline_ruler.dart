import 'package:flutter/material.dart';
import '../main.dart';

class TimelineRulerWidget extends StatelessWidget {
  final VoxrayDAWState dawState;
  const TimelineRulerWidget({Key? key, required this.dawState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double totalRulerWidth = dawState.songDuration * dawState.zoomX;

    return SizedBox(
      width: totalRulerWidth,  // explicit width — no infinite constraint
      height: 45,
      child: GestureDetector(
        onTapDown: (details) {
          double clickedSeconds = details.localPosition.dx / dawState.zoomX;
          dawState.jumpToTimelinePosition(clickedSeconds);
        },
        child: Stack(
          children: [
            // Loop region highlight
            if (dawState.isLoopModeActive)
              Positioned(
                left: dawState.loopStartBoundary * dawState.zoomX,
                width: (dawState.loopEndBoundary - dawState.loopStartBoundary) * dawState.zoomX,
                top: 0,
                bottom: 0,
                child: Container(color: Colors.blueAccent.withOpacity(0.15)),
              ),

            // Ruler tick marks and time labels
            CustomPaint(
              size: Size(totalRulerWidth, 45),
              painter: RulerGridPainter(
                zoomX: dawState.zoomX,
                duration: dawState.songDuration,
              ),
            ),

            // Marker pins (scroll with content)
            // long press to delete:
            ...dawState.markers.map((marker) {
              return Positioned(
                left: (marker['time'] as double) * dawState.zoomX - 8,
                top: 4,
                child: GestureDetector(
                  onTap: () => dawState.jumpToTimelinePosition(marker['time']),
                  onLongPress: () {
                    // Long press to delete
                    dawState.deleteMarker(marker['id']);
                  },
                  child: Tooltip(
                    message: marker['label'],  // just the label, no "long press to delete"
                    triggerMode: TooltipTriggerMode.tap,  // only show on tap, not long press
                    child: const Icon(Icons.location_on, color: Colors.amberAccent, size: 18),
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

class RulerGridPainter extends CustomPainter {
  final double zoomX;
  final double duration;
  RulerGridPainter({required this.zoomX, required this.duration});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white30..strokeWidth = 1.0;
    final textStyle = TextStyle(color: Colors.grey[400], fontSize: 10);

    // Decide tick interval based on zoom level
    double tickInterval = 1.0; // seconds between ticks
    if (zoomX < 80) tickInterval = 5.0;
    if (zoomX < 30) tickInterval = 10.0;

    double t = 0;
    while (t <= duration) {
      double xCoord = t * zoomX;
      bool isMajor = (t % (tickInterval * 5) < 0.001);
      double tickHeight = isMajor ? 18.0 : 8.0;

      canvas.drawLine(
        Offset(xCoord, size.height - tickHeight),
        Offset(xCoord, size.height),
        paint,
      );

      if (isMajor || tickInterval >= 5.0) {
        // Format as mm:ss
        int totalSeconds = t.round();
        int minutes = totalSeconds ~/ 60;
        int seconds = totalSeconds % 60;
        String label = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

        final textPainter = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(xCoord + 4, size.height - 35));
      }

      t += tickInterval;
    }
  }

  @override
  bool shouldRepaint(covariant RulerGridPainter oldDelegate) =>
      oldDelegate.zoomX != zoomX || oldDelegate.duration != duration;
}