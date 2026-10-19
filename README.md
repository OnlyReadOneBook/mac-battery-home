# mac-battery-home

집에서는 기본 50%를 유지하고, 캘린더의 하루 첫 외출 전에 충전 한도를 100%로 올린다. 집 밖에서는 100%를 유지한다.

## 동작

- LaunchAgent가 1분마다 집 공유기 주소와 충전 계획을 확인한다. Google 비공개 iCal 피드는 15분마다 갱신한다.
- `[학교]`, `[수업]`, `[시험]` 또는 실제 장소가 있는 일정을 외출로 본다. 온라인·비대면·마감·제출·환전·LeetCode 일정, 취소·거절·종일 일정은 제외한다.
- 기본 출발은 일정 시작 55분 전, 충전 시작은 출발 180분 전이다. 이 충전 여유는 실측값이 아니며 충전기·부하·온도에 따라 조정한다.
- 장소가 없는 일반 약속에는 제목에 `[외출]`을 넣는다. `[출발]` 일정은 시작 자체를 출발 시각으로 쓴다. 설명의 별도 줄 `출발: 08:00`은 기본 이동시간보다 우선한다. `[충전제외]`로 개별 일정을 제외한다.
- 출발일별 첫 일정만 사용한다. 충전 시간창부터 그 일정 종료까지 100% 한도를 유지하며, 실제 집 밖 이동이 관측된 날에는 뒤의 일정을 위해 다시 준비하지 않는다.
- 귀가했을 때만 50%까지 방전한다. 일정 취소나 변경으로 준비가 끝나도 강제 방전하지 않는다. 이전 비동기 방전 작업이 나중에 한도를 50%로 덮어쓰는 구조를 없앴다.
- 네트워크 판정 불가 또는 만료된 캘린더로 방전 제어를 계속할 수 없으면 전원을 복원한다. 24시간 이내 캐시는 통신 실패 시 사용한다.

외출은 캘린더의 표기와 공유기 주소를 바탕으로 추정한다. 미등록 외출이나 집과 같은 주소를 쓰는 외부 공유기는 정확히 알 수 없다. 일정 설명 전체를 자연어로 해석하거나 이동 경로를 자동 추정하지 않는다.

## 설치

Python 3.11+, AlDente가 필요하다. 방전은 SMC 키 `CHIE`(08 = 어댑터 끊기, 00 = 다시 연결)를 battery CLI 가 설치한 sudoers 항목으로 직접 써서 한다. AlDente 는 충전 한도만 맡는다. battery CLI 자체는 macOS 27에서 SMC 키를 찾지 못해 쓰지 않지만, 설치는 필요하다(smc 바이너리와 sudoers 항목). 일반 설치는 관리자 권한 없이 실행한다.

```sh
./install.sh
```

`~/.config/battery-home/config`의 설정:

```sh
HOME_GATEWAY="집 공유기 주소"
HOME_LIMIT=50
AWAY_LIMIT=100
COMMUTE_MINUTES=55
CHARGE_LEAD_MINUTES=180
```

Google Calendar 설정의 해당 캘린더 > 캘린더 통합 > iCal 형식의 비공개 주소를 `~/.config/battery-home/calendar-url`에 저장한다. 파일 권한은 `600`으로 둔다. 캘린더 소유자 이메일은 같은 디렉터리의 `calendar-owner`에 저장한다. 주소와 캐시·일정·이메일은 로컬에만 두며 Git에 넣지 않는다. 캘린더를 공개로 바꿀 필요가 없다.

## 잠든 맥의 깨우기

일반 LaunchAgent는 잠든 맥을 깨우지 못한다. 자동 충전을 위해서는 다음 보조 작업 설치가 필요하며 macOS 관리자 인증을 한 번 받는다.

```sh
sudo /bin/zsh install-wake-helper.sh
```

보조 작업은 root 소유 파일로 설치되고 1분마다 다음 충전 시작 시각을 읽어 자기 소유의 `pmset wakeorpoweron` 이벤트 하나만 갱신한다. sudoers 권한은 추가하지 않는다. 다른 앱의 깨우기 예약은 유지한다. 계획을 조회하는 Python이나 사용자가 편집할 수 있는 실행 코드를 root로 실행하지 않는다.

준비가 시작되면 연결된 전원에서 3시간 동안 유휴 절전을 막는다. 전원 연결, 덮개·OS 절전 정책과 실제 충전 상태에 따라 동작은 달라진다. 덮개를 닫은 상태의 예약 깨우기와 실제 출발 시 100% 도달은 별도 실기기 확인이 필요하다. 전원이 꺼져 로그인되지 않으면 사용자 LaunchAgent는 실행되지 않는다.

확인:

```sh
~/.config/battery-home/venv/bin/python ~/bin/calendar-plan.py --refresh
launchctl print gui/$(id -u)/local.battery-home
pmset -g sched
pmset -g batt
```

계획은 `~/.config/battery-home/plan.json`, 전환 기록은 `~/Library/Logs/battery-home/ticks.log`에 남는다. 오류 기록은 같은 폴더의 `errors.log`에서 확인한다.

## 검증

```sh
~/.config/battery-home/venv/bin/python -m unittest -v
zsh -n battery-home.sh install.sh wake-helper.sh install-wake-helper.sh
```

합성 일정으로 날짜·시간대·반복 예외·취소·제외 규칙을 검증하고, 가짜 기기 명령을 통해 준비 시 방전 해제, 취소 시 방전 방지, 실패 시 재시도와 네트워크 실패 시 전원 복원을 확인한다.
