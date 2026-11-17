---
name: plugin-load-check
description: >
  Prove a Cursor Plugin or Agent Plugin actually loads locally, with PASS/FAIL
  evidence instead of "should work". Validates the manifest, checks referenced
  skills/rules/MCP files exist, syntax-checks a JS stdio MCP server, installs the
  plugin as a real directory under ~/.cursor/plugins/local/<name>, optionally runs
  the shared local-plugin loader, and records what a shell cannot prove.
  Use when the user asks to "test my plugin locally", "prove the plugin loads",
  "install this plugin locally", "why doesn't Cursor see my plugin", or before
  publishing a plugin to a marketplace.
metadata:
  short-description: "Prove a plugin loads locally, PASS/FAIL"
---

# Plugin Load Check

You are proving that a plugin is installable and loadable, not that it is good. **Done** means every check below has a PASS, FAIL, or SKIP-with-a-reason, and you have told the user which is which. Never report a check you did not run as passed.

## When to use this skill

- A Cursor Plugin (`.cursor-plugin/plugin.json`) or Agent Plugin (root `plugin.json` with the agent-plugins `$schema`) was just written or changed
- The user says the IDE does not show their plugin
- Before submitting a plugin to a marketplace

## Preconditions

The plugin directory has one of:

- **Agent Plugin:** root `plugin.json` with `"$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"`
- **Cursor Plugin:** `.cursor-plugin/plugin.json` (a kebab-case `name`; no Agent Plugin `$schema` needed)

## Fast path: run the script

```bash
scripts/check-plugin.sh <plugin-dir>                 # static checks only
scripts/check-plugin.sh <plugin-dir> --install       # + install into a temp home
scripts/check-plugin.sh <plugin-dir> --install --home "$HOME"   # real install
```

It prints one `PASS` / `FAIL` / `SKIP` line per check and an `OVERALL:` line. Exit code is 0 only if nothing FAILed. Without `--home`, `--install` uses a fresh temp dir so a test run never touches the user's real `~/.cursor`. Only install into the real home when the user asked for it.

Paste the script output verbatim into your reply. Do not summarize a FAIL as a pass.

## Steps (what the script does, and what to do by hand)

1. **Manifest.** Find `plugin.json` (Agent) or `.cursor-plugin/plugin.json` (Cursor). JSON must parse. `name` must be kebab-case.
2. **Schema.** For Agent Plugins, validate `plugin.json` against https://agent-plugins.org/schemas/1.0.0/plugin.schema.json (python `jsonschema`). If `jsonschema` is missing or the URL does not resolve, the check is SKIP with that reason, never PASS. If the plugin has an Agent `mcp.json`, validate it by hand against `https://agent-plugins.org/schemas/1.0.0/mcp.schema.json`.
3. **Referenced files.** Every path the manifest references (`skills`, `rules`, `agents`, `commands`, `hooks`, `mcpServers`) exists inside the plugin dir. A `skills` dir must contain at least one `SKILL.md`.
4. **MCP smoke.** For a node stdio server, `node --check` the entry file. Then, by hand and only when safe (no writes, no paid calls), start the server and run `initialize`, `tools/list`, and one real `tools/call`. The script does not do the live call; say so if you skip it.
5. **Install path.** Copy into a **real directory** at `~/.cursor/plugins/local/<name>`. Not a symlink whose target is outside that folder; Cursor rejects those.
6. **Loader (optional).** If `@anysphere/cursor-plugins` is resolvable, run `loadUserLocalPlugins({ userHomeDir })` and expect the plugin name (plus its skills, rules, MCP server ids). If the package is not available, SKIP and say so.
7. **IDE.** Inside Cursor: Reload Window, then check Customize / the plugin list. Teams/Enterprise orgs may need "Allow Local Plugin Imports". A shell cannot prove this step; only the user (or an agent with the IDE open) can.
8. **Verify note.** Write a short note: plugin path, install path, each check's PASS/FAIL/SKIP, and what this environment could not prove.

## Verify note template

```
Plugin:   <name> (<cursor|agent> plugin) at <path>
Install:  <home>/.cursor/plugins/local/<name> (real dir: yes/no)
Checks:   <paste script output>
Not proven here: <IDE reload, org policy, live MCP call, loader if skipped>
Result:   PASS | FAIL (<which check>)
```

## What NOT to claim

- "The plugin loads in Cursor" when you only ran the script. The script proves the files are right and the install dir is real; the IDE step is separate.
- A schema PASS when the schema was not fetched or `jsonschema` was missing
- An MCP PASS from `node --check` alone; that is a syntax check, not a working server

## Done when

Manifest valid, referenced files present, local install present as a real directory, and either the loader/IDE reported the plugin or you wrote down why that step was skipped.
