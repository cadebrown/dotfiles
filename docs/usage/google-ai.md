# Gemini and Google APIs

Use Gemini CLI for coding, the Gemini Developer API for model calls and Live
audio, Google Cloud ADC for Vertex, and separate Workspace OAuth for personal
Google data. These have different credentials, quotas, and billing.

## Install and check

Prerequisites: the managed Node and Python toolchains; a Google account for
interactive login or an AI Studio API key for application calls.

```sh
bash ~/dotfiles/install/node.sh          # Gemini CLI + pinned Workspace CLI
bash ~/dotfiles/install/python.sh        # locked google-genai probe runtime
bash ~/dotfiles/install/agent-tools.sh   # df-gemini launcher
bash ~/dotfiles/install/auth.sh google-status
df-gemini --check-runtime               # local import check; no model request
```

Normal bootstrap runs Node and Python under `DF_DO_NODE` and `DF_DO_PYTHON`,
and always deploys the helper commands. Node packages live in the selected
nvm runtime; uv environments/cache respect the flat or `DF_USE_PLAT=1` layout.
On macOS, the Brewfile owns `gcloud-cli`. Linux users must provision Google's
[rootless archive installation](https://cloud.google.com/sdk/docs/install)
before Cloud/Vertex auth; this repo's macOS cask does not install gcloud there.

Expected result: `gemini --version`, `gws --version`, and the runtime check work.
A local import check does not establish API access. Status reports configured
credentials without printing them and keeps CLI project and ADC quota project
separate; it cannot determine a paid subscription or a model's usable quota.

## Choose the auth path

| Workflow | Setup | Credential / account boundary |
| --- | --- | --- |
| Gemini CLI with a personal Google plan | `bash ~/dotfiles/install/auth.sh gemini-cli` | Select **Login with Google**; `/auth` changes an existing selection |
| Gemini Developer API, including Live | `bash ~/dotfiles/install/auth.sh gemini` | `GEMINI_API_KEY` in owner-only `~/.gemini.env` |
| gcloud administration | `bash ~/dotfiles/install/auth.sh gcloud` | gcloud's own account login |
| Cloud MCP | `bash ~/dotfiles/install/auth.sh google` | Application Default Credentials (ADC) |
| Vertex model APIs | `bash ~/dotfiles/install/auth.sh vertex` | ADC, explicit project/region, and Vertex API enablement |
| Existing Workspace MCP | `bash ~/dotfiles/install/auth.sh workspace` | Separate Desktop OAuth client in `~/.google.env` |
| Workspace CLI | `bash ~/dotfiles/install/auth.sh workspace-cli` | Separate gws consent; read-only Drive/Gmail/Calendar scope selection |

The main auth walk offers Gemini API-key storage and Gemini CLI login. Open a
new login shell after storing a key, or run `. ~/.gemini.env` in the current
shell. `df-gemini` also loads this file when neither key is inherited. Keys
stay outside chezmoi and Git. No separate Live key is needed.

Google's GenAI SDK prioritizes `GOOGLE_API_KEY` over `GEMINI_API_KEY` if both
exist. Avoid a generic global Google key: it can silently select another
project or an incompatible API restriction. The probe fixes its backend to
Developer API unless you explicitly pass `--backend vertex`; a global
`GOOGLE_GENAI_USE_VERTEXAI` does not change that choice. See
[key configuration](https://ai.google.dev/gemini-api/docs/api-key).

The gcloud active project is a resource default. ADC's `quota_project_id` is a
quota/billing attribution setting and can differ. `GOOGLE_CLOUD_QUOTA_PROJECT`
overrides the ADC quota project for supporting libraries;
`GOOGLE_APPLICATION_CREDENTIALS` can select an entirely different credential
file. The account signed into gcloud need not be the ADC identity. See
[Google's authentication guide](https://cloud.google.com/docs/authentication)
and [Cloud MCP](/usage/google-cloud-mcp/).

The MCP relay has an additional `GOOGLE_CLOUD_PROJECT` override and a gcloud
project fallback; its [documented header selection](/usage/google-cloud-mcp/#use)
is distinct from the SDK's ADC quota field. A gcloud token refresh cannot
validate a different credential file selected for the relay.

## Gemini text and Live probes

```sh
. ~/.gemini.env
df-gemini models
df-gemini generate --model gemini-3.8-flash --prompt 'Reply with just OK.'
df-gemini live --model gemini-3.1-flash-live-preview --output /tmp/gemini-live.wav
```

These commands contact Google and consume the selected project's quota. The
Live probe sends a short synthetic text prompt and writes the spoken answer;
it does not record a microphone or camera. Success requires received audio and
a completed turn, and produces a 24 kHz mono PCM WAV. It refuses to overwrite
an existing file. Use `--timeout` to bound the session. Listen on macOS with
`afplay /tmp/gemini-live.wav`, or use any WAV player on Linux.

`models` establishes discovery access only: listed models can still reject a
request for quota, billing, region, or permission reasons. A 429 is a failed
probe, not proof the integration is ready. Select a model with nonzero quota
in [AI Studio rate limits](https://aistudio.google.com/rate-limit).

For Vertex, first choose a project with billing and the Vertex AI API enabled,
then use its supported regional model ID explicitly:

```sh
df-gemini generate --backend vertex --project YOUR_PROJECT_ID \
  --location us-central1 --model YOUR_VERTEX_MODEL_ID --prompt 'Reply with OK.'
```

The helper does not globally switch other applications to Vertex or transfer
your Developer API key to it. The interactive `vertex` auth command offers
API enablement; running a status or runtime check never enables Cloud APIs.

## Libraries for new projects

Install SDKs in each application's dependency graph, not as global CLI tools:

```sh
# In a Python project
uv add google-genai
# In a JavaScript / TypeScript project
npm install @google/genai
```

The reusable probe separately locks `google-genai` through uv script metadata.
Google also maintains Go (`google.golang.org/genai`), Java, and C# GenAI SDKs.
Its supported-language list does not include Rust; use the documented HTTP
and WebSocket protocols or evaluate a community crate explicitly. Do not start
new work with legacy `google-generativeai` or `@google/generativeai`; Google
marks them unmaintained and directs Live/Veo users to GenAI.
[Official SDK list](https://ai.google.dev/gemini-api/docs/libraries).

## Limits and cost

Reference checked **2026-09-09**; always inspect the selected project's live
dashboard before choosing capacity. Account observations belong in private
machine notes, not this public handbook.

| Quota pool | Current reference | How to confirm yours |
| --- | --- | --- |
| Gemini CLI Google login | Individual 1,000; AI Pro 1,500; AI Ultra 2,000 requests/day | Correct account in CLI; `/stats` and account plan |
| Developer API | Model-specific RPM, input TPM, RPD; limits apply per project, shared by its keys | AI Studio Rate Limit page |
| Vertex | Project, model, region and purchased capacity determine service limits | Cloud Console quota and billing pages |
| Workspace | Per-API and often per-user/project limits | API's quota page and OAuth consent |

CLI requests are model requests, not necessarily one user prompt: a coding
task can make multiple calls. CLI subscription quotas do not establish an API
billing tier. Personal Google login usually needs no Cloud project; enterprise
accounts have additional requirements. See [CLI quotas and supported
plans](https://geminicli.com/docs/resources/quota-and-pricing/) and
[CLI authentication](https://geminicli.com/docs/get-started/authentication/).

AI Pro also includes $10/month in Google Developer Program Cloud credits;
current Ultra variants list $40 or $100/month. Link the eligible membership
and inspect [My Benefits](https://me.developers.google.com/benefits) to redeem
credits against a billing account. Credit eligibility is not proof of
activation, remaining balance, or a paid API tier. See the
[benefits FAQ](https://developers.google.com/profile/help/benefits) and
[plan comparison](https://developers.google.com/program/plans-and-pricing).
Google also offers subscriber benefits inside AI Studio; these are distinct
from production pay-per-request API keys.
[AI Studio subscriber announcement](https://blog.google/innovation-and-ai/technology/developers-tools/google-one-ai-studio/).

Developer API daily quotas reset at midnight Pacific. Current paid progression
requires linked billing for Tier 1; Tier 2 requires $100 paid and 3 days after
first payment; Tier 3 requires $1,000 paid and 30 days. Current per-ten-minute
spend limits are $10/$50/$200 for tiers 1/2/3. These are provider limits, not a
recommended budget or an entitlement to every model. Verify actual values in
[rate-limit documentation](https://ai.google.dev/gemini-api/docs/rate-limits).

Examples from [current API pricing](https://ai.google.dev/gemini-api/docs/pricing):
Gemini 3.8 Flash paid text input/output costs $0.75/$3.75 per million tokens
through 2026-12-31, scheduled to double on 2027-01-01. Gemini 3.1 Flash Live
lists $3 per million audio input tokens ($0.005/minute) and $12 per million
audio output tokens ($0.018/minute); other Live models have their own prices. Caching, search/maps
grounding, image/video output and batch usage have separate line items. Free
tier content may be used to improve Google's products; the paid-tier table
says it is not. Review the applicable terms before submitting private data.

## Live application design

Live is a stateful WebSocket API, still marked Preview. Current input is text,
16 kHz little-endian 16-bit PCM audio, and image frames at up to 1 FPS; output
audio is 24 kHz PCM. Gemini CLI is not a substitute for this streaming API.
[Live overview](https://ai.google.dev/gemini-api/docs/live-api).

For a browser or glasses client, keep the persistent key on your backend and
issue constrained ephemeral tokens. These are Live-only, currently `v1beta`,
and default to one session with one minute to start and 30 minutes validity.
Do not embed the persistent key in JavaScript, an APK, or a client config.
[Ephemeral-token guide](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens).

Without compression, the session guide gives 15 minutes audio-only or two
minutes audio/video; connections themselves last roughly ten minutes. Use
context compression and session resumption for longer conversations, and
handle the server's `GoAway` message. These are separate from quota and token
expiration. [Session management](https://ai.google.dev/gemini-api/docs/live-api/session-management).

Process all parts of every received event. Gemini 3.1 Live can combine audio
and transcript in one event, and text updates use `send_realtime_input`.
Model capabilities differ: do not assume every Live model supports affective
dialogue, proactive audio, or asynchronous tools.
[Capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities).

## Workspace and optional services

`gws` covers Drive, Gmail, Calendar, Sheets, Docs and other discovery-backed
Workspace APIs. Its Google-hosted repository explicitly says it is **not an
officially supported Google product**, so this setup pins 0.22.5. Its npm
postinstall downloads a matching binary and checks its SHA-256. The auth
helper maps the existing Workspace OAuth client only into the gws process;
gws keeps its own tokens. It starts with read-only scopes for three services.
Selecting more access is a separate consent action. Do not run `gws auth setup`
casually: it can create a project and enable APIs. Unverified personal-account
OAuth clients should select a few services rather than the large recommended
scope bundle. [Upstream usage and auth](https://github.com/googleworkspace/cli).

| Addition | Useful for | Install / auth approach |
| --- | --- | --- |
| Embeddings, image generation, Veo, speech generation | Retrieval, assets, narration | Existing GenAI SDK; check model-specific billing/access |
| Search/Maps grounding | Answers backed by current web/place information | Model-specific tool configuration and pricing |
| Firebase AI Logic | Browser, Android, Apple app integration | Platform SDK + App Check; Firebase CLI only if managing Firebase projects |
| ADK | Agent tools, streaming orchestration and evaluation | Project-local `google-adk`; add when the application needs it |
| Cloud Speech, Vision, Translation, Document AI | Dedicated transcription, OCR and document pipelines | Enable selected Cloud APIs; ADC/IAM and per-service client libraries |
| Maps Platform / Places / Routes | Location and route features | Separate restricted Maps key and service billing |
| YouTube Data API | Video/channel data workflows | API-specific quota and OAuth where user data is needed |

These are researched options, not automatically enabled paid services. Start
with [Gemini capabilities](https://ai.google.dev/gemini-api/docs),
[Firebase AI Logic](https://firebase.google.com/docs/ai-logic),
[ADK](https://google.github.io/adk-docs/),
[Cloud API catalog](https://cloud.google.com/apis),
[Maps Platform](https://developers.google.com/maps/documentation), and
[YouTube Data API](https://developers.google.com/youtube/v3).

## Source and validation

Authoritative sources: [auth helper](../../install/auth.sh),
[npm packages](../../packages/npm.txt),
[reviewed install scripts](../../packages/npm-allow-scripts.txt),
[Python preparation](../../install/python.sh),
[SDK probe](../../install/gemini-api.py),
[SDK lock](../../install/gemini-api.py.lock),
[launcher](../../home/dot_local/bin/executable_df-gemini), and
[launcher installer](../../install/agent-tools.sh).

```sh
bats tests/google-auth.bats tests/gemini-api.bats
./tests/run.sh
./tests/ci.sh docs
```

Fixtures verify auth dispatch, credential masking, explicit backend selection,
and Live response handling without account credentials. Live access requires
the separate probes above. See [troubleshooting](/usage/troubleshooting/) for
ADC/project confusion and failed or exhausted quota.
