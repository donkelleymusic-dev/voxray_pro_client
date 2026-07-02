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
    showModalBottomSheet(
      context: context, backgroundColor: Colors.grey[950], isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {

            // --- Compute derived display values ---
            double actualMidi = (note['actual_midi'] ?? 60.0).toDouble();
            int originalMidiInt = actualMidi.round();
            String originalNoteName = _midiToName(originalMidiInt);

            // Get true cents variance — contour average if xray, else fractional midi
            double rawCentsFromPitch;
            if (note['contour'] != null && (note['contour'] as List).isNotEmpty) {
              List<dynamic> contour = note['contour'] as List;
              // Average of contour = true mean pitch drift in cents
              rawCentsFromPitch = contour
                  .map((c) => (c as num).toDouble())
                  .reduce((a, b) => a + b) / contour.length;
            } else {
              // Fractional microtonal difference natively derived from the floating point MIDI integer
              rawCentsFromPitch = (actualMidi - originalMidiInt) * 100;
            }

            int centsShift = note['cents_shift'] ?? 0;
            double totalCentsFromOriginal = rawCentsFromPitch + centsShift;

            // What semitone does the total shift land on?
            double adjustedMidi = actualMidi + (centsShift / 100.0);
            int adjustedMidiInt = adjustedMidi.round();
            String adjustedNoteName = _midiToName(adjustedMidiInt);

            bool noteNameChanged = adjustedMidiInt != originalMidiInt;

            // Xray data for the variance line
            bool hasXray = note.containsKey('contour') && note['contour'] != null;
            double? xrayCents = hasXray && (note['contour'] as List).isNotEmpty
                ? (note['contour'] as List)
                    .map((c) => (c as num).toDouble().abs())
                    .reduce((a, b) => a + b) / (note['contour'] as List).length
                : null;

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
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
                          // Original note name, and changed name if different
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                originalNoteName,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: noteNameChanged ? Colors.white54 : Colors.white,
                                  decoration: noteNameChanged ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              if (noteNameChanged) ...[
                                const Icon(Icons.arrow_forward, size: 14, color: Colors.amberAccent),
                                Text(
                                  adjustedNoteName,
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                ),
                              ],
                              const SizedBox(width: 8),
                              // Cents from the target note after adjustment
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
                          // Xray or basic variance line
                          if (hasXray && xrayCents != null)
                            Text(
                              'X-Ray avg drift: ${xrayCents.toStringAsFixed(1)}¢',
                              style: TextStyle(
                                fontSize: 12,
                                color: xrayCents <= 15 ? Colors.tealAccent : Colors.redAccent,
                              ),
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
                          dawState.registerUndoSnapshot();
                          setModalState(() {
                            note['cents_shift'] = -rawCentsFromPitch.round();
                          });
                          dawState.notifyChanged();
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white24),

                  // --- PITCH SHIFT SLIDER ---
                  const Text("Pitch Shift (Cents)", style: TextStyle(color: Colors.white70)),
                  Builder(builder: (context) {
                    double currentCents = (note['cents_shift'] ?? 0).toDouble();
                    double sMin = currentCents < -100.0 ? currentCents : -100.0;
                    double sMax = currentCents > 100.0 ? currentCents : 100.0;
                    return Slider(
                      value: currentCents, min: sMin, max: sMax,
                      activeColor: Colors.amberAccent,
                      onChangeStart: (_) => dawState.registerUndoSnapshot(),
                      onChanged: (val) {
                        setModalState(() => note['cents_shift'] = val.round());
                        dawState.notifyChanged();
                      },
                    );
                  }),

                  // --- VIBRATO ---
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text("Vibrato Width"),
                    Text("${((note['vibrato_scale'] ?? 1.0) * 100).round()}%"),
                  ]),
                  Slider(
                    value: note['vibrato_scale'] ?? 1.0, min: 0.0, max: 2.0,
                    activeColor: Colors.purpleAccent,
                    onChangeStart: (_) => dawState.registerUndoSnapshot(),
                    onChanged: (val) { setModalState(() => note['vibrato_scale'] = val); dawState.notifyChanged(); },
                  ),

                  // --- PITCH DRIFT ---
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text("Pitch Drift"),
                    Text(note['drift_scale'] == 0.0 ? "Flattened" : "${((note['drift_scale'] ?? 1.0) * 100).round()}%"),
                  ]),
                  Slider(
                    value: note['drift_scale'] ?? 1.0, min: 0.0, max: 2.0,
                    activeColor: Colors.orangeAccent,
                    onChangeStart: (_) => dawState.registerUndoSnapshot(),
                    onChanged: (val) { setModalState(() => note['drift_scale'] = val); dawState.notifyChanged(); },
                  ),

                  // --- TIME STRETCH ---
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text("Time Stretch / Warp", style: TextStyle(color: Colors.white70)),
                    Text("${((note['time_ratio'] ?? 1.0) * 100).round()}%", style: const TextStyle(color: Colors.white54)),
                  ]),
                  Slider(
                    value: note['time_ratio'] ?? 1.0, min: 0.5, max: 2.0,
                    activeColor: Colors.lightBlueAccent,
                    onChangeStart: (_) => dawState.registerUndoSnapshot(),
                    onChanged: (val) { setModalState(() => note['time_ratio'] = val); dawState.notifyChanged(); },
                  ),

                  // --- MUTE / DELETE ---
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    spacing: 8.0, runSpacing: 8.0,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: note['isMuted'] == true ? Colors.orange : Colors.grey[800]),
                        icon: Icon(note['isMuted'] == true ? Icons.volume_off : Icons.volume_up),
                        label: Text(note['isMuted'] == true ? "Muted" : "Mute"),
                        onPressed: () {
                          dawState.registerUndoSnapshot();
                          setModalState(() => note['isMuted'] = !(note['isMuted'] ?? false));
                          dawState.notifyChanged();
                        },
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: note['isDeleted'] == true ? Colors.redAccent : Colors.grey[800]),
                        icon: Icon(note['isDeleted'] == true ? Icons.restore : Icons.delete),
                        label: Text(note['isDeleted'] == true ? "Restore" : "Delete"),
                        onPressed: () {
                          dawState.registerUndoSnapshot();
                          setModalState(() => note['isDeleted'] = !(note['isDeleted'] ?? false));
                          dawState.notifyChanged();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
