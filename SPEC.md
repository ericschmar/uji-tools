---
id: uji-tools-pack
type: architecture-design
title: uji-tools pack integration
status: active
tags: [uji, packaging]
---

## Boundary

The repository root is a uji pack installable by GitHub shorthand or a local
directory. Its `uji_tools` module discovers the installed root from uji's pack
list. `setup()` registers the bundled goal, subagent and spec-graph directories
as local packs within that one checkout; uji's pack manager owns cloning and
updating the collection.

Mounting is idempotent and does not call the child plugins' setup functions,
select a theme, install dependencies, build code, or start an MCP server. Users
explicitly configure each feature. Child directories remain independently
loadable as local packs.

`path(relative)` resolves resource paths inside the collection without depending
on the user's project directory or a fixed installation location. Absolute paths,
backslashes and parent traversal segments are rejected. Resource paths are not
an authorization boundary for the tools themselves.

## Runtime dependencies

The Git checkout ships Lua source, not node_modules or PocketBase's generated
bundle. Spec-graph is pure Lua; users build PocketBase using its project
instructions. Runtime configuration uses
pack-relative resource paths. Credentials remain outside the repository.
