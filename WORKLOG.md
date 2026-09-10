# Mac verification and Git synchronization — September 10

The Mac uses the normal flat tools layout and its existing real ~/.codex on
local APFS. Native database integrity, rollout/index parity, authentication,
provider HTTP/WebSocket connectivity, managed configuration, and desktop task
reads pass. No Mac history migration is needed. The updated Bash/Zsh login and
launch paths plus Fish environment bridge were applied with scripts excluded;
previous shell files and chezmoi configuration are backed up locally. Shell
rendering has no remaining drift. CLI 0.154.0's terminal diagnostic passes with
an actual terminal configuration; optional Defender-exclusion and update-probe
warnings are not database/startup failures.

Git synchronization scope is the public dotfiles repository and its independent
private NVIDIA overlay, including their one shared remote checkout. Before
publication, both local main branches matched origin/main with no committed
divergence. Preserve unrelated Claude-default and MCP OAuth edits and the remote
overlay's unrelated doc/test.json. Publish the generic host/Codex repair and
private host presets as separate conventional commits; keep the public push
gate enabled and verify each hosted revision before declaring it current.

# Full-backup migration follow-up — September 10

User explicitly requested full history backups and reported SQLite code 26 plus
EXDEV at the legacy shared path. Current desktop processes were already local;
non-login Bash/Zsh wrappers still used the old environment-only launch. Added a
shared lazy launcher that re-resolves invocation policy while preserving explicit
CODEX_HOME overrides, including after a prior login resolution. Existing shells
need a one-time reload; npm-owned binaries are unchanged.

Full copy-only backups now include symlink referent bytes, raw SQLite/WAL/SHM,
configuration/auth, all history, and artifacts. SHA-256 copies plus a final
source inventory check gate completion; topology and original metadata are
recorded, private modes enforced, and incomplete snapshots are marked clearly.
The CLI backup mode never prepares or repairs the source. Three verified full
backups total 28,627,693,676 bytes and 23,838 files. Local runtime snapshots were
made with bounded writer suspension, then archived off-host and verified again
file-by-file. Private locations and archive checksums are in the deployment's
BACKUPS.md. The initial slower shared-storage attempt remains explicitly marked
incomplete; no originals were deleted.

Both stopped desktop backends received 111 missing portable files (140,584,354
bytes each): prompt history, attachments, generated images, and visualizations.
All 1,984 existing transcript/index files per host were preserved. Backends were
restarted with their original launch command/environment. The desktop-owned
processes are not managed by the separate Codex daemon CLI; its stop command
refused without changing state. Native desktop task reads succeed on both hosts,
and real non-login shells reach their local socket with CLI/server version
0.153.4. Full histories and raw original databases remain intact.

Follow-up validation complete: launcher tests, backup and portable importer
checks, shell checks, the final 271-case fast suite, docs, and the final 484-case
clean rootless Linux suite all pass (exit 0). An earlier Linux idempotence check
correctly detected a launcher source edit made after bootstrap; the frozen-source
rerun passes. Both native healthchecks and desktop task reads pass. All 2,095
portable files per host were rehashed against the backups; all six databases per
host passed SQLite quick_check on disposable copies, never the original backup.
An independent focused review found no backup/history data-loss issue; its
policy-refresh edge is documented explicitly: exported environment wins over
host-file edits, so root changes need a fresh SSH login, not a shell replacement.
Changes remain uncommitted and unpushed. Preserve unrelated local Claude/MCP
edits; remote rc files and their templates received only the Codex launcher hunk.
Final evidence logs: `/tmp/codex-migration-fast-final.log`,
`/tmp/codex-migration-docker-final.log`, `/tmp/codex-migration-docs-complete.log`,
`/tmp/codex-migration-shell-final.log`, and the two native host-check logs under
`/tmp/codex-migration-*-check.log`. The follow-up deployment is complete.

# Remote Codex and per-host configuration — September 10

Implementation and deployment are authorized for two remote workstations; the
unavailable workstation is out of scope. Public dotfiles owns a generic
data-only host resolver. The private dotfiles-nvidia overlay owns internal
hostname/path presets. Existing unrelated working-tree changes are preserved.

Confirmed: both machines share NFS HOME and NFS scratch. Codex 0.153.4 uses WAL
databases; the old per-file scratch symlinks also make database recovery fail
with EXDEV. A complete real host-local CODEX_HOME passes native Unix listener
initialization, unlike a symlinked app-server-control directory.

Implemented and deployed: runtime host input precedence and shell/bootstrap
integration; guided per-host configuration; host-local Codex managed assets;
retirement of SQLite scratch migration; copy-only history import. The shared
old state is intact. No remote package upgrades, commits, or pushes have been
performed for this repair.

History evidence: native Codex 0.153.4 reopened a copied 108 MB existing parent
transcript in a fresh local runtime: same ID, 56 turns, 1,738 items, original
SHA-256 unchanged. No database copy was needed. The generic importer now copies
portable transcripts and the session index only, checks source stability and
copied bytes, refuses destination links, and never overwrites continuations.
Four focused importer tests passed. Both desktop connections now report
connected and the desktop's native task reader retrieved the imported task
from both hosts. Each received 1,983 transcripts and the index (7,832,512,016
bytes), with originals untouched. The initial daemon start took extra time to
rebuild local indexes; steady-state reconnect succeeded without modifying the
app bundle. The scoped source and login files have recoverable backups. Private
deployment details live in the overlay. Both full native Codex healthchecks
pass, including declared plugins and generated-file hook protection. Existing
official plugin artifacts were restored without upgrading them. Fresh Bash and
Zsh logins resolve identical host-specific state paths; all 22 deployed source
files match the local checkout by SHA-256.

Validation complete: shell checks, native hook trust checks, 74 real-chezmoi
guard checks, 12 runtime tests, four importer tests, nine host tests on macOS
and Linux, and the documentation gate pass. The canonical macOS fast run passes
264 cases. The canonical clean rootless Linux bootstrap and all 477 Docker
cases pass (exit 0, no bootstrap degradations). Final logs are
`/tmp/dotfiles-host-fast-complete.log`, `/tmp/dotfiles-host-docker-complete.log`,
and `/tmp/dotfiles-host-docs-final.log`.

Final validation also caught and fixed Zsh's no-overlay NOMATCH failure, with
coverage for restoring caller shell options. Shell fixtures now choose policy
at runtime rather than via retired template data. The fake bootstrap clone
copies repository files, excluding ignored dependencies and private overlays;
its four cases pass independently on both platforms. No required work remains;
the changes are deployed but uncommitted and unpushed.

# Documentation revamp

## Objective and boundary

Replace mdBook with an Astro + Starlight technical handbook covering the public
setup: architecture, configuration, use cases, examples, agent instructions and
skills, source links, diagrams, demonstrations, and scoped performance data.
Make documentation and demonstration updates part of finishing repository work.

The revamp is local and uncommitted. No push, publication, Cloudflare change,
or OpenTofu apply was performed. Existing agent/configuration work was preserved;
another task committed it separately as f17a5df while this task ran.

## Delivered

- Pinned Astro 7.3.2 and Starlight 0.42.0 in site/, with a lockfile and source-only
  authoring in docs/. Generated content, data, output, and logs are ignored.
- 132 handbook routes from 58 authored Markdown/MDX sources and generated catalogs
  and diagnoses. Searchable inventories: 341 declarations, 78 skills, 27 MCP servers.
- Architecture, setup, workflows, all four agent families, instruction/skill
  ownership, managed configuration, troubleshooting, contribution, and hosting
  guides. Detailed shell, Ghostty/tmux/SSH, Neovim, editor, and agent examples.
- Dark/light design, responsive navigation and catalogs, Pagefind search, setup
  configurator, copyable annotated/collapsible code, accessible inline SVG diagrams,
  image zoom, self-hosted WOFF2 fonts, and four small WebP browser captures.
- Explicit feature map: 15 features own 206 unique installer, package, and managed
  configuration sources. New source files fail coverage until mapped deliberately.
- Legacy compatibility: 28 .html URLs and 279 original heading fragments. Source
  links and expected rendered pages are checked independently of Astro's exit code.
- Canonical docs/quality checks, explicit Chromium provisioning, Dependabot,
  Cloudflare build configuration, and isolated pre-push snapshot dependency setup.
- Root/nested instructions and PR template require use case, configuration,
  runnable example, expected result, evidence, limits, and source/upstream links.

## Evidence

- ./tests/ci.sh quality passed: shell checks, 187 Bats cases, Astro/content check,
  verifier fixtures, production render, source/internal links, feature coverage,
  legacy fragments, media hashes/dimensions, secret scan, and workflow lint.
- ./tests/ci.sh infrastructure passed: format, backend-free init, and validation.
- Fresh read-only reviewer recheck resolved all six material migration findings.
- Browser exercised the production preview at http://127.0.0.1:4388/: homepage,
  setup flags and invalid combinations, copy feedback, Pagefind results,
  catalog filtering and empty state, mobile navigation, light/dark presentation,
  image zoom/Escape, MDX tabs, collapsible code, and legacy fragment navigation.
- At a 390 x 844 browser viewport, the catalog and diagram page had document width
  and scroll width of 375 pixels. Wide diagrams scroll within a focusable frame.
- Raw local repeated build samples and six HTML/gzip sizes are captured in
  docs/_data/performance.json; the published report includes environment, date,
  source fingerprint, methods, and explicit measurement limits.
- Media provenance: docs/_data/media.json; captures contain only the new handbook.
- Complete local logs and verifier reports: ignored site/artifacts/.

## Reproduce / continue

### September 8: simpler documentation direction

- Replaced the splash page with a regular Starlight overview: a linked diagram
  of the package/configuration paths, installation and configuration commands,
  a read-only Codex walkthrough, and a compact guide index.
- Removed the slogan, promotional cards, custom hero, terminal wordmark, and
  condensed display font. Headings/body use Source Sans 3; code uses JetBrains
  Mono. Neutral light/dark surfaces retain blue links and native navigation.
- Preserved historical homepage links at relevant new sections. Alias elements
  use block markup without empty paragraphs; the rendered regression check
  rejects paragraph wrappers around compatibility anchors.
- Updated authoring instructions to prefer direct examples and actual system
  diagrams. Refreshed all four WebP screenshots and their provenance, and
  remeasured the final source after the media update.
- Browser checks at desktop and narrow widths covered both themes, the linked
  setup walkthrough, code copying, search, catalog filtering, mobile navigation,
  and the historical agent-section link. Homepage and catalog measured 375px
  document/scroll width in a 390px viewport, with no page-level overflow.
- The final `./tests/ci.sh docs` gate passed: Astro check, verifier fixtures,
  production build, 132 routes, source/link/feature checks, historical anchors,
  and four media records. The three local build samples were 4.75, 4.85, and
  5.84 seconds; homepage HTML was 58,906 bytes (11,995 with gzip-9). These are
  local build/artifact measurements, not observed page-load timings.

### September 8: Ubuntu typography and RGB accents

- Applied restrained RGB details to the neutral light/dark theme: header rule,
  source/apply/result diagram accents, selected navigation, and favicon.
- Replaced the previous font dependencies with pinned, self-hosted Ubuntu and
  Ubuntu Mono. Ubuntu covers prose and UI; Ubuntu Mono covers code, paths,
  keyboard labels, badges, diagram text, and chart labels. Normal/italic faces
  use Latin WOFF2 subsets and load on demand.
- Supplied Ubuntu Mono to build-time Chromium before Mermaid layout, and set
  both Mermaid font-family options. Diagram surfaces now follow the site theme.
- Browser font inspection found only the two requested families in homepage
  text and controls, search, the Claude diagram, and catalog/performance labels.
  Both themes, code copy feedback, setup flags, catalog filtering, mobile menu,
  and 390px layout were exercised. RGB text/background pairs passed 4.5:1.
- Replaced the four browser captures, verified their compact encodings, and
  updated source/asset provenance. All changes remain local and uncommitted.
- `./tests/ci.sh docs` passed with zero Astro check errors/warnings, seven
  verifier fixtures, two legacy tests, 132 routes, and four verified media
  records. The repeated local builds measured 9.19, 11.12, and 11.45 seconds;
  the updated snapshot records the unisolated host workload and source hash.
  The final production preview was rebuilt after that snapshot was written.

### September 8: concise guides and task navigation

- Renamed the site, homepage, README, and generated agent index to Cade's
  Dotfiles. Kept Ubuntu/Ubuntu Mono and the restrained RGB theme.
- Replaced alphabetical navigation with task order and short labels in
  `site/src/navigation.mjs`. Added breadcrumbs derived from that navigation,
  source-page links, visible heading anchors, and page-link copying.
- Condensed setup, agent, maintenance, homepage, and configuration prose;
  retained detailed references and troubleshooting diagnoses. Replaced repeated
  settings with canonical links, chooser tables, and concrete examples.
- Added package/skill/MCP entry permalinks, shareable catalog filters, and
  recovery when a fragment points at an entry hidden by incoming filters.
  Grouped the troubleshooting index into seven topic areas.
- Added a responsive brief/build/run/review diagram and direct configuration
  section links. Preserved old domain-workflow anchors after shortening headings.
- Corrected plain chezmoi-edit semantics, the df-task title flag, OpenCode's npm
  ownership, and CMake profile selection after source review.
- Added a rendered navigation-coverage check and a regression fixture for an
  orphan authored page versus an intentionally hidden page. Updated authoring
  instructions to keep new guides concise, linked, and in the reading order.
- Browser checks covered desktop/mobile, both themes, active navigation and
  breadcrumbs, copy feedback, query reload, conflicting filter/fragment recovery,
  the setup command, and Pagefind search. Mobile document and scroll widths
  matched at 375px in the 390px viewport.
- The canonical docs gate passed: Astro check, eight verifier fixtures, 132
  routes, 15 feature groups, internal/source links, and two legacy tests.
  Refreshed four real browser captures (about 213 KiB total) with hashes and
  dimensions. Full logs and editorial word counts are in `site/artifacts/`.
- Final measured builds were 4.75, 5.56, and 6.12 seconds on the unisolated
  local host. Updated the dated source fingerprint and six payload samples,
  rebuilt the preview, and reran artifact/media verification successfully.
  These timings are a fresh local snapshot, not a controlled speedup claim.

### Commands

    npm --prefix site ci --ignore-scripts
    npx --prefix site --no-install playwright install chromium
    ./tests/ci.sh docs
    npm --prefix site run dev

### September 8: release preparation

- Pinned Node 24 in `.node-version`, shared by GitHub Actions and Cloudflare
  Pages. The quality, infrastructure, workflow, and uncommitted-file secret
  checks passed, including 187 fixture tests and the full handbook gate.
- Applied the authorized Pages output migration from `docs/book` to
  `site/dist`, matching `infra/cloudflare/main.tf`. API readback confirmed the
  other build, source, and deployment configuration stayed unchanged.
- Started Colima for the required outgoing-commit gate. Publication must pass
  `tests/ci.sh full` in its isolated checkout, then hosted CI and a production
  browser check. Local validation alone is not deployment evidence.
- The default Docker data disk was full. Used a temporary Colima profile for
  release validation, with the inherited `DOCKER_HOST` cleared, and restored
  the default profile to its original stopped state. The test image built
  successfully with package signature checks intact.
- Sampled a separate Homebrew Bash 5.3.15 preprocessing stall in `heredoc_write`.
  Invocation-local `BASH_COMPAT=50` let Bats enumerate all 187 fixtures. Added
  the diagnosis and bounded workaround to the troubleshooting guide.
