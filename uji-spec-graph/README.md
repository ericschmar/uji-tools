# Spec graph for uji

A pure-Lua uji pack ported from [JetBrains/thinkrail's spec-graph extension](https://github.com/JetBrains/thinkrail/tree/main/packages/spec-graph).

It gives uji seven tools for navigating and maintaining specs, a spec-writing
skill, and a context rule that keeps applicable specs authoritative. It does not
require pi or thinkrail and does not add a graph viewer.

## Install

Requires only uji. There is nothing to build or install.

Add the directory to your existing pack list in `~/.config/uji/init.lua`:

```lua
uji.pack.add({
    "uji-labs/uji-plugins",
    { dir = "~/develop/uji-tools/uji-spec-graph" },
})
```

Add `"~/develop/uji-tools/uji-spec-graph/skills"` to the `roots` of your existing
`require("skills").setup(...)` call. Do not call skills setup a second time.
Then enable the tools:

```lua
require("spec_graph").setup({})
```

Run `/reload`. The skill is discoverable through the skills plugin, including
`/skill:spec-graph`. The graph tools are model tools, not slash commands.

The tools read the filesystem on every call and keep no worker process.

## Tools

| Tool | Purpose |
| --- | --- |
| `spec_grep` | Search spec content, optionally filtered by metadata |
| `spec_get` | Read metadata, resolved links, and a file path; use `read_file` for prose |
| `spec_graph` | Traverse a bounded subtree, ancestor chain, or neighborhood |
| `spec_create` | Create YAML frontmatter and type-specific section headings |
| `spec_update` | Edit frontmatter without changing the body |
| `spec_delete` | Delete a spec |
| `spec_validate` | Find duplicate IDs, dangling links, and parent cycles |

Read tools default to allow and mutation tools default to ask. Your existing
uji policy takes precedence, so a global `default = "allow"` also permits spec
mutations. To require approval explicitly:

```lua
uji.tool.policy({
    spec_create = { default = "ask" },
    spec_update = { default = "ask" },
    spec_delete = { default = "ask" },
})
```

When the optional `planmode` plugin is active, spec mutations are denied.
Update/delete subjects are spec IDs, not file paths; configure their own tool
policies rather than assuming `edit_file` or `write_file` policies apply.

## Spec format

The project root is uji's working directory. Markdown files are indexed when
they have nonempty `id` and `type` in YAML frontmatter:

```markdown
---
id: architecture
type: architecture-design
title: System architecture
status: active
parent: product
depends-on: []
tags: [architecture]
---

## Decisions

Record the contracts and boundaries that govern implementation.
```

Existing plain Markdown documentation is not automatically a spec. The skill
explains supported types, lifecycle statuses, links, and the writing workflow.
Generated/build directories and upstream assistant scratch directories are
excluded from indexing. Reads pick up external file changes automatically.

`spec_create` refuses paths outside the root, ignored directories, and symlinks.
`spec_update` preserves frontmatter comments, unknown fields, ordering, line endings,
and every byte of the body. Prose changes use uji's normal file tools.

## Development

```sh
python3 tests/check.py
```

The test runs in real uji with no model call. It checks all seven tools, approval
defaults, the plan-mode guard, in-place frontmatter edits, external edits, CRLF
and BOM files, UTF-8, validation findings and output bounds.

See [UPSTREAM.md](UPSTREAM.md) for attribution and [LICENSE](LICENSE) for licensing.
