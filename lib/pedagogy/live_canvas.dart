import 'package:flutter/material.dart';

class LiveScrollingCanvas extends StatelessWidget {
  final List<double?> pitchHistory;
  final int maxFrames;

  const LiveScrollingCanvas({Key? key, required this.pitchHistory, required this.maxFrames}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.infinite, painter: LivePitchPainter(pitchHistory: pitchHistory, maxFrames: maxFrames));
  }
}

class LivePitchPainter extends CustomPainter {
  final List<double?> pitchHistory;
  final int maxFrames;

  LivePitchPainter({required this.pitchHistory, required this.maxFrames});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.white10..strokeWidth = 1.0;
    final centerPitchPaint = Paint()..color = Colors.white24..strokeWidth = 1.5;
    
    double centerMidi = 60.0;
    for (int i = pitchHistory.length - 1; i >= 0; i--) {
      if (pitchHistory[i] != null) { centerMidi = pitchHistory[i]!.roundToDouble(); break; }
    }

    for (int offset = -3; offset <= 3; offset++) {
      double gridY = size.height / 2 - (offset * 40.0);
      canvas.drawLine(Offset(0, gridY), Offset(size.width, gridY), offset == 0 ? centerPitchPaint : bgPaint);
    }

    final tracePaint = Paint()..color = Colors.amberAccent..strokeWidth = 3.0..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final path = Path();
    bool isFirstPoint = true;
    double stepX = size.width / maxFrames; 

    for (int i = 0; i < pitchHistory.length; i++) {
      if (pitchHistory[i] != null) {
        double x = i * stepX;
        double deviation = pitchHistory[i]! - centerMidi;
        double y = (size.height / 2) - (deviation * 40.0);

        if (isFirstPoint) { path.moveTo(x, y); isFirstPoint = false; } 
        else { path.lineTo(x, y); }
      } else {
        isFirstPoint = true;
      }
    }
    canvas.drawPath(path, tracePaint);
  }
  @override bool shouldRepaint(covariant LivePitchPainter oldDelegate) => true;
}