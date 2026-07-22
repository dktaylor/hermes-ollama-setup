# hermes-ollama-setup

A small installer script for running [Hermes](https://hermes-agent.nousresearch.com/)
(the CLI agent) against a local Ollama model.

See [DECISIONS.md](DECISIONS.md) for why this repo is shaped the way it is.

## `setup-hermes.sh` — installs and configures Hermes

```bash
./setup-hermes.sh [target_user]
```

- `target_user` — the user to install Hermes for (default: `devuser`).

What it does, idempotently (safe to re-run):

1. Installs `ripgrep` (Hermes dependency).
2. Downloads and installs Hermes to `~/.local/bin/hermes`.
3. Patches `~/.hermes/config.yaml`: default provider → `custom` pointing at
   Ollama, plus a `model_aliases` entry for every alias defined in
   [`hermes.conf`](hermes.conf) (see **Configuration** and **Context
   length: what actually happens** below — read that before adding a
   second model alias).

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

- KV cache quantization (`OLLAMA_KV_CACHE_TYPE`) is daemon-wide in Ollama —
  not per-model, not per-request. It's set on the *Ollama* side, and every
  model that daemon serves shares it.
- Context length genuinely can be per-model, but not via Hermes'
  `model_aliases` config — there's no field for it there. Leaving
  `ollama_num_ctx` unset (as shipped) makes Hermes auto-detect each active
  model's real context from Ollama directly; `context_length` then only
  caps that auto-detected value, it doesn't force it up.
- Before adding a second `HERMES_ALIASES` entry, verify the model's real
  context and check it'll actually fit your VRAM at that context — don't
  assume:
  ```bash
  curl localhost:11434/api/show -d '{"name":"<model>"}'
  # check model_info.*.context_length, and any Modelfile num_ctx under "parameters"
  ```
  Hermes refuses any model under 64K effective context, and a model forced
  above its real context to clear that bar can exceed your VRAM budget
  instead — see [DECISIONS.md](DECISIONS.md) for what happened when this repo
  shipped a second alias without checking first.

## License

MIT — see [LICENSE](LICENSE).
