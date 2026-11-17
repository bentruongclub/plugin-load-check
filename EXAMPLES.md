# Examples

Two real runs of `scripts/check-plugin.sh` against [bentruongclub/fstack](https://github.com/bentruongclub/fstack), a Cursor plugin with a `.cursor-plugin/plugin.json` manifest and one skill. Output below is **pasted verbatim** from a Linux box on 2026-11-18 (fstack commit `2baa685`). Nothing is reconstructed. Both runs install into a throwaway `--home` under `/tmp`, so the real `~/.cursor` was not touched.

## 1. PASS: fstack as published

```bash
git clone --depth 1 https://github.com/bentruongclub/fstack /tmp/fstack
mkdir -p /tmp/plc-pass-home
scripts/check-plugin.sh /tmp/fstack --install --home /tmp/plc-pass-home
echo "exit=$?"
```

```
plugin-load-check: /tmp/fstack

PASS  manifest: .cursor-plugin/plugin.json (cursor plugin)
PASS  json: manifest parses
PASS  name: "fstack" is kebab-case
SKIP  schema: Cursor manifest without Agent Plugin $schema; only name/paths checked
PASS  paths: skills -> ./skills/ exists (1 SKILL.md)
SKIP  mcp: no MCP server config in this plugin
PASS  install: real directory at /tmp/plc-pass-home/.cursor/plugins/local/fstack (not a symlink)
SKIP  loader: @anysphere/cursor-plugins not resolvable here; loadUserLocalPlugins not run
SKIP  ide: Cursor Reload Window / Customize UI and org policy ("Allow Local Plugin Imports") can't be proven from a shell

OVERALL: PASS (5 pass, 4 skip, 0 fail)
exit=0
```

### What this proves, and what it doesn't

- **Proven:** the manifest is found and parses, the name is valid, the `skills` path it references exists and has a `SKILL.md`, and the plugin installs as a real directory (no symlinks) under `.cursor/plugins/local/fstack`.
- **Not proven:** that Cursor shows the plugin. The loader package was not available on this box, and the IDE step can only be checked inside Cursor. The four SKIP lines say so; they are not passes.
- fstack has no MCP server and no Agent Plugin `$schema`, so those checks are SKIP for this plugin, not for every plugin.

## 2. FAIL: fstack deliberately broken

To show the failure path, a copy of fstack was **deliberately broken** in two ways. The original clone was not modified.

```bash
cp -R /tmp/fstack /tmp/fstack-broken && rm -rf /tmp/fstack-broken/.git
# break it on purpose: invalid name + skills path that does not exist
sed -i 's/"name": "fstack"/"name": "FStack Pack"/; s|"skills": "./skills/"|"skills": "./skill/"|' \
  /tmp/fstack-broken/.cursor-plugin/plugin.json
mkdir -p /tmp/plc-fail-home
scripts/check-plugin.sh /tmp/fstack-broken --install --home /tmp/plc-fail-home
echo "exit=$?"
```

```
plugin-load-check: /tmp/fstack-broken

PASS  manifest: .cursor-plugin/plugin.json (cursor plugin)
PASS  json: manifest parses
FAIL  name: "FStack Pack" is not kebab-case (want e.g. my-plugin)
SKIP  schema: Cursor manifest without Agent Plugin $schema; only name/paths checked
FAIL  paths: skills -> ./skill/ is missing
SKIP  mcp: no MCP server config in this plugin
FAIL  install: refusing to install without a valid kebab-case name
SKIP  loader: needs a successful --install first
SKIP  ide: Cursor Reload Window / Customize UI and org policy ("Allow Local Plugin Imports") can't be proven from a shell

OVERALL: FAIL (2 pass, 4 skip, 3 fail)
exit=1
```

Both mistakes were caught, nothing was installed, and the exit code is 1, so a CI step or an agent can't read this run as a pass.

## How to reuse

Run the script on your own plugin dir, paste the output into your reply or PR as-is, then do the steps it marks SKIP by hand (IDE reload, a live MCP `tools/list`) and write down which ones you could not do.
