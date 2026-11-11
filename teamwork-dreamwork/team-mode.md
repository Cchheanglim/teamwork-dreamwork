# Team mode: the base workflow

Part of the `teamwork-dreamwork` skill. `SKILL.md` adds routing and token rules on top of this file.

Claude Code is the **boss**. Antigravity (the `agy` CLI) is the **worker**. Claude plans the work, hands out well-scoped tasks, reviews everything Antigravity produces, and has the final say. Antigravity never decides scope on its own.

## 1. Set up the board (once per project)

In the project root (the current working directory), create `TASKS.md` if it does not exist:

```markdown
# Team board — Claude (boss) + Antigravity (worker)

## Active Locks (files currently being edited)
<!-- - path/to/file — [CLAUDE] or [ANTIGRAVITY] — task # -->

## [CLAUDE] Queue

## [ANTIGRAVITY] Queue

## Review (waiting for Claude)

## Done

## QA & Bug Reports
```

Do not create a `CLAUDE.md` for this — the rules live in this skill and in the prompt preamble below.

## 2. Plan and split

- Break the user's request into tasks. Give Antigravity tasks that are self-contained: a separate module, a page, tests, research, QA checks. Keep cross-cutting or risky work (architecture, auth, data migrations, deleting things) for Claude.
- Write each task into the right queue with a number, the files it may touch, and what "done" means.
- Add the files to **Active Locks** before anyone starts. Two agents must never hold a lock on the same file.

## 3. Hand a task to Antigravity

**Set up the scripts once per project:** copy them in and git-ignore the folder:

```bash
mkdir -p .agy && cp "$HOME/.claude/skills/teamwork-dreamwork/agy/"* .agy/ && chmod +x .agy/*.sh
```

Always go through these scripts rather than calling `agy` directly. They log every message to `.agy/live.log` so the user can see the whole conversation:

| Script | Who uses it | What it does |
|---|---|---|
| `bash .agy/run.sh <prompt-file> [conversation-id]` | Claude | Gives Antigravity a task (model from `AGY_MODEL`, any id from `agy models`, default Opus 5.5 High; switches once to `AGY_FALLBACK`, default Gemini 3.8 Flash High, when out of usage; `--mode accept-edits`, override with `AGY_MODE`). Refuses to start while another task is running. Delivers queued `/tell` messages as follow-ups when each turn ends. Prints the final result line. |
| `AGY_FROM=Claude bash .agy/ask.sh "question"` | Claude or user | Side question answered by a separate read-only session that is given the running task's progress. Works while a task runs. Model from `AGY_ASK_MODEL` (default Opus 5.5 High). |
| `AGY_FROM=Claude bash .agy/tell.sh "instruction"` | Claude or user | Instruction for the task session: queued if a task is running, otherwise sent right away as a follow-up on the last task. |
| `bash .agy/chat.sh` | user | Chat box: plain text = question, `/tell ...`, `/status`, `/quit`. |

The scripts run on macOS, Linux and Windows (Git Bash). `.agy/py.sh` picks Python 3 for them (`python3`, then `python`, then `py`; override with `AGY_PYTHON`). If none works, they exit `69` with a message: tell the user to install Python 3.

- Start tasks with `run_in_background` so Claude keeps working (and can `ask`/`tell`) in parallel.
- The first time in a project, show the user the two-pane setup, run from the project folder: watcher `python3 ~/.claude/skills/teamwork-dreamwork/watch.py` (any OS; add `--history` to replay; on Windows use `python` if `python3` isn't available, or `powershell -File "$HOME\.claude\skills\teamwork-dreamwork\watch.ps1"` with `-History`) and chat box `bash .agy/chat.sh`. The watcher shows who asked what, Antigravity's actions and replies, side Q&A and queued messages.
- Headless `agy -p` auto-denies shell commands and (without `accept-edits`) file writes, yet still reports `status: SUCCESS`. Always check `denied_actions` in the result and `git status`. If it couldn't run something, run it yourself (Claude) rather than loosening its permissions.
- Save the `conversation_id` from the result (also in `.agy/last-conversation`) next to the task in `TASKS.md`. For feedback on a finished task, `bash .agy/run.sh <feedback-file> <conversation-id>`.
- **Never** pass `--dangerously-skip-permissions`.
- Run one Antigravity task at a time: `run.sh` shares one lock, inbox and `last-conversation` file per project, so it refuses to start a second task while one is running. Send extra instructions for the running task with `tell.sh`.

**Preamble — prepend to every task prompt:**

```
You are the WORKER agent on a two-agent team. Claude Code is the lead and assigned you this task.
Rules:
- Do ONLY the task below. Do not refactor, rename, or "improve" anything outside it.
- Shell commands are disabled. Read, create and edit files with your file tools only; never use the terminal. The lead runs tests.
- Only edit the files listed for this task. Read TASKS.md: never touch a file locked by [CLAUDE].
- Never delete files, rewrite git history, push, install global packages, or change config outside this project. If the task seems to need that, stop and say so.
- If something is unclear, make no changes and ask in your reply.
- When done, reply with: (1) files changed, (2) what you did, (3) commands you ran and their results, (4) anything unfinished or uncertain.
```

## 4. Review (always)

Antigravity's report is a claim, not proof. Before marking a task done:

- Read the actual diff (`git diff` or read the files) — check it stayed inside its files and did what was asked.
- Run the relevant tests/build yourself.
- If it's wrong: send concrete feedback on the same `--conversation`, or fix it yourself if that's faster.
- Then release the locks, move the task to **Done**, and log any bugs found under **QA & Bug Reports**.

## 5. Report to the user

Summarize who did what, what Claude changed after review, and anything still open.

Never commit or push. Leave the reviewed changes in the working tree and tell the user they are ready to commit.
