#!/bin/zsh
# One short tick owns both charging and discharge. No background worker can restore an obsolete limit.
# AlDente does both: the URL scheme sets the limit, its Discharge button drains to that limit.
set -eu
CONFIG="$HOME/.config/battery-home/config"
HOME_GATEWAY=""
HOME_LIMIT=50
AWAY_LIMIT=100
COMMUTE_MINUTES=55
CHARGE_LEAD_MINUTES=180
[[ -f "$CONFIG" ]] && source "$CONFIG"
[[ -z "$HOME_GATEWAY" ]] && exit 0
BASE="$HOME/.config/battery-home"
STATE="$HOME/.battery-home-state"
ALDENTE_ID="com.apphousekitchen.aldente-pro"
CAFFEINATE="${CAFFEINATE_CLI:-/usr/bin/caffeinate}"
prev=$(cat "$STATE" 2>/dev/null || true)

set_limit() {
  open -g -b "$ALDENTE_ID"
  sleep 3
  open -g "aldente://limit/$1"
}

# AlDente has no discharge URL; an applet presses the popover's Discharge button.
# It is a separate app so the Accessibility grant is scoped to it.
DISCHARGE_APP="${DISCHARGE_APP:-$HOME/Applications/BatteryHomeDischarge.app}"
start_discharge() {
  set_limit "$HOME_LIMIT"
  # The Discharge button toggles, so never press it while a discharge is already running.
  pmset -g batt | /usr/bin/grep -q 'discharging' && return 0
  sleep 2
  # Pressed once per transition: retrying every tick toggled a running discharge off again.
  open -g -W "$DISCHARGE_APP"
}

gw=$(ipconfig getoption en0 router 2>/dev/null || true)
if [[ -z "$gw" ]]; then
  # AlDente stops discharging at the limit by itself, so lost control needs no power restore.
  [[ "$prev" == "home-discharge" ]] && print -r -- home > "$STATE"
  exit 0
fi
location="away"
[[ "$gw" == "$HOME_GATEWAY" ]] && location="home"
day=$(TZ=Asia/Seoul date +%F)
completed=$(cat "$BASE/completed-day" 2>/dev/null || true)
if [[ "$location" == "away" ]]; then
  print -r -- "$day" > "$BASE/completed-day"
  mode="away"
else
  mode="home"
  if [[ -f "$BASE/calendar-url" ]]; then
    mode=$("$BASE/venv/bin/python" "$HOME/bin/calendar-plan.py" --mode --commute "$COMMUTE_MINUTES" --lead "$CHARGE_LEAD_MINUTES" --completed-date "$completed" || true)
    if [[ "$mode" == "unknown" || -z "$mode" ]]; then
      [[ "$prev" == "home-discharge" ]] && print -r -- home > "$STATE"
      exit 1
    fi
  fi
fi
pct=$(pmset -g batt | /usr/bin/grep -Eo '[0-9]+%' | head -1 | tr -d '%')
if [[ "$mode" == "prepare" || "$mode" == "away" ]]; then
  if [[ "$prev" != "$mode" ]]; then
    # Raising the limit also ends any discharge in progress.
    set_limit "$AWAY_LIMIT"
    if [[ "$mode" == "prepare" ]]; then
      "$CAFFEINATE" -s -t "$(( CHARGE_LEAD_MINUTES * 60 ))" >/dev/null 2>&1 &!
    fi
  fi
elif [[ "$prev" == "home-discharge" ]]; then
  if [[ -z "$pct" || "$pct" -gt "$HOME_LIMIT" ]]; then
    mode="home-discharge"
  fi
elif [[ "$prev" != "home" ]]; then
  # Any arrival at home mode (return from outside or end of a charge window) drains to the home limit.
  if [[ -n "$pct" && "$pct" -gt "$HOME_LIMIT" ]]; then
    start_discharge
    mode="home-discharge"
  else
    set_limit "$HOME_LIMIT"
  fi
fi
if [[ "$prev" != "$mode" ]]; then
  print -r -- "$(date -Iseconds) $prev -> $mode battery=$pct"
fi
print -r -- "$mode" > "$STATE"
