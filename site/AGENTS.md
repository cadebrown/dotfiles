# Handbook implementation

- Read the repository and `docs/AGENTS.md` instructions first.
- Author handbook prose in `../docs/`. `src/content/docs/`, `src/data/*.json`, `public/_redirects`, `public/llms.txt`, `public/evidence/`, and `dist/` are generated.
- `scripts/generate.mjs` stages source pages and preserves legacy URLs; `scripts/catalog.mjs` extracts public declarations. Do not copy private configuration or credentials into catalogs or media.
- Use the pinned Astro/Starlight APIs and preserve native search, keyboard navigation, code copying, and image-zoom behavior. Keep Markdown readable without client JavaScript.
- The site name is “Cade's Dotfiles”. `src/navigation.mjs` owns task order and short sidebar labels; breadcrumbs derive from Starlight's resolved sidebar. Preserve section/catalog permalinks, query-string catalog filters, and source-page links.
- Treat the homepage as a quick-start guide: explain the setup, diagram real source-to-result paths, then show commands and expected results. Use quiet typography and ordinary documentation navigation; avoid slogans, promotional heroes, and cards that repeat the sidebar.
- Typography is Ubuntu for prose/UI and Ubuntu Mono for code, paths, badges, chart labels, and diagrams. Keep fonts self-hosted, including build-time Mermaid measurement. Use restrained red/green/blue accents on neutral surfaces; the homepage diagram maps source → apply → result to R → G → B with visible text labels.
- Give meaningful figures accessible names; use SVG for diagrams and bounded WebP/AVIF for screenshots. Capture the real interface and record provenance in `docs/_data/media.json`.
- `npm run dev` is the interactive preview. `../tests/ci.sh docs` is the canonical gate: types, production render, internal/source links, feature coverage, redirects, media, and snippet checks.
- Exercise changed interactions at desktop and narrow widths. Record URL, viewport, observations, and screenshots. Review both light and dark presentation when changing theme tokens.
- Run `npm run measure -- --runs 3` only when refreshing the published measurement snapshot. Keep source fingerprints, raw samples, environment, and limitations intact.
- Do not weaken validation to make a migration pass. Repair the content or renderer and add a focused regression test for a real failure mode.
