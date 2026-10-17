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

# AlDente has no discharge URL; press the popover's Discharge button through accessibility.
start_discharge() {
  set_limit "$HOME_LIMIT"
  sleep 2
  osascript <<'EOF'
tell application "System Events"
  tell process "AlDente"
    if (count of windows) = 0 then
      perform action "AXPress" of menu bar item 1 of menu bar 2
      delay 2
    end if
    set pressed to false
    repeat with b in (buttons of UI element 1 of window 1)
      try
        if (value of attribute "AXHelp" of b) starts with "Discharges" then
          perform action "AXPress" of b
          set pressed to true
          exit repeat
        end if
      end try
    end repeat
    key code 53
    if not pressed then error "AlDente Discharge button not found"
  end tell
end tell
EOF
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
