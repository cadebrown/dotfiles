# Agent hook overhead

The common hooks preserve their existing responsibilities while avoiding work
that does not apply to the current event. RTK remains enabled; model defaults
are independent of these optimizations.

## Runtime and shell paths

`df-task` and `df-google-mcp` use the runtime-only path of
`install/agent-runtime.sh`. It shares the layout resolver with installers but
never loads installer traps, unrelated credential files, or compiler setup.
Flat mode needs no CPU detection; PLAT mode selects the current machine on each
invocation, including GUI launches and shared homes. Relocating `~/.local`
continues to resolve its current physical target.

Bash and zsh login profiles still establish the full environment. Their shared
partials use shell builtins to select platform specs and Node aliases/versions,
and pass the shell explicitly to `brew shellenv`. They do not cache a machine's
PATH or disable login initialization.

## Relevant Claude hooks

`install/claude-hook-scope.py` generates narrow negative gates in the installed
Hookify and Lean plugin hook declarations. Plugin skills, commands, bootstrap,
and applicable validation remain available. The source of truth is the repo's
patcher and `home/dot_claude/executable_hook-scope.sh`, not hand-edited cache files.

- Hookify checks its upstream rule-file glob every invocation. Creating a rule
  during a session activates it immediately.
- Lean prompt validation runs for explicit `/lean4:` invocations anywhere.
- Lean Bash validation retains force overrides and physical ancestor detection,
  including symlinked project directories and bounded stdin handling.
- Lean session bootstrap still runs so later Lean use has its runtime.

Bootstrap reconciles these gates after installing/updating plugins. After a
direct `claude plugin update`, run:

```sh
bash ~/dotfiles/install/claude.sh sync-hooks
```

`~/.claude/hook-scope-state.json` records whether each installed plugin is scoped.
A changed upstream gate implementation restores full upstream checks, emits a
warning, and records the reason. Review the changed source and update its known
hash only after testing applicability; do not remove the check to force a pass.
Claude sessions that already loaded plugin declarations may need restarting to
use the regenerated commands.

## Status line, edit guard, and Cursor

Claude's status line parses the incoming payload once. Its stdlib-only helper
stores aggregate transcript statistics and offsets under
`${XDG_CACHE_HOME:-~/.cache}/claude-statusline`, never transcript text. Appends are
processed incrementally. Replacement, truncation, timestamp changes at unchanged
size, and boundary fingerprints invalidate old state. Arbitrary edits in the
middle of an otherwise append-only transcript are outside that cache contract;
remove that transcript's derived cache to force a rescan. An unavailable cache
only affects performance.

The shared chezmoi guard uses one fresh ownership query for a multi-file patch.
There is no persistent ownership cache that could miss newly managed files.
Lexical and physical destination paths, symlink aliases, add/delete/move targets,
and filenames with spaces/newlines remain protected. Root normalization adds a
small cost to a single-file check while larger batches are much faster.

Cursor compares hashes of live settings and their source on each event. Unchanged
prompts do no import or extension inventory. Valid changed settings import
immediately; invalid/racing writes are rolled back and retried. Private cache
files contain hashes only. Extension inventory runs at session end or manually,
under a separate lock, so prompts do not wait for it. Direct manual sync:

```sh
bash ~/dotfiles/install/cursor.sh sync-extensions
```

## Validation and measurements

Run `./tests/run.sh` for the canonical Docker suite. Focused tests cover
applicable/inapplicable rules, upstream drift, symlink aliases, legacy jq syntax,
cache append/reset/concurrency, Cursor imports/inventory, GUI runtime paths,
flat/PLAT layouts, and fresh shell environment changes. The `execution` case in
`tests/agent_behavior.py` exercises generated zsh code in the native selected
model; its verifier checks counts, spaces, sorting, alternate cwd, and unchanged
inputs.

For a repeatable Cursor comparison against a saved pre-change git revision:

```sh
uv run tests/cursor-hook-benchmark.py --baseline PRE_CHANGE_REF
```

Benchmark medians are local subprocess measurements, not additive end-to-end
model latency. Keep original commands, iteration counts, cache warmth, input
sizes, and runtime state with any reported comparisons. A successful synthetic
hook probe does not establish that an already-open app reloaded its hook config.
See [troubleshooting](troubleshooting.md) for missing PyYAML, shell variable
collisions, Cargo test arguments, and bounded output recipes.
