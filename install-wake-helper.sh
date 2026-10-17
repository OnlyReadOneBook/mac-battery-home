#!/bin/zsh
# Run with sudo after reviewing wake-helper.sh. No sudoers permissions are added.
set -eu
[[ "$EUID" == 0 && -n "${SUDO_USER:-}" ]] || { echo '실행: sudo /bin/zsh install-wake-helper.sh'; exit 1; }
script_dir=${0:A:h}
user_home=$(/usr/bin/dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory | /usr/bin/sed 's/^NFSHomeDirectory: //')
[[ -d "$user_home/.config/battery-home" ]] || exit 1
root_dir='/Library/Application Support/BatteryHome'
plist='/Library/LaunchDaemons/local.battery-home-wake.plist'
mkdir -p "$root_dir"
/usr/bin/install -o root -g wheel -m 755 "$script_dir/wake-helper.sh" "$root_dir/wake-helper.sh"
/usr/bin/python3 - "$plist" "$root_dir/wake-helper.sh" "$user_home/.config/battery-home/plan.json" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'Label':'local.battery-home-wake', 'ProgramArguments':['/bin/zsh',sys.argv[2],sys.argv[3]],
                  'StartInterval':60,'RunAtLoad':True,'StandardErrorPath':'/var/log/battery-home-wake.log'}, f)
PY
chown root:wheel "$plist"
chmod 644 "$plist"
launchctl bootout system/local.battery-home-wake 2>/dev/null || true
launchctl bootstrap system "$plist"
/bin/zsh "$root_dir/wake-helper.sh" "$user_home/.config/battery-home/plan.json"
/usr/bin/pmset -g sched
echo '충전 시작 전 깨우기 예약 설치 완료'
