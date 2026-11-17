#!/usr/bin/env bash
# check-plugin.sh — prove a Cursor / Agent Plugin is well-formed and installs
# as a real local plugin directory. Prints one PASS/FAIL/SKIP line per check
# and an OVERALL line. Exit 0 only if no check FAILed.
#
# Usage:
#   scripts/check-plugin.sh <plugin-dir> [--install] [--home DIR]
#
#   --install   copy the plugin into <home>/.cursor/plugins/local/<name>
#   --home DIR  home dir to install under. Default: a fresh temp dir, so a
#               test run never touches your real ~/.cursor. Pass
#               --home "$HOME" only when you mean it.
#   -h, --help  show this help
#
# Needs: bash, python3. Optional: curl + python jsonschema (schema check),
# node (stdio server syntax check, loader check).
set -uo pipefail

SCHEMA_URL="${PLUGIN_LOAD_CHECK_SCHEMA_URL:-https://agent-plugins.org/schemas/1.0.0/plugin.schema.json}"

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

PLUGIN_DIR=""
DO_INSTALL=0
HOME_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) DO_INSTALL=1; shift ;;
    --home)
      [[ -n "${2:-}" ]] || { echo "--home needs a directory" >&2; usage 1; }
      HOME_DIR="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    -*) echo "Unknown arg: $1" >&2; usage 1 ;;
    *)
      [[ -z "$PLUGIN_DIR" ]] || { echo "Only one plugin dir allowed" >&2; usage 1; }
      PLUGIN_DIR="$1"; shift ;;
  esac
done

[[ -n "$PLUGIN_DIR" ]] || usage 1
[[ -d "$PLUGIN_DIR" ]] || { echo "Not a directory: $PLUGIN_DIR" >&2; exit 2; }
PLUGIN_DIR="$(cd "$PLUGIN_DIR" && pwd)"

N_PASS=0; N_FAIL=0; N_SKIP=0
pass() { echo "PASS  $1"; N_PASS=$((N_PASS + 1)); }
fail() { echo "FAIL  $1"; N_FAIL=$((N_FAIL + 1)); }
skip() { echo "SKIP  $1"; N_SKIP=$((N_SKIP + 1)); }

finish() {
  echo ""
  if [[ "$N_FAIL" -eq 0 ]]; then
    echo "OVERALL: PASS ($N_PASS pass, $N_SKIP skip, 0 fail)"
    exit 0
  fi
  echo "OVERALL: FAIL ($N_PASS pass, $N_SKIP skip, $N_FAIL fail)"
  exit 1
}

echo "plugin-load-check: $PLUGIN_DIR"
echo ""

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 is required to parse JSON manifests"
  finish
fi

# --- 1. manifest detected -------------------------------------------------
MANIFEST=""; KIND=""
if [[ -f "$PLUGIN_DIR/plugin.json" ]]; then
  MANIFEST="$PLUGIN_DIR/plugin.json"; KIND="agent"
elif [[ -f "$PLUGIN_DIR/.cursor-plugin/plugin.json" ]]; then
  MANIFEST="$PLUGIN_DIR/.cursor-plugin/plugin.json"; KIND="cursor"
fi
if [[ -z "$MANIFEST" ]]; then
  fail "manifest: no plugin.json or .cursor-plugin/plugin.json"
  finish
fi
pass "manifest: ${MANIFEST#"$PLUGIN_DIR"/} ($KIND plugin)"

# --- 2. JSON parses --------------------------------------------------------
if err="$(python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$MANIFEST" 2>&1)"; then
  pass "json: manifest parses"
else
  fail "json: manifest does not parse: $(echo "$err" | tail -1)"
  finish
fi

# Small helper: print a manifest field (strings as-is, else JSON).
field() {
  python3 - "$MANIFEST" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get(sys.argv[2]) if isinstance(d, dict) else None
if v is None:
    sys.exit(0)
print(v if isinstance(v, str) else json.dumps(v))
PY
}

# --- 3. kebab-case name ----------------------------------------------------
NAME="$(field name)"
if [[ -z "$NAME" ]]; then
  fail "name: manifest has no \"name\""
  NAME=""
elif [[ "$NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  pass "name: \"$NAME\" is kebab-case"
else
  fail "name: \"$NAME\" is not kebab-case (want e.g. my-plugin)"
fi

# --- 4. Agent Plugin schema ------------------------------------------------
SCHEMA_FIELD="$(field "\$schema")"
if [[ "$KIND" != "agent" && "$SCHEMA_FIELD" != *agent-plugins.org* ]]; then
  skip "schema: Cursor manifest without Agent Plugin \$schema; only name/paths checked"
elif ! python3 -c 'import jsonschema' >/dev/null 2>&1; then
  skip "schema: python jsonschema not installed (pip install jsonschema)"
elif ! command -v curl >/dev/null 2>&1; then
  skip "schema: curl not available to fetch $SCHEMA_URL"
else
  SCHEMA_TMP="$(mktemp)"
  code="$(curl -sSL --max-time 15 -o "$SCHEMA_TMP" -w '%{http_code}' "$SCHEMA_URL" 2>/dev/null || true)"
  if [[ "$code" != "200" ]] || ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SCHEMA_TMP" >/dev/null 2>&1; then
    skip "schema: $SCHEMA_URL did not resolve to JSON (HTTP ${code:-none}); not validated"
  elif out="$(python3 - "$SCHEMA_TMP" "$MANIFEST" <<'PY' 2>&1
import json, sys
import jsonschema
schema = json.load(open(sys.argv[1]))
doc = json.load(open(sys.argv[2]))
cls = jsonschema.validators.validator_for(schema)
errs = sorted(cls(schema).iter_errors(doc), key=lambda e: list(e.path))
for e in errs[:5]:
    loc = "/".join(str(p) for p in e.path) or "(root)"
    print(f"{loc}: {e.message}")
sys.exit(1 if errs else 0)
PY
  )"; then
    pass "schema: manifest valid against $SCHEMA_URL"
  else
    fail "schema: manifest invalid against $SCHEMA_URL: $(echo "$out" | head -3 | tr '\n' ';')"
  fi
  rm -f "$SCHEMA_TMP"
fi

# --- 5. referenced component paths exist -----------------------------------
# Cursor manifests reference paths via skills/rules/agents/commands/hooks/
# mcpServers. Agent Plugins discover components by convention, so we also
# look at conventional dirs when nothing is referenced.
REFS="$(python3 - "$MANIFEST" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for key in ("skills", "rules", "agents", "commands", "hooks", "mcpServers"):
    v = d.get(key) if isinstance(d, dict) else None
    vals = v if isinstance(v, list) else [v]
    for x in vals:
        if isinstance(x, str):
            print(f"{key}\t{x}")
PY
)"
if [[ -z "$REFS" ]]; then
  found=0
  for conv in skills rules agents commands hooks mcp.json .mcp.json; do
    if [[ -e "$PLUGIN_DIR/$conv" ]]; then
      pass "paths: conventional $conv present"
      found=1
    fi
  done
  [[ "$found" -eq 1 ]] || skip "paths: manifest references no component paths and no conventional dirs found"
else
  while IFS=$'\t' read -r key rel; do
    [[ -n "$key" ]] || continue
    if [[ "$rel" == /* || "$rel" == *..* ]]; then
      fail "paths: $key -> $rel points outside the plugin dir"
      continue
    fi
    target="$PLUGIN_DIR/${rel#./}"
    if [[ ! -e "$target" ]]; then
      fail "paths: $key -> $rel is missing"
    elif [[ "$key" == "skills" && -d "$target" ]]; then
      n="$(find "$target" -name SKILL.md -type f | wc -l | tr -d ' ')"
      if [[ "$n" -gt 0 ]]; then
        pass "paths: $key -> $rel exists ($n SKILL.md)"
      else
        fail "paths: $key -> $rel exists but has no SKILL.md"
      fi
    else
      pass "paths: $key -> $rel exists"
    fi
  done <<< "$REFS"
fi

# --- 6. MCP stdio server syntax --------------------------------------------
MCP_FILE=""
MCP_REF="$(field mcpServers)"
if [[ -n "$MCP_REF" && "$MCP_REF" != \{* && -f "$PLUGIN_DIR/${MCP_REF#./}" ]]; then
  MCP_FILE="$PLUGIN_DIR/${MCP_REF#./}"
elif [[ -f "$PLUGIN_DIR/mcp.json" ]]; then
  MCP_FILE="$PLUGIN_DIR/mcp.json"
elif [[ -f "$PLUGIN_DIR/.mcp.json" ]]; then
  MCP_FILE="$PLUGIN_DIR/.mcp.json"
fi
if [[ -z "$MCP_FILE" && "$MCP_REF" != \{* ]]; then
  skip "mcp: no MCP server config in this plugin"
else
  # Lists "<server>\t<abs js path>" for node stdio servers with a local .js entry.
  JS="$(python3 - "${MCP_FILE:-$MANIFEST}" "$PLUGIN_DIR" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1]))
root = sys.argv[2]
servers = d.get("mcpServers", d) if isinstance(d, dict) else {}
if not isinstance(servers, dict):
    sys.exit(0)
for name, cfg in servers.items():
    if not isinstance(cfg, dict) or "node" not in os.path.basename(str(cfg.get("command", ""))):
        continue
    for a in cfg.get("args", []) or []:
        a = str(a).replace("${CURSOR_PLUGIN_ROOT}", root).replace("${PLUGIN_ROOT}", root)
        if a.endswith((".js", ".mjs", ".cjs")):
            p = a if os.path.isabs(a) else os.path.join(root, a)
            print(f"{name}\t{os.path.normpath(p)}")
PY
  )"
  if [[ -z "$JS" ]]; then
    skip "mcp: config found but no local node .js stdio entry to syntax-check"
  elif ! command -v node >/dev/null 2>&1; then
    skip "mcp: node not installed; JS stdio server not syntax-checked"
  else
    while IFS=$'\t' read -r srv js; do
      [[ -n "$srv" ]] || continue
      if [[ ! -f "$js" ]]; then
        fail "mcp: $srv entry $js is missing"
      elif err="$(node --check "$js" 2>&1)"; then
        pass "mcp: node --check $srv (${js#"$PLUGIN_DIR"/})"
      else
        fail "mcp: node --check $srv failed: $(echo "$err" | head -1)"
      fi
    done <<< "$JS"
  fi
  skip "mcp: live initialize / tools/list not run by this script (do it by hand when safe)"
fi

# --- 7. install as a real directory ----------------------------------------
INSTALLED=0
if [[ "$DO_INSTALL" -eq 0 ]]; then
  skip "install: not requested (pass --install)"
elif [[ -z "$NAME" || ! "$NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  fail "install: refusing to install without a valid kebab-case name"
else
  if [[ -z "$HOME_DIR" ]]; then
    HOME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plugin-load-check-home.XXXXXX")"
    echo "      (no --home given; using temp home $HOME_DIR)"
  fi
  mkdir -p "$HOME_DIR/.cursor/plugins/local"
  DEST="$HOME_DIR/.cursor/plugins/local/$NAME"
  if [[ -e "$DEST" || -L "$DEST" ]]; then
    fail "install: $DEST already exists; remove it or use another --home"
  elif ! cp -R "$PLUGIN_DIR" "$DEST"; then
    fail "install: copy to $DEST failed"
  else
    rm -rf "$DEST/.git"
    if [[ -L "$DEST" ]]; then
      fail "install: $DEST is a symlink (Cursor rejects symlinks pointing outside)"
    elif [[ ! -d "$DEST" ]]; then
      fail "install: $DEST is not a directory"
    elif [[ ! -f "$DEST/${MANIFEST#"$PLUGIN_DIR"/}" ]]; then
      fail "install: manifest missing in $DEST"
    else
      links="$(find "$DEST" -type l | wc -l | tr -d ' ')"
      if [[ "$links" -gt 0 ]]; then
        fail "install: $DEST is a real dir but contains $links symlink(s)"
      else
        pass "install: real directory at $DEST (not a symlink)"
        INSTALLED=1
      fi
    fi
  fi
fi

# --- 8. optional shared loader ---------------------------------------------
if [[ "$INSTALLED" -eq 0 ]]; then
  skip "loader: needs a successful --install first"
elif ! command -v node >/dev/null 2>&1; then
  skip "loader: node not installed"
elif ! node -e 'require.resolve("@anysphere/cursor-plugins")' >/dev/null 2>&1; then
  skip "loader: @anysphere/cursor-plugins not resolvable here; loadUserLocalPlugins not run"
else
  if out="$(HOME_DIR="$HOME_DIR" NAME="$NAME" node -e '
    const m = require("@anysphere/cursor-plugins");
    Promise.resolve(m.loadUserLocalPlugins({ userHomeDir: process.env.HOME_DIR }))
      .then(r => { const s = JSON.stringify(r);
        if (s && s.includes(JSON.stringify(process.env.NAME))) { console.log("found"); }
        else { console.log("not listed"); process.exit(1); } })
      .catch(e => { console.log(String(e && e.message || e)); process.exit(1); });
  ' 2>&1)"; then
    pass "loader: loadUserLocalPlugins lists \"$NAME\""
  else
    fail "loader: loadUserLocalPlugins: $(echo "$out" | tail -1)"
  fi
fi

# --- 9. what a shell cannot prove -------------------------------------------
skip "ide: Cursor Reload Window / Customize UI and org policy (\"Allow Local Plugin Imports\") can't be proven from a shell"

finish
