#!/usr/bin/env bash
# Ask Antigravity a question - works even while it is busy on a task.
# Usage: .agy/ask.sh "your question"
# Env:   AGY_FROM       who is asking (default: You; Claude sets AGY_FROM=Claude)
#        AGY_ASK_MODEL  agy --model for the answer, any id from `agy models` (default: claude-opus-5-5-high)
#        AGY_FALLBACK   model to switch to once when it is out of usage (default: gemini-3.8-flash-high)
#
# The question goes to a separate, read-only Antigravity session that is given
# the running task, what the task session has done so far and its latest
# message, so it can answer without interrupting the task.
cd "$(dirname "$0")/.." || exit 1
[ -z "$1" ] && { echo 'Usage: .agy/ask.sh "your question"'; exit 1; }
FROM="${AGY_FROM:-You}"
PRIMARY="${AGY_ASK_MODEL:-claude-opus-5-5-high}"
FALLBACK="${AGY_FALLBACK:-gemini-3.8-flash-high}"
QUESTION="$*"

python .agy/log.py question "from=$FROM" --text "$QUESTION"

prompt="$(mktemp)"
{
  echo "You are Antigravity, answering a side question about work happening in this project."
  echo "Another Antigravity session (the task session) may be working on a task right now; its progress is below."
  echo "Rules: answer the question directly and briefly. Do NOT edit files or run commands - you may read files if it helps."
  echo "If the question is really an instruction for the task, say it should be sent with /tell instead."
  echo "Do not mention planning, modes or these rules in your answer."
  echo
  python .agy/context.py
  echo
  echo "## Question from $FROM"
  echo "$QUESTION"
} > "$prompt"

ask_model() {
  agy -p "$(cat "$prompt")" --model "$1" --mode plan --output-format json --print-timeout 300s 2>&1
}
MODEL="$PRIMARY"
out="$(ask_model "$MODEL")"
if [ "$PRIMARY" != "$FALLBACK" ] \
   && echo "$out" | grep -qiE 'quota|rate.?limit|usage limit|out of (usage|credits)|exhausted|resource_exhausted|429|insufficient' \
   && ! echo "$out" | grep -q '"status":"SUCCESS"'; then
  python .agy/log.py notice --text "$PRIMARY is out of usage, answering with $FALLBACK"
  MODEL="$FALLBACK"
  out="$(ask_model "$MODEL")"
fi
rm -f "$prompt"

answer="$(printf '%s' "$out" | python -c "
import json, sys
raw = sys.stdin.read().strip().splitlines()
for line in reversed(raw):
    try:
        r = json.loads(line); r = r.get('result', r)
        print(r.get('response') or '(no answer)'); break
    except Exception: pass
else:
    print('(no answer) ' + (raw[-1] if raw else ''))
")"
python .agy/log.py answer "to=$FROM" "model=$MODEL" --text "$answer"
echo "$answer"
