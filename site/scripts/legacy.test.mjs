import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { parseHTML } from 'linkedom';
import { fileURLToPath } from 'node:url';
import { preserveLegacyFragments } from './generate.mjs';

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(siteRoot, '..');

function outputFile(output, route) {
  return route === '/' ? path.join(output, 'index.html') : path.join(output, route.slice(1), 'index.html');
}

function ids(html) {
  return [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
}

test('adds only absent aliases at their mapped section or page top', () => {
  const inventory = {
    routes: {
      '/old.html': {
        target: '/new/',
        fragments: [
          { id: 'already-there', heading: 'Already there' },
          { id: 'old-section', heading: 'Removed section' },
          { id: 'old-page', heading: 'Old page title' },
        ],
      },
    },
    placements: { '/new/': { 'old-section': 'new-section' } },
  };
  const rendered = preserveLegacyFragments('## Already there\n\n## New section\n', '/new/', inventory);

  assert.doesNotMatch(rendered, /id="already-there"/);
  assert.match(rendered, /id="old-section"[^]*## New section/);
  assert.match(rendered, /^<div id="old-page"/);
});

test('every historical fragment resolves exactly once in the built destination', async () => {
  const output = process.env.DOCS_OUT_DIR || path.join(siteRoot, 'dist');
  const inventory = JSON.parse(await readFile(path.join(repoRoot, 'docs/_data/legacy-fragments.json'), 'utf8'));
  const failures = [];

  for (const [legacyRoute, entry] of Object.entries(inventory.routes)) {
    const file = outputFile(output, entry.target);
    const html = await readFile(file, 'utf8').catch(() => null);
    if (!html) {
      failures.push(`${legacyRoute}: missing built destination ${path.relative(repoRoot, file)}`);
      continue;
    }
    const counts = new Map();
    for (const id of ids(html)) counts.set(id, (counts.get(id) ?? 0) + 1);
    const { document } = parseHTML(html);
    for (const anchor of document.querySelectorAll('.legacy-fragment-anchor')) {
      if (anchor.parentElement?.tagName === 'P') failures.push(`${entry.target}#${anchor.id}: alias created an empty visible paragraph`);
    }
    for (const fragment of entry.fragments) {
      const count = counts.get(fragment.id) ?? 0;
      if (count !== 1) failures.push(`${legacyRoute}#${fragment.id}: expected one destination anchor, found ${count}`);
    }
  }

  assert.deepEqual(failures, []);
});
