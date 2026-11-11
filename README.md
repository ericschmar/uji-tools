# uji-tools

A monorepo for local [uji](https://github.com/uji-labs/uji) plugins and MCP tools.
Each project keeps its own source, dependencies, tests, and documentation.

## Projects

- [uji-subagents](uji-subagents/README.md): background agents, live conversations, steering, and a compact sidebar.
- [uji-goal](uji-goal/README.md): persistent project goals, tasks, and bounded continuation.
- [uji-spec-graph](uji-spec-graph/README.md): spec navigation and editing tools, plus a spec-writing skill.
- [pocketbase-mcp](pocketbase-mcp/README.md): a PocketBase MCP server.

## Install as a uji pack

Add the GitHub repository alongside your existing packs in
`~/.config/uji/init.lua`. uji installs it into its managed pack directory; no
manual clone or fixed checkout location is needed:

```lua
uji.pack.add({ "uji-labs/uji-plugins", "ericschmar/uji-tools" })
local tools = require("uji_tools").setup()

require("goal").setup({ max_auto_turns = 10 })
require("spec_graph").setup({})
require("managed_subagent").setup({ concurrency = 2 })
```

The collection's `setup()` makes the three bundled Lua packs available; it does
not enable them, change your theme, or start an MCP server. Keep each plugin's
setup call and options in your config. See the individual READMEs for details,
including the subagent theme wrapper.

`/sync` updates the repository through uji's pack manager. Run `/reload` after
changing your config. A remote installation only includes committed and pushed
changes; use the local development option below to test unpublished edits.

### Skills and resource paths

`tools.path(relative)` resolves a resource inside the installed pack, regardless
of whether uji cloned it or you use a local checkout. Add this entry to the roots
of your existing `require("skills").setup(...)` call:

```lua
tools.path("uji-spec-graph/skills")
```

Point your existing PocketBase MCP server configuration at:

```lua
cmd = { "node", tools.path("pocketbase-mcp/build/index.js") }
```

Supply PocketBase credentials through the environment. Do not commit credentials
or your personal uji configuration.

### Runtime dependencies

Pack installation clones source; it does not run dependency installers or builds.
Spec-graph is pure Lua and needs no installation step.

For PocketBase, install its dependencies and build the server in the directory
returned by `tools.path("pocketbase-mcp")`, following that project's README.
Its `build/index.js` is generated and is not shipped in Git. Reinstall dependencies
or rebuild after updates that require it. Goal, subagents and spec-graph need no
separate JavaScript dependency installation.

### Local development

To use this working copy instead of the GitHub version, replace the repository
entry with its local directory, keeping the same setup and resource-path calls:

```lua
uji.pack.add({ "uji-labs/uji-plugins", { dir = "~/develop/uji-tools" } })
local tools = require("uji_tools").setup()
```

The child packs can still be loaded individually through their local directories.
Do not load a local and remote copy of the collection together.

## Checks

Run `python3 tests/check.py` from the repository root to verify pack loading from
an arbitrary checkout location without a model call or network installation.

Run checks from each project's own directory:

- `uji-subagents`: `python3 tests/check.py`
- `uji-goal`: `python3 tests/check.py` and `python3 tests/terminal.py`
- `uji-spec-graph`: `python3 tests/check.py`
- `pocketbase-mcp`: `npm run build` (requires the project's documented build tools, including pnpm)

## Repository and licensing

All four projects are tracked by this one Git repository, not nested repositories
or submodules. Dependencies, build products, local environment files, and runtime
data are excluded from Git.

Upstream attribution and license notices remain with their projects. In
particular, review [uji-goal/UPSTREAM.md](uji-goal/UPSTREAM.md) for its upstream
license caveat before publishing or redistributing that code. There is no new
blanket license overriding the individual projects' terms.
