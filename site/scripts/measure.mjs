import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawn, execFileSync } from 'node:child_process';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';

const site = fileURLToPath(new URL('../', import.meta.url));
const repo = path.resolve(site, '..');
const runsIndex = process.argv.indexOf('--runs');
const runs = runsIndex < 0 ? 3 : Number(process.argv[runsIndex + 1]);
if (!Number.isInteger(runs) || runs < 3 || runs > 10) throw new Error('Use --runs 3 through --runs 10 for a small repeated measurement.');
const artifacts = path.join(site, 'artifacts');
await fs.mkdir(artifacts, { recursive: true });
async function walk(directory) {
  const files = [];
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    if (['node_modules', 'dist', '.astro', 'artifacts', 'book'].includes(entry.name)) continue;
    const target = path.join(directory, entry.name);
    files.push(...entry.isDirectory() ? await walk(target) : [target]);
  }
  return files.sort();
}
const digest = createHash('sha256');
const inputs = [
  ...await walk(path.join(repo, 'docs')),
  ...await walk(path.join(repo, 'packages')),
  ...await walk(path.join(repo, 'home/dot_claude/skills')),
  ...await walk(path.join(site, 'src')),
  ...await walk(path.join(site, 'scripts')),
  ...await walk(path.join(site, 'public')),
  ...['astro.config.mjs', 'package.json', 'package-lock.json', 'tsconfig.json'].map((file) => path.join(site, file)),
].filter((file) => !file.includes('/src/content/docs/') && !file.includes('/src/data/') && !file.includes('/public/evidence/') && !file.endsWith('/performance.json') && !file.endsWith('/public/llms.txt') && !file.endsWith('/public/_redirects')).sort();
for (const file of inputs) {
  const bytes = await fs.readFile(file);
  digest.update(path.relative(repo, file)).update('\0').update(String(bytes.length)).update('\0').update(bytes);
}
const samples = [];
for (let index = 0; index < runs; index++) {
  const log = await fs.open(path.join(artifacts, `measure-build-${index + 1}.log`), 'w');
  const start = performance.now();
  const result = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [path.join(site, 'node_modules/astro/bin/astro.mjs'), 'build'], { cwd: site, env: { ...process.env, DOCS_OUT_DIR: path.join(site, 'dist') }, stdio: ['ignore', log.fd, log.fd] });
    child.on('error', reject);
    child.on('exit', (code) => resolve(code));
  });
  const elapsed = performance.now() - start;
  await log.close();
  if (result !== 0) throw new Error(`Measured build ${index + 1} failed (${result}). See artifacts/measure-build-${index + 1}.log; previous measurements were not overwritten.`);
  samples.push(Number(elapsed.toFixed(1)));
  console.log(`Build ${index + 1}/${runs}: ${(elapsed / 1000).toFixed(2)} s`);
}
const pages = [];
for (const route of ['/', '/architecture/overview/', '/agents/codex/', '/reference/packages/', '/reference/skills/', '/setup/choose-your-setup/']) {
  const html = await fs.readFile(path.join(site, 'dist', route, 'index.html'));
  pages.push({ route, htmlBytes: html.byteLength, gzipBytes: gzipSync(html, { level: 9 }).byteLength });
}
const ordered = [...samples].sort((a,b) => a-b);
const data = {
  schemaVersion: 1,
  capturedAt: new Date().toISOString(),
  command: `npm --prefix site run measure -- --runs ${runs}`,
  environment: { platform: os.platform(), architecture: os.arch(), cpu: os.cpus()[0]?.model ?? 'unavailable', logicalCpus: os.cpus().length, node: process.version },
  revision: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repo, encoding: 'utf8' }).trim(),
  workingTreeDirty: Boolean(execFileSync('git', ['status', '--porcelain'], { cwd: repo, encoding: 'utf8' }).trim()),
  sourceSha256: digest.digest('hex'),
  method: 'Three or more sequential local production builds with dependencies and Chromium already installed. The link validator invalidates the content cache on each build. Other host workloads were not isolated. HTML bytes and gzip-9 bytes come from the final measured artifact; gzip values are a transfer-size estimate, not observed HTTP payloads.',
  limitations: 'This is a local build and artifact snapshot, not a Core Web Vitals, network, shell startup, model inference, CI, deployment, or physical-device benchmark. The source fingerprint excludes this measurement file and generated staging data to avoid a self-reference.',
  build: { samplesMs: samples, medianMs: (ordered[Math.floor((ordered.length - 1) / 2)] + ordered[Math.floor(ordered.length / 2)]) / 2, minimumMs: ordered[0], maximumMs: ordered.at(-1) },
  pages,
};
await fs.writeFile(path.join(repo, 'docs/_data/performance.json'), JSON.stringify(data, null, 2) + '\n');
console.log(`Saved measured snapshot: median ${(data.build.medianMs / 1000).toFixed(2)} s; ${pages.length} page payloads.`);
