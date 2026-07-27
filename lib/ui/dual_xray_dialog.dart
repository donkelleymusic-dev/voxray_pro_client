// lib/ui/dual_xray_dialog.dart
import 'package:flutter/material.dart';
import '../models/audio_channel.dart';

class DualXRayComparatorDialog extends StatefulWidget {
  final List<AudioChannel> availableChannels;
  final Function(AudioChannel source, AudioChannel target) onRunComparison;

  const DualXRayComparatorDialog({
    Key? key,
    required this.availableChannels,
    required this.onRunComparison,
  }) : super(key: key);

  @override
  _DualXRayComparatorDialogState createState() => _DualXRayComparatorDialogState();
}

class _DualXRayComparatorDialogState extends State<DualXRayComparatorDialog> {
  AudioChannel? sourceTrack;
  AudioChannel? targetTrack;

  @override
  void initState() {
    super.initState();
    if (widget.availableChannels.length >= 2) {
      sourceTrack = widget.availableChannels[0];
      targetTrack = widget.availableChannels[1];
    } else if (widget.availableChannels.isNotEmpty) {
      sourceTrack = widget.availableChannels[0];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text('Compare Stems', style: TextStyle(color: Colors.white)),
      content: widget.availableChannels.length < 2
          ? const Text('You need at least two tracks in your workspace.', style: TextStyle(color: Colors.white70))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Source Track:', style: TextStyle(color: Colors.amberAccent)),
                DropdownButton<AudioChannel>(
                  isExpanded: true,
                  dropdownColor: Colors.grey[850],
                  value: sourceTrack,
                  items: widget.availableChannels.map((c) {
                    return DropdownMenuItem(value: c, child: Text(c.name, style: const TextStyle(color: Colors.white)));
                  }).toList(),
                  onChanged: (val) => setState(() => sourceTrack = val),
                ),
                const SizedBox(height: 16),
                const Text('Target Track:', style: TextStyle(color: Colors.pinkAccent)),
                DropdownButton<AudioChannel>(
                  isExpanded: true,
                  dropdownColor: Colors.grey[850],
                  value: targetTrack,
                  items: widget.availableChannels.map((c) {
                    return DropdownMenuItem(value: c, child: Text(c.name, style: const TextStyle(color: Colors.white)));
                  }).toList(),
                  onChanged: (val) => setState(() => targetTrack = val),
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
          onPressed: (sourceTrack != null && targetTrack != null && sourceTrack!.id != targetTrack!.id)
              ? () {
                  Navigator.pop(context);
                  widget.onRunComparison(sourceTrack!, targetTrack!);
                }
              : null,
          child: const Text('Compare Contours', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
