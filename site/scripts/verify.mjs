import { access, mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseHTML } from 'linkedom';
import { spawnSync } from 'node:child_process';

const siteRoot = fileURLToPath(new URL('../', import.meta.url));
const repoRoot = path.resolve(siteRoot, '..');
const outputRoot = path.resolve(process.env.DOCS_OUT_DIR || path.join(siteRoot, 'dist'));
const githubPrefix = 'https://github.com/cadebrown/dotfiles/';
const textLength = (value) => (value ?? '').replace(/\s+/g, ' ').trim().length;

async function exists(file) {
  try { await access(file); return true; } catch { return false; }
}

async function filesUnder(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map((entry) => {
    const target = path.join(directory, entry.name);
    return entry.isDirectory() ? filesUnder(target) : [target];
  }));
  return files.flat();
}

function addFailure(report, check, message) {
  report.failures.push({ check, message });
}

function routeToFile(route, output = outputRoot) {
  const cleaned = route.replace(/^\//, '').replace(/\?.*$/, '');
  if (cleaned === '404' || cleaned === '404/') return path.join(output, '404.html');
  return path.join(output, cleaned, 'index.html');
}

function localPathFromHref(href, sourceFile, output = outputRoot) {
  const url = new URL(href, `https://dotfiles.cade.io/${path.relative(output, sourceFile).replace(/index\.html$/, '')}`);
  if (url.origin !== 'https://dotfiles.cade.io') return null;
  const pathname = decodeURIComponent(url.pathname);
  if (pathname.endsWith('/')) return { file: routeToFile(pathname, output), hash: url.hash.slice(1) };
  const direct = path.join(output, pathname.replace(/^\//, ''));
  if (path.extname(pathname)) return { file: direct, hash: url.hash.slice(1) };
  return { file: routeToFile(pathname, output), hash: url.hash.slice(1) };
}

function isExternal(href) {
  if (!/^(?:[a-z][a-z\d+.-]*:|\/\/)/i.test(href)) return false;
  try { return new URL(href, 'https://dotfiles.cade.io').origin !== 'https://dotfiles.cade.io'; } catch { return true; }
}

async function documentFor(file, cache) {
  if (!cache.has(file)) {
    const text = await readFile(file, 'utf8');
    cache.set(file, parseHTML(text).document);
  }
  return cache.get(file);
}

async function sourceLineCount(file, cache) {
  if (!cache.has(file)) cache.set(file, (await readFile(file, 'utf8')).split(/\r?\n/).length);
  return cache.get(file);
}

function githubSource(href) {
  if (!href.startsWith(githubPrefix)) return null;
  const match = href.match(/^https:\/\/github\.com\/cadebrown\/dotfiles\/(?:blob|edit)\/main\/([^#]+)(?:#L(\d+))?$/);
  return match ? { source: decodeURIComponent(match[1]), line: match[2] ? Number(match[2]) : null } : null;
}

async function verifyPages(report, pages, output) {
  const docs = new Map();
  for (const page of pages) {
    const file = routeToFile(page.route, output);
    if (!await exists(file)) {
      addFailure(report, 'route', `${page.route} (${page.source}) has no rendered ${path.relative(output, file)}`);
      continue;
    }
    const document = await documentFor(file, docs);
    const title = document.querySelector('title')?.textContent;
    const h1 = document.querySelector('main h1');
    const main = document.querySelector('main');
    if (!title || !h1 || !main || textLength(main.textContent) < 80) {
      addFailure(report, 'route', `${page.route} lacks a substantive title, h1, or main content`);
    }
    if (!page.generated && !page.hidden) {
      const links = [...document.querySelectorAll('nav[aria-label="Main"] a[href]')];
      if (!links.some((link) => link.getAttribute('href') === page.route)) {
        addFailure(report, 'navigation', `${page.route} has no main navigation entry; add it to site/src/navigation.mjs`);
      }
    }
  }
  report.checks.routes = { expected: pages.length, rendered: pages.filter((page) => docs.has(routeToFile(page.route, output))).length };
  return docs;
}

async function verifyLinks(report, output, root) {
  const htmlFiles = (await filesUnder(output)).filter((file) => file.endsWith('.html'));
  const docs = new Map();
  const sourceLines = new Map();
  for (const file of htmlFiles) {
    const document = await documentFor(file, docs);
    for (const element of document.querySelectorAll('[href], [src]')) {
      const value = element.getAttribute('href') ?? element.getAttribute('src');
      if (!value || value.startsWith('data:') || value.startsWith('mailto:') || value.startsWith('tel:') || value.startsWith('javascript:')) continue;
      const source = githubSource(value);
      if (source) {
        const target = path.resolve(root, source.source);
        if (!target.startsWith(`${root}${path.sep}`) || !await exists(target)) {
          addFailure(report, 'source-link', `${path.relative(output, file)} links missing repository source ${source.source}`);
        } else if (source.line && (source.line < 1 || source.line > await sourceLineCount(target, sourceLines))) {
          addFailure(report, 'source-link', `${path.relative(output, file)} links ${source.source}#L${source.line} outside file bounds`);
        }
        continue;
      }
      if (isExternal(value)) continue;
      const target = localPathFromHref(value, file, output);
      if (!target) continue;
      if (!await exists(target.file)) {
        addFailure(report, 'link', `${path.relative(output, file)} → ${value} is missing (${path.relative(output, target.file)})`);
        continue;
      }
      if (target.hash) {
        const targetDocument = await documentFor(target.file, docs);
        const fragment = decodeURIComponent(target.hash);
        if (!targetDocument.getElementById(fragment)) {
          addFailure(report, 'fragment', `${path.relative(output, file)} → ${value} has no #${fragment}`);
        }
      }
    }
  }
  report.checks.links = { htmlFiles: htmlFiles.length, checked: true };
}

async function verifyFeatures(report, output, root) {
  const manifest = JSON.parse(await readFile(path.join(root, 'docs/_data/features.json'), 'utf8'));
  const features = manifest.features;
  const sourceCounts = new Map();
  for (const feature of features) {
    if (!feature.page || !await exists(routeToFile(feature.page, output))) addFailure(report, 'feature', `${feature.id} targets missing route ${feature.page}`);
    if (typeof feature.demo !== 'string' || !feature.demo.trim()) addFailure(report, 'feature', `${feature.id} has no demo or check`);
    for (const source of feature.sources ?? []) {
      sourceCounts.set(source, (sourceCounts.get(source) ?? 0) + 1);
      const target = path.resolve(root, source);
      if (!target.startsWith(`${root}${path.sep}`) || !await exists(target)) addFailure(report, 'feature', `${feature.id} names missing source ${source}`);
    }
  }
  const required = [...new Set([
    'bootstrap.sh',
    ...(await readdir(path.join(root, 'install'), { withFileTypes: true }))
      .filter((entry) => entry.isFile() && /\.(sh|py)$/.test(entry.name)).map((entry) => `install/${entry.name}`),
    ...(await filesUnder(path.join(root, 'install/plat'))).filter((file) => file.endsWith('.sh')).map((file) => path.relative(root, file)),
    ...(await readdir(path.join(root, 'home/dot_local/bin'))).filter((name) => name.startsWith('executable_')).map((name) => `home/dot_local/bin/${name}`),
    ...(await filesUnder(path.join(root, 'packages'))).map((file) => path.relative(root, file)),
    ...(await filesUnder(path.join(root, 'home')))
      .filter((file) => {
        const relative = path.relative(path.join(root, 'home'), file).split(path.sep).join('/');
        return path.basename(file) !== 'AGENTS.md' && !relative.startsWith('dot_claude/skills/') && !relative.includes('/__pycache__/');
      })
      .map((file) => path.relative(root, file)),
  ])];
  for (const source of required) {
    const count = sourceCounts.get(source) ?? 0;
    if (count !== 1) addFailure(report, 'feature-coverage', `${source} must be mapped exactly once; found ${count}`);
  }
  report.checks.features = { features: features.length, requiredSources: required.length };
}

async function verifyRedirects(report, output, root) {
  const legacy = JSON.parse(await readFile(path.join(root, 'docs/_data/legacy-routes.json'), 'utf8'));
  const redirects = await readFile(path.join(output, '_redirects'), 'utf8').catch(() => '');
  for (const [from, to] of Object.entries(legacy)) {
    const legacyFile = path.join(output, from.replace(/^\//, ''));
    if (!await exists(legacyFile)) addFailure(report, 'redirect', `${from} has no legacy HTML file`);
    if (!redirects.split(/\r?\n/).includes(`${from} ${to} 301`)) addFailure(report, 'redirect', `${from} → ${to} is missing from _redirects`);
  }
  const pagefind = path.join(output, 'pagefind');
  if (!await exists(path.join(pagefind, 'pagefind.js')) || !await exists(path.join(pagefind, 'pagefind-entry.json'))) {
    addFailure(report, 'pagefind', 'Pagefind JavaScript or index metadata is absent');
  }
  report.checks.redirects = { legacyRoutes: Object.keys(legacy).length };
}

async function verifyAssetsAndAccessibility(report, output) {
  const files = await filesUnder(output);
  for (const file of files) {
    const relative = path.relative(output, file);
    const ext = path.extname(file).toLowerCase();
    const size = (await stat(file)).size;
    const name = path.basename(file).toLowerCase();
    if (['.png', '.jpg', '.jpeg'].includes(ext) && !name.startsWith('favicon.')) addFailure(report, 'asset', `${relative} is a shipped raster; use WebP or AVIF`);
    if (['.webp', '.avif'].includes(ext) && size > 350 * 1024) addFailure(report, 'asset', `${relative} exceeds the 350 KiB screenshot budget`);
    if (ext === '.svg' && size > 250 * 1024) addFailure(report, 'asset', `${relative} exceeds the 250 KiB SVG budget`);
  }
  const htmlFiles = files.filter((file) => file.endsWith('.html'));
  for (const file of htmlFiles) {
    const document = await documentFor(file, new Map());
    for (const image of document.querySelectorAll('main img')) {
      if (!image.hasAttribute('alt')) addFailure(report, 'accessibility', `${path.relative(output, file)} has image without alt text`);
      if (!image.hasAttribute('width') || !image.hasAttribute('height')) addFailure(report, 'accessibility', `${path.relative(output, file)} has image without explicit dimensions`);
    }
    // Starlight adds decorative controls to main. Mermaid is the generated
    // figure contract: its root carries the flowchart class and an id prefix.
    for (const svg of document.querySelectorAll('main svg.flowchart, main svg[id^="mermaid-"]')) {
      if (svg.getAttribute('aria-hidden') === 'true') continue;
      const labelledBy = svg.getAttribute('aria-labelledby');
      const title = svg.querySelector('title');
      const validLabel = labelledBy && labelledBy.split(/\s+/).every((id) => document.getElementById(id));
      if (!title && !validLabel) addFailure(report, 'accessibility', `${path.relative(output, file)} has SVG without title or valid aria-labelledby`);
    }
  }
  report.checks.assets = { files: files.length, htmlFiles: htmlFiles.length };
}

function extractBootstrapSnippet(text) {
  return [...text.matchAll(/```(?:sh|bash)?\s*\n([\s\S]*?)```/g)].map((match) => match[1]).find((snippet) => snippet.includes('raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh'));
}

function shellWords(source) {
  const words = [];
  let word = '';
  let quote = null;
  const push = () => {
    if (word) words.push(word);
    word = '';
  };
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (character === '\\') {
      const next = source[index + 1];
      if (next === '\n') { index += 1; continue; }
      if (next !== undefined) { word += next; index += 1; continue; }
    }
    if (quote) {
      if (character === quote) quote = null;
      else word += character;
      continue;
    }
    if (character === "'" || character === '"') { quote = character; continue; }
    if (/\s/.test(character)) { push(); continue; }
    word += character;
  }
  push();
  return words;
}

function pipelineSides(source) {
  let quote = null;
  let start = 0;
  const sides = [];
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (character === '\\') {
      index += 1;
      continue;
    }
    if (quote) {
      if (character === quote) quote = null;
      continue;
    }
    if (character === "'" || character === '"') { quote = character; continue; }
    if (character === '|') {
      if (source[index - 1] === '|' || source[index + 1] === '|' || source[index + 1] === '&') return null;
      sides.push(source.slice(start, index));
      start = index + 1;
    }
  }
  sides.push(source.slice(start));
  return sides.length === 2 ? sides : null;
}

function isDfAssignment(word) {
  return /^DF_[A-Z0-9_]+=.*/.test(word);
}

export function verifyBootstrapSnippet(text, label, report) {
  const snippet = extractBootstrapSnippet(text);
  if (!snippet) return addFailure(report, 'bootstrap-snippet', `${label} has no bootstrap pipe example`);
  // `-n` parses the actual extracted example but does not evaluate substitutions,
  // start a pipeline, download the bootstrap script, or execute its input.
  const syntax = spawnSync('bash', ['--noprofile', '--norc', '-n', '-c', snippet], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH || '/usr/bin:/bin', BASH_ENV: '/dev/null', HOME: '/' },
  });
  if (syntax.status !== 0) {
    addFailure(report, 'bootstrap-snippet', `${label} has invalid shell syntax`);
    return;
  }
  const sides = pipelineSides(snippet);
  if (!sides) {
    addFailure(report, 'bootstrap-snippet', `${label} must use one curl-to-bash pipeline`);
    return;
  }
  const [upstream, downstream] = sides.map(shellWords);
  const bashIndex = downstream.indexOf('bash');
  const downstreamAssignments = downstream.slice(0, bashIndex);
  if (!upstream.includes('curl') || upstream.some(isDfAssignment) || bashIndex < 1
    || !downstreamAssignments.every(isDfAssignment) || !downstreamAssignments.some(isDfAssignment)) {
    addFailure(report, 'bootstrap-snippet', `${label} must assign DF_* variables to downstream bash, after the pipe`);
    return;
  }
}

async function verifyBootstrapSnippets(report, root) {
  for (const source of ['README.md', 'docs/setup/bootstrap.md']) {
    verifyBootstrapSnippet(await readFile(path.join(root, source), 'utf8'), source, report);
  }
}

export async function verifySite({ repo = repoRoot, site = siteRoot, output = outputRoot } = {}) {
  const report = { output: path.relative(repo, output) || '.', checkedAt: new Date().toISOString(), checks: {}, failures: [] };
  if (!await exists(output)) {
    addFailure(report, 'artifact', `output directory does not exist: ${output}`);
    return report;
  }
  const pages = JSON.parse(await readFile(path.join(site, 'src/data/pages.json'), 'utf8'));
  await verifyPages(report, pages, output);
  await verifyLinks(report, output, repo);
  await verifyFeatures(report, output, repo);
  await verifyRedirects(report, output, repo);
  await verifyAssetsAndAccessibility(report, output);
  await verifyBootstrapSnippets(report, repo);
  return report;
}

async function main() {
  const report = await verifySite();
  const artifactDir = path.join(siteRoot, 'artifacts');
  await mkdir(artifactDir, { recursive: true });
  await writeFile(path.join(artifactDir, 'verification.json'), `${JSON.stringify(report, null, 2)}\n`);
  if (report.failures.length) {
    for (const failure of report.failures) console.error(`[${failure.check}] ${failure.message}`);
    console.error(`Documentation verification failed with ${report.failures.length} issue(s). Full report: site/artifacts/verification.json`);
    process.exitCode = 1;
  } else {
    console.log(`Documentation verification passed: ${report.checks.routes.expected} routes, ${report.checks.features.features} features, ${report.checks.assets.htmlFiles} HTML files.`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
