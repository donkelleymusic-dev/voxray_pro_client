import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import '../main.dart'; 

class DrumSubmixerGroupWidget extends StatefulWidget {
  final VoxrayDAWState dawState;

  const DrumSubmixerGroupWidget({Key? key, required this.dawState}) : super(key: key);

  @override
  State<DrumSubmixerGroupWidget> createState() => _DrumSubmixerGroupWidgetState();
}

class _DrumSubmixerGroupWidgetState extends State<DrumSubmixerGroupWidget> {
  bool isExpanded = false;

  final Map<String, Map<String, dynamic>> drumSubStems = {
    'kick': {'label': 'KICK', 'color': const Color(0xFFFF2A00), 'icon': Icons.circle},
    'snare': {'label': 'SNARE', 'color': const Color(0xFFFF5500), 'icon': Icons.adjust},
    'hihat': {'label': 'HI-HAT', 'color': const Color(0xFFFF8800), 'icon': Icons.graphic_eq},
    'toms': {'label': 'TOMS', 'color': const Color(0xFFFF3344), 'icon': Icons.grid_view},
    'cymbals': {'label': 'CYMBALS', 'color': const Color(0xFFFFB700), 'icon': Icons.blur_on},
  };

  void _updateDrumVolumes() {
    // 1. Force the HTDemucs "drums" unified track to be totally silent ALWAYS
    if (widget.dawState.stemHandles.containsKey('drums')) {
      SoLoud.instance.setVolume(widget.dawState.stemHandles['drums']!, 0.0);
    }

    // 2. Master Drum Bus Multiplier
    final masterState = widget.dawState.getChannelState('drums');
    double busMultiplier = masterState.isMuted ? 0.0 : masterState.volume;

    // 3. Apply scaled volume to the 5 sub-stems
    for (String subKey in drumSubStems.keys) {
      final subState = widget.dawState.getChannelState(subKey);
      double finalVol = subState.isMuted ? 0.0 : (subState.volume * busMultiplier);
      
      if (widget.dawState.stemHandles.containsKey(subKey)) {
         final handle = widget.dawState.stemHandles[subKey]!;
         if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
           SoLoud.instance.setVolume(handle, finalVol);
         }
      }
    }
  }

  Widget _buildFader(String key, String title, Color color, IconData icon, {bool isMaster = false}) {
    final state = widget.dawState.getChannelState(key);
    bool isAudible = widget.dawState.activePlaybackSources.contains(key) || 
                     (isMaster && widget.dawState.activePlaybackSources.isNotEmpty);

    return Container(
      width: 68,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: isMaster ? color.withOpacity(0.15) : Colors.black87,
        border: Border.all(color: isMaster ? color : color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4.0, bottom: 2.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isMaster)
                  GestureDetector(
                    onTap: () => setState(() => isExpanded = !isExpanded),
                    child: Icon(isExpanded ? Icons.unfold_less : Icons.unfold_more, color: color, size: 14),
                  )
                else
                  Icon(icon, color: color, size: 10),
                const SizedBox(width: 4),
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 9)),
              ],
            ),
          ),

          // VU Meter (Driven by the backend stem_rms_data)
          ValueListenableBuilder<double>(
            valueListenable: widget.dawState.channelLevels[key] ?? ValueNotifier(0.0),
            builder: (context, currentLevel, child) {
              double displayLevel = (widget.dawState.isPlaying && isAudible && !state.isMuted) ? currentLevel : 0.0;
              return ChannelVuMeter(level: displayLevel);
            },
          ),
          const SizedBox(height: 8),

          // 🎛️ PLUGIN SLOTS (Only for individual stems, not the master bus)
          if (!isMaster) ...[
            widget.dawState.buildPluginSlot(key, state.plugin1, color, (val) {
              setState(() => state.plugin1 = val!);
              widget.dawState.dirtyStems.add(key);
              widget.dawState.applyStemPlugins(key);
            }),
            widget.dawState.buildPluginSlot(key, state.plugin2, color, (val) {
              setState(() => state.plugin2 = val!);
              widget.dawState.dirtyStems.add(key);
              widget.dawState.applyStemPlugins(key);
            }),
            widget.dawState.buildPluginSlot(key, state.plugin3, color, (val) {
              setState(() => state.plugin3 = val!);
              widget.dawState.dirtyStems.add(key);
              widget.dawState.applyStemPlugins(key);
            }),
            widget.dawState.buildPluginSlot(key, state.plugin4, color, (val) {
              setState(() => state.plugin4 = val!);
              widget.dawState.dirtyStems.add(key);
              widget.dawState.applyStemPlugins(key);
            }),
            const SizedBox(height: 4),
          ] else ...[
            // Spacer for Master Bus to keep vertical alignment
            const SizedBox(height: 100), 
          ],

          // Mute Button
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
                state.isMuted ? Icons.volume_off : Icons.volume_up,
                color: !state.isMuted ? color : Colors.white38,
                size: 18),
            onPressed: () {
              setState(() {
                state.isMuted = !state.isMuted;
                widget.dawState.dirtyStems.add(key);
                widget.dawState.hasBeenSaved = false;
              });
              _updateDrumVolumes();
            },
          ),

          // Volume Fader
          Expanded(
            child: GestureDetector(
              onDoubleTap: () {
                setState(() {
                  state.volume = 1.0;
                  widget.dawState.dirtyStems.add(key);
                });
                _updateDrumVolumes();
              },
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: color,
                    inactiveTrackColor: Colors.white10,
                  ),
                  child: Slider(
                    value: state.volume,
                    min: 0.0, max: 1.5,
                    onChanged: (v) { 
                      setState(() {
                        state.volume = v;
                        widget.dawState.dirtyStems.add(key);
                      });
                      _updateDrumVolumes();
                    }
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(state.volume * 100).round()}%',
              style: const TextStyle(fontSize: 9, color: Colors.white54)),
          
          // Pan slider (Only for individual stems)
          if (!isMaster) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 16,
              child: GestureDetector(
                onDoubleTap: () {
                  setState(() {
                    state.pan = 0.0;
                    widget.dawState.dirtyStems.add(key);
                  });
                  if (widget.dawState.stemHandles.containsKey(key)) {
                     SoLoud.instance.setPan(widget.dawState.stemHandles[key]!, 0.0);
                  }
                },
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: color,
                    inactiveTrackColor: Colors.white10,
                  ),
                  child: Slider(
                    value: state.pan, min: -1.0, max: 1.0,
                    onChanged: (v) { 
                      setState(() {
                        state.pan = v;
                        widget.dawState.dirtyStems.add(key);
                      });
                      if (widget.dawState.stemHandles.containsKey(key)) {
                         SoLoud.instance.setPan(widget.dawState.stemHandles[key]!, v);
                      }
                    }
                  ),
                ),
              ),
            ),
            Text(
              state.pan == 0 ? 'C' : (state.pan < 0 ? 'L ${-(state.pan * 100).round()}' : 'R ${(state.pan * 100).round()}'),
              style: const TextStyle(fontSize: 8, color: Colors.white54),
            ),
          ] else ...[
            const SizedBox(height: 20), // Alignment spacer
          ],
          
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The Parent Bus
        _buildFader('drums', 'DRUM BUS', const Color(0xFFFF2A00), Icons.grid_view, isMaster: true),
        // The Children Faders (Collapsible)
        if (isExpanded) ...drumSubStems.entries.map((entry) {
          return _buildFader(entry.key, entry.value['label'], entry.value['color'], entry.value['icon']);
        }).toList(),
      ],
    );
  }
}
