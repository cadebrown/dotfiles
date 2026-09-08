#!/usr/bin/env node
import {cp, lstat, readdir} from 'node:fs/promises';
import {basename, dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const targetArgument = process.argv[2];
if (!targetArgument) {
  throw new Error('Usage: node scaffold.mjs /absolute/output/mission-control');
}

const target = resolve(targetArgument);
const source = resolve(dirname(fileURLToPath(import.meta.url)), '../assets/mission-control');

try {
  const entries = await readdir(target);
  if (entries.length) {
    throw new Error(`Refusing to overwrite non-empty directory: ${target}`);
  }
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

await cp(source, target, {
  recursive: true,
  filter: path => !['node_modules', 'test-results', 'playwright-report'].includes(basename(path))
});
const stat = await lstat(target);
if (!stat.isDirectory()) throw new Error(`Scaffold target is not a directory: ${target}`);
process.stdout.write(`WebMCP Mission Control created at ${target}\n`);
