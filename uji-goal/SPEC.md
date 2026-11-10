---
id: uji-goal
type: architecture-design
status: active
title: Native uji goal management
tags: [uji, goals]
---

## Drivers

Long-running objectives need durable state independent of model context, with explicit user control over lifecycle and a bounded execution budget.

## Decisions

The native pack targets uji 0.2.3. The integration layer owns native registrations, drafting authorization, and persistence coordination. Pure goal/task policy is independent of UI and scheduling. The runner owns only session-local execution authorization and never restores it from disk. Views never mutate goal state.

Goals are scoped to the session directory. Completed goals remain available until explicit archival. Archived goals retain their evidence and task history. Objective changes require a user-initiated tweak flow scoped to the goal and session. No independent audit is claimed: completion gates check supplied summaries, evidence and task resolution.

## Invariants

- Goal creation is opt-in: the agent's `goal_set` requires a session-local user-initiated `/goals` or `/sisyphus` draft. Successful creation consumes that authorization; clearing the draft or changing sessions revokes it. Direct user `/goal-set` and `/sisyphus-set` commands remain available.
- Ordinary turns receive no goal context. Reading/restoring state or selecting a goal never opts into work; explicit creation or `/goal-resume` does. Drafting and tweak flows supply their own context. Paused, completed and archived goals do not inject work instructions.
- Invalid mutations and storage failures never change the accepted in-memory state.
- Corrupt persisted state is surfaced, never replaced by an empty pool.
- Completed or archived goals cannot continue executing or accept task mutations.
- Nonempty completion summaries are mandatory; verification contracts require nonempty evidence.
- A task cannot complete before its descendants are completed or skipped. Skips require a reason.
- Continuation is armed only by explicit start or resume. New sessions and reloads do not arm it.
- At most the configured number of automatic follow-up turns may run (default ten). User messages have precedence.
- User interruption, execution errors, goal switching, pause, completion, abort and budget exhaustion stop automatic continuation. Interruption is never interpreted as normal completion.
- Plugin setup does not replace the user's theme, tool policy, or default keybindings.

## Out of scope

Independent AI auditing, subagent orchestration, spec-graph integration, upstream-state migration, and modification of the user's live configuration.
