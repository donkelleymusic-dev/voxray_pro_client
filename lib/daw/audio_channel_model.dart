class AudioChannel {
  final String id;
  String name;
  final String stemType; // 'vocals', 'bass', 'guitar', 'drums', etc.
  final String filePath;
  bool isMuted;
  double volume;

  AudioChannel({
    required this.id,
    required this.name,
    required this.stemType,
    required this.filePath,
    this.isMuted = false,
    this.volume = 1.0,
  });
}
