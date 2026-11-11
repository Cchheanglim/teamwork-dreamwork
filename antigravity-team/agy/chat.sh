#!/usr/bin/env bash
# Chat box for talking to Antigravity while it works. Run in its own terminal pane:
#   bash .agy/chat.sh
# Everything you send also shows up in the watcher pane.
cd "$(dirname "$0")/.." || exit 1
export AGY_FROM="${AGY_FROM:-You}"

c_dim=$'\e[90m'; c_you=$'\e[35m'; c_ag=$'\e[36m'; c_off=$'\e[0m'
cat <<EOF
${c_ag}Antigravity chat${c_off}  ${c_dim}(you are "$AGY_FROM")${c_off}
  ${c_dim}question            ask anything - answered right away, even while it is busy${c_off}
  ${c_dim}/tell <message>     instruction for the task (queued until its current step ends)${c_off}
  ${c_dim}/status             what the task session is doing now${c_off}
  ${c_dim}/quit               exit${c_off}
EOF

while true; do
  echo
  IFS= read -r -e -p "${c_you}${AGY_FROM} >${c_off} " line || break
  [ -z "${line// }" ] && continue
  history -s "$line"
  case "$line" in
    /quit|/exit) break ;;
    /status)
      if python .agy/context.py --running; then echo "${c_dim}A task is running.${c_off}"; else echo "${c_dim}No task running.${c_off}"; fi
      python .agy/context.py | sed -n '/## What the task session/,$p' | tail -n 15 ;;
    /tell\ *) bash .agy/tell.sh "${line#/tell }" ;;
    /*) echo "${c_dim}Unknown command. Use /tell, /status or /quit.${c_off}" ;;
    *)
      echo "${c_dim}thinking...${c_off}"
      answer="$(bash .agy/ask.sh "$line")"
      echo "${c_ag}Antigravity >${c_off} $answer" ;;
  esac
done
