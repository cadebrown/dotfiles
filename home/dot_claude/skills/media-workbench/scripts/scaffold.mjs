import {cp, mkdir, readdir} from 'node:fs/promises';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const target = process.argv[2];
if (!target) throw new Error('Usage: node scaffold.mjs /absolute/output/project');
const output = resolve(target);
await mkdir(output, {recursive: true});
if ((await readdir(output)).length) throw new Error(`Destination must be empty: ${output}`);
await cp(resolve(dirname(fileURLToPath(import.meta.url)), '../assets/remotion-template'), output, {recursive: true});
console.log(`Created ${output}\nRun npm ci, npm run render, or npm run studio in that directory.`);
