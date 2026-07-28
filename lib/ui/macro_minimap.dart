import 'package:flutter/material.dart';
import '../main.dart';

class MacroMinimapWidget extends StatelessWidget {
  final VoxrayDAWState dawState;

  const MacroMinimapWidget({Key? key, required this.dawState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dawState.horizontalScrollController,
      builder: (context, child) {
        double visibleStart = 0.0;
        double visibleDuration = dawState.songDuration;

        if (dawState.horizontalScrollController.hasClients) {
          double offset = dawState.horizontalScrollController.offset;
          double viewport = dawState.horizontalScrollController.position.viewportDimension;
          
          visibleStart = offset / dawState.zoomX;
          visibleDuration = viewport / dawState.zoomX;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => _handleInteraction(details.localPosition, context),
          onTapDown: (details) => _handleInteraction(details.localPosition, context),
          child: RepaintBoundary(
            child: CustomPaint(
              size: const Size(double.infinity, 24), 
              painter: _MinimapPainter(
                dawState: dawState,
                visibleStart: visibleStart,
                visibleDuration: visibleDuration,
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleInteraction(Offset localPosition, BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final width = renderBox.size.width;
    double dx = localPosition.dx.clamp(0.0, width);
    double targetTime = (dx / width) * dawState.songDuration;
    dawState.jumpToTimelinePosition(targetTime);
  }
}

class _MinimapPainter extends CustomPainter {
  final VoxrayDAWState dawState;
  final double visibleStart;
  final double visibleDuration;

  _MinimapPainter({
    required this.dawState,
    required this.visibleStart,
    required this.visibleDuration,
  });

  // Assign high-contrast, vibrant neon spectrum colors
  Color _getStemColor(String key) {
    if (['vocals', 'vocals2'].contains(key)) return const Color(0xFF00FFCC); // Electric Cyan / Mint (Dominant)
    if (['guitar', 'acoustic'].contains(key)) return const Color(0xFFFFB703); // Warm Amber Gold
    if (['drums', 'kick', 'snare', 'hihat', 'toms', 'cymbals'].contains(key)) return const Color(0xFFFF0055); // Hot Neon Pink / Red
    if (['piano', 'keys', 'synth'].contains(key)) return const Color(0xFF9D4EDD); // Vivid Purple
    if (['bass', 'contrabass', '808'].contains(key)) return const Color(0xFF3A86FF); // Electric Blue
    return const Color(0xFF38B000); // Vibrant Emerald Green for Orchestral / Other
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Clean, dark studio background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF07070B),
    );

    if (dawState.songDuration <= 0) return;

    // Sort generated stems so that vocals ALWAYS render last (on top of everything else)
    List<String> sortedStems = dawState.generatedStems.toList();
    sortedStems.sort((a, b) {
      bool isVocalsA = ['vocals', 'vocals2'].contains(a);
      bool isVocalsB = ['vocals', 'vocals2'].contains(b);
      if (isVocalsA) return 1;  // Push vocals to the end of the list (drawn last/on top)
      if (isVocalsB) return -1;
      return 0;
    });

    // 2. Draw each track as a vibrant, stacked heat layer
    for (String stem in sortedStems) {
      final state = dawState.getChannelState(stem);
      if (state.rmsEnvelope.isEmpty || state.isMuted) continue;

      final Color baseColor = _getStemColor(stem);
      bool isVocals = ['vocals', 'vocals2'].contains(stem);

      // Vocals get full opacity and a dominant pop; background instruments get balanced saturation
      double opacity = isVocals ? 0.95 : 0.70;

      final Paint wavePaint = Paint()
        ..color = baseColor.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      final Path wavePath = Path();
      wavePath.moveTo(0, size.height);

      int points = state.rmsEnvelope.length;
      for (int i = 0; i < points; i++) {
        double x = (i / (points - 1)) * size.width;
        
        double rawVal = state.rmsEnvelope[i];
        // Floor lift: ensures even quiet parts don't completely vanish into the dark background
        double boostedVal = (rawVal * 1.3 + 0.15).clamp(0.0, 1.0);
        
        double y = size.height - (boostedVal * size.height);
        wavePath.lineTo(x, y);
      }
      wavePath.lineTo(size.width, size.height);
      wavePath.close();

      canvas.drawPath(wavePath, wavePaint);
    }

    // 3. Dim the areas outside the current viewbox
    double startX = (visibleStart / dawState.songDuration) * size.width;
    double boxWidth = (visibleDuration / dawState.songDuration) * size.width;

    final Paint dimPaint = Paint()..color = Colors.black.withOpacity(0.55);
    canvas.drawRect(Rect.fromLTWH(0, 0, startX, size.height), dimPaint);
    canvas.drawRect(Rect.fromLTWH(startX + boxWidth, 0, size.width - (startX + boxWidth), size.height), dimPaint);

    // 4. Clean View-Box Frame
    final Paint framePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(Rect.fromLTWH(startX, 0, boxWidth, size.height), framePaint);

    // 5. Playhead indicator (Bright Yellow Line)
    double playheadX = (dawState.currentPosition / dawState.songDuration) * size.width;
    final Paint playheadPaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 1.8;
    canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    // Returning true guarantees the minimap instantly refreshes 
    // when projects load, zoom changes, or tracks are added/deleted.
    return true; 
  }
}
