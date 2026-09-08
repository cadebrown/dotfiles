import { defineConfig } from 'astro/config';
import { unified } from '@astrojs/markdown-remark';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';
import starlightImageZoom from 'starlight-image-zoom';
import { pluginCollapsibleSections } from '@expressive-code/plugin-collapsible-sections';
import { pluginLineNumbers } from '@expressive-code/plugin-line-numbers';
import rehypeMermaid from 'rehype-mermaid';
import remarkDocsLinks from './scripts/remark-links.mjs';
import rehypeDiagramFrames from './scripts/rehype-diagrams.mjs';
import { generate } from './scripts/generate.mjs';
import { sidebar } from './src/navigation.mjs';
import { readFileSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';

await generate();
const redirects = JSON.parse(readFileSync(new URL('./src/data/redirects.json', import.meta.url), 'utf8'));

export default defineConfig({
  site: 'https://dotfiles.cade.io',
  output: 'static',
  outDir: process.env.DOCS_OUT_DIR || './dist',
  trailingSlash: 'always',
  markdown: {
    processor: unified({
      remarkPlugins: [remarkDocsLinks],
      rehypePlugins: [[rehypeMermaid, {
        strategy: 'inline-svg',
        css: new URL('./src/styles/mermaid-fonts.css', import.meta.url),
        mermaidConfig: { theme: 'base', securityLevel: 'strict', fontFamily: 'Ubuntu Mono, monospace', themeVariables: { primaryColor: '#f0f4fc', primaryTextColor: '#20252d', primaryBorderColor: '#2c5ba8', lineColor: '#687383', secondaryColor: '#eff7f2', tertiaryColor: '#fbf2f3', fontFamily: 'Ubuntu Mono, monospace' } },
      }], rehypeDiagramFrames],
    }),
  },
  integrations: [{ name: 'legacy-documentation-routes', hooks: {
    'astro:build:done': async ({ dir }) => {
      for (const [from, to] of Object.entries(redirects)) {
        const target = new URL(from.slice(1), dir);
        await mkdir(new URL('./', target), { recursive: true });
        await writeFile(target, `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Documentation moved</title><meta name="robots" content="noindex"><link rel="canonical" href="https://dotfiles.cade.io${to}"><meta http-equiv="refresh" content="0;url=${to}"></head><body><p>This page moved to <a href="${to}">${to}</a>.</p><script>location.replace(${JSON.stringify(to)}+location.search+location.hash)</script></body></html>`);
      }
    },
  } }, starlight({
    title: "Cade's Dotfiles",
    description: 'Setup, configuration, and workflow guides for a macOS and Linux development environment.',
    favicon: '/favicon.svg',
    social: [{ icon: 'github', label: 'Source on GitHub', href: 'https://github.com/cadebrown/dotfiles' }],
    customCss: ['./src/styles/handbook.css'],
    components: { PageTitle: './src/components/PageTitle.astro' },
    expressiveCode: { themes: ['github-dark', 'github-light'], styleOverrides: { codeFontFamily: 'var(--sl-font-mono)', uiFontFamily: 'var(--sl-font)', codeFontSize: '.95rem', borderRadius: '.25rem' }, plugins: [pluginCollapsibleSections(), pluginLineNumbers()], defaultProps: { wrap: true }, shiki: { langAlias: { gotmpl: 'go', gitconfig: 'ini' } } },
    plugins: [starlightImageZoom(), starlightLinksValidator()],
    sidebar,
    tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 3 },
    pagination: true,
  })],
  vite: {
    plugins: [{ name: 'handbook-source-watch', configureServer(server) {
      const sourceRoot = new URL('../docs/', import.meta.url).pathname;
      server.watcher.add(sourceRoot);
      let pending;
      server.watcher.on('all', (_event, file) => {
        if (file.startsWith(sourceRoot) && /\.mdx?$/.test(file) && !file.includes('/book/')) {
          clearTimeout(pending);
          pending = setTimeout(() => generate().catch((error) => server.config.logger.error(String(error))), 100);
        }
      });
    } }],
  },
});
