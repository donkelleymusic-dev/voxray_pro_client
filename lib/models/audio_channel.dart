// lib/models/audio_channel.dart
class AudioChannel {
  final String id;
  String name;
  final String stemKey; // e.g. 'vocals', 'vocals2', 'bass3'
  final String baseType; // e.g. 'vocals', 'bass'
  final String filePath;

  AudioChannel({
    required this.id,
    required this.name,
    required this.stemKey,
    required this.baseType,
    required this.filePath,
  });
}
