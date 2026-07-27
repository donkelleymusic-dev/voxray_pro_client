import 'package:flutter/material.dart';
import 'dart:math' as math;

class BouncingEqIndicator extends StatefulWidget {
  final Color color;
  final double height;

  const BouncingEqIndicator({
    Key? key,
    this.color = Colors.amberAccent,
    this.height = 12.0,
  }) : super(key: key);

  @override
  State<BouncingEqIndicator> createState() => _BouncingEqIndicatorState();
}

class _BouncingEqIndicatorState extends State<BouncingEqIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (index) {
            // Offset phase for each bar so they bounce out of sync
            double value = (math.sin((_controller.value * math.pi) + (index * 1.2)) + 1) / 2;
            double barHeight = math.max(3.0, value * widget.height);

            return Container(
              width: 2.5,
              height: barHeight,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.0),
              ),
            );
          }),
        );
      },
    );
  }
}
