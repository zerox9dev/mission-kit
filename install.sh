#!/usr/bin/env sh
#
# install.sh — install mission-kit into the current project (idempotent).
#
# Per-project layout (the choice for this kit):
#   .claude/agents/{planner,worker,verifier}.md   subagents
#   .claude/commands/mission.md                    /mission slash command (the loop)
#   .claude/hooks/gate.sh                          objective gate
#   .claude/mission-kit/templates/*.md             mission templates
#   .claude/mission-kit/bin/mission                state helper (no LLM calls)
#   .claude/settings.json                          PostToolUse hook (Edit|Write)
#   missions/ added to .gitignore                  state stays out of git
#
# The loop runs inside a normal Claude Code session via /mission — no claude -p,
# no separate billing path. Everything uses the user's subscription.
#
# Usage:
#   ./install.sh                                   # from a checkout
#   curl -fsSL .../install.sh | sh                 # remote (clones the repo)
#
# Re-running is safe: kit-owned files are overwritten, your settings/gitignore
# are edited in place without duplication.

set -eu

REPO_URL="${MISSION_KIT_REPO:-https://github.com/zerox9dev/mission-kit}"
BRANCH="${MISSION_KIT_BRANCH:-main}"

say()  { printf '· %s\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m!\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# --------------------------------------------------------------------------
# locate the kit source: local checkout, or clone for curl-pipe installs
# --------------------------------------------------------------------------
SCRIPT_DIR=""
# shellcheck disable=SC2128
if [ -n "${0:-}" ] && [ -f "$0" ]; then
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
fi

SRC=""
CLONED=""
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/agents" ] && [ -f "$SCRIPT_DIR/mission" ]; then
  SRC="$SCRIPT_DIR"
  say "installing from local checkout: $SRC"
else
  command -v git >/dev/null 2>&1 || die "git required for remote install"
  SRC="$(mktemp -d)"
  CLONED="$SRC"
  say "fetching mission-kit from $REPO_URL ($BRANCH)…"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$SRC" >/dev/null 2>&1 \
    || die "clone failed: $REPO_URL"
fi

cleanup() { [ -n "$CLONED" ] && rm -rf "$CLONED"; }
trap cleanup EXIT

[ -d "$SRC/agents" ] || die "kit source incomplete: no agents/ in $SRC"

# --------------------------------------------------------------------------
# target = current working directory (the project being equipped)
# --------------------------------------------------------------------------
PROJECT="$(pwd)"
[ "$PROJECT" = "$SRC" ] && die "run install.sh from inside your target project, not the kit checkout"

say "target project: $PROJECT"
mkdir -p .claude/agents .claude/commands .claude/hooks \
         .claude/mission-kit/templates .claude/mission-kit/bin

# --- agents (kit-owned, overwrite) ----------------------------------------
for a in planner worker verifier; do
  cp "$SRC/agents/$a.md" ".claude/agents/$a.md"
done
ok "agents → .claude/agents/"

# --- slash command (kit-owned, overwrite) ---------------------------------
cp "$SRC/commands/mission.md" ".claude/commands/mission.md"
ok "/mission command → .claude/commands/mission.md"

# --- gate (kit-owned, overwrite) ------------------------------------------
cp "$SRC/hooks/gate.sh" ".claude/hooks/gate.sh"
chmod +x ".claude/hooks/gate.sh"
ok "gate → .claude/hooks/gate.sh"

# --- templates (kit-owned, overwrite) -------------------------------------
cp "$SRC/templates/"*.md ".claude/mission-kit/templates/"
ok "templates → .claude/mission-kit/templates/"

# --- mission state helper (project-local; called by /mission) -------------
cp "$SRC/mission" ".claude/mission-kit/bin/mission"
chmod +x ".claude/mission-kit/bin/mission"
ok "mission helper → .claude/mission-kit/bin/mission"

# --------------------------------------------------------------------------
# register the PostToolUse gate hook in .claude/settings.json (merge, no dup)
# --------------------------------------------------------------------------
SETTINGS=".claude/settings.json"
HOOK_CMD='"$CLAUDE_PROJECT_DIR"/.claude/hooks/gate.sh'

register_hook_jq() {
  tmp="$(mktemp)"
  jq --arg cmd "$HOOK_CMD" '
    .hooks //= {} |
    .hooks.PostToolUse //= [] |
    if any(.hooks.PostToolUse[]?; (.hooks[]?.command? // "") | contains("gate.sh"))
    then .
    else .hooks.PostToolUse += [{
      "matcher": "Edit|Write",
      "hooks": [{ "type": "command", "command": $cmd }]
    }] end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

register_hook_py() {
  python3 - "$SETTINGS" "$HOOK_CMD" <<'PY'
import json, sys, os
path, cmd = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path) and os.path.getsize(path):
    with open(path) as f:
        data = json.load(f)
hooks = data.setdefault("hooks", {})
post = hooks.setdefault("PostToolUse", [])
exists = any(
    "gate.sh" in (h.get("command", ""))
    for entry in post for h in entry.get("hooks", [])
)
if not exists:
    post.append({
        "matcher": "Edit|Write",
        "hooks": [{"type": "command", "command": cmd}],
    })
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
if command -v jq >/dev/null 2>&1; then
  register_hook_jq && ok "PostToolUse gate hook registered (jq) in $SETTINGS"
elif command -v python3 >/dev/null 2>&1; then
  register_hook_py && ok "PostToolUse gate hook registered (python3) in $SETTINGS"
else
  warn "neither jq nor python3 found — add this hook to $SETTINGS manually:"
  cat >&2 <<EOF
  "hooks": { "PostToolUse": [
    { "matcher": "Edit|Write",
      "hooks": [{ "type": "command", "command": $HOOK_CMD }] } ] }
EOF
fi

# --------------------------------------------------------------------------
# keep mission state out of git (this kit's choice: gitignore missions/)
# --------------------------------------------------------------------------
if [ -d .git ] || git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ ! -f .gitignore ] || ! grep -qxF "missions/" .gitignore 2>/dev/null; then
    printf '\n# mission-kit state\nmissions/\n' >> .gitignore
    ok "added missions/ to .gitignore"
  else
    say "missions/ already in .gitignore"
  fi
fi

cat <<EOF

$(ok 'mission-kit installed.')

The loop runs inside Claude Code via the /mission command. Open claude in this
project, then:

  1. Confirm subscription billing (not pay-per-token):
       echo \$ANTHROPIC_API_KEY     # should be empty
  2. Create + plan a mission:
       /mission new "add OAuth login"
  3. Review missions/<slug>/PLAN.md, set its status to 'approved', then:
       /mission run <slug>
  4. Anytime:
       /mission status

Optional: add a .mission.yml to pin gate commands (lint/types/test).
Terminal shortcut (optional): alias mission='.claude/mission-kit/bin/mission'
EOF
