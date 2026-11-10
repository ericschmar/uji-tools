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

`core/` owns parsing, the derived read index, graph traversal, and validation.
`tools/` defines host-neutral schemas and handlers. `bridge.ts` validates requests
against those schemas and runs them in a persistent Bun process. The Lua module
registers the tools through `uji.tool.add` and the rule through `uji.context.add`.
No pi or thinkrail runtime is required.

The worker inherits uji's working directory as its spec root. It is started only
on the first tool call, reused across calls, and stopped on cancellation, timeout,
setup replacement, or application exit. Every read revalidates the filesystem;
the in-memory index is never authoritative.

`tools.json` is generated from the tool definitions with `bun run manifest` and
is checked against them in tests. Chunked JSON-line responses preserve UTF-8 and
keep individual transport lines bounded. Only formatted text reaches uji; internal
structured results stay inside the worker. Errors retain a visible `Error:` marker.

## Invariants

- The filesystem is the source of truth. Specs are Markdown files whose YAML
  frontmatter carries nonempty `id` and `type` fields.
- Only create, update, and delete mutate project files. Update edits frontmatter
  alone, preserving prose, comments, unknown fields, ordering, and line endings.
- Read tools default to allow; mutation tools default to ask. The user's uji
  policy still takes precedence.
- Large results are bounded to 50 KiB and 2,000 lines; overflow is captured in
  private temporary files with an explicit notice.
- Failed or interrupted transport never silently retries a mutation. The user
  must inspect the file before retrying an uncertain outcome.

## Out of scope

A graph viewer, semantic search, spec moves/renames, and migrating existing
plain Markdown documents to the frontmatter schema.
