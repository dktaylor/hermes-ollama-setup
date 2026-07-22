# hermes-ollama-setup

A small installer script for running [Hermes](https://hermes-agent.nousresearch.com/)
(the CLI agent) against a local Ollama model.

## `setup-hermes.sh` — installs and configures Hermes

```bash
./setup-hermes.sh [target_user] [path/to/context.md]
```

- `target_user` — the user to install Hermes for (default: `devuser`).
- `path/to/context.md` — optional. If given, its content is copied to
  `~/.hermes/context.md` and picked up as Hermes' injected session context.
  This is *your* project's context — nothing project-specific ships in this
  repo.

What it does, idempotently (safe to re-run):

1. Installs `ripgrep` (Hermes dependency).
2. Downloads and installs Hermes to `~/.local/bin/hermes`.
3. Patches `~/.hermes/config.yaml`: default provider → `custom` pointing at
   Ollama, plus a `model_aliases` entry for every alias defined in
   [`hermes.conf`](hermes.conf) (see **Configuration** and **Context
   length: what actually happens** below — read that before adding a
   second model alias).
4. Copies your `context.md` in, if you passed one.

## Configuration

Model and context settings live in [`hermes.conf`](hermes.conf), not
hardcoded in the script.

**`HERMES_ALIASES`** is a bash array of `name=ollama-model-tag` pairs — one
per line, as many as you want:

```bash
HERMES_ALIASES=(
    "local=qwen3.5:4b"
    # "coding=qwen2.5-coder:7b-instruct-q8_0"
)
```

Each `name` becomes both the YAML key under `model_aliases:` in
`config.yaml` *and* the value you pass on the command line —
`"coding=..."` above gives you `hermes -m coding -z "..."`. All aliases
share the same `HERMES_CONTEXT_LENGTH` and `OLLAMA_BASE_URL` (below); it's a
plain array, so it isn't env-var-overridable — edit it directly.

**Before adding a second alias, read "Context length: what actually
happens" below.** There's no per-alias context override in Hermes'
`model_aliases` schema — every alias you add shares the same context
ceiling, and a model that needs a different one can fail outright or tank
performance. This is exactly why the shipped default has only one alias.

The remaining settings are scalars, each overridable by exporting the
same-named env var before running `setup-hermes.sh` (an exported var always
wins over the file's default) instead of editing the file:

| Variable | Default | Meaning |
|---|---|---|
| `HERMES_DEFAULT_ALIAS` | `local` | Which `HERMES_ALIASES` key Hermes uses with no `-m` flag |
| `HERMES_CONTEXT_LENGTH` | `131072` | Written to `context_length` in `config.yaml` — a ceiling, not a forced value (see below) |
| `OLLAMA_BASE_URL` | `http://localhost:11434/v1` | Ollama's OpenAI-compatible endpoint |

**The shipped default is tuned for an 8 GB dGPU (RTX 4060)** — `qwen3.5:4b`
with **q8_0 KV cache quantization** and **131072 (128K) context** is what
fits in 8 GB of VRAM alongside a small embedding model on this hardware.
`q8_0` is set on the *Ollama* side, not by this script
(`OLLAMA_KV_CACHE_TYPE=q8_0` in Ollama's systemd `override.conf`, or the
equivalent env var if you run Ollama another way — and note it's daemon-wide,
not per-model, see below). If you have more or less VRAM, or a different GPU
vendor, adjust `HERMES_ALIASES` and `HERMES_CONTEXT_LENGTH` (and your
Ollama-side KV cache setting) to fit.

Usage after setup (with the shipped default):

```bash
hermes -z "your task"   # default alias (local)
hermes                  # interactive session
```

Requires: a running Ollama daemon, `sudo` access (installs `ripgrep` +
writes to another user's home if `target_user` isn't you).

## Context length: what actually happens

This took real live-machine testing to pin down, so it's documented in full
here rather than left to be re-derived later.

**KV cache quantization (`q8_0`, `q4_0`, `f16`, ...) is daemon-wide in
Ollama, not per-model or per-request.** `OLLAMA_KV_CACHE_TYPE` is a single
env var on the Ollama process — every model it serves uses the same
quantization. There's no config on the Hermes or Ollama-request side to
vary this per model. The only way to genuinely run two models at different
KV quantizations at once is two separate Ollama daemons on different ports
(each with its own `OLLAMA_HOST`, `OLLAMA_KV_CACHE_TYPE`, etc.) — a bigger
undertaking, and one that doesn't add VRAM: both daemons still share the
same physical GPU, so it only helps if the two models aren't resident
simultaneously. Not implemented here; flagged as a possible future
direction, not attempted.

**Context length *is* genuinely per-model — but not via Hermes' config.**
Checked Hermes' actual source
(`hermes_cli/model_switch.py`): a `model_aliases` entry parses into a
`DirectAlias` — a `NamedTuple` of exactly `model`, `provider`, `base_url`.
No context field exists there at all. Setting `context_length` or
`ollama_num_ctx` only works in the single top-level `model:` block, and
applies to whichever model is currently active — not per-alias.

**What `context_length` and `ollama_num_ctx` actually do (from Hermes'
source, `agent/agent_init.py`):**

- If `ollama_num_ctx` is set explicitly, Hermes forces that exact value for
  every request, to every model, no matter what that model actually
  supports. This is what earlier versions of this script did, hardcoded.
- If `ollama_num_ctx` is *unset* (this script's current behavior) and the
  endpoint is local, Hermes queries Ollama's `/api/show` for the *currently
  active model* and reads its real trained context from GGUF metadata —
  genuinely per-model, automatically, no config needed.
- `context_length`, if set, then acts as a **ceiling** on that
  auto-detected value — it does not force it up. A model with a smaller
  native context than the ceiling just uses its own smaller value.
- Ollama's daemon-side `OLLAMA_CONTEXT_LENGTH` env var is the fallback of
  last resort if auto-detection fails for any reason (network hiccup,
  non-Ollama endpoint, etc.) — set it in Ollama's own config so a detection
  failure doesn't silently fall back to Ollama's un-set default (2048).

**Why this matters, confirmed by live testing on an RTX 4060 8 GB:**
`qwen3.5:4b`'s real native context is 262144 (GDN hybrid — no clamp);
`qwen3:8b`'s is 40960. Hermes itself refuses to use *any* model whose
effective context is below 64,000 tokens ("Hermes needs at least 64,000
tokens for reliable tool use") — so `qwen3:8b` at its honest native context
doesn't even meet Hermes' own floor. Forcing it up via `ollama_num_ctx`
(the only way to make Hermes accept it) technically works, but the model's
loaded footprint (8.8 GB) then exceeds the 8 GB card: confirmed **22%/78%
CPU/GPU split** and **70+ seconds for a trivial request**, versus **5.4
seconds** requesting its own correct 40960 directly (still split, since 8.8
GB just doesn't fit regardless of context — the context override wasn't
even the main problem there, the model's size was). Both numbers are cold
loads (first request after the model wasn't resident) — a warm/already-loaded
model responds much faster than either figure; the *relative* gap between
them is the meaningful part, not the absolute seconds.

**The takeaway:** don't add a second `HERMES_ALIASES` entry for a model
whose real context is under ~64K, or whose loaded footprint doesn't
comfortably fit your VRAM at that context — check both with `curl
localhost:11434/api/show -d '{"name":"<model>"}'` (look at
`model_info.*.context_length` and any Modelfile `num_ctx` under
`parameters`) before adding it, not after.

**Not included:** a Claude/Anthropic-API model alias. Hermes' remote-model
support needs a billed [console.anthropic.com](https://console.anthropic.com)
API key — separate from, and not covered by, a Claude Code subscription. If
you want Claude available inside Hermes, add your own `model_aliases` entry
in `~/.hermes/config.yaml` with your own key.

**Not included:** an MCP/RAG bridge. If you're pairing this with a
self-hosted Open WebUI RAG instance, see
[rag-stack](https://github.com/dktaylor/rag-stack), which owns and
maintains the MCP bridge for that.

## License

MIT — see [LICENSE](LICENSE).
