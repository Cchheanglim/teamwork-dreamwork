---
name: teamwork-dreamwork
description: Token-saving team mode. Every task goes to the cheapest model and effort level that can do it right - Claude inline for tiny edits, a Haiku sub-agent for lookups, Antigravity on Gemini Flash (low/medium) for small mechanical work, Antigravity on Sonnet or Opus for bigger self-contained work, and Claude plus the built-in /advisor (Opus/Fable) only for hard or risky calls. Use when the user says "teamwork dreamwork", "advisor team", "save tokens", "cheap mode", or wants Claude + Antigravity + advisor together.
---

# Advisor team mode

Goal: the same result as using the strongest model for everything, for far fewer tokens. A strong model only touches what needs a strong model.

This skill builds on `antigravity-team`. Before the first hand-off, read `~/.claude/skills/antigravity-team/SKILL.md` and follow it for the board (`TASKS.md`), script setup, the worker preamble, locks and review. This file only adds **routing** and **token rules**.

## 1. Setup the user does once

The advisor is a built-in Claude Code feature, not a skill. Tell the user, if it isn't set yet:

- `/model sonnet` — the main Claude session runs on the cheaper model.
- `/advisor opus` (or `/advisor fable`) — the stronger model is consulted only when the main model asks it.
- Or set `"model": "sonnet"` and `"advisorModel": "opus"` in `~/.claude/settings.json`.

If the main model is already Opus, the advisor adds nothing; say so once and continue.

## 1b. Know both teams' skills

Claude already sees its own skills. Antigravity has a separate set that Claude does not see. Once per session, before the first hand-off, list only their names (no descriptions, to save tokens):

```bash
ls ~/.gemini/config/skills ~/.gemini/antigravity-cli/builtin/skills 2>/dev/null
```

- When a task matches one of Antigravity's skills, name it in the task prompt: "Load your `<skill>` skill as a skill (do not open its file by path), then use it to ...". Antigravity loads its own skills in headless mode; it just won't pick one unless the task points it there. Without the "as a skill" hint it sometimes reads the skill file by path, which headless mode denies, and it then returns an empty `SUCCESS`.
- If both sides have the same skill (e.g. `ponytail`, `security-audit`), that work can go to Antigravity in the cheapest fitting lane instead of Claude.
- Never ask Antigravity to use a Claude skill, or the other way around; each only has its own.

## 2. Route every task to the cheapest lane that can do it

| Size | Examples | Who | How |
|---|---|---|---|
| **Tiny** | one-line fix, rename, config value, typo | Claude, inline | Do it yourself. A hand-off costs more tokens than the edit. |
| **Lookup** | find where X is used, read many files and summarize | Claude sub-agent, Haiku | Agent tool with `model: "haiku"`, `effort: "low"`; you get the conclusion, not the file dumps. |
| **Small, mechanical** | tests for existing code, boilerplate, docs, copy, simple page/component, lint fixes | Antigravity, Flash | `AGY_MODEL=gemini-3.8-flash-low` for copy/docs/renames, `gemini-3.8-flash-medium` for tests and simple components |
| **Medium, self-contained** | a new module, a feature behind a clear interface, a multi-file page | Antigravity, Sonnet/Opus | `AGY_MODEL=claude-sonnet-5-5-medium` first; `claude-opus-5-5-high` (the default) when it needs real design or failed once |
| **Hard or risky** | architecture, auth, security, data migrations, deleting things, a bug that survived 2 attempts | Claude + advisor | Consult the advisor before choosing the approach, then do it yourself. |

Command: `AGY_MODEL=<id> bash .agy/run.sh <prompt-file>`. In Antigravity the effort level is part of the model id (`-low` / `-medium` / `-high`); `agy models` lists them all. Write the chosen id next to the task in `TASKS.md`.

### Backup lane: Antigravity unavailable

Use this only when Antigravity can't take the task: `run.sh` exits `75` (the model and its Flash fallback are both out of usage) or `69` (`agy` produced no result: missing, not signed in, or crashed). Then the Small and Medium lanes go to a Claude sub-agent instead of the main session:

| Lane | Sub-agent call |
|---|---|
| Small, mechanical | Agent tool, `subagent_type: "general-purpose"`, `model: "sonnet"`, `effort: "low"` |
| Medium, self-contained | same, `effort: "medium"` |

- Give it the same prompt you would give Antigravity: worker preamble, task, files allowed, what "done" means. It may run commands, so also tell it to run the relevant tests and never commit, push or delete files.
- Lock its files as `[CLAUDE-SUB]` in `TASKS.md` and note `backup: sonnet-low` (or `-medium`) next to the task.
- Review its diff exactly as you would review Antigravity's. Same escalation rule: one step up (effort, then `opus`) if it fails review.
- This spends Claude usage, so don't use it while Antigravity is available. Re-check Antigravity on the next task (a cheap `ask` with `AGY_ASK_MODEL=gemini-3.8-flash-low`) and switch back as soon as it works.
- Tiny, Lookup and Hard lanes are unchanged.

Rules:
- When unsure between two lanes, pick the cheaper one. If its result fails review, escalate one step (higher effort first, then a stronger model) — don't retry the same model and effort more than once.
- Feedback on a finished task reuses its conversation: pass the same `AGY_MODEL` with the conversation id.
- Claude cannot switch its own session's model or effort; only the user can (`/model`, `/effort`). When the remaining work is a long run of easy edits, suggest `/effort low` to the user once; when a hard stretch starts, suggest `/effort high`. Sub-agents can take `model` and `effort` per call — this skill authorizes setting them.
- Consult the advisor at these points only: the initial plan for a multi-task request, every hard/risky task, and after 2 failed attempts at the same problem. Never for tiny or small tasks.
- Run Antigravity tasks with `run_in_background`, one at a time, and keep working on your own unlocked files.
- An empty `response` with `status: SUCCESS` means the worker did nothing: check `denied_actions` before trusting it.
- Side questions are small work: `AGY_FROM=Claude AGY_ASK_MODEL=gemini-3.8-flash-low bash .agy/ask.sh "..."`. The default ask model is Opus-high, so leave it only for questions that need deep reasoning.

## 3. Token rules for Claude

- **Short prompts.** Preamble + task + files allowed + what "done" means. No restating the whole project; Antigravity can read files itself.
- **Cheap review first.** Read the result line and `git diff --stat`. Read the full diff only for the files that task was allowed to touch. Never read `.agy/live.log` or `.agy/last-*.log` whole — grep them (`denied_actions`, `error`) if needed.
- **Review as deep as the risk.** Small lane: diff + run the tests. Medium lane: diff + tests + check edge cases. Hard lane: full review.
- **Don't re-read files** you already read this session unless they changed.
- **Batch small tasks** into one Flash hand-off when they touch different files and share context.

## 4. Report to the user

For each task: lane used, who did it, what Claude changed after review. End with what is still open.

Never commit or push. Leave the reviewed changes in the working tree and tell the user they are ready to commit.
