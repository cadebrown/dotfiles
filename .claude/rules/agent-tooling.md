---
paths:
  - "install/claude.sh"
  - "install/claude-desktop.sh"
  - "install/codex.sh"
  - "install/codex-desktop.sh"
  - "install/opencode.sh"
  - "install/memory.sh"
  - "install/skills-sync.sh"
  - "install/blender-mcp.sh"
  - "install/auth.sh"
  - "install/scratch.sh"
  - "packages/mcp-servers.txt"
  - "packages/agent-skills.txt"
  - "packages/claude-plugins.txt"
  - "home/dot_claude/**"
  - "home/dot_codex/**"
  - "home/dot_config/opencode/**"
  - "home/dot_pi/**"
  - "home/dot_cursor/**"
---

# Agent harnesses, MCP, skills, memory

Four CLI harnesses (Claude Code, Codex, opencode, pi) share one declarative config
layer: `packages/mcp-servers.txt` (servers), `packages/agent-skills.txt` (skills →
shared `~/.claude/skills` tree), `packages/claude-plugins.txt` (Claude plugins),
and chezmoi-managed guidance files built from shared partials.

- **Plugins are mirrored in THREE places** — `packages/claude-plugins.txt`,
  `_MARKETPLACES` in `install/claude.sh` (third-party marketplaces only), and
  `enabledPlugins`/`extraKnownMarketplaces` in `home/dot_claude/settings.json`.
  Update all three.

## Gotchas

- **MCP spec 2026-07-28 is shipping, but negotiation is the harnesses' job — this
  repo still carries no protocol config.** The revision drops the initialization
  handshake for per-request negotiation (`io.modelcontextprotocol/protocolVersion`
  in `_meta`, `MCP-Protocol-Version` on Streamable HTTP), adds a mandatory
  `server/discover` RPC, and replaces server-initiated requests (elicitation
  included) with MRTR `input_required` results. Adoption as of 2026-08-15:
  Cloudflare's product servers run it statelessly on `/mcp` (legacy clients still
  accepted), github-mcp-server ≥ v1.9.0 negotiates it, and all four Tier-1 SDKs
  speak it. Client side: opencode ≥ 1.18.9 negotiates automatically
  (`@modelcontextprotocol/client` 2.0); pi-mcp-adapter has per-server
  `protocolVersion` ("legacy" default / "auto" / "2026-07-28"); Codex gates it
  behind `[features] mcp_2026_07_28` — protocol-only, stage UnderDevelopment,
  leave OFF until it reaches Stable (the same bar multi_agent_v2 met before we
  enabled it); Claude Code has not shipped the new wire protocol. On the auth
  side the revision deprecates DCR in favor of CIMD (URL-based client IDs,
  SEP-991) and mandates RFC 9207 issuer validation; CIMD clients today: Claude
  Code (since 2.1.81), Codex 0.148-alpha ≥ .9; opencode (#25961 open) and
  pi-mcp-adapter still register via DCR. `packages/mcp-servers.txt` stays
  URL/command/auth-source only. Probe a server with
  `curl -sX POST <url> -H 'MCP-Protocol-Version: 2026-07-28' -d '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{}}'`.
- **Claude plugin installs resolve against LOCAL marketplace clones** — with
  `DISABLE_AUTOUPDATER=1` the clones under `~/.claude/plugins/marketplaces/` never
  refresh themselves, so a plugin added upstream after a marketplace's clone date
  fails with "not found in any configured marketplace" (the official catalog once
  sat 4 months stale while its plugin existed upstream). `claude.sh` runs
  `claude plugin marketplace update` (no name = update all; there is NO `--all`
  flag — the old upgrade path passed one and errored silently behind `>/dev/null`)
  before the install loop in EVERY mode — don't move that refresh back inside the
  upgrade-only block. Manual one-off fix:
  `claude plugin marketplace update <name>` then re-install.
- **rtk hook wiring** — 0.42+ re-introduced `rtk hook claude|cursor|gemini|copilot` as
  the canonical built-in; our hooks are thin wrappers (`dot_claude/rtk-rewrite.sh`,
  `dot_cursor/hooks/rtk-rewrite.sh`) that PATH-harden + `command -v rtk || exit 0` then
  delegate to it. opencode/pi use in-process TS plugins calling `rtk rewrite` (no built-in
  hook exists for those). Codex uses a hand-rolled PreToolUse `updatedInput` hook
  (`dot_codex/executable_rtk-rewrite.sh`, wired in `dot_codex/hooks.json`; rtk ships no
  Codex hook itself). rtk's deny/ask verdicts (exit 2/3) pass through UNREWRITTEN there;
  the default full-auto policy runs the original command, while an explicitly
  interactive session can still apply execpolicy rules. Trust hashes are managed by
  `codex.sh sync-config` — no interactive /hooks review is needed after managed edits.
  (Install source: the rtk-ai/tap — see `.claude/rules/homebrew.md`.)
- **rtk preserves full-auto execution** — Claude runs in `bypassPermissions`, Cursor
  allows `Shell(*)`, and Codex uses `approval_policy = "never"`. Rewrites are transparent;
  commands rtk declines to rewrite pass through to the unrestricted host policy.
- **chezmoi-guard covers all four CLI harnesses** — Claude + Codex via PreToolUse
  hooks, opencode via `dot_config/opencode/plugin/chezmoi-guard.ts`, pi via
  `dot_pi/agent/extensions/chezmoi-guard.ts`. All four are thin adapters around
  `~/.local/bin/df-chezmoi-guard` (exit 2 = blocked) — detection logic lives ONLY
  there. Cursor is the exception: its sync-back hooks capture edits instead of
  blocking them.
- **GitHub MCP can't use OAuth** — `api.githubcopilot.com/mcp` advertises OAuth, but
  GitHub's IdP implements neither Dynamic Client Registration (RFC 7591) nor CIMD
  (no `registration_endpoint`, no `client_id_metadata_document_supported` in its AS
  metadata — probed 2026-08-15), so Claude
  Code's `/mcp` Authenticate flow fails with "Incompatible auth server" (tracked in
  anthropics/claude-code#3433). GitHub's own install guide just recommends a static PAT,
  so `mcp-servers.txt` uses `auth=gh`: Claude resolves the token at connection time via
  `~/.claude/gh-mcp-headers.sh` (headersHelper), Codex via `bearer_token_env_var =
  "GH_TOKEN"` filled by the `codex()` shell wrapper. **Token source is `$GITHUB_TOKEN`
  (the PAT in `~/.github.env`) first, `gh auth token` keyring as fallback** — one value,
  sourced into every shell, shared across the NFS fleet, no token in any MCP config.
- **A stale `GITHUB_TOKEN` silently shadows the gh keyring** — `gh auth token` returns
  `$GH_TOKEN`/`$GITHUB_TOKEN` ahead of its stored credential when either is set, by design
  (cli/cli#8347), and `gh auth login` even refuses to run while the env var is non-empty.
  So an expired PAT in `~/.github.env` poisons both the MCP helper and `gh` itself, and
  the only symptom is a cryptic MCP 401. The headersHelper now reads `$GITHUB_TOKEN`
  directly (env-first is explicit, not accidental), and `auth.sh status` pings the API to
  print a `github-mcp: live / EXPIRED` line so expiry is visible. Rotate with
  `bash install/auth.sh github`; to switch a machine to the keyring instead, clear
  `GITHUB_TOKEN` then `gh auth login`. After rotating, relaunch Claude Code — the running
  process caches the old env token at launch.
- **Codex MCP OAuth against spec-compliant servers was broken 0.143–0.146,
  fixed in 0.147.0** — the rmcp-era callback handling dropped the RFC 9207
  `iss` param, so servers like Cloudflare's died with "Authorization server
  response missing required issuer" (openai/codex#31573; fixed by the rmcp
  3.0.0 client rework — the issue may still sit open administratively, so
  judge by retest, not by issue state). Cloudflare's bearer annotation was
  dropped 2026-08-15; OAuth needs a one-time `codex mcp login cloudflare` per
  machine. The `--codex-bearer <ENV_VAR>` annotation in
  `packages/mcp-servers.txt` REMAINS supported for the next broken flow:
  parsed by `mcp_servers_each` into its own field (like `--codex-client-id`),
  rendered ONLY by `install/codex.sh` as `bearer_token_env_var` — the other
  harnesses keep OAuth for the same server. (mcp.cloudflare.com still accepts
  API-token bearers if scope-bounded access is ever wanted again; with a
  bearer, a 403 means missing token scopes, not broken auth.)
- **Google MCP is split: Cloud = official ADC, Workspace = community server** —
  two different mechanisms for two different reasons.
  **Cloud** (`cloud-run`/`cloud-resmgr`/`cloud-storage`/`bigquery`): Google's
  official remote MCP endpoints (`*.googleapis.com/mcp`), authenticated by
  Application Default Credentials. `cloud-platform` is not a sensitive scope, so
  `bash install/auth.sh google` works with gcloud's built-in OAuth client and
  zero setup; the `auth=gcloud` helpers mint a short-lived token per connection.
  **Workspace** (`google-workspace` = Gmail/Calendar/Drive): the community
  `uvx workspace-mcp` (taylorwilsdon) server, full read+WRITE, OAuth client creds
  in `~/.google.env` (`bash install/auth.sh workspace`). We did NOT use Google's
  official Workspace MCP because (a) it's Developer Preview + read-mostly (Gmail
  drafts-only/no send, Calendar read-only, Drive no edit/delete), and (b) its
  scopes are *restricted* — Google blocks gcloud's generic client ("This app is
  blocked"), so it needs a self-made OAuth client anyway. At equal client-setup
  cost, full write beats read-only. The community server uses the STANDARD
  Gmail/Calendar/Drive APIs (no Preview Program). The `auth=gcloud` helpers
  mint a short-lived access token at connection time
  (Claude: `~/.claude/gcloud-mcp-headers.sh`; Codex: `GOOGLE_MCP_TOKEN` via the
  `codex()` wrapper) — nothing at rest, like `auth=gh`. Three gotchas: (1) ADC
  access tokens expire ~hourly and the helper runs at *connect*, so an MCP
  session held open >1h needs a `/mcp` reconnect to re-mint. (2) User-credential
  calls need a quota project via `x-goog-user-project` — `auth.sh google` sets it
  with `gcloud auth application-default set-quota-project`; without it some Cloud
  APIs 403 "user project required". (3) The official Workspace servers are
  **Developer Preview and read-mostly** and need Workspace Developer Preview
  Program enrollment + `gcloud services enable <product>mcp.googleapis.com` —
  which is why we run the community server instead.
- **Codex profiles are per-file since 0.134** — `[profiles.*]` tables in config.toml
  are silently ignored; profiles are delta-only `~/.codex/<name>.config.toml` files
  with top-level keys. `@openai/codex` is UNPINNED in `packages/npm.txt` (upgrades pull
  latest; `codex.sh` reconciles the managed config right after, so format drift surfaces
  in its healthcheck). If Codex breaks config compatibility again, re-pin there until
  the config catches up, and run `bash install/codex.sh check` after any bump.
- **Codex curated plugins drift with the codex-cli version** — `openai-curated` is a
  snapshot bundled with the (unpinned) codex-cli, so its plugin set changes across
  releases. `packages/codex-plugins.txt` selectors a newer codex-cli drops fail to
  install; `codex.sh` `_check_plugins` compares declared entries against `codex plugin
  list --json | jq '.available'` and now *warns* (`dropped upstream: … — prune …`)
  when one is gone from the snapshot instead of dying — but a plugin still offered yet
  not installed/enabled stays a hard failure. Prune dropped entries when you see the
  warning (`openai-developers`, `build-web-data-visualization` went away at 0.144.6).
- **Codex full-auto is explicit at every layer** — `default_permissions =
  ":danger-full-access"` removes the local sandbox, `approval_policy = "never"`
  suppresses interactive execpolicy prompts, and generated MCP/app policy uses
  `approve`. `rules/dotfiles.rules` is retained for sessions that deliberately
  override the approval policy to an interactive mode.
- **cass Linux prebuilts need host glibc >= 2.38** — they link system glibc, not the
  Homebrew one. install/memory.sh falls back to `cargo install --git` on older hosts.
  Its brew tap is NOT used (formula sha lagged a release-asset re-upload, June 2026).
- **cass source build needs NIGHTLY + the rustup cargo, not brew's** — on glibc<2.38
  hosts cass builds from source, and it requires a nightly toolchain (a dep gates
  `#![feature(try_trait_v2)]`; the repo pins `channel="nightly"`). Two traps bit this for
  months: stable fails (`E0554`, or an MSRV error on an older stable), AND a lingering
  Homebrew `rust` formula (an orphaned build-dep — NOT in the Brewfile, nothing `uses` it)
  shadows rustup in bootstrap's PATH at an old version, so `cargo` resolved to brew's
  1.94.0 even after rust.sh updated rustup to 1.97.1. `_cass_build_from_source` now installs
  nightly on demand and invokes `$CARGO_HOME/bin/cargo +nightly` explicitly. If cass still
  won't build, run `which -a cargo` for a stray brew rust and `brew uninstall rust`.
- **npm globals belong to exactly one Node, and native addons enforce it.** Node's
  `NODE_MODULE_VERSION` changes every major, so a package with native addons
  (qmd → better-sqlite3, sqlite-vec, node-llama-cpp) only runs under the Node that
  installed it. Two hazards, both live in Aug 2026: every `npm.txt` package had been
  installed twice — once under nvm, once under Homebrew's node keg — and a Homebrew
  Node major upgrade then broke its copies with `ERR_DLOPEN_FAILED` due to an addon ABI
  mismatch. It hides well: only subcommands that load the addon fail, so
  `qmd collection show` passes while `qmd update` aborts. `_lib.sh` now prepends nvm's
  bin for every install script (`brew shellenv` otherwise puts brew's node first, and
  the shebang is `#!/usr/bin/env node`), and the duplicate globals were removed with
  `npm uninstall -g --prefix "$(brew --prefix)" <pkg>`. Check with
  `npm ls -g --depth=0 --prefix "$(brew --prefix)"` — it should list only `npm` itself.
- **Guard qmd collections with `collection show`, not by grepping `collection list`.**
  `list` prints a human-readable report and a grep guard can't tell "absent" from "that
  command failed" — with stderr discarded, one hiccup reads as absent, and the
  `collection add` that follows exits non-zero on an existing collection, killing
  `memory.sh` under `set -e` (`Collection 'kb' already exists.` → `[fail] memory.sh
  failed`, Aug 2026). `collection show <name>` answers by exit code (0/1), and a failed
  add now degrades to a warning rather than taking the daemons down with it.
- **cass's macOS TCC prompts come from the `aider` crawl, NOT from the connectors that
  read `~/Library/Application Support`.** Aider histories are project-local, so discovery
  crawls `CASS_AIDER_DATA_ROOT`, which **defaults to `$HOME`** — walking `~/Pictures`,
  `~/Documents`, `~/Desktop`, `~/Downloads` and `~/Library`, and requesting Photos,
  MediaLibrary, AddressBook, Calendar, AppData and AllFiles on every 300 s pass. cass is
  ad-hoc signed, so "Allow" dies at the next binary update. `memory.sh` + both cass
  LaunchAgents pin `CASS_AIDER_DATA_ROOT=$HOME/dev`; keep the three copies in sync.
  **Don't "fix" this by excluding cursor/chatgpt/copilot** — measured 2026-08-05, a scan
  that opens 13 Cursor `state.vscdb` files raises zero TCC requests, because Cursor is a
  non-sandboxed Electron app with no registered container and its app-support dir isn't
  protected. Excluding them costs cross-harness coverage and fixes nothing.
  **Don't diagnose this from cass's own logs either**: they record paths cass opens
  deliberately, not what a directory walk touches, so they look clean while prompts keep
  firing — which is exactly how the wrong culprit got blamed. Use tccd:
  `/usr/bin/log show --last 30m --predicate 'process == "tccd"' --info | rg 'Sub:\{.*/cass\}'`
  (`/usr/bin/log` explicitly; `log` is a shell function here).
- **Memory indexes are per-machine** — qmd (~/.cache/qmd) and cass (~/.cass) are
  local; only ~/kb (git) and dotfiles sync across machines. qmd on macOS needs
  Homebrew sqlite (system libsqlite3 blocks loadable extensions).
- **cass is an ARCHIVE, not a rebuildable index — that's why it's ~/.cass.** qmd
  can always be rebuilt from ~/kb, but cass indexes transcripts the harnesses
  eventually rotate away, and it refuses source-only rebuilds to protect them.
  `cass doctor`'s `sole_copy_candidate_count: 124` is narrower than it sounds —
  its `root_cause_kind` is `mirror-missing-with-db-sole-copy`, i.e. 124 rows whose
  raw-mirror blob is absent, not 124 vanished upstream transcripts. Measured
  2026-08-01: a from-scratch index into an empty data dir re-discovered all 785
  conversations from live sources. Keep the archive stance anyway — that headroom
  is a snapshot, and it is the harnesses' rotation policy, not cass, that decides
  when it ends. Nearly all of the ~10 GB is `raw-mirror/` (verbatim capture);
  only ~287 MB (vector_index, index, models) is derived. `cass mirror prune`
  retires by `--older-than`/`--max-size` only — there is no "prune where upstream
  still exists", so age-based pruning sheds exactly the sole-copy rows first.
  Living under ~/.cache invited any cache sweep to delete it; scratch.sh still
  symlinks ~/.cass into scratch where that exists (10 TB there), same path.
- **cass ingest is append-only per conversation — `--full` does NOT re-parse.** A
  conversation already in the canonical DB is never re-read, so parser improvements
  never reach old rows and the archive silently drifts behind what the same files
  would yield today (found 2026-08-01: codex sat at 15,037 messages where a fresh
  parse of the same 88 rollouts gives 85,488 — 82% of that history was unsearchable;
  cursor 3,384 vs 6,949). `--full` only forces a full *scan* + lexical rebuild —
  its log says `skipping historical salvage because canonical database is already
  populated`. The re-parse recipe, per connector:
  `cass forget --source-glob '<path>/**' --apply`, then reset the connector
  watermark (`update meta set value='0' where key='last_scan_ts:connector:<name>'`
  — `--full` still honours it, and rollouts dated months back never beat it), then
  `cass index --full`. Verify every `source_path` still exists on disk BEFORE the
  forget, and back up with `sqlite3 ... ".backup"` (a plain `cp` can tear a live WAL).
  Two cass bugs to work around: `forget` leaks `conversation_tail_state` rows keyed
  by the deleted `conversation_id`, and since that column is a plain rowid SQLite
  reuses freed ids — a future conversation inherits a stale "ingested through idx N"
  marker and gets silently truncated. Delete the orphans afterwards.
- **qmd upgrades need the daemon stopped on NFS** — the qmd MCP daemon
  (`qmd mcp --http`) keeps native addons (sqlite-vec, node-llama-cpp,
  better-sqlite3) mmap'd. On an NFS home npm can't unlink an open file — NFS
  silly-renames it to `.nfsXXXX` and `npm install -g @tobilu/qmd` dies with
  `EBUSY`. `node.sh` stops the daemon around the qmd upgrade and restarts it
  through the `qmd_daemon_{running,stop,start}` helpers in `_lib.sh`
  (Linux-gated via `$OS`; macOS uses the launchd agent + a local FS, no EBUSY).
  memory.sh's lazy-start and node.sh's quiesce share those helpers — don't
  reintroduce an inline `qmd mcp --http --daemon` start. See
  `docs/usage/troubleshooting.md`.
- **Skill dirs are installer-managed** — `skills-sync.sh` rows install via
  `npx skills add` into `~/.claude/skills/`; never add chezmoi sources for those
  dirs (one writer per skill dir; vendored skills live in `home/dot_claude/`).
