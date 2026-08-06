import 'package:flutter/material.dart';
import '../main.dart';
import 'dart:math' as math;

class TimelineRulerWidget extends StatelessWidget {
  final VoxrayDAWState dawState;
  const TimelineRulerWidget({Key? key, required this.dawState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Force the ruler to be AT LEAST the width of the screen so short songs don't clip
    double screenWidth = MediaQuery.of(context).size.width;
    double songWidth = dawState.songDuration * dawState.zoomX;
    double totalRulerWidth = math.max(screenWidth, songWidth);

    return SizedBox(
      width: totalRulerWidth,
      height: 45,
      child: GestureDetector(
        onTapDown: (details) {
          double clickedSeconds = details.localPosition.dx / dawState.zoomX;
          dawState.jumpToTimelinePosition(clickedSeconds.clamp(0.0, dawState.songDuration));
        },
        // NEW: Allows smooth dragging/scrubbing across the ruler!
        onPanUpdate: (details) {
          // ✅ Removed the per-frame delta check! 
          // Slow scrubbing will now work perfectly.
          double draggedSeconds = details.localPosition.dx / dawState.zoomX;
          dawState.jumpToTimelinePosition(draggedSeconds.clamp(0.0, dawState.songDuration));
        },
        child: Stack(
          children: [
            if (dawState.isLoopModeActive)
              Positioned(
                left: dawState.loopStartBoundary * dawState.zoomX,
                width: (dawState.loopEndBoundary - dawState.loopStartBoundary) * dawState.zoomX,
                top: 0,
                bottom: 0,
                child: Container(color: Colors.blueAccent.withOpacity(0.15)),
              ),

            CustomPaint(
              size: Size(totalRulerWidth, 45),
              painter: RulerGridPainter(
                zoomX: dawState.zoomX,
                duration: dawState.songDuration,
                barLines: dawState.barLines, // 🟢 Pass state down to main
                tempoMap: dawState.tempoMap, // 🟢 Pass state down to main
              ),
            ),

            ...dawState.markers.map((marker) {
              return Positioned(
                left: (marker['time'] as double) * dawState.zoomX - 8,
                top: 4,
                child: GestureDetector(
                  onTap: () => dawState.jumpToTimelinePosition(marker['time']),
                  onLongPress: () => dawState.deleteMarker(marker['id']),
                  child: Tooltip(
                    message: marker['label'],
                    triggerMode: TooltipTriggerMode.tap,
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
  
  final List<double> barLines;
  final List<Map<String, dynamic>> tempoMap;
  
  RulerGridPainter({
    required this.zoomX, 
    required this.duration,
    this.barLines = const [],
    this.tempoMap = const [],
  });

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
    // =========================================================================
    // 🟢 OVERLAY MUSICAL BAR & TEMPO MARKERS ON RULER
    // =========================================================================
    if (barLines.isNotEmpty) {
      final markerPaint = Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 1.5;

      for (int i = 0; i < barLines.length; i++) {
        double barTime = barLines[i];
        double x = barTime * zoomX;

        // Ensure we only draw text inside the actual track width boundaries
        if (x >= 0 && x <= size.width) {
          // Draw vertical notch on ruler
          canvas.drawLine(Offset(x, size.height - 12), Offset(x, size.height), markerPaint);

          // Find matching tempo map
          var matchingMap = tempoMap.firstWhere(
            (m) => ((m['time'] as num?)?.toDouble() ?? -1.0) == barTime,
            orElse: () => <String, dynamic>{},
          );

          int timeSig = (matchingMap['time_sig'] as num?)?.toInt() ?? 4;
          double bpm = (matchingMap['bpm'] as num?)?.toDouble() ?? 120.0;

          // Draw Bar Number & Meter Label
          String label = 'B${i + 1} [$timeSig/8] ${bpm.toStringAsFixed(1)}';
          TextPainter tp = TextPainter(
            text: TextSpan(
              text: label, 
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold)
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x + 3, size.height - 22));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant RulerGridPainter oldDelegate) =>
      oldDelegate.zoomX != zoomX || 
      oldDelegate.duration != duration ||
      oldDelegate.barLines != barLines || // 🟢 Trigger redraw on new math
      oldDelegate.tempoMap != tempoMap;
}
