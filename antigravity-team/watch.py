# Live chat view of the Claude <-> Antigravity conversation (cross-platform port of watch.ps1).
# Usage (from a project folder):  python3 watch.py [--history] [--log PATH]
#   --history   replay everything already in the log before following new messages
#   --log PATH  log file to follow (default .agy/live.log)
import argparse
import json
import os
import sys
import time

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if os.name == "nt":
    os.system("")  # turns on ANSI colors in the Windows console

ap = argparse.ArgumentParser()
ap.add_argument("--log", default=os.path.join(".agy", "live.log"))
ap.add_argument("--history", action="store_true")
args = ap.parse_args()
log = args.log

if not os.path.exists(log):
    os.makedirs(os.path.dirname(os.path.abspath(log)), exist_ok=True)
    open(log, "a").close()
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(log)), "..")).rstrip("\\/") + os.sep

# PowerShell color name -> ANSI foreground code (background = +10)
FG = {"Black": 30, "Red": 31, "Green": 32, "DarkYellow": 33, "Blue": 34, "Magenta": 35,
      "DarkCyan": 36, "DarkGray": 90, "Yellow": 93, "Cyan": 96, "White": 97}

TOOL_LABELS = {
    "write_to_file": "write", "replace_file_content": "edit", "multi_replace_file_content": "edit",
    "view_file": "read", "list_dir": "list", "find_by_name": "find", "grep_search": "search",
    "run_command": "run", "search_web": "web", "read_url_content": "fetch",
}

in_reply = False
reply_started = False
resumed = False


def out(text="", color=None, newline=True):
    if color:
        text = "\x1b[%dm%s\x1b[0m" % (FG[color], text)
    sys.stdout.write(text + ("\n" if newline else ""))


def short(s):
    if not s:
        return ""
    s = s.replace(root, "").replace(root.replace("\\", "/"), "")
    return s[:140] + "..." if len(s) > 140 else s


def end_reply_line():
    global in_reply
    if in_reply:
        out()
        in_reply = False


def header(who, color, extra, t=None):
    out()
    out("\x1b[30;%dm %s \x1b[0m" % (FG[color] + 10, who), newline=False)
    out("  %s  %s" % (t or time.strftime("%H:%M"), extra), "DarkGray")


def lines_of(e):
    return str(e.get("text") or "").split("\n")


def from_color(e):
    return "Magenta" if e.get("from") == "You" else "DarkYellow"


def after_side_message():
    global reply_started, resumed
    if reply_started:
        reply_started = False
        resumed = True


def handle(e):
    global in_reply, reply_started, resumed
    ev = e.get("event")
    if ev == "prompt":
        end_reply_line()
        header("%s -> Antigravity" % e.get("from"), from_color(e), "task  (%s)" % e.get("model"), e.get("time"))
        lines = lines_of(e)
        for l in lines[:25]:
            out("  " + l)
        if len(lines) > 25:
            out("  ... (%d more lines)" % (len(lines) - 25), "DarkGray")
        reply_started = False
        resumed = False
    elif ev == "question":
        end_reply_line()
        header("%s asks" % e.get("from"), from_color(e), "side question - task keeps running", e.get("time"))
        for l in lines_of(e):
            out("  " + l)
        after_side_message()
    elif ev == "answer":
        end_reply_line()
        header("Antigravity answers %s" % e.get("to"), "Blue", "(%s)" % e.get("model"), e.get("time"))
        for l in lines_of(e):
            out("  " + l, "White")
        after_side_message()
    elif ev == "queued":
        end_reply_line()
        header("%s -> task (queued)" % e.get("from"), from_color(e), "delivered when the current step ends", e.get("time"))
        for l in lines_of(e):
            out("  " + l)
        after_side_message()
    elif ev == "notice":
        end_reply_line()
        out("\n  ! %s" % e.get("text"), "Yellow")
    elif ev == "step_update":
        s = e.get("step_update") or {}
        stype = s.get("step_type")
        if not reply_started and stype in ("agent_response", "tool"):
            header("Antigravity", "Cyan", "working on task (continued)" if resumed else "working on task")
            reply_started = True
        if stype == "tool" and s.get("state") == "ACTIVE":
            end_reply_line()
            p = (s.get("tool_info") or {}).get("parameters") or {}
            detail = ""
            if isinstance(p, dict):
                for k in ("CommandLine", "TargetFile", "AbsolutePath", "DirectoryPath", "Query"):
                    if p.get(k):
                        detail = p[k]
                        break
            if not detail:
                detail = json.dumps(p, separators=(",", ":"), ensure_ascii=False)
            name = s.get("tool_name")
            label = TOOL_LABELS.get(name) or name
            out("  * %-7s%s" % (label, short(str(detail))), "DarkCyan")
        elif stype == "agent_response" and s.get("text_delta"):
            if not in_reply:
                out("  ", newline=False)
                in_reply = True
            out(str(s["text_delta"]).replace("\n", "\n  "), newline=False)
    elif ev == "result":
        end_reply_line()
        r = e.get("result") or {}
        denied = r.get("denied_actions")
        ok = r.get("status") == "SUCCESS" and not denied
        msg = "  -- %s: %s, %ds" % ("done" if ok else "problem", r.get("status"), round(r.get("duration_seconds") or 0))
        if denied:
            msg += ", BLOCKED: " + ", ".join(str(d.get("display_name")) for d in denied)
        out(msg, "Green" if ok else "Red")
        reply_started = False


out("Antigravity chat - %s  (Ctrl+C to stop)" % os.path.abspath(log), "DarkGray")
sys.stdout.flush()

try:
    pos = 0 if args.history else os.path.getsize(log)
    buf = b""
    while True:
        size = os.path.getsize(log)
        if size < pos:  # file shrank: start again from the top
            pos, buf = 0, b""
        if size > pos:
            with open(log, "rb") as f:
                f.seek(pos)
                buf += f.read()
                pos = f.tell()
            *done, buf = buf.split(b"\n")  # keep a trailing partial line for next round
            for raw in done:
                try:
                    e = json.loads(raw.decode("utf-8-sig", "replace"))
                except ValueError:
                    continue
                if isinstance(e, dict):
                    handle(e)
            sys.stdout.flush()
        time.sleep(0.3)
except KeyboardInterrupt:
    pass
