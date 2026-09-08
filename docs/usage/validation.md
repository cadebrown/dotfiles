# Validation before publishing

The Docker bootstrap suite is only one part of CI. ShellCheck, fast fixtures,
documentation, secrets, workflow linting, macOS smoke, and infrastructure checks
also need to pass. Their commands live in `tests/ci.sh`, which both local checks
and GitHub Actions invoke.

```sh
./tests/ci.sh full           # complete local gate
./tests/ci.sh quality        # shell, fixtures, docs, secrets, workflow lint
./tests/ci.sh shell          # syntax and ShellCheck
./tests/ci.sh fast           # fixture-based tests
./tests/ci.sh macos          # constrained-PATH smoke; requires macOS
./tests/ci.sh infrastructure # backend-free OpenTofu validation
./tests/run.sh              # Docker bootstrap only
```

The full gate runs quality and infrastructure, macOS smoke on macOS, then the
Docker bootstrap suite. It requires a running Docker daemon and the declared
validation tools. Missing tools and failed checks stop the gate; it does not
silently install dependencies or skip unavailable checks. Temporary homes,
documentation output, and provider data keep checks away from live settings.
The full gate always rebuilds the test image from the committed Dockerfile;
`DOCKER_BUILD=0` remains available only for focused `tests/run.sh` iterations.

## Install the push gate

Once per Git checkout:

```sh
./tests/install-hooks.sh
```

This selects the versioned `.githooks` directory in this repository's local Git
configuration. It refuses to replace an existing hook configuration or
executable hooks; compose existing hooks explicitly first. It does not change
global Git settings. Git does not clone local configuration, so a fresh clone
needs this installation too.

Normal `git push` now validates every distinct outgoing commit in an independent
temporary clone with its history. It calls that commit's `tests/ci.sh full` and
blocks the entire push if validation fails or the entrypoint is missing.
Clones live under the ignored `.ci-validation/` directory so Docker uses the
same shared host mount as the original checkout; each clone is removed on exit.
Uncommitted fixes cannot conceal committed failures; unrelated working changes
are left alone. Branch and annotated-tag updates to the same commit share one
validation within the push. Ref deletion publishes no new code and needs no
validation. No success receipt from an earlier commit or environment is reused.

The validation runs once as part of the push, so there is no need to manually run
the full gate immediately before pushing. Use focused modes while editing.
After a failed check, fix and commit the correction before retrying.

## What a passing gate establishes

A pass establishes the tested commit on this host and its Docker architecture.
It does not establish the other hosted architecture, other operating systems,
or the availability of remote registries at a later time. Check the exact pushed
SHA's GitHub Actions run before reporting CI success:

```sh
gh run list --commit "$(git rev-parse HEAD)"
gh run watch RUN_ID --exit-status
```

Git hooks are local safeguards and can be bypassed by Git options or by a clone
where they are not installed. GitHub required checks on `main` provide the
server-side boundary when that publishing policy is enabled. A hook alone
cannot guarantee that failing code never reaches `main`.
