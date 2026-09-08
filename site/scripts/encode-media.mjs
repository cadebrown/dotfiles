import fs from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';

const [input, output] = process.argv.slice(2);
if (!input || !output || !output.endsWith('.webp')) throw new Error('Usage: node scripts/encode-media.mjs INPUT OUTPUT.webp');
await fs.mkdir(path.dirname(output), { recursive: true });
await sharp(input).resize({ width: 1600, withoutEnlargement: true }).webp({ quality: 88, effort: 6 }).toFile(output);
const info = await sharp(output).metadata();
const { size } = await fs.stat(output);
if (size > 350 * 1024) throw new Error(`${output} exceeds the 350 KiB screenshot budget (${size} bytes). Use a more focused capture.`);
console.log(JSON.stringify({ file: output, width: info.width, height: info.height, bytes: size, format: 'webp' }, null, 2));
