import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';

export async function verify(path) {
  const probe=JSON.parse(execFileSync('ffprobe',['-v','error','-show_format','-show_streams','-of','json',path],{encoding:'utf8'}));
  const video=probe.streams.find(s=>s.codec_type==='video');
  const audio=probe.streams.find(s=>s.codec_type==='audio');
  if(!video || video.codec_name!=='h264' || video.pix_fmt!=='yuv420p') throw new Error('Expected H.264 yuv420p video');
  if(!audio || audio.codec_name!=='aac') throw new Error('Expected AAC audio');
  if(video.width!==1920 || video.height!==1080 || video.avg_frame_rate!=='30/1') throw new Error('Unexpected size/frame rate');
  if(Math.abs(Number(probe.format.duration)-24)>.1) throw new Error('Unexpected duration');
  execFileSync('ffmpeg',['-v','error','-i',path,'-f','null','-'],{stdio:['ignore','ignore','pipe']});
  return {path,sha256:createHash('sha256').update(await readFile(path)).digest('hex'),duration:probe.format.duration,video:{codec:video.codec_name,width:video.width,height:video.height,fps:video.avg_frame_rate,frames:video.nb_frames,pixelFormat:video.pix_fmt},audio:{codec:audio.codec_name,sampleRate:audio.sample_rate,channels:audio.channels}};
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) console.log(JSON.stringify(await verify(process.argv[2] || 'out/creative-system.mp4'),null,2));
