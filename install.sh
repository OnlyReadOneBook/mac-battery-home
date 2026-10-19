#!/bin/zsh
# battery-home.sh 를 ~/bin 에 복사하고 1분마다 돌리는 LaunchAgent 를 등록한다.
# battery CLI 와 AlDente 는 따로 설치해 둔다(README 참고).
set -e
cd "$(dirname "$0")"

LABEL="local.battery-home"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG="$HOME/.config/battery-home/config"

mkdir -p "$HOME/bin" "$(dirname "$CONFIG")"
python_bin="${PYTHON_BIN:-$(command -v python3)}"
[[ -x "$python_bin" ]] || { echo "Python 3.11+ is required"; exit 1; }
"$python_bin" -c 'import sys; assert sys.version_info >= (3, 11)'
"$python_bin" -m venv "$HOME/.config/battery-home/venv"
"$HOME/.config/battery-home/venv/bin/pip" install -r requirements.txt
install -m 755 calendar-plan.py "$HOME/bin/calendar-plan.py"
install -m 755 battery-home.sh "$HOME/bin/battery-home.sh"
mkdir -p "$HOME/Library/Logs/battery-home"

if [[ ! -f "$CONFIG" ]]; then
  gw=$(ipconfig getoption en0 router 2>/dev/null || true)
  printf 'HOME_GATEWAY="%s"\nHOME_LIMIT=50\nAWAY_LIMIT=100\n' "$gw" > "$CONFIG"
  echo "설정 파일을 만들었다: $CONFIG (지금 공유기 $gw 를 집으로 등록)"
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$HOME/bin/battery-home.sh</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/battery-home/ticks.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/battery-home/errors.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

# AlDente 가 로그인 때 켜져 있어야 한도가 지켜진다.
osascript -e 'tell application "System Events" to if not (exists login item "AlDente") then make login item at end with properties {path:"/Applications/AlDente.app", hidden:true}' >/dev/null

echo "설치 완료. 상태 초기화: rm ~/.battery-home-state"
