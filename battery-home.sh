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
DEFAULTS="${DEFAULTS_CLI:-/usr/bin/defaults}"
SET_LIMIT_FILE="$BASE/set-limit"
prev=$(cat "$STATE" 2>/dev/null || true)

set_limit() {
  open -g -b "$ALDENTE_ID"
  sleep 3
  open -g "aldente://limit/$1"
  print -r -- "$1" > "$SET_LIMIT_FILE"
}

# A limit the user set by hand (AlDente's chargeVal differs from the last value this script wrote)
# is a manual hold: the script never raises it. The hold ends when the script next writes a limit
# that matches it (arriving home sets HOME_LIMIT) or when the user sets the last written value back.
manual_hold() {
  local wanted current
  wanted=$(cat "$SET_LIMIT_FILE" 2>/dev/null || true)
  [[ -z "$wanted" ]] && return 1
  current=$("$DEFAULTS" read "$ALDENTE_ID" chargeVal 2>/dev/null || true)
  [[ -n "$current" && "$current" != "$wanted" ]]
}

# Discharge by cutting the adapter through the SMC CHIE key (08 = adapter off, 00 = on).
# battery CLI's key detection fails on macOS 27 and AlDente's button is a toggle, but the
# raw key works through the sudoers entry battery CLI installed.
SMC="${SMC_CLI:-/usr/local/co.palokaj.battery/smc}"
SUDO="${SUDO_CLI-sudo -n}"
adapter() {
  if [[ "$1" == off ]]; then ${=SUDO} "$SMC" -k CHIE -w 08; else ${=SUDO} "$SMC" -k CHIE -w 00; fi
}
start_discharge() {
  set_limit "$HOME_LIMIT"
  adapter off
}
stop_discharge() {
  adapter on
}

gw=$(ipconfig getoption en0 router 2>/dev/null || true)
if [[ -z "$gw" ]]; then
  if [[ "$prev" == "home-discharge" ]]; then
    stop_discharge
    print -r -- home > "$STATE"
  fi
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
      if [[ "$prev" == "home-discharge" ]]; then
        stop_discharge
        print -r -- home > "$STATE"
      fi
      exit 1
    fi
  fi
fi
pct=$(pmset -g batt | /usr/bin/grep -Eo '[0-9]+%' | head -1 | tr -d '%')
if [[ "$mode" == "prepare" || "$mode" == "away" ]]; then
  if [[ "$prev" != "$mode" ]]; then
    [[ "$prev" == "home-discharge" ]] && stop_discharge
    if manual_hold; then
      print -r -- "$(date -Iseconds) manual limit kept, not raising to $AWAY_LIMIT"
    else
      set_limit "$AWAY_LIMIT"
      if [[ "$mode" == "prepare" ]]; then
        "$CAFFEINATE" -s -t "$(( CHARGE_LEAD_MINUTES * 60 ))" >/dev/null 2>&1 &!
      fi
    fi
  fi
elif [[ "$prev" == "home-discharge" ]]; then
  if [[ -z "$pct" || "$pct" -gt "$HOME_LIMIT" ]]; then
    mode="home-discharge"
  else
    stop_discharge
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
