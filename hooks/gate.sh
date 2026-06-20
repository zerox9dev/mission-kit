#!/usr/bin/env bash
#
# gate.sh — objective quality gate for mission-kit.
#
# Runs the project's lint / type-check / test commands. A non-zero exit means
# the change is not acceptable and must be fixed before a step can close.
#
# Two modes:
#   1. PostToolUse hook (Claude Code calls it after Edit|Write). It reads the
#      hook JSON on stdin, runs the gate, and on failure exits 2 with a message
#      on stderr so Claude is told to fix things.
#   2. CLI (`gate.sh` directly, or via `mission run`). Prints results, exits
#      0 (pass) or 1 (fail).
#
# Stack detection is automatic. Override anything via .mission.yml in the repo
# root (simple key: value lines), e.g.:
#
#   lint:  npm run lint
#   types: npm run typecheck
#   test:  npm test
#
# An empty value disables that check. If no commands are detected or configured,
# the gate passes vacuously (and says so).

set -uo pipefail

ROOT="$(pwd)"
CONFIG="$ROOT/.mission.yml"
IS_HOOK=0
# Detect hook mode: Claude Code pipes JSON on stdin for PostToolUse.
if [ ! -t 0 ] && [ -p /dev/stdin -o -s /dev/stdin ]; then
  STDIN_DATA="$(cat 2>/dev/null || true)"
  case "$STDIN_DATA" in
    *'"hook_event_name"'*|*'"tool_name"'*) IS_HOOK=1 ;;
  esac
fi

# --- read overrides from .mission.yml (naive key: value parser) ------------
cfg() {
  # cfg <key> -> prints value if present in .mission.yml, else nothing
  [ -f "$CONFIG" ] || return 0
  sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" "$CONFIG" | head -n1 \
    | sed 's/[[:space:]]*$//'
}

CFG_LINT="$(cfg lint)"
CFG_TYPES="$(cfg types)"
CFG_TEST="$(cfg test)"
CFG_SET=0
[ -f "$CONFIG" ] && CFG_SET=1

LINT_CMD=""
TYPES_CMD=""
TEST_CMD=""

if [ "$CFG_SET" = "1" ]; then
  # Config present: use it verbatim (empty value = disabled).
  LINT_CMD="$CFG_LINT"
  TYPES_CMD="$CFG_TYPES"
  TEST_CMD="$CFG_TEST"
else
  # --- autodetect stack ----------------------------------------------------
  has() { command -v "$1" >/dev/null 2>&1; }
  pkg_has() {
    # pkg_has <script-name> -> 0 if package.json defines that npm script
    [ -f "$ROOT/package.json" ] || return 1
    grep -q "\"$1\"[[:space:]]*:" "$ROOT/package.json"
  }

  if [ -f "$ROOT/package.json" ]; then
    runner="npm run"; rtest="npm test"
    if [ -f "$ROOT/pnpm-lock.yaml" ] && has pnpm; then runner="pnpm"; rtest="pnpm test"
    elif [ -f "$ROOT/yarn.lock" ] && has yarn; then runner="yarn"; rtest="yarn test"
    fi
    pkg_has lint      && LINT_CMD="$runner lint"
    pkg_has typecheck && TYPES_CMD="$runner typecheck"
    pkg_has tsc       && [ -z "$TYPES_CMD" ] && TYPES_CMD="$runner tsc"
    pkg_has test      && TEST_CMD="$rtest"
  fi

  if [ -f "$ROOT/pyproject.toml" ] || [ -f "$ROOT/setup.py" ] || [ -f "$ROOT/requirements.txt" ]; then
    if has ruff; then LINT_CMD="${LINT_CMD:-ruff check .}"; fi
    if has mypy && { [ -f "$ROOT/mypy.ini" ] || grep -q "\[tool.mypy\]" "$ROOT/pyproject.toml" 2>/dev/null; }; then
      TYPES_CMD="${TYPES_CMD:-mypy .}"
    fi
    if has pytest; then TEST_CMD="${TEST_CMD:-pytest -q}"; fi
  fi

  if [ -f "$ROOT/go.mod" ] && has go; then
    LINT_CMD="${LINT_CMD:-go vet ./...}"
    TEST_CMD="${TEST_CMD:-go test ./...}"
  fi

  if [ -f "$ROOT/Cargo.toml" ] && has cargo; then
    LINT_CMD="${LINT_CMD:-cargo clippy --quiet}"
    TEST_CMD="${TEST_CMD:-cargo test --quiet}"
  fi
fi

# --- run the checks --------------------------------------------------------
FAILED=0
REPORT=""

run_check() {
  local name="$1" cmd="$2"
  [ -z "$cmd" ] && return 0
  printf '── gate: %s → %s\n' "$name" "$cmd" >&2
  local out rc
  out="$(eval "$cmd" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    REPORT="${REPORT}✓ ${name}\n"
  else
    FAILED=1
    REPORT="${REPORT}✗ ${name} (exit $rc)\n"
    REPORT="${REPORT}$(printf '%s\n' "$out" | tail -n 40)\n"
  fi
}

run_check "lint"  "$LINT_CMD"
run_check "types" "$TYPES_CMD"
run_check "test"  "$TEST_CMD"

if [ -z "$LINT_CMD$TYPES_CMD$TEST_CMD" ]; then
  msg="gate: no checks detected or configured — passing vacuously."
  msg="$msg Add .mission.yml with lint/types/test to enable."
  if [ "$IS_HOOK" = "1" ]; then exit 0; fi
  printf '%s\n' "$msg" >&2
  exit 0
fi

# --- report ----------------------------------------------------------------
if [ "$FAILED" = "0" ]; then
  if [ "$IS_HOOK" = "1" ]; then exit 0; fi
  printf 'GATE: PASS\n'
  printf "$REPORT"
  exit 0
else
  if [ "$IS_HOOK" = "1" ]; then
    # exit 2 → Claude Code feeds stderr back to the model as a must-fix.
    printf 'Quality gate failed. Fix before finishing:\n' >&2
    printf "$REPORT" >&2
    exit 2
  fi
  printf 'GATE: FAIL\n'
  printf "$REPORT"
  exit 1
fi
