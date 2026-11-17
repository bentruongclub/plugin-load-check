# Plugin Load Check

An agent skill for AI coding assistants (Grok, Cursor, etc.) that **proves a Cursor Plugin or Agent Plugin actually loads locally**, with PASS/FAIL evidence, instead of "it should work now".

This is a **skill** (markdown instructions + one bash script + a tiny installer), not a platform or runtime.

The usual failure looks like this:

```
write plugin.json → "plugin is ready!" → user reloads Cursor → plugin isn't there → guess why
```

This skill makes the agent run the checks first and report each one:

```
manifest → JSON → name → schema → referenced files → MCP syntax → real install dir → loader → (IDE: by hand)
```

## Install (one-liner from a clone)

```bash
git clone https://github.com/bentruongclub/plugin-load-check.git
cd plugin-load-check
chmod +x install.sh
./install.sh                # → ~/.grok/skills/plugin-load-check
# ./install.sh --target cursor   # → ~/.cursor/skills/plugin-load-check
# ./install.sh --target project  # → ./.cursor/skills/plugin-load-check
# ./install.sh --target all
# ./install.sh --dry-run
```

Then invoke:

```
/plugin-load-check ./my-plugin
```

Or run the script directly:

```bash
scripts/check-plugin.sh ./my-plugin                  # static checks
scripts/check-plugin.sh ./my-plugin --install        # + install into a temp home
scripts/check-plugin.sh ./my-plugin --install --home "$HOME"   # real install
```

`--install` without `--home` uses a fresh temp dir, so trying it out never touches your real `~/.cursor`.

### Manual copy (if you prefer)

```bash
mkdir -p ~/.grok/skills/plugin-load-check/scripts
cp SKILL.md ~/.grok/skills/plugin-load-check/
cp scripts/check-plugin.sh ~/.grok/skills/plugin-load-check/scripts/
chmod +x ~/.grok/skills/plugin-load-check/scripts/check-plugin.sh
```

## The checks

Each prints one `PASS`, `FAIL`, or `SKIP` line, then `OVERALL:`. Exit code is 0 only if nothing FAILed.

| Check | What it does |
|-------|--------------|
| manifest | Finds root `plugin.json` (Agent Plugin) or `.cursor-plugin/plugin.json` (Cursor Plugin) |
| json | Manifest parses |
| name | `name` is kebab-case |
| schema | Agent Plugins: validates against https://agent-plugins.org/schemas/1.0.0/plugin.schema.json with python `jsonschema`. SKIP (with the reason) if `jsonschema` is missing, the URL doesn't resolve, or it's a Cursor manifest without that `$schema` |
| paths | Every referenced `skills`/`rules`/`agents`/`commands`/`hooks`/`mcpServers` path exists inside the plugin; a skills dir has at least one `SKILL.md` |
| mcp | `node --check` on a local JS stdio server entry, if node is installed |
| install | With `--install`: copies into `<home>/.cursor/plugins/local/<name>` and checks it is a real directory with no symlinks |
| loader | If `@anysphere/cursor-plugins` is resolvable, runs `loadUserLocalPlugins({ userHomeDir })` and looks for the plugin name |
| ide | Always SKIP: see below |

Needs bash and python3. curl, python `jsonschema`, and node are optional; without them the related check is SKIP, never PASS.

## What it cannot prove

- **That Cursor shows the plugin.** Reload Window and the Customize UI only exist inside the IDE. Teams/Enterprise orgs may also need "Allow Local Plugin Imports". The script prints a SKIP line for this every time.
- **That an MCP server works.** `node --check` is a syntax check. A live `initialize` / `tools/list` / `tools/call` is a manual step in `SKILL.md`.
- **The loader step, if the package isn't installed.** `@anysphere/cursor-plugins` is not on the public npm registry, so on most machines this is SKIP.
- **That the plugin is any good.** It checks loading, not content.

## Worked example

See [EXAMPLES.md](./EXAMPLES.md) for two real runs against [fstack](https://github.com/bentruongclub/fstack): one PASS, and one FAIL on a copy that was broken on purpose. Output is pasted verbatim.

## Files

| File | Purpose |
|------|--------|
| `SKILL.md` | Full agent instructions (frontmatter + workflow + verify note) |
| `scripts/check-plugin.sh` | The PASS/FAIL/SKIP check script |
| `install.sh` | Copy skill + script into local Grok/Cursor skill dirs |
| `EXAMPLES.md` | Real PASS and FAIL runs against fstack |

## License

MIT, see [LICENSE](./LICENSE).
