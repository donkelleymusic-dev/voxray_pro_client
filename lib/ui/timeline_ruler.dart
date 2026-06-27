import 'package:flutter/material.dart';
import '../main.dart';

class TimelineRulerWidget extends StatelessWidget {
  final VoxrayDAWState dawState;
  const TimelineRulerWidget({Key? key, required this.dawState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double totalRulerWidth = dawState.songDuration * dawState.zoomX;

    return GestureDetector(
      onTapDown: (details) {
        double clickedSeconds = details.localPosition.dx / dawState.zoomX;
        dawState.jumpToTimelinePosition(clickedSeconds);
      },
      child: Container(
        height: 45, width: totalRulerWidth,
        decoration: BoxDecoration(color: Colors.grey[900], border: const Border(bottom: BorderSide(color: Colors.white12))),
        child: Stack(
          children: [
            if (dawState.isLoopModeActive)
              Positioned(
                left: dawState.loopStartBoundary * dawState.zoomX,
                width: (dawState.loopEndBoundary - dawState.loopStartBoundary) * dawState.zoomX,
                top: 0, bottom: 0,
                child: Container(color: Colors.blueAccent.withOpacity(0.15)),
              ),
            CustomPaint(
              size: Size(totalRulerWidth, 45),
              painter: RulerGridPainter(zoomX: dawState.zoomX, duration: dawState.songDuration),
            ),
            ...dawState.markers.map((marker) {
              return Positioned(
                left: (marker['time'] as double) * dawState.zoomX - 8, top: 4,
                child: GestureDetector(
                  onTap: () => dawState.jumpToTimelinePosition(marker['time']),
                  child: Tooltip(message: marker['label'], child: const Icon(Icons.location_on, color: Colors.amberAccent, size: 18)),
                ),
              );
            }).toList(),
            Positioned(
              right: 10, top: 10,
              child: Row(
                children: [
                  const Icon(Icons.repeat, size: 16, color: Colors.blueAccent),
                  Switch(
                    value: dawState.isLoopModeActive, 
                    onChanged: (val) => dawState.setState(() => dawState.isLoopModeActive = val),
                  ),
                  IconButton(icon: const Icon(Icons.add_location_alt, size: 18), onPressed: dawState.addMarkerAtCurrentPlayhead),
                ],
              )
            )
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
    
    for (int idx = 0; idx <= duration; idx++) {
      double xCoord = idx * zoomX;
      double tickHeight = (idx % 5 == 0) ? 18.0 : 8.0;
      canvas.drawLine(Offset(xCoord, size.height - tickHeight), Offset(xCoord, size.height), paint);
      
      if (idx % 5 == 0) {
        final textPainter = TextPainter(text: TextSpan(text: "${idx}s", style: textStyle), textDirection: TextDirection.ltr)..layout();
        textPainter.paint(canvas, Offset(xCoord + 4, size.height - 35));
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}