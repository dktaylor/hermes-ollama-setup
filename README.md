# hermes-ollama-setup

Two small, independent tools for running [Hermes](https://hermes-agent.nousresearch.com/)
(the CLI agent) against a local Ollama model with Claude as a fallback
"brain," backed by a self-hosted [Open WebUI](https://openwebui.com/) RAG
instance.

## `setup-hermes.sh` — installs and configures Hermes

Installs the Hermes CLI, points its default model at a local Ollama
endpoint, and adds `model_aliases` so you can escalate to Claude for
anything that needs more than a fast local model:

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
   `http://localhost:11434/v1` (Ollama), plus `model_aliases` —
   `brain` → `claude-opus-4-8`, `claude` → `claude-sonnet-4-6`, `local` →
   whatever Ollama model you configure (edit the script's `qwen3.5:4b`
   default to your own model).
4. Copies your `context.md` in, if you passed one.
5. Leaves an `ANTHROPIC_API_KEY=REPLACE_ME` placeholder in `~/.hermes/.env`.

Usage after setup:

```bash
hermes -z "your task"           # local Ollama — fast, routine
hermes -m brain -z "your task"  # Claude Opus — complex/architectural
hermes                          # interactive session
```

Requires: a running Ollama daemon, `sudo` access (installs `ripgrep` +
writes to another user's home if `target_user` isn't you).

## `mcp/openwebui-mcp.py` — MCP bridge to Open WebUI RAG

A stdio [MCP](https://modelcontextprotocol.io/) server that gives Hermes (or
Claude Code, or any other MCP client) tool access to a self-hosted Open
WebUI instance's RAG knowledge bases, organized into four tiers:

| Tier | KB name pattern | Contains |
|------|------------------|----------|
| 1 | `framework-{name}` | Framework/CMS reference docs |
| 2 | `project-{slug}` | Per-project source + devops config |
| 3 | `common-issues` | Cross-cutting gotchas, bugs, fixes |
| 4 | `devops-general` | Infrastructure reference |

Tools exposed: `rag_search`, `rag_add_doc`, `rag_add_issue`,
`rag_index_project`, `rag_list_kbs`.

Config via environment:

- `OPENWEBUI_URL` — base URL (default `http://localhost:3000`)
- `OPENWEBUI_TOKEN` — JWT auth token
- `RAG_CWD_DETECT` — `1` (default) to auto-detect project/framework from the
  current working directory

Register it with your MCP client pointing at
`python3 mcp/openwebui-mcp.py`. No fedora-proart-kickstart-specific code —
works with any Open WebUI instance and any 4-tier (or fewer) KB layout.

## License

MIT — see [LICENSE](LICENSE).
