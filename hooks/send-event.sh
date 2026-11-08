#!/bin/sh
# Claude Code hook -> 混音守門員。stdin 的 hook JSON 原樣轉送到本機 App。
# 用法：send-event.sh <stop|notification|permission|submit|end>
# 不輸出任何東西、永遠 exit 0，App 沒開也不影響 Claude。

KIND="${1:-stop}"
case "$KIND" in stop|notification|permission|submit|end) ;; *) exit 0 ;; esac

TOKEN_FILE="$HOME/.claude/mix-keeper.token"
[ -r "$TOKEN_FILE" ] || { cat >/dev/null; exit 0; }
TOKEN=$(head -c 128 "$TOKEN_FILE" | tr -cd 'A-Za-z0-9')

# Terminal 分頁才有 tty；桌面版 session 找不到就留空。
TTY_=""
pid=$PPID
i=0
while [ "$i" -lt 5 ] && [ "${pid:-1}" -gt 1 ] 2>/dev/null; do
  line=$(ps -o tty= -o ppid= -p "$pid" 2>/dev/null)
  t=$(echo "$line" | awk '{print $1}')
  parent=$(echo "$line" | awk '{print $2}')
  case "$t" in ""|"?"|"??") ;; *) TTY_="/dev/${t#/dev/}"; break ;; esac
  pid=$parent
  i=$((i + 1))
done

h() { printf '%s' "$1" | tr -cd '[:print:]' | cut -c1-200; }

curl -s -m 2 --noproxy '*' -o /dev/null -X POST "http://127.0.0.1:17917/event" \
  -H 'Content-Type: application/json' \
  -H "X-Keeper-Token: $TOKEN" \
  -H "X-Keeper-Kind: $KIND" \
  -H "X-Keeper-Tty: $(h "$TTY_")" \
  -H "X-Keeper-Term: $(h "$TERM_PROGRAM")" \
  -H "X-Keeper-Entry: $(h "$CLAUDE_CODE_ENTRYPOINT")" \
  --data-binary @- >/dev/null 2>&1
exit 0
