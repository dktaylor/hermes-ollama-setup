#!/usr/bin/env bash
# =============================================================================
# setup-hermes.sh — Install and configure Hermes agent for a local Ollama setup
#
# Usage: setup-hermes.sh [target_user]
# Idempotent: safe to re-run.
#
# What it does:
#   1. Installs ripgrep (required by Hermes)
#   2. Downloads and installs Hermes agent to ~/.hermes/
#   3. Writes ~/.hermes/config.yaml (points at local Ollama; a model_aliases
#      entry per HERMES_ALIASES) — model/context settings come from
#      hermes.conf (edit it, or export the same-named env vars before
#      running this script). Does NOT force a per-model context value —
#      only sets context_length as a ceiling and lets Hermes auto-detect
#      per-model from Ollama. See README.md, "Context length: what actually
#      happens" before adding a second model alias.
# =============================================================================
set -euo pipefail

TARGET_USER="${1:-devuser}"
USER_HOME="/home/${TARGET_USER}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hermes.conf
source "$SCRIPT_DIR/hermes.conf"
# HERMES_ALIASES is a bash array (name=model pairs) — can't be exported as
# an env var directly, so serialize it one pair per line for the Python
# patch step below to parse.
HERMES_ALIASES_SERIALIZED="$(printf '%s\n' "${HERMES_ALIASES[@]}")"
export HERMES_ALIASES_SERIALIZED HERMES_DEFAULT_ALIAS HERMES_CONTEXT_LENGTH OLLAMA_BASE_URL

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

# Patch key settings in-place (preserves all other defaults). Values come
# from hermes.conf (HERMES_ALIASES / HERMES_DEFAULT_ALIAS /
# HERMES_CONTEXT_LENGTH / OLLAMA_BASE_URL), exported above.
#
# Deliberately does NOT set ollama_num_ctx. Hermes auto-detects the real
# per-model context from Ollama's /api/show when it's unset, which is what
# makes it safe to eventually have more than one alias here — a hardcoded
# global ollama_num_ctx forces the SAME value onto every model regardless
# of what it actually supports (confirmed: forcing a too-large context onto
# a smaller-context model doesn't just get clamped cleanly — it can blow
# the VRAM budget and tank performance). context_length still acts as a
# ceiling on whatever gets auto-detected. See README.md.
python3 - "$HERMES_CONF" <<'PYEOF'
import os, sys, re

path          = sys.argv[1]
context_len   = os.environ["HERMES_CONTEXT_LENGTH"]
base_url      = os.environ["OLLAMA_BASE_URL"]
default_alias = os.environ["HERMES_DEFAULT_ALIAS"]

aliases = dict(
    line.split("=", 1)
    for line in os.environ["HERMES_ALIASES_SERIALIZED"].splitlines()
    if line.strip()
)
if default_alias not in aliases:
    sys.exit(f"HERMES_DEFAULT_ALIAS={default_alias!r} is not a key in HERMES_ALIASES ({list(aliases)}) — fix hermes.conf")
default_model = aliases[default_alias]

with open(path) as f:
    content = f.read()

patches = [
    # Default model
    (r'(^\s*default:\s*")[^"]*(")', rf'\g<1>{default_model}\2'),
    # Provider
    (r'(^\s*)provider:\s*"auto"', r'\1provider: "custom"  # local Ollama'),
    # Base URL
    (r'(^\s*)base_url:\s*"https://openrouter\.ai/api/v1"',
     rf'\1base_url: "{base_url}"'),
    # Context length ceiling (commented-out placeholder in Hermes' stock
    # config.yaml) — NOT ollama_num_ctx, see comment above.
    (r'#\s*context_length:\s*\d+', f'context_length: {context_len}'),
]

for pattern, replacement in patches:
    content = re.sub(pattern, replacement, content, flags=re.MULTILINE)

# Add model_aliases block if not present — one entry per HERMES_ALIASES pair
if 'model_aliases:' not in content:
    entries = "\n".join(
        f'  {name}:\n    model: {model}\n    provider: custom\n    base_url: "{base_url}"'
        for name, model in aliases.items()
    )
    aliases_block = f"\nmodel_aliases:\n{entries}\n"
    # Insert before Privacy section
    content = content.replace('# =============================================================================\n# Privacy', aliases_block + '# =============================================================================\n# Privacy')

with open(path, 'w') as f:
    f.write(content)

print(f"  config.yaml patched. Aliases: {', '.join(aliases)} (default: {default_alias})")
PYEOF

chown "$TARGET_USER:$TARGET_USER" "$HERMES_CONF"

echo ""
echo "  Hermes setup complete."
echo "  Usage:"
echo "    hermes -z 'your task'              # default alias: $HERMES_DEFAULT_ALIAS"
for pair in "${HERMES_ALIASES[@]}"; do
    alias_name="${pair%%=*}"
    [[ "$alias_name" == "$HERMES_DEFAULT_ALIAS" ]] && continue
    echo "    hermes -m $alias_name -z 'your task'  # alias: $alias_name"
done
echo "    hermes                             # interactive session"
echo "=============================================="
