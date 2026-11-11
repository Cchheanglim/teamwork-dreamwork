#!/usr/bin/env bash
# Give Antigravity a task (the main "task" lane).
# Usage: .agy/run.sh <prompt-file> [conversation-id]
# Env:   AGY_FROM  who is asking, shown in the watcher (default: Claude)
#        AGY_MODE  agy --mode (default: accept-edits; headless denies writes otherwise)
#        AGY_MODEL agy --model (default: claude-opus-5-5-high; use gemini-3.8-flash-high for small tasks)
# Runs on AGY_MODEL; falls back to Gemini 3.8 Flash (High) if it is out of usage.
# Exit: 0 done, 1 another task is running, 69 agy unavailable (no result), 75 out of usage.
# Messages queued with `.agy/tell.sh` while the task runs are delivered as follow-ups
# on the same conversation as soon as the current turn ends.
cd "$(dirname "$0")/.." || exit 1
PROMPT_FILE="$1"; CONV="$2"
FROM="${AGY_FROM:-Claude}"
MODE="${AGY_MODE:-accept-edits}"
PRIMARY="${AGY_MODEL:-claude-opus-5-5-high}"
FALLBACK=gemini-3.8-flash-high
INBOX=.agy/inbox.jsonl

# One task at a time: the lock, inbox and last-conversation files are shared per project.
pid="$(cat .agy/task.lock 2>/dev/null)"
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  echo "Another Antigravity task is running (pid $pid). Wait for it to finish, or send this with .agy/tell.sh." >&2
  exit 1
fi

is_out_of_usage() {
  grep -qiE 'quota|rate.?limit|usage limit|out of (usage|credits)|exhausted|resource_exhausted|429|insufficient' "$1" \
    && ! grep -q '"status":"SUCCESS"' "$1"
}

# One turn on one model. Streams into the shared log for the watcher.
turn() {
  local model="$1" from="$2" file="$3" out=".agy/last-$1.log"
  local args=(-p "$(cat "$file")" --model "$model" --mode "$MODE" --output-format stream-json --print-timeout 900s)
  [ -n "$CONV" ] && args+=(--conversation "$CONV")
  python .agy/log.py prompt lane=task "from=$from" "model=$model" "conversation_id=$CONV" --text-file "$file"
  agy "${args[@]}" 2>&1 | tee "$out" | tee -a .agy/live.log >/dev/null
  local id; id=$(grep -o '"conversation_id":"[^"]*"' "$out" | tail -n 1 | cut -d'"' -f4)
  [ -n "$id" ] && CONV="$id" && echo "$id" > .agy/last-conversation
  LAST_OUT="$out"
  is_out_of_usage "$out" && return 75
  # No result line: agy is missing, not signed in, or crashed.
  grep -q '"event":"result"' "$out" || return 69
  return 0
}

# A turn with automatic model fallback.
turn_with_fallback() {
  turn "$MODEL" "$1" "$2"; local rc=$?
  if [ $rc -eq 75 ] && [ "$MODEL" = "$PRIMARY" ] && [ "$PRIMARY" != "$FALLBACK" ]; then
    python .agy/log.py notice --text "$PRIMARY is out of usage, switching to $FALLBACK"
    MODEL="$FALLBACK"; CONV=""   # fresh conversation on the fallback model
    turn "$MODEL" "$1" "$2"; rc=$?
  fi
  return $rc
}

echo $$ > .agy/task.lock          # tell.sh queues messages while this exists
trap 'rm -f .agy/task.lock' EXIT

MODEL="$PRIMARY"
turn_with_fallback "$FROM" "$PROMPT_FILE"; rc=$?

# Deliver anything queued while that turn ran, oldest first, until the inbox is empty.
while [ $rc -eq 0 ] && [ -s "$INBOX" ]; do
  batch=".agy/inbox.$$.jsonl"; mv "$INBOX" "$batch"
  msg=".agy/inbox.$$.txt"
  python - "$batch" "$msg" <<'PY'
import json, sys
items = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write("Follow-up message(s) sent while you were working. Apply them now; same rules as before.\n\n")
    for i in items:
        f.write(f"From {i['from']}: {i['text']}\n")
PY
  senders=$(python -c "import json,sys; print(' + '.join(sorted({json.loads(l)['from'] for l in open(sys.argv[1],encoding='utf-8') if l.strip()})))" "$batch")
  turn_with_fallback "$senders" "$msg"; rc=$?
  rm -f "$batch" "$msg"
done

tail -n 1 "$LAST_OUT"
[ $rc -eq 69 ] && echo "agy produced no result (missing, not signed in, or crashed). See $LAST_OUT" >&2
exit $rc
