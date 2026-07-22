# Decisions

Short record of non-obvious choices in this repo and why, so they don't get
re-litigated or re-guessed later.

## Model/context config lives in `hermes.conf`, not hardcoded in the script

**Why:** so the repo is actually reusable by someone else's hardware/models
without editing Python embedded in a bash heredoc.

## `HERMES_ALIASES` is a bash array, arbitrary count, not a fixed pair

**Why:** users want purpose-specific models (coding, big-context, etc.), not
just a fixed default+fallback slot.

## `setup-hermes.sh` does not set `ollama_num_ctx`, only `context_length` (as a ceiling)

**Why:** `ollama_num_ctx`, when set, forces that exact value onto *every*
model regardless of what it actually supports. Hermes has built-in
per-model context auto-detection (via Ollama's `/api/show`) when
`ollama_num_ctx` is left unset — `context_length` still caps the
auto-detected value, it just doesn't force it up. Confirmed via Hermes'
own source (`agent/agent_init.py`) and live-tested.

## Shipped default is a single alias (`local`), no second/fallback model

**Why:** live-tested a second alias (`qwen3:8b`) on the reference 8GB GPU
and found it doesn't work: its real context (40960) is below Hermes' hard
64K minimum, and forcing it above that to satisfy Hermes causes VRAM
overflow (partial CPU offload, 10x+ latency). There's no per-alias context
override in Hermes' config schema to work around this per-model — confirmed
via source (`hermes_cli/model_switch.py`). Adding a second alias later
needs a model that clears both constraints, verified via `/api/show`
first, not assumed.

## KV cache quantization is not configurable per-model here

**Why:** it's a daemon-wide Ollama setting (`OLLAMA_KV_CACHE_TYPE`), not
per-model or per-request — confirmed no per-request override actually
works. The only way to vary it per model is running multiple Ollama
daemons on different ports, which doesn't add VRAM (same GPU either way)
and isn't implemented here. Flagged as a possible future direction, not
attempted.

## No external context/config injection in this script

**Why:** keeps this installer scoped to exactly one job — wiring Hermes to
a local Ollama endpoint. Anything project-specific belongs in whatever's
calling this script, not baked into it.
