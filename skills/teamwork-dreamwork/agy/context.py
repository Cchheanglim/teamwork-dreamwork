"""Summarise the current Antigravity task from .agy/live.log.

Used by ask.sh so a side session can answer questions about a task that is
still running in another Antigravity session.

    python .agy/context.py            -> prints a context block for a prompt
    python .agy/context.py --running  -> exit 0 if a task is running, else 1
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(HERE, "live.log")
ROOT = os.path.dirname(HERE) + os.sep
LABELS = {
    "write_to_file": "wrote", "replace_file_content": "edited", "multi_replace_file_content": "edited",
    "view_file": "read", "list_dir": "listed", "find_by_name": "searched for", "grep_search": "searched",
    "run_command": "ran", "search_web": "web-searched", "read_url_content": "fetched",
}


def load():
    events = []
    try:
        with open(LOG, encoding="utf-8") as f:
            for line in f:
                try:
                    events.append(json.loads(line))
                except ValueError:
                    pass
    except FileNotFoundError:
        pass
    return events


def short(s):
    s = (s or "").replace(ROOT, "").replace(ROOT.replace("\\", "/"), "")
    return s if len(s) <= 120 else s[:120] + "..."


def summarise(events):
    last_task = None
    for i, e in enumerate(events):
        if e.get("event") == "prompt" and e.get("lane", "task") == "task":
            last_task = i
    if last_task is None:
        return None
    prompt = events[last_task]
    actions, reply, result = [], [], None
    for e in events[last_task + 1:]:
        if e.get("event") == "prompt" and e.get("lane", "task") == "task":
            # a queued follow-up on the same task: keep going, note it
            actions.append(f"received follow-up from {e.get('from')}: {short(e.get('text'))}")
            reply, result = [], None
            continue
        if e.get("event") == "result":
            result = e["result"]
            continue
        s = e.get("step_update") or {}
        if s.get("step_type") == "tool" and s.get("state") == "ACTIVE":
            p = (s.get("tool_info") or {}).get("parameters") or {}
            detail = p.get("CommandLine") or p.get("TargetFile") or p.get("AbsolutePath") or p.get("DirectoryPath") or p.get("Query") or ""
            actions.append(f"{LABELS.get(s.get('tool_name'), s.get('tool_name'))} {short(detail)}")
        elif s.get("step_type") == "agent_response" and s.get("text_delta"):
            reply.append(s["text_delta"])
    side = [e for e in events if e.get("event") in ("question", "answer")][-6:]
    return prompt, actions, "".join(reply), result, side


def main():
    info = summarise(load())
    running = info is not None and info[3] is None
    if "--running" in sys.argv:
        sys.exit(0 if running else 1)
    if info is None:
        print("No task has been given to Antigravity in this project yet.")
        return
    prompt, actions, reply, result, side = info
    status = "STILL RUNNING" if running else f"FINISHED ({result.get('status')})"
    text = prompt.get("text", "")
    if len(text) > 2500:
        text = text[:2500] + "\n... (truncated)"
    out = [f"## Current task: {status}",
           f"Sent by {prompt.get('from', 'Claude')} at {prompt.get('time', '?')}:", text, "",
           "## What the task session has done so far (oldest first)"]
    out += [f"- {a}" for a in actions[-30:]] or ["- nothing yet"]
    reply = reply.strip()
    if reply:
        out += ["", "## Its latest message (tail)", reply[-1500:]]
    if side:
        out += ["", "## Recent side questions and answers"]
        for e in side:
            who = e.get("from", "?") if e["event"] == "question" else "Antigravity"
            out.append(f"{who}: {short(e.get('text'))}")
    print("\n".join(out))


if __name__ == "__main__":
    main()
