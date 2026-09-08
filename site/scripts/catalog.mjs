import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { parse as parseYaml } from 'yaml';
import Slugger from 'github-slugger';

const repositoryUrl = 'https://github.com/cadebrown/dotfiles/blob/main/';
const packageManagers = new Map([
  ['cargo.txt', 'cargo'], ['go.txt', 'go'], ['npm.txt', 'npm'],
  ['pip.txt', 'uv-tool'], ['pip-full.txt', 'uv-tool'], ['python.txt', 'python-library'],
  ['mlx-models.txt', 'mlx-model'], ['cursor-extensions.txt', 'cursor-extension'],
  ['vscode-extensions.txt', 'vscode-extension'], ['codex-plugins.txt', 'codex-plugin'],
  ['claude-plugins.txt', 'claude-plugin'],
]);

const markdownEscape = (value = '') => String(value).replaceAll('|', '\\|').replaceAll('\n', ' ');
const sourceUrl = (source, line) => `${repositoryUrl}${source}${line ? `#L${line}` : ''}`;
const htmlEscape = (value) => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const entryLink = (record) => `<a id="${record.anchor}" class="catalog-entry" href="#${record.anchor}"><code>${htmlEscape(record.name)}</code></a>`;
function anchorRecords(records, prefix) {
  const slugger = new Slugger();
  for (const record of records) record.anchor = slugger.slug(`${prefix ? `${record[prefix]}-` : ''}${record.name}`);
}
const stable = (records) => records.sort((left, right) =>
  left.name.localeCompare(right.name) || left.source.localeCompare(right.source) || left.line - right.line,
);

async function lines(file) {
  return (await readFile(file, 'utf8')).split(/\r?\n/);
}

function commentDescription(comments) {
  const description = comments.filter((comment) => !/^#+/.test(comment)).join(' ')
    .replace(/^#+\s*/, '').replace(/\s+/g, ' ').trim();
  return description.length > 360 ? '' : description;
}

function platformFrom(line) {
  if (/macos-only|OS\.mac\?/.test(line)) return 'macos';
  if (/linux-only|OS\.linux\?/.test(line)) return 'linux';
  return 'all';
}

function profileFrom(line) {
  return line.match(/\bprofile=([^\s]+)/)?.[1] ?? 'core';
}

function parseTextManifest(content, source, manager) {
  const records = [];
  let comments = [];
  content.forEach((raw, index) => {
    const line = raw.trim();
    if (!line) { comments = []; return; }
    if (line.startsWith('#')) { comments.push(line.replace(/^#\s?/, '')); return; }
    const name = line.split(/\s+/)[0];
    if (!name || name === 'if' || name === 'end') return;
    records.push({
      name, manager, source, line: index + 1,
      description: commentDescription(comments) || `${manager} declaration`,
      platform: manager === 'mlx-model' ? 'macos (Apple Silicon)' : platformFrom(line),
      profile: manager === 'mlx-model' ? 'opt-in pull-models' : source.endsWith('cargo.txt') || (manager === 'uv-tool' && source.endsWith('pip-full.txt')) ? 'full' : 'core',
    });
    comments = [];
  });
  return records;
}

function parseBrewfile(content, source) {
  const records = [];
  let comments = [];
  const platformStack = [];
  let activePlatform = 'all';
  let section = 'Homebrew';
  content.forEach((raw, index) => {
    const line = raw.trim();
    if (!line) { comments = []; return; }
    if (line.startsWith('#')) {
      const comment = line.replace(/^#\s?/, '');
      const heading = comment.replace(/^#+\s*/, '').replace(/\s*#+\s*$/, '');
      if (heading && /^#+/.test(comment)) section = heading;
      comments.push(comment);
      return;
    }
    if (/^if\s+OS\.mac\?/.test(line)) { platformStack.push(activePlatform); activePlatform = 'macos'; return; }
    if (/^if\s+OS\.linux\?/.test(line)) { platformStack.push(activePlatform); activePlatform = 'linux'; return; }
    if (line === 'end') { activePlatform = platformStack.pop() ?? 'all'; return; }
    const match = line.match(/^(brew|cask|tap)\s+"([^"]+)"/);
    if (!match) return;
    const manager = match[1] === 'brew' ? 'homebrew' : match[1] === 'cask' ? 'homebrew-cask' : 'homebrew-tap';
    records.push({ name: match[2], manager, source, line: index + 1,
      description: commentDescription(comments) || `${section} (${manager})`,
      platform: platformFrom(line) === 'all' ? activePlatform : platformFrom(line), profile: 'core' });
    comments = [];
  });
  return records;
}

function parseSkills(content, source) {
  const records = [];
  let comments = [];
  content.forEach((raw, index) => {
    const line = raw.trim();
    if (!line) { comments = []; return; }
    if (line.startsWith('#')) { comments.push(line.replace(/^#\s?/, '')); return; }
    const [name, owner] = line.split(/\s+/, 3);
    if (!name || !owner) return;
    records.push({ name, owner: `installer-${owner}`, source, line: index + 1,
      description: commentDescription(comments) || 'Installer-managed agent skill' });
    comments = [];
  });
  return records;
}

function parseMcp(content, source) {
  const records = [];
  content.forEach((raw, index) => {
    const line = raw.trim();
    if (!line || line.startsWith('#')) return;
    const [name, transport] = line.split(/\s+/);
    if (!name || !['http', 'stdio'].includes(transport)) return;
    const commandText = raw.includes('cmd:') ? raw.slice(raw.indexOf('cmd:') + 4).trim() : '';
    // Manifest commands may name environment variables but never carry their values.
    const command = commandText.replace(/([A-Z][A-Z0-9_]*(?:TOKEN|KEY|SECRET|PASSWORD))=\S+/g, '$1=<ENV>');
    records.push({ name, transport, profile: profileFrom(line), risk: line.match(/\brisk=([^\s]+)/)?.[1] ?? 'read',
      source, line: index + 1, command });
  });
  return records;
}

function skillMetadata(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n/);
  return match ? parseYaml(match[1]) ?? {} : {};
}

async function repoSkills(repoRoot) {
  const root = join(repoRoot, 'home/dot_claude/skills');
  const entries = await readdir(root, { withFileTypes: true });
  const records = [];
  for (const entry of entries.filter((item) => item.isDirectory())) {
    const absolute = join(root, entry.name, 'SKILL.md');
    try {
      const content = await readFile(absolute, 'utf8');
      const metadata = skillMetadata(content);
      const source = relative(repoRoot, absolute);
      records.push({ name: metadata.name || entry.name, owner: 'repository', source,
        line: 1, description: metadata.description || 'Repository-managed skill' });
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
      // A skill directory without SKILL.md is not a catalogued skill.
    }
  }
  return records;
}

function table(records, columns) {
  const heading = `| ${columns.map(([label]) => label).join(' | ')} |`;
  const rule = `| ${columns.map(() => '---').join(' | ')} |`;
  return [heading, rule, ...records.map((record) => `| ${columns.map(([, get]) => markdownEscape(get(record))).join(' | ')} |`)].join('\n');
}

function page(title, description, editUrl, body) {
  return `---\ntitle: ${title}\ndescription: ${description}\neditUrl: ${editUrl.replace('/blob/main/', '/edit/main/')}\n---\n\n${body}\n`;
}

export async function generateCatalog({ repoRoot, siteRoot }) {
  const packages = [];
  for (const [file, manager] of packageManagers) {
    const source = `packages/${file}`;
    const content = await lines(join(repoRoot, source));
    packages.push(...parseTextManifest(content, source, manager));
  }
  packages.push(...parseBrewfile(await lines(join(repoRoot, 'packages/Brewfile')), 'packages/Brewfile'));
  const skills = [...parseSkills(await lines(join(repoRoot, 'packages/agent-skills.txt')), 'packages/agent-skills.txt'), ...await repoSkills(repoRoot)];
  const servers = parseMcp(await lines(join(repoRoot, 'packages/mcp-servers.txt')), 'packages/mcp-servers.txt');
  const features = JSON.parse(await readFile(join(repoRoot, 'docs/_data/features.json'), 'utf8')).features;
  stable(packages); stable(skills); stable(servers); features.sort((a, b) => a.id.localeCompare(b.id));
  anchorRecords(packages, 'manager');
  anchorRecords(skills);
  anchorRecords(servers);

  const catalog = { packages, skills, servers, features };
  const generated = join(siteRoot, 'src/content/docs/reference');
  await mkdir(generated, { recursive: true });
  await mkdir(join(siteRoot, 'src/data'), { recursive: true });
  await writeFile(join(siteRoot, 'src/data/catalog.json'), `${JSON.stringify(catalog, null, 2)}\n`);
  await writeFile(join(generated, 'packages.md'), page('Package catalog', 'Declarative packages, plugins, extensions, and models.', sourceUrl('packages/Brewfile'),
    `Find a declaration, open its source, or link to it by name. [Add a package](/setup/packages/) · [Package ownership](/architecture/package-ownership/)\n\n## Inventory\n\n${packages.length} declarations. Filter by name and manager; each name is a permalink.\n\n${table(packages, [['Name', entryLink], ['Manager', (r) => r.manager], ['Platform', (r) => r.platform], ['Profile', (r) => r.profile], ['Description', (r) => r.description], ['Source', (r) => `[${r.source}:${r.line}](${sourceUrl(r.source, r.line)})`]])}`));
  await writeFile(join(generated, 'skills.md'), page('Skill catalog', 'Installer-managed and repository-managed agent skills.', sourceUrl('packages/agent-skills.txt'),
    `[Use or change a skill](/agents/skills/) · [Workflow examples](/agents/domain-workflows/)\n\n## Inventory\n\n${skills.length} skills. One owner per directory; each name is a permalink.\n\n${table(skills, [['Name', entryLink], ['Owner', (r) => r.owner], ['Description', (r) => r.description], ['Source', (r) => `[${r.source}:${r.line}](${sourceUrl(r.source, r.line)})`]])}`));
  await writeFile(join(generated, 'mcp.md'), page('MCP catalog', 'Declared MCP transports, profiles, risk labels, and public commands.', sourceUrl('packages/mcp-servers.txt'),
    `[Configure connections](/agents/inventories/) · [Check agent health](/agents/validation/)\n\n## Inventory\n\n${servers.length} declared servers. Each name is a permalink. Credentials are omitted; a declaration does not prove a connection.\n\n${table(servers, [['Name', entryLink], ['Transport', (r) => r.transport], ['Profile', (r) => r.profile], ['Risk', (r) => r.risk], ['Command', (r) => r.command || '—'], ['Source', (r) => `[${r.source}:${r.line}](${sourceUrl(r.source, r.line)})`]])}`));
  await writeFile(join(generated, 'features.md'), page('Feature map', 'Coverage manifest for installers, helpers, and bootstrap features.', sourceUrl('docs/_data/features.json'),
    `## Inventory\n\n${features.length} logical features.\n\n${table(features, [['Feature', (r) => r.title], ['Description', (r) => r.description], ['Guide', (r) => `[${r.page}](${r.page})`], ['Demo or check', (r) => `\`${r.demo}\``], ['Sources', (r) => r.sources.map((s) => `[${s}](${sourceUrl(s)})`).join(', ')]])}`));
  return catalog;
}
