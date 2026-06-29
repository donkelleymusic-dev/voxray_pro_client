import 'package:flutter/material.dart';
import '../ui/timeline_canvas.dart'; // Reuse the PianoKeysPainter from the DAW!

class LiveScrollingCanvas extends StatefulWidget {
  final List<double?> pitchHistory;
  final int maxFrames;

  const LiveScrollingCanvas({Key? key, required this.pitchHistory, required this.maxFrames}) : super(key: key);

  @override
  State<LiveScrollingCanvas> createState() => _LiveScrollingCanvasState();
}

class _LiveScrollingCanvasState extends State<LiveScrollingCanvas> {
  // Lock the canvas to the same dimensions as your forensic DAW
  final int minMidi = 36;
  final int maxMidi = 84;
  final double zoomY = 24.0;
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void didUpdateWidget(LiveScrollingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Find the most recent valid pitch to keep the view centered
    double? latestPitch;
    for (int i = widget.pitchHistory.length - 1; i >= 0; i--) {
      if (widget.pitchHistory[i] != null) {
        latestPitch = widget.pitchHistory[i];
        break;
      }
    }

    // Auto-scroll to follow the singer's pitch
    if (latestPitch != null && _verticalScrollController.hasClients) {
      double viewportHeight = _verticalScrollController.position.viewportDimension;
      double targetY = ((maxMidi - latestPitch) * zoomY) - (viewportHeight / 2) + (zoomY / 2);
      targetY = targetY.clamp(0.0, _verticalScrollController.position.maxScrollExtent);

      // Using jumpTo instead of animateTo because live audio fires this 20+ times a second.
      // AnimateTo would cause massive stuttering here.
      _verticalScrollController.jumpTo(targetY);
    }
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double totalHeight = (maxMidi - minMidi + 1) * zoomY;

    return SingleChildScrollView(
      controller: _verticalScrollController,
      scrollDirection: Axis.vertical,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Piano Keys on the Left
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
                zoomY: zoomY,
              ),
            ),
          ),
          
          // 2. Scrolling Live Pitch Trace on the Right
          Expanded(
            child: SizedBox(
              height: totalHeight,
              child: CustomPaint(
                size: Size.infinite,
                painter: LivePitchPainter(
                  pitchHistory: widget.pitchHistory,
                  maxFrames: widget.maxFrames,
                  minMidi: minMidi,
                  maxMidi: maxMidi,
                  zoomY: zoomY,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LivePitchPainter extends CustomPainter {
  final List<double?> pitchHistory;
  final int maxFrames;
  final int minMidi;
  final int maxMidi;
  final double zoomY;

  LivePitchPainter({
    required this.pitchHistory,
    required this.maxFrames,
    required this.minMidi,
    required this.maxMidi,
    required this.zoomY,
  });

  bool _isBlackKey(int midi) {
    int note = midi % 12;
    return note == 1 || note == 3 || note == 6 || note == 8 || note == 10;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = Colors.white.withOpacity(0.05)..strokeWidth = 1.0;
    final blackKeyBgPaint = Paint()..color = Colors.white.withOpacity(0.02);

    // Draw horizontal grid lines and black key shading
    for (int i = maxMidi; i >= minMidi; i--) {
      double topY = (maxMidi - i) * zoomY;
      if (_isBlackKey(i)) {
        canvas.drawRect(Rect.fromLTWH(0, topY, size.width, zoomY), blackKeyBgPaint);
      }
      canvas.drawLine(Offset(0, topY), Offset(size.width, topY), gridPaint);
    }

    // Draw the actual pitch trace
    final tracePaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool isFirstPoint = true;
    double stepX = size.width / maxFrames;

    for (int i = 0; i < pitchHistory.length; i++) {
      if (pitchHistory[i] != null) {
        double x = i * stepX;
        
        // Map the float midi value precisely to the Y coordinate
        // Add zoomY / 2 to center the line exactly in the middle of the corresponding key
        double y = (maxMidi - pitchHistory[i]!) * zoomY + (zoomY / 2);

        if (isFirstPoint) {
          path.moveTo(x, y);
          isFirstPoint = false;
        } else {
          path.lineTo(x, y);
        }
      } else {
        isFirstPoint = true; // Break the line if pitch tracking drops (breaths/silence)
      }
    }
    canvas.drawPath(path, tracePaint);
  }

  @override
  bool shouldRepaint(covariant LivePitchPainter oldDelegate) => true;
}