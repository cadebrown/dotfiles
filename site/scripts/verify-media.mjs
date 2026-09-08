import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import sharp from 'sharp';

const site = fileURLToPath(new URL('../', import.meta.url));
const repo = path.resolve(site, '..');
const inventory = JSON.parse(await fs.readFile(path.join(repo, 'docs/_data/media.json'), 'utf8'));
const listed = new Set();
for (const record of inventory.images) {
  if (!record.file.startsWith('site/public/media/') || record.file.includes('..') || listed.has(record.file)) throw new Error(`Invalid or duplicate media source: ${record.file}`);
  listed.add(record.file);
  for (const field of ['route', 'capturedAt', 'source', 'capture', 'encoding', 'scope', 'sha256']) if (!record[field]) throw new Error(`${record.file} lacks provenance field ${field}`);
  const bytes = await fs.readFile(path.join(repo, record.file));
  const metadata = await sharp(bytes).metadata();
  const efficientFormat = metadata.format === 'webp' || (metadata.format === 'heif' && metadata.compression === 'av1');
  if (!efficientFormat || bytes.length > 350 * 1024) throw new Error(`${record.file}: use WebP/AVIF under 350 KiB`);
  if (record.bytes !== bytes.length || record.width !== metadata.width || record.height !== metadata.height || record.sha256 !== createHash('sha256').update(bytes).digest('hex')) throw new Error(`${record.file}: update provenance after recapturing or encoding the image`);
}
for (const file of await fs.readdir(path.join(site, 'public/media'))) {
  if (!listed.has(`site/public/media/${file}`)) throw new Error(`Media asset ${file} has no provenance record`);
}
console.log(`Media provenance verified: ${listed.size} screenshots, dimensions, sizes, and SHA-256 hashes.`);
