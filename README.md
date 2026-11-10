# uji-tools

A monorepo for local [uji](https://github.com/uji-labs/uji) plugins and MCP tools.
Each project keeps its own source, dependencies, tests, and documentation.

## Projects

- [uji-subagents](uji-subagents/README.md): background agents, live conversations, steering, and a compact sidebar.
- [uji-goal](uji-goal/README.md): persistent project goals, tasks, and bounded continuation.
- [uji-spec-graph](uji-spec-graph/README.md): spec navigation and editing tools, plus a spec-writing skill.
- [pocketbase-mcp](pocketbase-mcp/README.md): a PocketBase MCP server.

## Local uji setup

Clone this repository to `~/develop/uji-tools`, then add the plugin directories
alongside your existing packs in `~/.config/uji/init.lua`:

```lua
uji.pack.add({
    "uji-labs/uji-plugins",
    { dir = "~/develop/uji-tools/uji-subagents" },
    { dir = "~/develop/uji-tools/uji-goal" },
    { dir = "~/develop/uji-tools/uji-spec-graph" },
})
```

Keep each plugin's existing setup call. Add
`~/develop/uji-tools/uji-spec-graph/skills` to the roots of your existing skills
setup. See the individual READMEs for dependencies and configuration.

The repository root is a collection, not a single uji pack: load the three
plugin subdirectories rather than registering the root as a pack.

Build PocketBase's MCP server in `pocketbase-mcp/` and point your MCP configuration
at that directory's `build/index.js`. Supply credentials locally through the
environment; do not commit credentials or your personal uji configuration.

Run `/reload` after changing your uji configuration.

## Checks

Run checks from each project's own directory:

- `uji-subagents`: `python3 tests/check.py`
- `uji-goal`: `python3 tests/check.py` and `python3 tests/terminal.py`
- `uji-spec-graph`: `bun run typecheck` and `bun test`
- `pocketbase-mcp`: `npm run build` (requires the project's documented build tools, including pnpm)

## Repository and licensing

All four projects are tracked by this one Git repository, not nested repositories
or submodules. Dependencies, build products, local environment files, and runtime
data are excluded from Git.

Upstream attribution and license notices remain with their projects. In
particular, review [uji-goal/UPSTREAM.md](uji-goal/UPSTREAM.md) for its upstream
license caveat before publishing or redistributing that code. There is no new
blanket license overriding the individual projects' terms.
