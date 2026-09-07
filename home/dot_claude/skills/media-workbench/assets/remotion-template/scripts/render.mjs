import {bundle} from '@remotion/bundler';
import {renderMedia, renderStill, selectComposition} from '@remotion/renderer';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {makeScore} from './score.mjs';
import {verify} from './verify.mjs';
import {writeTimeline} from './timeline.mjs';

await mkdir('out',{recursive:true});
await makeScore(resolve('public/score.wav'));
const serveUrl=await bundle({entryPoint:resolve('src/index.jsx'),outDir:resolve('.cache/bundle')});
const composition=await selectComposition({serveUrl,id:'CreativeSystem'});
for(const frame of [100,340,580]) {
  await renderStill({serveUrl,composition,frame,output:resolve(`out/frame-${frame}.png`)});
}
if(!process.argv.includes('--stills')) {
  const output=resolve('out/creative-system.mp4');
  await renderMedia({serveUrl,composition,codec:'h264',audioCodec:'aac',pixelFormat:'yuv420p',colorSpace:'bt709',imageFormat:'png',crf:18,concurrency:4,outputLocation:output});
  const media=await verify(output);
  await writeTimeline(output,composition);
  const sourceFiles=['src/index.jsx','scripts/render.mjs','scripts/score.mjs','scripts/timeline.mjs','scripts/verify.mjs','package.json','package-lock.json'];
  const sourceHashes={};
  for(const file of sourceFiles) sourceHashes[file]=createHash('sha256').update(await readFile(file)).digest('hex');
  const editableTimeline='out/creative-system.kdenlive';
  const timelineSha256=createHash('sha256').update(await readFile(editableTimeline)).digest('hex');
  await writeFile('out/manifest.json',JSON.stringify({schemaVersion:1,createdAt:new Date().toISOString(),composition:composition.id,sourceHashes,media,sourceProject:process.cwd(),renderCommand:'npm run render',studioCommand:'npm run studio',editableTimeline,timelineSha256,notes:'Regenerate from project sources; animation is frame deterministic. Existing Kdenlive edits are preserved. Manifest confirms encoding, not playback review.'},null,2)+'\n');
  console.log(`Rendered and verified ${output}`);
}
