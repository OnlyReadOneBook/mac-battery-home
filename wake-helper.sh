#!/bin/zsh
# Root-owned helper: only schedule/cancel this automation's own power event.
set -eu
plan="$1"
record="/var/run/local.battery-home-wake"
owner="local.battery-home"
iso=$(/usr/bin/plutil -extract next_wake raw -o - "$plan" 2>/dev/null || true)
old=$(cat "$record" 2>/dev/null || true)
if [[ -z "$iso" ]]; then
  if [[ -n "$old" ]]; then
    /usr/bin/pmset schedule cancel wakeorpoweron "$old" "$owner" 2>/dev/null || true
    rm -f "$record"
  fi
  exit 0
fi
[[ "$iso" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+09:00$' ]] || exit 1
epoch=$(/bin/date -j -f '%Y-%m-%dT%H:%M:%S%z' "${iso%+09:00}+0900" +%s)
now=$(/bin/date +%s)
(( epoch > now && epoch < now + 864000 )) || exit 0
stamp=$(/bin/date -r "$epoch" '+%m/%d/%y %H:%M:%S')
if [[ "${2:-}" == "--dry-run" ]]; then
  printf 'wakeorpoweron %s %s\n' "$stamp" "$owner"
  exit 0
fi
[[ "$stamp" == "$old" ]] && exit 0
if [[ -n "$old" ]]; then
  /usr/bin/pmset schedule cancel wakeorpoweron "$old" "$owner" 2>/dev/null || true
fi
/usr/bin/pmset schedule wakeorpoweron "$stamp" "$owner"
printf '%s\n' "$stamp" > "$record"
