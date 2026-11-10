# uji-goal

Persistent, project-scoped goals for [uji](https://github.com/uji-labs/uji), adapted from [g4bwy/maki-goal](https://github.com/g4bwy/maki-goal). Native Lua tools, commands, context, goal picker, task overlay and toolbar; no external service or model dependency beyond uji itself.

Tested against **uji 0.2.3**. Uses the default uji provider loop. The original source and README are retained in `upstream/`, but are not loaded. See [UPSTREAM.md](UPSTREAM.md) for provenance and the upstream license caveat.

## Install locally

Add the pack and call setup after your existing defaults/pack configuration:

```lua
uji.pack.add({ { dir = "~/develop/uji-tools/uji-goal" } })
require("goal").setup({
  max_auto_turns = 10,
  toolbar = true,
})
```

Run `/reload` to load the changed configuration. This repository does not alter your configuration automatically. `setup` is idempotent; changing options requires reloading uji.

No keys are bound by default. Optionally add command-to-key mappings:

```lua
require("goal").setup({
  keys = {
    ["goal-list"] = "<C-g>",
    ["goal-tasks"] = "<C-S-g>",
  },
})
```

Choose keys that do not conflict with your existing bindings; explicit mappings replace what those keys do.

## Workflow

- `/goals <topic>` — discuss an objective, success criteria, boundaries and constraints before creating a goal.
- `/sisyphus <topic>` — draft a goal that follows an ordered plan. Its mode is retained when the agent creates the goal.
- `/goal-set <objective>` — create a goal and start work immediately.
- `/sisyphus-set <objective>` — create and start an ordered goal immediately.
- `/goal-list` or `/goal-focus` — choose a non-archived goal, including completed ones. Focusing alone does not start execution.
- `/goal-status` — inspect the focused goal in an overlay.
- `/goal-tasks` — inspect the recursive task tree, IDs, contracts, evidence and skip reasons.
- `/goal-pause` — stop continuation and pause the goal.
- `/goal-resume` — start/resume the focused goal with a fresh continuation budget.
- `/goal-abort` — abort and archive the focused goal.
- `/goal-clear` — cancel a draft/tweak, or archive the focused goal without deleting its history.
- `/goal-tweak [hint]` — authorize one objective revision for the current goal and session. Ordinary agent updates cannot rewrite objectives.
- `/goal-settings` — display project continuation settings and usage.

Drafting allows read-only research, not implementation. Sisyphus mode asks the model to follow the user's ordered steps without inventing extra preflight work; it does not bypass safety checks or tool approvals.

## Bounded continuation

Creating a goal arms its continuation unless disabled. Explicit `/goal-resume` also arms it. After a normal turn ends unfinished, the plugin submits a continuation message, up to **ten follow-up turns** by default, in addition to the initial turn.

Completion, pause, abort, changing focus, errors, interruption, a queued user message or budget exhaustion stops continuation. Reaching the budget pauses the goal with a reason. Queued user messages take precedence; continuation stays disarmed until an explicit start/resume. Merely restoring a session, reading a goal or using the agent's lifecycle `resume` action does not arm it.

The budget bounds follow-up turns, **not tokens, tool calls, elapsed time, or spending within a turn**. Normal tool approval policy is unchanged. Automatic continuation requires an interactive uji session; `uji run` normally exits after its first turn.

Persisted project overrides:

```text
/goal-settings max_auto_turns 5
/goal-settings auto_continue off
/goal-settings auto_continue on
```

Zero follow-up turns is valid. Changing settings disarms execution; use `/goal-resume` to start a fresh run. A goal created with `auto_continue = false` remains manual even if project continuation is enabled.

Interruption behavior was verified against uji tag `v0.2.3`, `lua/uji/core/agent/init.lua`: `Agent:interrupt()` appends an error message before `turn_finished`. The runner observes that error rather than treating every `turn_finished` as successful completion.

## Agent tools

- `goal_get({mode = "focused" | "all"})` — inspect focused goal or list retained goals.
- `goal_set({objective, sisyphus?, auto_continue?, verification_contract?, tasks?})` — create and focus a goal.
- `goal_update({action, ...})` — `complete`, `pause`, `resume`, `abort` or `tweak`.
  - Complete requires `completion_summary`; a goal contract also requires `verification_summary`.
  - Pause/abort require `reason`; pause optionally accepts `suggested_action`.
  - Tweak requires a user-initiated `/goal-tweak` flow, `new_objective` and `change_summary`.
- `goal_list({})` — list non-archived goals.
- `goal_focus({goal_id})` — change focus without starting work.
- `goal_archive({goal_id?})` — archive a selected or focused goal.
- `propose_task_list({tasks})` — replace an active goal's task breakdown; supplied tasks start pending. It applies the list directly, not through a separate confirmation dialog.
- `complete_task({task_id, evidence?})` — complete a pending task; a task contract requires nonempty evidence.
- `skip_task({task_id, reason})` — skip a pending task and its pending descendants, retaining already-completed descendants and recording the inherited reason.

Task records accept `id` (generated if omitted), `title`, `verification_contract` and recursive `subtasks`. IDs and case-insensitive titles must be unique within a goal; maximum depth is eight levels. Parents cannot complete before their descendants are complete or skipped. Goals cannot complete while tasks remain unresolved. Completed and archived goals cannot accept task mutations.

These are **evidence checks, not independent AI auditing**. They enforce required fields and task state, but do not prove that evidence is truthful, tests were run, or artifacts satisfy natural-language criteria. The agent remains responsible for verification.

Goal tools declare an `allow` policy, but your explicit uji tool policies still take precedence. This does not grant approval to any implementation tools.

## Persistence and limitations

One versioned JSON record per session working directory is kept through `uji.data` as `goal-<sha256(directory)>.json`. The record stores goals (including archived history), focused goal and project settings. Working-directory strings are the project boundary: subdirectories and alternate path spellings are separate scopes, not automatically coalesced to a Git root.

State loads on the first goal tool or command after startup/session change. The context provider asks the model to read it when needed. Loading never starts execution. Completed goals stay visible until explicitly archived; archived history remains in the JSON record. There is no import from maki state.

Operations in a session are serialized. Failed writes do not accept the proposed in-memory state. Invalid/corrupt records surface an error and block replacement; back up and repair the file outside the plugin rather than resetting it blindly. If a write was already committed when interrupted, its data can remain on disk, but its callback cannot authorize execution or cross a session boundary.

**Use one writing uji session per working directory.** This first version has no cross-process locking or merge protocol; two independent sessions editing the same directory's goal record can overwrite each other's changes. Child-agent/headless orchestration is outside this version's scope.

## Tests

From this repository:

```sh
python3 tests/check.py
python3 tests/terminal.py
```

These use an isolated config/data directory and a fake model response: no credentials, network model calls or changes to your live config. They cover core policies, malformed storage, native lifecycle/tools, evidence gates, tweak authorization, persistence failures, bounded continuation, actual runtime interruption, session restoration, cancellation/session races, and terminal toolbar/picker/task rendering.

Pure Lua checks can also run separately:

```sh
LUA_PATH='lua/?.lua;;' lua tests/core.lua
LUA_PATH='lua/?.lua;;' lua tests/runner.lua
find lua tests -name '*.lua' -exec luac -p {} \;
```
