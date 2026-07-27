import 'package:flutter/material.dart';

class OptimizeMixDialog extends StatefulWidget {
  final Function(bool hasVocals, bool hasGuitar) onConfirm;

  const OptimizeMixDialog({Key? key, required this.onConfirm}) : super(key: key);

  @override
  State<OptimizeMixDialog> createState() => _OptimizeMixDialogState();
}

class _OptimizeMixDialogState extends State<OptimizeMixDialog> {
  // Default to true so casual users don't accidentally skip stems
  bool hasVocals = true;
  bool hasGuitar = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: const BorderSide(color: Colors.white12),
      ),
      title: const Row(
        children: [
          Icon(Icons.bolt, color: Colors.amberAccent),
          SizedBox(width: 8),
          Text(
            "OPTIMIZE EXTRACTION",
            style: TextStyle(
              color: Colors.white, 
              fontSize: 15, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 1.2
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Save GPU time by unchecking instruments you know are missing from this track.",
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),

          // Vocals Toggle
          Container(
            decoration: BoxDecoration(
              color: hasVocals ? Colors.tealAccent.withOpacity(0.05) : Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hasVocals ? Colors.tealAccent.withOpacity(0.5) : Colors.white10),
            ),
            child: CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              title: const Text("Contains Vocals", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: const Text("Singing, speech, or choir.", style: TextStyle(color: Colors.white54, fontSize: 11)),
              value: hasVocals,
              activeColor: Colors.tealAccent,
              checkColor: Colors.black,
              onChanged: (val) => setState(() => hasVocals = val ?? true),
            ),
          ),
          const SizedBox(height: 12),

          // Guitar Toggle
          Container(
            decoration: BoxDecoration(
              color: hasGuitar ? Colors.amberAccent.withOpacity(0.05) : Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hasGuitar ? Colors.amberAccent.withOpacity(0.5) : Colors.white10),
            ),
            child: CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              title: const Text("Contains Guitar", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: const Text("Acoustic or electric guitars.", style: TextStyle(color: Colors.white54, fontSize: 11)),
              value: hasGuitar,
              activeColor: Colors.amberAccent,
              checkColor: Colors.black,
              onChanged: (val) => setState(() => hasGuitar = val ?? true),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.only(right: 16, bottom: 16, top: 8),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.tealAccent,
            foregroundColor: Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () {
            Navigator.pop(context);
            widget.onConfirm(hasVocals, hasGuitar);
          },
          child: const Text("START PROCESSING", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
        ),
      ],
    );
  }
}
