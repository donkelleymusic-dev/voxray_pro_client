import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../main.dart';

class PerformanceScorecardDialog extends StatelessWidget {
  final VoxrayDAWState dawState;

  const PerformanceScorecardDialog({
    Key? key,
    required this.dawState,
  }) : super(key: key);

  String _midiToNoteName(num midi) {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    int m = midi.round();
    return '${noteNames[m % 12]}${(m ~/ 12) - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final notes = dawState.rawNotes;
    
    // Filter active (non-deleted) playable notes
    final activeNotes = notes.where((n) {
      if (n['isDeleted'] == true) return false;
      if (n['type'] == 'xray_line') return false;
      double baseMidi = (n['actual_midi'] ?? 60.0).toDouble() + (n['semitone_shift'] ?? 0);
      return baseMidi.round() != 36; // Exclude low-end dummy pitches
    }).toList();

    int totalNotes = activeNotes.length;
    
    if (totalNotes == 0) {
      return AlertDialog(
        backgroundColor: const Color(0xFF16162A),
        title: const Text("Performance Scorecard", style: TextStyle(color: Colors.white)),
        content: const Text("No note data available to score for this stem.", style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: Colors.tealAccent)),
          )
        ],
      );
    }

    int perfectCount = 0;   // <= 10 cents
    int broadcastCount = 0; // <= 25 cents
    int flaggedCount = 0;   // > 25 cents
    double totalError = 0.0;
    double netTendencySum = 0.0;

    for (var note in activeNotes) {
      double effectiveCents = 0.0;
      double rawCents = 0.0;

      if (note['contour'] != null && (note['contour'] as List).isNotEmpty) {
        List<dynamic> contour = note['contour'];
        double avgDrift = contour.map((c) => (c as num).toDouble().abs()).reduce((a, b) => a + b) / contour.length;
        rawCents = contour.map((c) => (c as num).toDouble()).reduce((a, b) => a + b) / contour.length;
        effectiveCents = avgDrift;
      } else {
        double baseMidi = (note['actual_midi'] ?? 60.0).toDouble() + (note['semitone_shift'] ?? 0);
        rawCents = (baseMidi - baseMidi.round()) * 100 + (note['cents_shift'] ?? 0).toDouble();
        effectiveCents = rawCents.abs();
      }

      totalError += effectiveCents;
      netTendencySum += rawCents;

      if (effectiveCents <= 10.0) {
        perfectCount++;
      } else if (effectiveCents <= 25.0) {
        broadcastCount++;
      } else {
        flaggedCount++;
      }
    }

    double avgError = totalError / totalNotes;
    double pctPerfect = (perfectCount / totalNotes) * 100;
    double pctBroadcast = (broadcastCount / totalNotes) * 100;
    double pctFlagged = (flaggedCount / totalNotes) * 100;
    double netTendency = netTendencySum / totalNotes;

    // Grade Determination
    String grade;
    Color gradeColor;
    if (avgError < 8.0) {
      grade = 'A+'; gradeColor = Colors.tealAccent;
    } else if (avgError < 12.0) {
      grade = 'A'; gradeColor = Colors.tealAccent;
    } else if (avgError < 18.0) {
      grade = 'B'; gradeColor = Colors.lightGreenAccent;
    } else if (avgError < 25.0) {
      grade = 'C'; gradeColor = Colors.amberAccent;
    } else if (avgError < 35.0) {
      grade = 'D'; gradeColor = Colors.orangeAccent;
    } else {
      grade = 'F'; gradeColor = Colors.redAccent;
    }

    String tendencyText = netTendency > 3.0 
        ? "Tends Sharp (+${netTendency.toStringAsFixed(1)}¢)" 
        : (netTendency < -3.0 ? "Tends Flat (${netTendency.toStringAsFixed(1)}¢)" : "Centered Pitch");

    return AlertDialog(
      backgroundColor: const Color(0xFF121222),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: const BorderSide(color: Colors.white12),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: Colors.tealAccent, size: 22),
              const SizedBox(width: 8),
              Text(
                "SCORECARD: ${dawState.activeEditableStem.toUpperCase()}",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.1),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: gradeColor.withOpacity(0.15),
              border: Border.all(color: gradeColor, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              grade,
              style: TextStyle(color: gradeColor, fontSize: 18, fontWeight: FontWeight.black),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Summary Row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem("Analyzed Notes", "$totalNotes", Colors.white70),
                  _buildStatItem("Avg Error", "${avgError.toStringAsFixed(1)}¢", Colors.amberAccent),
                  _buildStatItem("Tendency", tendencyText, netTendency.abs() > 3.0 ? Colors.orangeAccent : Colors.tealAccent),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text("INTONATION ACCURACY BREAKDOWN", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 10),

            // Tier 1: Studio Accurate
            _buildAccuracyBar(
              label: "Studio Precision (≤10¢)",
              percentage: pctPerfect,
              count: perfectCount,
              barColor: Colors.tealAccent,
            ),
            const SizedBox(height: 8),

            // Tier 2: Broadcast Acceptable
            _buildAccuracyBar(
              label: "Broadcast Acceptable (11–25¢)",
              percentage: pctBroadcast,
              count: broadcastCount,
              barColor: Colors.amberAccent,
            ),
            const SizedBox(height: 8),

            // Tier 3: Off-Pitch / Flagged
            _buildAccuracyBar(
              label: "Off-Pitch (>25¢)",
              percentage: pctFlagged,
              count: flaggedCount,
              barColor: Colors.redAccent,
            ),
            const SizedBox(height: 16),

            // Visual Segmented Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    if (pctPerfect > 0) Expanded(flex: perfectCount, child: Container(color: Colors.tealAccent)),
                    if (pctBroadcast > 0) Expanded(flex: broadcastCount, child: Container(color: Colors.amberAccent)),
                    if (pctFlagged > 0) Expanded(flex: flaggedCount, child: Container(color: Colors.redAccent)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close", style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
      ],
    );
  }

  Widget _buildAccuracyBar({
    required String label,
    required double percentage,
    required int count,
    required Color barColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            Text("${percentage.toStringAsFixed(1)}% ($count)", style: TextStyle(color: barColor, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (percentage / 100).clamp(0.0, 1.0),
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 5,
          ),
        ),
      ],
    );
  }
}
