import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse, stringify } from 'yaml';
import Slugger from 'github-slugger';
import { unified } from 'unified';
import remarkParse from 'remark-parse';
import { visit } from 'unist-util-visit';
import { generateCatalog } from './catalog.mjs';

export const siteRoot = fileURLToPath(new URL('../', import.meta.url));
export const repoRoot = path.resolve(siteRoot, '..');
const docsRoot = path.join(repoRoot, 'docs');
const output = path.join(siteRoot, 'src/content/docs');

export async function walk(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const name = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(name) : [name];
  }));
  return files.flat().sort();
}

export function readMarkdown(text) {
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n/);
  return { data: match ? parse(match[1]) ?? {} : {}, body: match ? text.slice(match[0].length) : text };
}

export function slugify(text) {
  return text.toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-');
}

function nodeText(node) {
  return (node.children ?? []).map((child) => child.value ?? nodeText(child)).join('');
}

export function markdownHeadings(markdown) {
  const headings = [];
  const slugger = new Slugger();
  visit(unified().use(remarkParse).parse(markdown), 'heading', (node) => {
    const text = nodeText(node);
    headings.push({ text, id: slugger.slug(text), offset: node.position.start.offset });
  });
  return headings;
}

function legacyAnchor(id) {
  return `<div id="${id}" class="legacy-fragment-anchor" aria-hidden="true"></div>`;
}

export function preserveLegacyFragments(body, route, inventory) {
  const fragments = Object.values(inventory.routes)
    .filter((entry) => entry.target === route)
    .flatMap((entry) => entry.fragments);
  if (!fragments.length) return body;

  const headings = markdownHeadings(body);
  const existing = new Set(['_top', ...headings.map((heading) => heading.id)]);
  const missing = fragments.filter((fragment) => !existing.has(fragment.id));
  if (!missing.length) return body;

  const insertions = new Map();
  const atTop = [];
  for (const fragment of missing) {
    const target = inventory.placements?.[route]?.[fragment.id];
    const heading = headings.find((candidate) => candidate.id === target || candidate.text === fragment.heading);
    if (heading) {
      const aliases = insertions.get(heading.offset) ?? [];
      aliases.push(legacyAnchor(fragment.id));
      insertions.set(heading.offset, aliases);
    } else {
      atTop.push(legacyAnchor(fragment.id));
    }
  }

  let rendered = body;
  for (const [offset, aliases] of [...insertions.entries()].sort(([left], [right]) => right - left)) {
    rendered = `${rendered.slice(0, offset)}${aliases.join('\n')}\n\n${rendered.slice(offset)}`;
  }
  return atTop.length ? `${atTop.join('\n')}\n\n${rendered}` : rendered;
}

async function writeChanged(file, text) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  if (await fs.readFile(file, 'utf8').catch(() => '') !== text) await fs.writeFile(file, text);
}

export async function generate() {
  const files = (await walk(docsRoot)).filter((file) => {
    const relative = path.relative(docsRoot, file);
    return /\.mdx?$/.test(file) && !relative.split(path.sep).some((p) => p.startsWith('_') || p === 'book') && !['AGENTS.md', 'SUMMARY.md'].includes(path.basename(file));
  });
  const pages = [];
  const outputs = new Set();
  const legacyFragments = JSON.parse(await fs.readFile(path.join(docsRoot, '_data/legacy-fragments.json'), 'utf8'));
  async function emit(relative, data, body, source) {
    const slug = relative.replace(/\.mdx?$/, '').replace(/^intro$/, 'index').replace(/(^|\/)README$/i, '$1index');
    const target = path.join(output, `${slug}${relative.endsWith('.mdx') ? '.mdx' : '.md'}`);
    outputs.add(target);
    const frontmatter = { ...data, editUrl: data.editUrl ?? `https://github.com/cadebrown/dotfiles/edit/main/docs/${source}` };
    const route = `/${slug.replace(/(^|\/)index$/, '$1')}`.replace(/\/$/, '') + '/';
    const preservedBody = preserveLegacyFragments(body.trim(), route, legacyFragments);
    await writeChanged(target, `---\n${stringify(frontmatter)}---\n\n${preservedBody}\n`);
    pages.push({ slug, title: data.title, description: data.description ?? '', source: `docs/${source}`, route, generated: source !== relative, hidden: data.sidebar?.hidden === true });
  }
  for (const file of files) {
    const relative = path.relative(docsRoot, file).split(path.sep).join('/');
    const { data, body: rawBody } = readMarkdown(await fs.readFile(file, 'utf8'));
    const heading = rawBody.match(/^# (.+)\r?\n/);
    const title = data.title ?? heading?.[1] ?? path.basename(file, '.md');
    const body = heading ? rawBody.slice(heading[0].length) : rawBody;
    const firstParagraph = body.trim().split(/\n\s*\n/).find((p) => /^[A-Za-z[]/.test(p)) ?? `${title}: configuration, commands, operating examples, and source references for the dotfiles setup.`;
    const frontmatter = { title, description: firstParagraph.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1').replace(/[`*_\n]/g, ' ').slice(0, 175), ...data };
    if (relative === 'usage/troubleshooting.md') {
      frontmatter.pagefind = false;
      frontmatter.sidebar = { hidden: true };
      const sections = [...body.matchAll(/^## (.+)\n([\s\S]*?)(?=^## |$(?![\s\S]))/gm)];
      for (const [, sectionTitle, sectionBody] of sections) {
        const slug = slugify(sectionTitle);
        // Both source and destination are one level below docs/. Unqualified sibling
        // links still need the original usage/ directory after splitting a diagnosis.
        const adjusted = sectionBody.replace(/\]\((?![a-z]+:|\/|#|\.\.\/)([^)]+\.md(?:#[^)]*)?)\)/g, '](/usage/$1)');
        await emit(`troubleshooting/${slug}.md`, { title: sectionTitle, description: `Diagnose and resolve: ${sectionTitle}. Confirmation steps, root cause, and a targeted fix.`, sidebar: { hidden: true } }, `Source: [Troubleshooting reference](/usage/troubleshooting/#${slug})\n\n${adjusted}`, relative);
      }
    }
    await emit(relative, frontmatter, body, relative);
  }
  const trouble = pages.filter((p) => p.slug.startsWith('troubleshooting/'));
  if (trouble.length) {
    const categories = [
      ['Build & CI', /\bCI\b|Cloudflare Pages|Docker bootstrap|ShellCheck/i],
      ['Memory & search', /\bcass\b|\bqmd\b/i],
      ['Shared homes & storage', /shared home|symlinked|PLAT|\.nfs|EBUSY/i],
      ['Editors & desktop', /Cursor|VS Code|GUI app|Mac App Store/i],
      ['Agents & integrations', /agent|Codex|Claude|OpenCode|MCP|skill|Playwright|tool responses/i],
      ['Shell & PATH', /PATH|shell|nvm|node.*script|chezmoi|SSH session|Colima|completion/i],
      ['Packages & runtimes', /./],
    ];
    const grouped = new Map(categories.map(([label]) => [label, []]));
    for (const page of trouble) {
      const [label] = categories.find(([, pattern]) => pattern.test(page.title));
      grouped.get(label).push(page);
    }
    await emit('troubleshooting/index.md', { title: 'Troubleshooting', description: 'Find a symptom, understand its root cause, verify the diagnosis, and apply a targeted fix.' },
      `Search an exact error message or choose an area below. Each diagnosis includes a cause, confirmation commands, and a fix. [Full reference](/usage/troubleshooting/)\n\n## Diagnosis index\n\n${[...grouped].filter(([, entries]) => entries.length).map(([label, entries]) => `### ${label}\n\n${entries.map((p) => `- [${p.title}](${p.route})`).join('\n')}`).join('\n\n')}`, 'usage/troubleshooting.md');
  }
  await generateCatalog({ repoRoot, siteRoot });
  for (const name of ['packages', 'skills', 'mcp', 'features']) {
    const file = path.join(output, 'reference', `${name}.md`);
    outputs.add(file);
    const { data } = readMarkdown(await fs.readFile(file, 'utf8'));
    pages.push({ slug: `reference/${name}`, route: `/reference/${name}/`, title: data.title, description: data.description, source: 'site/scripts/catalog.mjs', generated: true });
  }
  await fs.mkdir(output, { recursive: true });
  for (const old of await walk(output)) if (!outputs.has(old)) await fs.unlink(old);
  await writeChanged(path.join(siteRoot, 'src/data/pages.json'), JSON.stringify(pages, null, 2) + '\n');
  const redirects = JSON.parse(await fs.readFile(path.join(docsRoot, '_data/legacy-routes.json'), 'utf8'));
  await writeChanged(path.join(siteRoot, 'src/data/redirects.json'), JSON.stringify(redirects, null, 2) + '\n');
  await writeChanged(path.join(siteRoot, 'public/_redirects'), Object.entries(redirects).map(([from, to]) => `${from} ${to} 301`).join('\n') + '\n');
  await writeChanged(path.join(siteRoot, 'public/llms.txt'), `# Cade's Dotfiles\n\nSetup, configuration, and workflow guides for Cade's macOS and Linux environment. Generated from the website's Markdown; configuration declarations do not establish live service access.\n\n${pages.filter((p) => !p.generated).map((p) => `- [${p.title}](https://dotfiles.cade.io${p.route}): ${p.description}`).join('\n')}\n`);
  const performanceFile = path.join(docsRoot, '_data/performance.json');
  await writeChanged(path.join(siteRoot, 'public/evidence/performance.json'), await fs.readFile(performanceFile, 'utf8'));
  console.log(`Generated ${pages.length} documentation pages from ${files.length} Markdown sources.`);
  return pages;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await generate();
