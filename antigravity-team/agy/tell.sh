#!/usr/bin/env bash
# Send an instruction to Antigravity's task session (like typing to Claude mid-task).
# Usage: .agy/tell.sh "use port 9000 instead"
# Env:   AGY_FROM  who is sending (default: You)
#
# If a task is running, the message is queued and delivered as soon as its
# current turn ends. If nothing is running, it is sent right away as a
# follow-up on the last task conversation.
cd "$(dirname "$0")/.." || exit 1
[ -z "$1" ] && { echo 'Usage: .agy/tell.sh "message for the task"'; exit 1; }
FROM="${AGY_FROM:-You}"
MSG="$*"

pid="$(cat .agy/task.lock 2>/dev/null)"
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  python -c "import json,sys; print(json.dumps({'from': sys.argv[1], 'text': sys.argv[2]}, ensure_ascii=False))" "$FROM" "$MSG" >> .agy/inbox.jsonl
  python .agy/log.py queued "from=$FROM" --text "$MSG"
  echo "Queued - Antigravity gets this when its current step finishes."
else
  tmp="$(mktemp)"; printf '%s\n' "$MSG" > "$tmp"
  echo "No task running - sending now as a follow-up on the last task."
  AGY_FROM="$FROM" bash .agy/run.sh "$tmp" "$(cat .agy/last-conversation 2>/dev/null)" >/dev/null
  rm -f "$tmp"
  echo "Done - see the chat pane for the reply."
fi
