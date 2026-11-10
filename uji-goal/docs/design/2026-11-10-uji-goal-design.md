# Native uji goal management

Approved design: adapt g4bwy/maki-goal to native uji Lua APIs. Keep persistent multi-goal lifecycle, drafting, explicit tweaks, recursive tasks, verification contracts and ordered Sisyphus execution. No subagent or spec-graph integration and no independent AI auditor.

Goals belong to the session working directory. Completed goals remain visible until explicitly archived. Storage failures and corruption must be surfaced, not treated as empty state. Objective revisions require a user-initiated tweak flow.

Explicitly starting or resuming a goal arms bounded continuation, defaulting to ten automatic follow-up turns. Completion, pause, abort, errors, interruption and the budget stop continuation. Queued user messages take precedence. Reloads and session restoration never automatically arm execution. Runtime interruption semantics must be verified before enabling the scheduler.

Completion requires a nonempty summary, contract evidence where applicable, and resolved tasks. Parent tasks require resolved descendants. Skips require reasons. Evidence checks validate claims supplied by the agent; they are not an independent audit.

Use native uji tools, commands, context providers, pickers, overlays and toolbar. Keybindings are opt-in. Verify lifecycle, storage, task gates, scheduling and native runtime loading using an isolated, model-free harness. Do not change the user's live uji configuration.
