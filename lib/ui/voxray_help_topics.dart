import 'help_tooltip_wrapper.dart';

class VoxrayHelpTopics {
  static const mainLogo = HelpTopic(
    title: 'voXRay Logo & Brand Bar',
    whatItIs: 'Displays app branding and build profile.',
    onTapAction: '',
    relatedFeatures: '',
  );

  static const dspWallet = HelpTopic(
    title: 'DSP Token Wallet',
    whatItIs: 'Displays available compute tokens required for cloud GPU tasks (Roformer, X-Ray, AI Detection).',
    onTapAction: 'Opens the Wallet Screen to check balance, view usage history, or purchase additional tokens.',
    relatedFeatures: 'Tokens are consumed when executing Stem Separations, X-Ray Contours, or Dual-Take Alignments.',
  );

  static const mainMenu = HelpTopic(
    title: 'Main Menu (App Controls)',
    whatItIs: 'Central gateway for file I/O, project saves, AI tools, inspection modes, and settings.',
    onTapAction: 'Opens the main drop-down menu listing all global DAW commands.',
    relatedFeatures: 'Contains Save/Load commands, Pitch Key guides, Dossier reports, and Account options.',
  );

  static const studioMixerButton = HelpTopic(
    title: 'Studio Mixer Toggle',
    whatItIs: 'Toggles between floating modal mixer (mobile) and docked bottom mixer (desktop/tablet).',
    onTapAction: 'Opens or docks/undocks the multi-track studio mixing console.',
    relatedFeatures: 'Controls track volumes, panning, mute/solo states, and real-time DSP plugin slots.',
  );

  static const regionCutTool = HelpTopic(
    title: 'Region Cut / Mute Tool',
    whatItIs: 'Enables timeline slicing mode to isolate and silence unwanted noise, breaths, or flubbed notes.',
    onTapAction: 'Toggles Cut Mode on/off. Dragging across the timeline silences the highlighted segment.',
    relatedFeatures: 'Muted regions appear darkened on the timeline and Macro Minimap.',
  );

  static const dragPitchMode = HelpTopic(
    title: 'Pitch Drag Mode Selector',
    whatItIs: 'Configures timeline note movement behavior: Normal (Off), Semitone Drag, or Micro-Tuning Drag.',
    onTapAction: 'Opens a selector menu to switch pitch quantization rules when dragging notes on the canvas.',
    relatedFeatures: 'Normal allows inspector opening; Semitone locks to piano keys; Micro-Tuning allows free cent movement.',
  );

  static const renderEarIcon = HelpTopic(
    title: 'DSP Render Engine (Ear Icon)',
    whatItIs: 'Monitors pending pitch and time edits on the active track.',
    onTapAction: 'Glows red when edits are pending. Tapping sends edits to the server to render updated audio.',
    relatedFeatures: 'Dirty tracks light up this icon until rendered or saved.',
  );

  static const xrayToggle = HelpTopic(
    title: 'X-Ray Micro-Contour Toggle',
    whatItIs: 'Generates and displays continuous, high-resolution pitch tracking curves across note blocks.',
    onTapAction: 'Triggers or toggles the teal continuous pitch contour line for the active stem.',
    relatedFeatures: 'Visualizes micro-vibrato, pitch drift, scoops, and human intonation variance.',
  );

  static const dualXrayToggle = HelpTopic(
    title: 'Dual X-Ray Comparison',
    whatItIs: 'Cross-correlates phase and pitch contours between two different vocal or instrument takes.',
    onTapAction: 'Opens the Dual-Take comparator modal to mathematically align Take A and Take B.',
    relatedFeatures: 'Overlays Cyan (Take A) and Magenta (Take B) traces; highlights identical match regions in green.',
  );

  static const aiDetectionTool = HelpTopic(
    title: 'AI Synthetic Voice Detector',
    whatItIs: 'Deep neural network scanner that checks stems or drum sub-mixes for AI synthesis hallmarks.',
    onTapAction: 'Runs forensic analysis on the selected stem and opens the AI Forensics Report modal.',
    relatedFeatures: 'Displays AI probability scores, flagged event timestamps, and timeline heatmaps.',
  );

  static const meterBridge = HelpTopic(
    title: 'Stem Meter Bridge & Selector',
    whatItIs: 'Displays active stem chips, real-time LED VU meters, mute/solo states, and nudge controls.',
    onTapAction: 'Tap a chip to set it as the active editable track on the piano roll. Long-press to hide track.',
    relatedFeatures: 'Mute (Volume icon), Solo (Headphones icon), and Nudge (+/- 0.1s time-shift).',
  );

  static const fitToScreen = HelpTopic(
    title: 'Fit Timeline to Screen',
    whatItIs: 'Recalculates Zoom X and Zoom Y to fit the entire song duration and pitch range inside the window.',
    onTapAction: 'Instantly resets zoom levels and jumps scrollbars to origin (0,0).',
    relatedFeatures: 'Adjusts Zoom X (horizontal) and Zoom Y (vertical) sliders automatically.',
  );

  static const macroMinimap = HelpTopic(
    title: 'Macro Minimap',
    whatItIs: 'Birds-eye waveform heatmap of the full track showing viewbox frame, playhead, and marker flags.',
    onTapAction: 'Tap or drag anywhere on the minimap to instantly jump the playhead to that timestamp.',
    relatedFeatures: 'Reflects track volumes, muted regions, and active view boundaries in real-time.',
  );

  static const transportPlayPause = HelpTopic(
    title: 'Master Transport (Play / Pause)',
    whatItIs: 'Main playback controller for all unmuted stems, synths, and master mix tracks.',
    onTapAction: 'Starts or pauses multi-track audio playback.',
    relatedFeatures: 'Honors global trim boundaries, active solo states, and timeline loop settings.',
  );

  static const timelineRuler = HelpTopic(
    title: 'Timeline Ruler & Scrub Bar',
    whatItIs: 'Displays time increments (mm:ss), loop region highlights, and marker flag locations.',
    onTapAction: 'Tap or drag across the ruler to scrub the playhead smoothly across time.',
    relatedFeatures: 'Contains marker handles, loop boundaries, and trim curtains.',
  );

  static const pianoKeysScale = HelpTopic(
    title: 'Vertical Piano Keys (Pitch Scale)',
    whatItIs: 'Interactive MIDI key scale displaying note names and chromatic key layouts.',
    onTapAction: 'Scroll vertically to reveal higher or lower pitch registers.',
    relatedFeatures: 'Notes on the canvas align horizontally with their corresponding MIDI key.',
  );

  static const timelineCanvas = HelpTopic(
    title: 'Piano Roll Timeline Canvas',
    whatItIs: 'Primary workspace displaying extracted pitch blocks, drum blobs, X-Ray lines, and heatmaps.',
    onTapAction: 'Tap a note in Normal mode to open Note Inspector; drag in Pitch Mode to retune.',
    relatedFeatures: 'Colors indicate tuning accuracy: Teal (<=10c), Amber (11-25c), Red (>25c).',
  );

  static const sidebarMarkerTools = HelpTopic(
    title: 'Sidebar Marker & Loop Tools',
    whatItIs: 'Utility bar for dropping navigation flags, creating loop regions, setting trims, and undo/redo.',
    onTapAction: 'Add marker at playhead, jump to marker, set loop bounds, trim song end/start, or step undo/redo.',
    relatedFeatures: 'Markers are embedded into exported WAV files for external DAWs like Reaper or Audacity.',
  );

  static const noteInspector = HelpTopic(
    title: 'Note Inspector Modal',
    whatItIs: 'Surgical micro-tuning editor for individual polyphonic or monophonic notes.',
    onTapAction: 'Allows fine cent adjustment (+/-100c), vibrato scale, pitch drift, time-stretch, and snapping.',
    relatedFeatures: 'Edits mark the track as "dirty" until processed via the Render Ear Icon.',
  );
}
