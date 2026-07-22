#!/usr/bin/env bash
# =============================================================================
# setup-hermes.sh — Install and configure Hermes agent for a local Ollama setup
#
# Usage: setup-hermes.sh [target_user] [path/to/context.md]
# Idempotent: safe to re-run.
#
# What it does:
#   1. Installs ripgrep (required by Hermes)
#   2. Downloads and installs Hermes agent to ~/.hermes/
#   3. Writes ~/.hermes/config.yaml (points at local Ollama; local/local-8b
#      model aliases for switching between local models)
#   4. Copies the given context.md (if any) into ~/.hermes/ — this is your
#      own project's Hermes system-prompt context, not part of this repo
#
# NOTE: this intentionally does NOT wire up a Claude/Anthropic-API model
# alias. Hermes' remote-model support needs a billed console.anthropic.com
# API key — separate from (and not covered by) a Claude Code subscription.
# If you want Claude available inside Hermes, add your own model_aliases
# entry in ~/.hermes/config.yaml with your own API key.
# =============================================================================
set -euo pipefail

TARGET_USER="${1:-devuser}"
CONTEXT_SRC="${2:-}"
USER_HOME="/home/${TARGET_USER}"

run_as_user() {
    sudo -u "$TARGET_USER" env HOME="$USER_HOME" PATH="$USER_HOME/.local/bin:$PATH" "$@"
}

echo "Installing Hermes agent..."
echo "=============================================="

# --- Step 1: ripgrep (required by Hermes) ---
if ! command -v rg &>/dev/null; then
    echo "  Installing ripgrep..."
    dnf install -y ripgrep
fi

# --- Step 2: Install Hermes ---
HERMES_BIN="$USER_HOME/.local/bin/hermes"
if [[ -x "$HERMES_BIN" ]]; then
    echo "  Hermes already installed at $HERMES_BIN — skipping download."
else
    echo "  Downloading Hermes installer..."
    run_as_user bash -c \
        'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup'
fi

# --- Step 3: Write config.yaml ---
HERMES_CONF="$USER_HOME/.hermes/config.yaml"
if [[ -f "$HERMES_CONF" ]]; then
    echo "  Backing up existing config to config.yaml.bak"
    cp "$HERMES_CONF" "${HERMES_CONF}.bak"
fi

# Patch key settings in-place (preserves all other defaults)
python3 - "$HERMES_CONF" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

patches = [
    # Default model
    (r'(^\s*default:\s*")[^"]*(")', r'\g<1>qwen3.5:4b\2'),
    # Provider
    (r'(^\s*)provider:\s*"auto"', r'\1provider: "custom"  # local Ollama'),
    # Base URL
    (r'(^\s*)base_url:\s*"https://openrouter\.ai/api/v1"',
     r'\1base_url: "http://localhost:11434/v1"'),
    # Context length: qwen3.5:4b is natively 262K (GDN hybrid, no n_ctx_train
    # clamp) — 131072 is honest, not a padded-up workaround like the old
    # 64K-minimum-check bypass was for qwen2.5-coder.
    (r'#\s*context_length:\s*131072', 'context_length: 131072'),
]

for pattern, replacement in patches:
    content = re.sub(pattern, replacement, content, flags=re.MULTILINE)

# Add ollama_num_ctx after context_length if not present
# Must stay in sync with OLLAMA_CONTEXT_LENGTH in the ollama.service.d
# override.conf — Ollama's /v1 endpoint can ignore this and silently fall
# back to the daemon default (verified: unset daemon default loads at 4096).
if 'ollama_num_ctx' not in content:
    content = content.replace(
        'context_length: 131072',
        'context_length: 131072\n  ollama_num_ctx: 131072  # force Ollama 131K context window'
    )

# Add model_aliases block if not present
if 'model_aliases:' not in content:
    aliases = """
model_aliases:
  local:
    model: qwen3.5:4b
    provider: custom
    base_url: "http://localhost:11434/v1"
  local-8b:
    model: qwen3:8b   # legacy fallback — clamps to 40960 ctx (no YaRN in GGUF)
    provider: custom
    base_url: "http://localhost:11434/v1"
"""
    # Insert before Privacy section
    content = content.replace('# =============================================================================\n# Privacy', aliases + '# =============================================================================\n# Privacy')

with open(path, 'w') as f:
    f.write(content)

print("  config.yaml patched.")
PYEOF

chown "$TARGET_USER:$TARGET_USER" "$HERMES_CONF"

# --- Step 4: Copy context.md ---
CONTEXT_DST="$USER_HOME/.hermes/context.md"
if [[ -n "$CONTEXT_SRC" && -f "$CONTEXT_SRC" ]]; then
    cp "$CONTEXT_SRC" "$CONTEXT_DST"
    chown "$TARGET_USER:$TARGET_USER" "$CONTEXT_DST"
    echo "  context.md installed to ~/.hermes/"
fi

echo ""
echo "  Hermes setup complete."
echo "  Usage:"
echo "    hermes -z 'your task'           # local Ollama (default model)"
echo "    hermes -m local-8b -z 'your task'  # local Ollama (8b fallback)"
echo "    hermes                          # interactive session"
echo "=============================================="
