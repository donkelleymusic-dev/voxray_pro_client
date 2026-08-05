import 'package:flutter/material.dart';
import 'voxray_help_topics.dart';

class HelpTopic {
  final String title;
  final String whatItIs;
  final String onTapAction;
  final String relatedFeatures;

  const HelpTopic({
    required this.title,
    required this.whatItIs,
    required this.onTapAction,
    required this.relatedFeatures,
  });
}

class VoxrayHelpTarget extends StatelessWidget {
  final HelpTopic topic;
  final bool isHelpModeActive;
  final Widget child;

  const VoxrayHelpTarget({
    Key? key,
    required this.topic,
    required this.isHelpModeActive,
    required this.child,
  }) : super(key: key);

  void _showHelpModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_center_outlined, color: Colors.amberAccent, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    topic.title.toUpperCase(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(ctx),
                )
              ],
            ),
            const Divider(color: Colors.white24, height: 20),
            _infoSection('WHAT IT SHOWS / DOES', topic.whatItIs, Colors.tealAccent),
            const SizedBox(height: 12),
            _infoSection('TAP ACTION', topic.onTapAction, Colors.amberAccent),
            const SizedBox(height: 12),
            _infoSection('RELATED UI & STATE', topic.relatedFeatures, Colors.lightBlueAccent),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _infoSection(String label, String body, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isHelpModeActive) return child;

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Material(
            color: Colors.amberAccent.withOpacity(0.12),
            child: InkWell(
              highlightColor: Colors.amberAccent.withOpacity(0.25),
              splashColor: Colors.amberAccent.withOpacity(0.4),
              onTap: () => _showHelpModal(context),
            ),
          ),
        ),
      ],
    );
  }
}
