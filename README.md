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
   `http://localhost:11434/v1` (Ollama), plus `model_aliases` — `local` and
   `local-8b` for switching between local models (edit the script's
   `qwen3.5:4b` default to your own model).
4. Copies your `context.md` in, if you passed one.

Usage after setup:

```bash
hermes -z "your task"              # local Ollama — default model
hermes -m local-8b -z "your task"  # local Ollama — 8b fallback
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
