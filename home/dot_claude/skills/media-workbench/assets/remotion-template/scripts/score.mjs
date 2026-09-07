import {mkdir, writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';

export async function makeScore(path) {
  const rate=48000, seconds=24, channels=2, count=rate*seconds;
  const wav=Buffer.alloc(44+count*channels*2);
  wav.write('RIFF'); wav.writeUInt32LE(wav.length-8,4); wav.write('WAVEfmt ',8);
  wav.writeUInt32LE(16,16); wav.writeUInt16LE(1,20); wav.writeUInt16LE(channels,22);
  wav.writeUInt32LE(rate,24); wav.writeUInt32LE(rate*channels*2,28); wav.writeUInt16LE(channels*2,32); wav.writeUInt16LE(16,34);
  wav.write('data',36); wav.writeUInt32LE(count*channels*2,40);
  const chords=[[130.8128,164.8138,195.9977,246.9417],[110,146.8324,164.8138,220],[130.8128,164.8138,195.9977,261.6256]];
  for(let i=0;i<count;i++) {
    const t=i/rate, section=Math.min(2,Math.floor(t/8)), notes=chords[section];
    const envelope=Math.min(1,t/1.5,(24-t)/2)*Math.min(1,(t%8)/.2+.05,(8-t%8)/.2);
    const pulse=t%(.5), note=notes[Math.floor(t*2)%4]*2;
    const bell=Math.sin(2*Math.PI*note*pulse)*Math.exp(-pulse*11)*.07;
    for(let ch=0;ch<channels;ch++) {
      const pad=notes.reduce((sum,f,n)=>sum+Math.sin(2*Math.PI*(f+ch*.08)*t+n*.4),0)*.025;
      const sample=Math.max(-1,Math.min(1,(pad+bell)*envelope));
      wav.writeInt16LE(Math.round(sample*32767),44+(i*channels+ch)*2);
    }
  }
  await mkdir(new URL('../public/',import.meta.url),{recursive:true});
  await writeFile(path,wav);
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) await makeScore(new URL('../public/score.wav',import.meta.url));
