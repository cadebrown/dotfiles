import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { verifyBootstrapSnippet, verifySite } from './verify.mjs';

const body = '<nav aria-label="Main"><a href="/">Fixture page</a></nav><main><h1 id="_top">Fixture page</h1><p>This is deliberately substantial rendered fixture content used to verify a documentation artifact without running Astro for every assertion.</p></main>';

async function write(file, content) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, content);
}

async function fixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'dotfiles-verify-test.'));
  const repo = path.join(root, 'repo');
  const site = path.join(root, 'site');
  const output = path.join(root, 'dist');
  await write(path.join(site, 'src/data/pages.json'), JSON.stringify([
    { route: '/', title: 'Fixture page', source: 'docs/page.md' },
  ]));
  await write(path.join(repo, 'docs/page.md'), '# Fixture page\n');
  await write(path.join(repo, 'docs/_data/features.json'), JSON.stringify({ features: [{
    id: 'fixture', page: '/', demo: 'fixture --check', sources: ['bootstrap.sh', 'install/auth.sh'],
  }] }));
  await write(path.join(repo, 'docs/_data/legacy-routes.json'), JSON.stringify({ '/old.html': '/' }));
  await write(path.join(repo, 'bootstrap.sh'), '#!/usr/bin/env bash\n');
  await write(path.join(repo, 'install/auth.sh'), '#!/usr/bin/env bash\n');
  await mkdir(path.join(repo, 'install/plat'), { recursive: true });
  await mkdir(path.join(repo, 'home/dot_local/bin'), { recursive: true });
  await mkdir(path.join(repo, 'packages'), { recursive: true });
  await write(path.join(repo, 'README.md'), '```sh\ncurl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | \\\n  DF_NAME="Fixture" DF_EMAIL="fixture@example.com" bash\n```\n');
  await write(path.join(repo, 'docs/setup/bootstrap.md'), '```sh\ncurl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | \\\n  DF_NAME="Fixture" DF_EMAIL="fixture@example.com" bash\n```\n');
  await write(path.join(output, 'index.html'), `<!doctype html><title>Fixture page</title>${body}`);
  await write(path.join(output, 'old.html'), '<!doctype html><title>Moved</title>');
  await write(path.join(output, '_redirects'), '/old.html / 301\n');
  await write(path.join(output, 'pagefind/pagefind.js'), '// fixture\n');
  await write(path.join(output, 'pagefind/pagefind-entry.json'), '{}\n');
  return { root, repo, site, output };
}

async function withFixture(run) {
  const value = await fixture();
  try { await run(value); } finally { await rm(value.root, { recursive: true, force: true }); }
}

function failures(report, check) {
  return report.failures.filter((failure) => failure.check === check).map((failure) => failure.message);
}

test('accepts a complete minimal rendered documentation artifact', async () => {
  await withFixture(async ({ repo, site, output }) => {
    const report = await verifySite({ repo, site, output });
    assert.deepEqual(report.failures, []);
  });
});

test('rejects an authored page omitted from navigation while allowing explicitly hidden pages', async () => {
  await withFixture(async ({ repo, site, output }) => {
    await write(path.join(output, 'index.html'), `<!doctype html><title>Fixture page</title>${body.replace(/<nav[^]*?<\/nav>/, '')}`);
    const report = await verifySite({ repo, site, output });
    assert.equal(failures(report, 'navigation').length, 1);
    await write(path.join(site, 'src/data/pages.json'), JSON.stringify([{ route: '/', title: 'Fixture page', source: 'docs/page.md', hidden: true }]));
    const hidden = await verifySite({ repo, site, output });
    assert.deepEqual(failures(hidden, 'navigation'), []);
  });
});

test('detects a missing route and an unresolved link fragment', async () => {
  await withFixture(async ({ repo, site, output }) => {
    await rm(path.join(output, 'index.html'));
    let report = await verifySite({ repo, site, output });
    assert.ok(failures(report, 'route').some((message) => message.includes('no rendered')));

    await write(path.join(output, 'index.html'), `<!doctype html><title>Fixture page</title>${body}<a href="#missing">broken</a><a href="/absent/">missing route</a>`);
    report = await verifySite({ repo, site, output });
    assert.ok(failures(report, 'fragment').some((message) => message.includes('#missing')));
    assert.ok(failures(report, 'link').some((message) => message.includes('/absent/')));
  });
});

test('detects missing and duplicate feature sources plus a missing legacy artifact', async () => {
  await withFixture(async ({ repo, site, output }) => {
    const features = path.join(repo, 'docs/_data/features.json');
    await write(features, JSON.stringify({ features: [{ id: 'fixture', page: '/', demo: 'fixture --check', sources: ['bootstrap.sh', 'install/missing.sh'] }] }));
    let report = await verifySite({ repo, site, output });
    assert.ok(failures(report, 'feature').some((message) => message.includes('install/missing.sh')));
    assert.ok(failures(report, 'feature-coverage').some((message) => message.includes('install/auth.sh')));

    await write(features, JSON.stringify({ features: [{ id: 'fixture', page: '/', demo: 'fixture --check', sources: ['bootstrap.sh', 'bootstrap.sh', 'install/auth.sh'] }] }));
    await rm(path.join(output, 'old.html'));
    report = await verifySite({ repo, site, output });
    assert.ok(failures(report, 'feature-coverage').some((message) => message.includes('bootstrap.sh') && message.includes('found 2')));
    assert.ok(failures(report, 'redirect').some((message) => message.includes('/old.html')));
  });
});

test('requires new package and managed-home sources to be mapped exactly once', async () => {
  await withFixture(async ({ repo, site, output }) => {
    await write(path.join(repo, 'packages/new-tool.txt'), 'new-tool\n');
    await write(path.join(repo, 'home/dot_config/example/config'), 'enabled = true\n');
    const report = await verifySite({ repo, site, output });

    assert.ok(failures(report, 'feature-coverage').some((message) => message.includes('packages/new-tool.txt')));
    assert.ok(failures(report, 'feature-coverage').some((message) => message.includes('home/dot_config/example/config')));
  });
});

test('rejects bootstrap variables assigned to curl instead of downstream bash', () => {
  const report = { checks: {}, failures: [] };
  verifyBootstrapSnippet('```sh\nDF_NAME=wrong curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | bash\n```', 'unsafe fixture', report);
  assert.equal(report.failures.length, 1);
  assert.equal(report.failures[0].check, 'bootstrap-snippet');
});

test('rejects a malformed bootstrap snippet without executing it', () => {
  const report = { checks: {}, failures: [] };
  verifyBootstrapSnippet('```sh\ncurl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | DF_NAME=x bash -s -- "unterminated\n```', 'malformed fixture', report);
  assert.deepEqual(failures(report, 'bootstrap-snippet'), ['malformed fixture has invalid shell syntax']);
});

test('accepts a multiline pipeline with assignments attached to downstream bash', () => {
  const report = { checks: {}, failures: [] };
  verifyBootstrapSnippet('```bash\ncurl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | \\\n  DF_NAME="Fixture Name" \\\n  DF_EMAIL="fixture@example.com" bash -s --\n```', 'valid fixture', report);
  assert.deepEqual(report.failures, []);
});
