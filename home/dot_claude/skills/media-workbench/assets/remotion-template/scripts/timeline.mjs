import {randomUUID} from 'node:crypto';
import {access, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';

export async function writeTimeline(video, {fps,width,height,durationInFrames:duration}) {
  const destination='out/creative-system.kdenlive';
  try { await access(destination); return; } catch(error) { if(error.code!=='ENOENT') throw error; }
  const escape=(s)=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
  const properties=(values)=>Object.entries(values).map(([key,value])=>`<property name="${escape(key)}">${escape(value)}</property>`).join('\n');
  const uuid=`{${randomUUID()}}`, end=duration-1;
  const source=(id,path,binId,name,extra={})=>`<chain id="${id}" in="0" out="${end}">${properties({length:duration,eof:'pause',resource:path,mlt_service:'avformat','kdenlive:id':binId,'kdenlive:clipname':name,'kdenlive:folderid':-1,...extra})}</chain>`;
  const entries=[0,240,480].map(start=>`<entry producer="video" in="${start}" out="${start+239}">${properties({'kdenlive:id':4})}</entry>`).join('\n');
  const xml=`<?xml version="1.0" encoding="UTF-8"?>
<mlt producer="main_bin" version="7.30.0" root="${escape(dirname(video))}">
<profile description="HD 1080p 30 fps" width="${width}" height="${height}" frame_rate_num="${fps}" frame_rate_den="1" progressive="1" sample_aspect_num="1" sample_aspect_den="1" display_aspect_num="16" display_aspect_den="9" colorspace="709"/>
<producer id="black" in="0" out="${end}">${properties({length:duration,eof:'continue',resource:'black',mlt_service:'color','kdenlive:playlistid':'black_track',mlt_image_format:'rgba','set.test_audio':1})}</producer>
${source('video',video,4,'Creative System · motion graphics',{'set.test_audio':1,audio_index:-1,video_index:0})}
${source('audio',resolve('public/score.wav'),5,'Original stereo score',{'set.test_image':1,video_index:-1,audio_index:0})}
<playlist id="audio-main">${properties({'kdenlive:audio_track':1})}<entry producer="audio" in="0" out="${end}">${properties({'kdenlive:id':5})}</entry></playlist>
<playlist id="audio-mix">${properties({'kdenlive:audio_track':1})}</playlist>
<tractor id="audio-track" in="0" out="${end}">${properties({'kdenlive:audio_track':1,'kdenlive:track_name':'Original score','kdenlive:trackheight':90,'kdenlive:timeline_active':1})}<track producer="audio-main" hide="video"/><track producer="audio-mix" hide="video"/></tractor>
<playlist id="video-main">${entries}</playlist><playlist id="video-mix"/>
<tractor id="video-track" in="0" out="${end}">${properties({'kdenlive:track_name':'Think / Make / Finish','kdenlive:trackheight':100,'kdenlive:timeline_active':1})}<track producer="video-main" hide="audio"/><track producer="video-mix" hide="audio"/></tractor>
<tractor id="${uuid}" in="0" out="${end}">${properties({'kdenlive:uuid':uuid,'kdenlive:clipname':'Creative System','kdenlive:id':3,'kdenlive:producer_type':17,'kdenlive:duration':'00:00:24.000','kdenlive:maxduration':duration,'kdenlive:sequenceproperties.documentuuid':uuid,'kdenlive:sequenceproperties.hasAudio':1,'kdenlive:sequenceproperties.hasVideo':1,'kdenlive:sequenceproperties.tracksCount':2,'kdenlive:sequenceproperties.tracks':2,'kdenlive:sequenceproperties.activeTrack':1,'kdenlive:sequenceproperties.audioTarget':0,'kdenlive:sequenceproperties.videoTarget':1,'kdenlive:sequenceproperties.zonein':0,'kdenlive:sequenceproperties.zoneout':duration,'kdenlive:sequenceproperties.zoom':8,'kdenlive:sequenceproperties.position':100,'kdenlive:sequenceproperties.groups':'[]','kdenlive:sequenceproperties.guides':JSON.stringify([{pos:0,comment:'Think',type:0},{pos:8,comment:'Make',type:0},{pos:16,comment:'Finish',type:0}])})}
<track producer="black"/><track producer="audio-track"/><track producer="video-track"/>
<transition in="0" out="${end}">${properties({a_track:0,b_track:1,mlt_service:'mix',internal_added:237,always_active:1,sum:1})}</transition>
<transition in="0" out="${end}">${properties({a_track:0,b_track:2,mlt_service:'qtblend',internal_added:237,always_active:1})}</transition>
</tractor>
<playlist id="main_bin">${properties({'kdenlive:docproperties.documentid':Date.now(),'kdenlive:docproperties.uuid':uuid,'kdenlive:docproperties.version':'1.1','kdenlive:docproperties.kdenliveversion':'26.04.3','kdenlive:docproperties.profile':'atsc_1080p_30','kdenlive:docproperties.audioChannels':2,'kdenlive:docproperties.compositing':1,'kdenlive:docproperties.activetimeline':uuid,'kdenlive:docproperties.opensequences':uuid,'kdenlive:docproperties.guidesCategories':JSON.stringify([{color:'#adf0bc',comment:'Chapters',index:0}]),xml_retain:1})}<entry producer="video" in="0" out="${end}"/><entry producer="audio" in="0" out="${end}"/><entry producer="${uuid}" in="0" out="${end}"/></playlist>
<tractor id="project" in="0" out="${end}">${properties({'kdenlive:projectTractor':1})}<track producer="${uuid}" in="0" out="${end}"/></tractor>
</mlt>\n`;
  await writeFile(destination,xml,{flag:'wx'});
}
