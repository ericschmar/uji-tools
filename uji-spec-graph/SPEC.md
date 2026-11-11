---
id: module-spec-graph
type: module-design
status: active
title: Spec-graph uji pack
depends-on: []
tags: [spec-graph, uji-plugin]
---

## Responsibility

Expose frontmatter-tagged Markdown specs as a navigable graph in uji. The pack
provides seven `spec_*` tools, a spec-graph skill, and an always-on context rule
that makes applicable specs authoritative without requiring unrelated reading.

## Boundary

The pack is pure Lua running inside uji; it needs no Bun, Node or build step.
`lua/spec_graph/yaml.lua` reads the YAML subset frontmatter uses. `model.lua`
owns the is-a-spec rule, in-place frontmatter editing, the derived graph,
validation, bounded graph slices and content grep, and never touches the
filesystem. `init.lua` scans the project, formats results, and registers the
tools through `uji.tool.add` and the rule through `uji.context.add`.

The spec root is the session's working directory. Every call rescans the
filesystem, so external edits are always seen and no index is authoritative.

## Invariants

- The filesystem is the source of truth. Specs are Markdown files whose YAML
  frontmatter carries nonempty `id` and `type` fields. Build and tooling
  directories (`node_modules`, `.git`, `dist`, `build`, assistant scratch
  directories) are not indexed and symlinks are never followed.
- Only create, update, and delete mutate project files. Update edits frontmatter
  in place, preserving prose, comments, unknown fields, ordering, and line
  endings; only the fields it changes are rewritten.
- Read tools default to allow; mutation tools default to ask. The user's uji
  policy still takes precedence, and plan mode denies mutations.
- Results are bounded to 50 KiB and 2,000 lines; overflow is saved to a
  temporary file with an explicit notice. Errors carry an `Error:` marker.

## Out of scope

A graph viewer, semantic search, spec moves/renames, full YAML (anchors, nested
maps and multi-document files are not frontmatter), and migrating existing plain
Markdown documents to the frontmatter schema.
