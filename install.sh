#!/usr/bin/env bash
# Install plugin-load-check skill into local agent skill dirs.
# Usage:
#   ./install.sh                 # install to ~/.grok/skills (default)
#   ./install.sh --target cursor # ~/.cursor/skills
#   ./install.sh --target project# ./.cursor/skills (cwd)
#   ./install.sh --target all    # grok + cursor home
#   ./install.sh --dry-run
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="grok"
DRY_RUN=0

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown arg: $1" >&2; usage 1 ;;
  esac
done

install_one() {
  local dest="$1"
  local skill_dir="$dest/plugin-load-check"
  echo "→ $skill_dir"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  (dry-run) would copy SKILL.md + scripts/"
    return 0
  fi
  mkdir -p "$skill_dir/scripts"
  cp "$REPO_DIR/SKILL.md" "$skill_dir/SKILL.md"
  cp -R "$REPO_DIR/scripts/." "$skill_dir/scripts/"
  chmod +x "$skill_dir/scripts/"*.sh
  echo "  installed"
}

case "$TARGET" in
  grok)
    install_one "${HOME}/.grok/skills"
    ;;
  cursor)
    install_one "${HOME}/.cursor/skills"
    ;;
  project)
    install_one "$(pwd)/.cursor/skills"
    ;;
  all)
    install_one "${HOME}/.grok/skills"
    install_one "${HOME}/.cursor/skills"
    ;;
  *)
    echo "Invalid --target: $TARGET (use grok|cursor|project|all)" >&2
    exit 1
    ;;
esac

echo ""
echo "Done. Invoke with: /plugin-load-check <plugin-dir>"
echo "Or run directly:   <skill dir>/scripts/check-plugin.sh <plugin-dir> [--install] [--home DIR]"
