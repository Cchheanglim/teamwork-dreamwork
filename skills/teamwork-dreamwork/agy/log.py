"""Append one JSON event to .agy/live.log for the chat watcher.

    python .agy/log.py <event> [key=value ...] [--text-file PATH | --text TEXT]
"""
import datetime
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PREAMBLE_END = "(4) anything unfinished or uncertain."

event = {"event": sys.argv[1], "time": datetime.datetime.now().strftime("%H:%M")}
args = sys.argv[2:]
i = 0
while i < len(args):
    a = args[i]
    if a == "--text-file":
        with open(args[i + 1], encoding="utf-8") as f:
            event["text"] = f.read()
        i += 2
    elif a == "--text":
        event["text"] = args[i + 1]
        i += 2
    else:
        k, _, v = a.partition("=")
        event[k] = v or None
        i += 1

text = event.get("text")
if text is not None:
    # Hide the standard worker preamble; it is the same on every task.
    if text.startswith("You are the WORKER agent") and PREAMBLE_END in text:
        text = "[worker rules]\n" + text.split(PREAMBLE_END, 1)[1].lstrip("\n")
    event["text"] = text.strip()

with open(os.path.join(HERE, "live.log"), "a", encoding="utf-8") as f:
    f.write(json.dumps(event, ensure_ascii=False) + "\n")
