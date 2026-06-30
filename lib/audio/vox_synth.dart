import 'dart:math';
import 'dart:typed_data';

enum Waveform {
  sine,
  square,
  triangle,
  saw,
}

class ADSR {
  final double attack;
  final double decay;
  final double sustain;
  final double release;

  const ADSR({
    this.attack = 0.01,
    this.decay = 0.05,
    this.sustain = .8,
    this.release = .08,
  });
}

double oscillator(
    Waveform waveform,
    double phase,
    ) {

  switch (waveform) {

    case Waveform.square:
      return sin(phase) >= 0 ? 1 : -1;

    case Waveform.triangle:
      return (2 / pi) * asin(sin(phase));

    case Waveform.saw:
      return 2 * (phase / (2 * pi) -
          (phase / (2 * pi)).floor()) - 1;

    case Waveform.sine:
      return sin(phase);

  }
}

double midiToHz(double midi){

  return 440 *
      pow(
          2,
          (midi-69)/12
      );

}

Float32List renderNotes({

required List notes,

Waveform waveform=Waveform.sine,

ADSR adsr=const ADSR(),

int sampleRate=44100,

required double duration,

}){

final totalSamples=
(duration*sampleRate).ceil();

final output=
Float32List(totalSamples);

for(final note in notes){

if(note.isDeleted) continue;

if(note.isMuted) continue;

final freq=
midiToHz(note.actualMidi);

final start=
(note.startTime*sampleRate).round();

final end=
(note.endTime*sampleRate).round();

final noteSamples=end-start;

for(int i=0;i<noteSamples;i++){

double env=1;

final t=i/sampleRate;

if(t<adsr.attack){

env=t/adsr.attack;

}
else if(t<adsr.attack+adsr.decay){

final x=(t-adsr.attack)/
adsr.decay;

env=
1-
(1-adsr.sustain)*x;

}
else{

final releaseStart=
noteSamples/sampleRate-
adsr.release;

if(t>releaseStart){

env=
adsr.sustain*
(1-
((t-releaseStart)/
adsr.release));

}
else{

env=
adsr.sustain;

}

}

final phase=
2*pi*freq*i/sampleRate;

output[start+i]+=
oscillator(
waveform,
phase,
)
*
env
*
note.volume;

}

}

return output;

}

double peak=0;

for(final s in output){

if(s.abs()>peak)
peak=s.abs();

}

if(peak>0){

for(int i=0;i<output.length;i++){

output[i]/=peak;

}

}

Uint8List floatToPCM(
Float32List input){

final bytes=
BytesBuilder();

for(final sample in input){

final s=
(sample*32767)
.clamp(
-32768,
32767,
)
.round();

bytes.addByte(s&255);

bytes.addByte((s>>8)&255);

}

return bytes.toBytes();

}

Uint8List makeWaveFile(
Float32List audio){

// builds 44-byte WAV header
// append PCM bytes

}

