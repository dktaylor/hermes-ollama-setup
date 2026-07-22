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
   [`hermes.conf`](hermes.conf) (see **Configuration** below).
4. Copies your `context.md` in, if you passed one.

## Configuration

Model and context settings live in [`hermes.conf`](hermes.conf), not
hardcoded in the script.

**`HERMES_ALIASES`** is a bash array of `name=ollama-model-tag` pairs — one
per line, as many as you want:

```bash
HERMES_ALIASES=(
    "local=qwen3.5:4b"
    "local-8b=qwen3:8b"
    # "coding=qwen2.5-coder:7b-instruct-q8_0"
    # "big-context=qwen3.5:4b"
)
```

Each `name` becomes both the YAML key under `model_aliases:` in
`config.yaml` *and* the value you pass on the command line —
`"coding=..."` above gives you `hermes -m coding -z "..."`. All aliases
share the same `HERMES_CONTEXT_LENGTH` and `OLLAMA_BASE_URL` (below); it's a
plain array, so it isn't env-var-overridable — edit it directly.

The remaining settings are scalars, each overridable by exporting the
same-named env var before running `setup-hermes.sh` (an exported var always
wins over the file's default) instead of editing the file:

| Variable | Default | Meaning |
|---|---|---|
| `HERMES_DEFAULT_ALIAS` | `local` | Which `HERMES_ALIASES` key Hermes uses with no `-m` flag |
| `HERMES_CONTEXT_LENGTH` | `131072` | Written to both `context_length` and `ollama_num_ctx` in `config.yaml` |
| `OLLAMA_BASE_URL` | `http://localhost:11434/v1` | Ollama's OpenAI-compatible endpoint |

**The shipped defaults are tuned for an 8 GB dGPU (RTX 4060)** —
`qwen3.5:4b` with **q8_0 KV cache quantization** and **131072 (128K)
context** is what fits in 8 GB of VRAM alongside a small embedding model on
this hardware. `q8_0` is set on the *Ollama* side, not by this script
(`OLLAMA_KV_CACHE_TYPE=q8_0` in Ollama's systemd `override.conf`, or the
equivalent env var if you run Ollama another way) — `HERMES_CONTEXT_LENGTH`
here needs to match whatever your own Ollama setup can actually hold, at
whatever quantization you use. If you have more or less VRAM, or a different
GPU vendor, adjust `HERMES_ALIASES` and `HERMES_CONTEXT_LENGTH` (and your
Ollama-side KV cache setting) to fit.

Usage after setup (with the shipped defaults):

```bash
hermes -z "your task"              # default alias (local)
hermes -m local-8b -z "your task"  # local-8b alias
hermes                             # interactive session
```

Requires: a running Ollama daemon, `sudo` access (installs `ripgrep` +
writes to another user's home if `target_user` isn't you).

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
