#!/bin/bash
# Claude Code HUD - Install / Uninstall Script
# Usage: ./install.sh          (install)
#        ./install.sh --uninstall  (uninstall)

set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CRED_FILE="$CLAUDE_DIR/.credentials.json"
LOG_FILE="$CLAUDE_DIR/usage-log.jsonl"
PLAN_CACHE="$CLAUDE_DIR/plan-usage-cache.json"

LINKS=(
    "statusline.sh"
    "fetch-plan-usage.sh"
    "log-session.sh"
)

# --- Colors ---
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
RESET='\033[0m'

info()  { echo -e "${GREEN}✓${RESET} $1"; }
warn()  { echo -e "${YELLOW}⚠${RESET} $1"; }
error() { echo -e "${RED}✗${RESET} $1"; }

# POSIX-compatible readlink -f replacement
resolve_path() {
    local path="$1"
    if command -v realpath &>/dev/null; then
        realpath "$path"
    else
        (cd "$(dirname "$path")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$path")")
    fi
}

# Cleanup trap for temp files
_cleanup_files=()
trap 'rm -f "${_cleanup_files[@]+"${_cleanup_files[@]}"}"' EXIT

# --- Uninstall ---
uninstall() {
    echo -e "${BOLD}${CYAN}Claude Code HUD${RESET} — Uninstall"
    echo

    # Remove symlinks
    for file in "${LINKS[@]}"; do
        target="$CLAUDE_DIR/$file"
        if [ -L "$target" ]; then
            rm "$target"
            info "Removed symlink: $target"
        elif [ -f "$target" ]; then
            warn "$target exists but is not a symlink — skipping"
        else
            echo "  $target not found — skipping"
        fi
    done

    # Remove lib symlink
    if [ -L "$CLAUDE_DIR/lib" ]; then
        rm "$CLAUDE_DIR/lib"
        info "Removed symlink: $CLAUDE_DIR/lib"
    fi

    # Remove settings entries
    if [ -f "$SETTINGS_FILE" ]; then
        if [ -L "$SETTINGS_FILE" ]; then
            error "settings.json is a symlink — aborting for safety"
            exit 1
        fi
        local tmp
        tmp=$(mktemp)
        _cleanup_files+=("$tmp")
        jq 'del(.statusLine) | del(.hooks.SessionEnd)
            | if .hooks == {} then del(.hooks) else . end' \
            "$SETTINGS_FILE" > "$tmp"
        mv "$tmp" "$SETTINGS_FILE"
        info "Removed HUD entries from settings.json"
    fi

    # Ask about log/cache files
    echo
    if [ -f "$LOG_FILE" ]; then
        read -rp "  Delete usage log ($LOG_FILE)? [y/N] " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            rm "$LOG_FILE"
            info "Deleted $LOG_FILE"
        else
            echo "  Kept $LOG_FILE"
        fi
    fi

    if [ -f "$PLAN_CACHE" ]; then
        rm "$PLAN_CACHE"
        info "Deleted cache: $PLAN_CACHE"
    fi

    echo
    info "Uninstall complete. Restart Claude Code to apply changes."
    exit 0
}

# --- Uninstall flag ---
if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall
fi

# =============================================================
# Install
# =============================================================
echo -e "${BOLD}${CYAN}Claude Code HUD${RESET} — Install"
echo

# 1. Dependency check
missing=()
for cmd in jq curl bc; do
    if ! command -v "$cmd" &>/dev/null; then
        missing+=("$cmd")
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    error "Missing dependencies: ${missing[*]}"
    echo "  Install them first:"
    echo "    sudo apt install ${missing[*]}    # Debian/Ubuntu"
    echo "    brew install ${missing[*]}         # macOS"
    exit 1
fi
info "Dependencies OK (jq, curl, bc)"

# 2. Credentials check
if [ -f "$CRED_FILE" ]; then
    info "Credentials found"
else
    warn "No credentials at $CRED_FILE"
    echo "  Plan usage tracking will be limited."
    echo "  (This is normal if you haven't logged in via claude.ai OAuth)"
    echo
fi

# 3. ~/.claude directory
mkdir -p "$CLAUDE_DIR"

# 4. Symlinks
echo
echo -e "${BOLD}Creating symlinks...${RESET}"

# Symlink lib directory
LIB_SRC="$SCRIPT_DIR/lib"
LIB_DEST="$CLAUDE_DIR/lib"
if [ -d "$LIB_SRC" ]; then
    if [ -L "$LIB_DEST" ] || [ ! -e "$LIB_DEST" ]; then
        ln -sfn "$LIB_SRC" "$LIB_DEST"
        info "lib/ → $LIB_DEST"
    else
        warn "lib/ exists at $LIB_DEST but is not a symlink — skipping"
    fi
fi

for file in "${LINKS[@]}"; do
    src="$SCRIPT_DIR/$file"
    dest="$CLAUDE_DIR/$file"

    if [ ! -f "$src" ]; then
        error "Source not found: $src"
        exit 1
    fi

    if [ -L "$dest" ]; then
        existing=$(resolve_path "$dest")
        expected=$(resolve_path "$src")
        if [ "$existing" = "$expected" ]; then
            info "$file — already linked"
            continue
        fi
        warn "$file — symlink exists but points to $existing"
        read -rp "  Overwrite? [y/N] " ans
        if [[ ! "$ans" =~ ^[Yy]$ ]]; then
            echo "  Skipped $file"
            continue
        fi
    elif [ -f "$dest" ]; then
        warn "$file — regular file exists at $dest"
        read -rp "  Overwrite with symlink? [y/N] " ans
        if [[ ! "$ans" =~ ^[Yy]$ ]]; then
            echo "  Skipped $file"
            continue
        fi
    fi

    ln -sf "$src" "$dest"
    info "$file → $dest"
done

# 5. settings.json update
echo
echo -e "${BOLD}Updating settings.json...${RESET}"

# HUD config to merge
HUD_CONFIG='{
    "statusLine": {
        "type": "command",
        "command": "~/.claude/statusline.sh"
    },
    "hooks": {
        "SessionEnd": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": "~/.claude/log-session.sh"
                    }
                ]
            }
        ]
    }
}'

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "$HUD_CONFIG" | jq '.' > "$SETTINGS_FILE"
    info "Created $SETTINGS_FILE"
else
    # Safety: refuse to modify a symlinked settings file
    if [ -L "$SETTINGS_FILE" ]; then
        error "settings.json is a symlink — aborting for safety"
        exit 1
    fi

    updated=false

    # Check statusLine
    has_status=$(jq 'has("statusLine")' "$SETTINGS_FILE")
    if [ "$has_status" = "false" ]; then
        tmp=$(mktemp)
        _cleanup_files+=("$tmp")
        jq --argjson sl "$(echo "$HUD_CONFIG" | jq '.statusLine')" \
            '.statusLine = $sl' "$SETTINGS_FILE" > "$tmp"
        mv "$tmp" "$SETTINGS_FILE"
        info "Added statusLine config"
        updated=true
    else
        warn "statusLine already exists — skipping (existing config preserved)"
    fi

    # Check hooks.SessionEnd
    has_hook=$(jq '.hooks.SessionEnd // null | type' "$SETTINGS_FILE" 2>/dev/null)
    if [ "$has_hook" = '"null"' ] || [ "$has_hook" = "null" ]; then
        tmp=$(mktemp)
        _cleanup_files+=("$tmp")
        jq --argjson se "$(echo "$HUD_CONFIG" | jq '.hooks.SessionEnd')" \
            '.hooks.SessionEnd = $se' "$SETTINGS_FILE" > "$tmp"
        mv "$tmp" "$SETTINGS_FILE"
        info "Added SessionEnd hook"
        updated=true
    else
        warn "hooks.SessionEnd already exists — skipping (existing config preserved)"
    fi

    if [ "$updated" = false ]; then
        echo "  No changes needed — settings already configured"
    fi
fi

# 6. Success
echo
echo -e "${BOLD}${GREEN}Installation complete!${RESET}"
echo
echo -e "${DIM}Preview (sample data):${RESET}"
echo

# Run a preview with dummy data
PREVIEW_INPUT='{
    "model": {"display_name": "Opus 4.6", "id": "claude-opus-4-6"},
    "cost": {"total_cost_usd": 1.2345, "total_duration_ms": 300000, "total_api_duration_ms": 180000},
    "context_window": {"used_percentage": 35.2, "total_input_tokens": 45200, "total_output_tokens": 12800},
    "rate_limits": {"five_hour": {"used_percentage": 21, "resets_at": 1775049600}, "seven_day": {"used_percentage": 62, "resets_at": 1775390400}}
}'

echo "$PREVIEW_INPUT" | "$CLAUDE_DIR/statusline.sh" 2>/dev/null || true

echo
echo -e "Restart Claude Code to activate the HUD."
echo -e "To uninstall later: ${DIM}./install.sh --uninstall${RESET}"
