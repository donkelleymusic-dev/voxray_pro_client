import 'package:flutter/material.dart';
import '../main.dart';

class MacroMinimapWidget extends StatelessWidget {
  final VoxrayDAWState dawState;

  const MacroMinimapWidget({Key? key, required this.dawState}) : super(key: key);

  Color _getStemColor(String key) {
    if (['vocals', 'vocals2'].contains(key)) return Colors.tealAccent; // Cyan / Teal
    if (['guitar', 'acoustic'].contains(key)) return Colors.amberAccent; // Gold / Amber
    if (['drums', 'kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(key)) return Colors.redAccent; // Crimson
    if (['piano', 'keys', 'synth'].contains(key)) return Colors.purpleAccent; // Neon Purple
    if (['bass', 'contrabass', '808'].contains(key)) return Colors.blueAccent; // Deep Blue
    return Colors.greenAccent; // Emerald Green for Orchestral / Other
  }

  @override
  Widget build(BuildContext context) {
    // We use an AnimatedBuilder attached to the scroll controller so the view-box 
    // slides smoothly as the user scrolls the main timeline.
    return AnimatedBuilder(
      animation: dawState.horizontalScrollController,
      builder: (context, child) {
        double visibleStart = 0.0;
        double visibleDuration = dawState.songDuration;

        // Calculate the view-box boundaries based on the main scroll position
        if (dawState.horizontalScrollController.hasClients) {
          double offset = dawState.horizontalScrollController.offset;
          double viewport = dawState.horizontalScrollController.position.viewportDimension;
          
          visibleStart = offset / dawState.zoomX;
          visibleDuration = viewport / dawState.zoomX;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Dragging or tapping instantly calculates the time and jumps the DAW
          onPanUpdate: (details) => _handleInteraction(details.localPosition, context),
          onTapDown: (details) => _handleInteraction(details.localPosition, context),
          child: CustomPaint(
            size: const Size(double.infinity, 40), // Sleek 40px height
            painter: _MinimapPainter(
              dawState: dawState,
              visibleStart: visibleStart,
              visibleDuration: visibleDuration,
              colorMapper: _getStemColor,
            ),
          ),
        );
      },
    );
  }

  void _handleInteraction(Offset localPosition, BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final width = renderBox.size.width;
    
    // Clamp the interaction within bounds
    double dx = localPosition.dx.clamp(0.0, width);
    
    // Convert X pixel to Song Time
    double targetTime = (dx / width) * dawState.songDuration;
    
    // Jump the DAW! (This seeks audio AND scrolls the timeline)
    dawState.jumpToTimelinePosition(targetTime);
  }
}

class _MinimapPainter extends CustomPainter {
  final VoxrayDAWState dawState;
  final double visibleStart;
  final double visibleDuration;
  final Color Function(String) colorMapper;

  _MinimapPainter({
    required this.dawState,
    required this.visibleStart,
    required this.visibleDuration,
    required this.colorMapper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw the background track
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black45,
    );

    if (dawState.songDuration <= 0) return;

    // 2. Draw the RMS waveforms stacked with transparency
    for (String stem in dawState.generatedStems) {
      final state = dawState.getChannelState(stem);
      if (state.rmsEnvelope.isEmpty || state.isMuted) continue;

      final Color stemColor = colorMapper(stem);
      final Paint wavePaint = Paint()
        ..color = stemColor.withOpacity(0.4) // Semi-transparent overlap
        ..style = PaintingStyle.fill;

      final Path wavePath = Path();
      wavePath.moveTo(0, size.height);

      int points = state.rmsEnvelope.length;
      for (int i = 0; i < points; i++) {
        double x = (i / (points - 1)) * size.width;
        // Scale envelope to height (assuming envelope values max around 1.0)
        double y = size.height - (state.rmsEnvelope[i] * size.height).clamp(0.0, size.height);
        wavePath.lineTo(x, y);
      }
      wavePath.lineTo(size.width, size.height);
      wavePath.close();

      canvas.drawPath(wavePath, wavePaint);
    }

    // 3. Draw the View-Box (The bright semi-transparent window)
    double startX = (visibleStart / dawState.songDuration) * size.width;
    double boxWidth = (visibleDuration / dawState.songDuration) * size.width;

    // Dim the areas OUTSIDE the view-box to make the view-box pop
    final Paint dimPaint = Paint()..color = Colors.black.withOpacity(0.6);
    canvas.drawRect(Rect.fromLTWH(0, 0, startX, size.height), dimPaint);
    canvas.drawRect(Rect.fromLTWH(startX + boxWidth, 0, size.width - (startX + boxWidth), size.height), dimPaint);

    // Frame the view-box with a sleek white border
    final Paint framePaint = Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(Rect.fromLTWH(startX, 0, boxWidth, size.height), framePaint);

    // 4. Draw the Playhead (Current Position)
    double playheadX = (dawState.currentPosition / dawState.songDuration) * size.width;
    final Paint playheadPaint = Paint()
      ..color = Colors.tealAccent
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.dawState.currentPosition != dawState.currentPosition ||
           oldDelegate.visibleStart != visibleStart ||
           oldDelegate.dawState.generatedStems.length != dawState.generatedStems.length;
  }
}
