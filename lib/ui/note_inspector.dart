import 'package:flutter/material.dart';
import '../main.dart';

class NoteInspector {
  static void show(BuildContext context, VoxrayDAWState dawState, int noteIndex, Map<String, dynamic> note) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.grey[950], isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom, 
                  left: 20, right: 20, top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FIXED: Changed rigid Row to a responsive Wrap
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8.0,
                    runSpacing: 12.0,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Note Properties", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(
                            "Variance: ${note['display_cents'] ?? 0} cents",
                            style: TextStyle(
                              fontSize: 14, 
                              color: (note['display_cents']?.abs() ?? 0) > 15 ? Colors.redAccent : Colors.tealAccent
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700]),
                        icon: const Icon(Icons.auto_fix_high, size: 16), 
                        label: const Text("Snap to Scale"),
                        onPressed: () {
                          dawState.registerUndoSnapshot();
                          setModalState(() {
                            double rawMidi = note['actual_midi'];
                            int nearestInt = rawMidi.round();
                            note['cents_shift'] = -((rawMidi - nearestInt) * 100).round();
                          });
                          dawState.setState(() {}); 
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white24),
                  
                  const Text("Pitch Shift (Cents)", style: TextStyle(color: Colors.white70)),
                  Slider(
                    value: (note['cents_shift'] ?? 0).toDouble(), min: -100, max: 100, activeColor: Colors.amberAccent,
                    onChangeStart: (_) => dawState.registerUndoSnapshot(),
                    onChanged: (val) { setModalState(() => note['cents_shift'] = val.round()); dawState.setState(() {}); },
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Vibrato Width"), Text("${((note['vibrato_scale'] ?? 1.0) * 100).round()}%"),
                    ],
                  ),
                  Slider(
                    value: note['vibrato_scale'] ?? 1.0, min: 0.0, max: 2.0, activeColor: Colors.purpleAccent,
                    onChangeStart: (_) => dawState.registerUndoSnapshot(),
                    onChanged: (val) { setModalState(() => note['vibrato_scale'] = val); dawState.setState(() {}); },
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Pitch Drift"), Text(note['drift_scale'] == 0.0 ? "Flattened" : "${((note['drift_scale'] ?? 1.0) * 100).round()}%"),
                    ],
                  ),
                  Slider(
                    value: note['drift_scale'] ?? 1.0, min: 0.0, max: 2.0, activeColor: Colors.orangeAccent,
                    onChangeStart: (_) => dawState.registerUndoSnapshot(),
                    onChanged: (val) { setModalState(() => note['drift_scale'] = val); dawState.setState(() {}); },
                  ),

                  const Text("Time Stretch / Warp", style: TextStyle(color: Colors.white70)),
                  Slider(
                    value: note['time_ratio'] ?? 1.0, min: 0.5, max: 2.0, activeColor: Colors.lightBlueAccent,
                    onChangeStart: (_) => dawState.registerUndoSnapshot(),
                    onChanged: (val) { setModalState(() => note['time_ratio'] = val); dawState.setState(() {}); },
                  ),

                  // FIXED: Changed to Wrap so buttons don't crush on narrow phones
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: note['isMuted'] == true ? Colors.orange : Colors.grey[800]),
                        icon: Icon(note['isMuted'] == true ? Icons.volume_off : Icons.volume_up), label: Text(note['isMuted'] == true ? "Muted" : "Mute"),
                        onPressed: () { dawState.registerUndoSnapshot(); setModalState(() => note['isMuted'] = !(note['isMuted'] ?? false)); dawState.setState(() {}); },
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: note['isDeleted'] == true ? Colors.redAccent : Colors.grey[800]),
                        icon: Icon(note['isDeleted'] == true ? Icons.restore : Icons.delete), label: Text(note['isDeleted'] == true ? "Restore" : "Delete"),
                        onPressed: () { dawState.registerUndoSnapshot(); setModalState(() => note['isDeleted'] = !(note['isDeleted'] ?? false)); dawState.setState(() {}); },
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