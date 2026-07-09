import 'package:flutter/material.dart';
import '../main.dart';

class NoteInspector {
  // Helper: convert midi number to note name string e.g. 60 -> "C4"
  static String _midiToName(num midi) {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    int m = midi.round();
    return '${noteNames[m % 12]}${(m ~/ 12) - 1}';
  }

  static void show(BuildContext context, VoxrayDAWState dawState, int noteIndex, Map<String, dynamic> note) {
    // Isolate state for temporary changes to enable Save/Cancel
    int originalCents = note['cents_shift'] ?? 0;
    
    int tempCents = originalCents;
    double tempVibrato = note['vibrato_scale'] ?? 1.0;
    double tempDrift = note['drift_scale'] ?? 1.0;
    double tempTime = note['time_ratio'] ?? 1.0;
    bool tempMuted = note['isMuted'] ?? false;
    bool tempDeleted = note['isDeleted'] ?? false;

    showModalBottomSheet(
      context: context, backgroundColor: Colors.grey[950], isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {

            // --- Compute derived display values ---
            double actualMidi = (note['actual_midi'] ?? 60.0).toDouble();
            int semitoneShift = note['semitone_shift'] ?? 0; // The macro shift from dragging
            double baseMidi = actualMidi + semitoneShift; // The new foundational pitch
            
            int baseMidiInt = baseMidi.round();
            String currentNoteName = _midiToName(baseMidiInt);

            // Get true cents variance relative to the baseMidi 
            double rawCentsFromPitch;
            if (note['contour'] != null && (note['contour'] as List).isNotEmpty) {
              List<dynamic> contour = note['contour'] as List;
              rawCentsFromPitch = contour
                  .map((c) => (c as num).toDouble())
                  .reduce((a, b) => a + b) / contour.length;
            } else {
              rawCentsFromPitch = (actualMidi - actualMidi.round()) * 100;
            }

            // Xray data for the variance line
            bool hasXray = note.containsKey('contour') && note['contour'] != null;
            double? xrayCents = hasXray && (note['contour'] as List).isNotEmpty
                ? (note['contour'] as List)
                    .map((c) => (c as num).toDouble().abs())
                    .reduce((a, b) => a + b) / (note['contour'] as List).length
                : null;

            var forensics = note['forensics'];
            bool isAnalyzed = forensics != null && forensics['is_analyzed'] == true;
            
            if (isAnalyzed) {
                double prob = forensics['tuning_probability'];
                double stdDev = forensics['std_deviation'];
                
                // Example UI Logic:
                // if (prob > 0.85) -> Show Red "Mechanical Tuning Detected" warning
                // if (prob < 0.30) -> Show Green "Natural Human Wobble" text
            }
            
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 10,
                    left: 20, right: 20, top: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // --- HEADER: Note name + xray variance ---
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8.0, runSpacing: 12.0,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  currentNoteName,
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  rawCentsFromPitch >= 0
                                      ? '+${rawCentsFromPitch.toStringAsFixed(1)}¢'
                                      : '${rawCentsFromPitch.toStringAsFixed(1)}¢',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: rawCentsFromPitch.abs() <= 10
                                        ? Colors.tealAccent
                                        : rawCentsFromPitch.abs() <= 25
                                            ? Colors.amberAccent
                                            : Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            if (hasXray && xrayCents != null)
                              Text(
                                'X-Ray avg drift: ${xrayCents.toStringAsFixed(1)}¢',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: xrayCents <= 15 ? Colors.tealAccent : Colors.redAccent,
                                ),
                                if (prob > 0.85) -> Show Red "Mechanical Tuning Detected" warning
                                if (prob < 0.30) -> Show Green "Natural Human Wobble" text
                              )
                            else if (!hasXray && dawState.isXrayMode)
                              const Text('X-Ray: processing...', style: TextStyle(fontSize: 12, color: Colors.white38))
                            else if (!hasXray)
                              const Text('X-Ray not enabled', style: TextStyle(fontSize: 12, color: Colors.white38)),
                          ],
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700]),
                          icon: const Icon(Icons.auto_fix_high, size: 16),
                          label: const Text("Snap to Scale"),
                          onPressed: () {
                            setModalState(() {
                              tempCents = -rawCentsFromPitch.round();
                            });
                          },
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white24),

                    // --- PITCH SHIFT SLIDER (Micro) ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Micro Tuning (Cents)", style: TextStyle(color: Colors.white70)),
                        Text(
                          "Original: ${originalCents > 0 ? '+' : ''}$originalCents¢  |  New: ${tempCents > 0 ? '+' : ''}$tempCents¢", 
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 12)
                        ),
                      ]
                    ),
                    Row(
                      children: [
                        const Text("-100", style: TextStyle(color: Colors.white38, fontSize: 10)),
                        Expanded(
                          child: Slider(
                            value: tempCents.toDouble(), 
                            min: -100.0, 
                            max: 100.0,
                            divisions: 200, 
                            label: "${tempCents > 0 ? '+' : ''}$tempCents¢",
                            activeColor: Colors.amberAccent,
                            onChanged: (val) {
                              setModalState(() => tempCents = val.round());
                            },
                          )
                        ),
                        const Text("+100", style: TextStyle(color: Colors.white38, fontSize: 10)),
                      ]
                    ),

                    // --- VIBRATO ---
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text("Vibrato Width"),
                      Text("${(tempVibrato * 100).round()}%"),
                    ]),
                    Slider(
                      value: tempVibrato, min: 0.0, max: 2.0,
                      activeColor: Colors.purpleAccent,
                      onChanged: (val) { setModalState(() => tempVibrato = val); },
                    ),

                    // --- PITCH DRIFT ---
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text("Pitch Drift"),
                      Text(tempDrift == 0.0 ? "Flattened" : "${(tempDrift * 100).round()}%"),
                    ]),
                    Slider(
                      value: tempDrift, min: 0.0, max: 2.0,
                      activeColor: Colors.orangeAccent,
                      onChanged: (val) { setModalState(() => tempDrift = val); },
                    ),

                    // --- TIME STRETCH ---
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text("Time Stretch / Warp", style: TextStyle(color: Colors.white70)),
                      Text("${(tempTime * 100).round()}%", style: const TextStyle(color: Colors.white54)),
                    ]),
                    Slider(
                      value: tempTime, min: 0.5, max: 2.0,
                      activeColor: Colors.lightBlueAccent,
                      onChanged: (val) { setModalState(() => tempTime = val); },
                    ),

                    const SizedBox(height: 12),

                    // --- SAVE / CANCEL / MUTE / DELETE (Action Bar) ---
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(tempMuted ? Icons.volume_off : Icons.volume_up),
                          color: tempMuted ? Colors.orange : Colors.white54,
                          tooltip: tempMuted ? "Unmute" : "Mute",
                          onPressed: () { setModalState(() => tempMuted = !tempMuted); },
                        ),
                        IconButton(
                          icon: Icon(tempDeleted ? Icons.restore : Icons.delete),
                          color: tempDeleted ? Colors.redAccent : Colors.white54,
                          tooltip: tempDeleted ? "Restore" : "Delete",
                          onPressed: () { setModalState(() => tempDeleted = !tempDeleted); },
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context), 
                          child: const Text("Cancel", style: TextStyle(color: Colors.white54))
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                          onPressed: () {
                            dawState.registerUndoSnapshot();
                            note['cents_shift'] = tempCents;
                            note['vibrato_scale'] = tempVibrato;
                            note['drift_scale'] = tempDrift;
                            note['time_ratio'] = tempTime;
                            note['isMuted'] = tempMuted;
                            note['isDeleted'] = tempDeleted;
                            dawState.notifyChanged();
                            Navigator.pop(context);
                          },
                          child: const Text("Save Changes")
                        )
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
