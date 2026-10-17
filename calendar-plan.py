#!/usr/bin/env python3
"""Read a private iCalendar feed and plan the first departure of each day."""
import argparse
from datetime import datetime, time, timedelta
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from zoneinfo import ZoneInfo

from icalendar import Calendar
import recurring_ical_events

BASE = Path.home() / '.config/battery-home'
TZ = ZoneInfo('Asia/Seoul')


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read_calendar(now, refresh=False):
    cache = BASE / 'calendar.ics'
    if refresh or not cache.exists() or now.timestamp() - cache.stat().st_mtime > 900:
        url = (BASE / 'calendar-url').read_text().strip()
        if not re.fullmatch(r'https://calendar\.google\.com/calendar/ical/[^\s"\\]+/private-[a-zA-Z0-9]+/basic\.ics', url):
            raise ValueError('Invalid private calendar URL')
        # curl uses macOS trust roots; keep the bearer URL out of argv and logs.
        result = subprocess.run(['/usr/bin/curl', '--fail', '--silent', '--max-time', '20', '--config', '-'],
                                input=f'url = "{url}"\n', text=True, capture_output=True)
        if result.returncode == 0 and result.stdout.startswith('BEGIN:VCALENDAR'):
            Calendar.from_ical(result.stdout)
            atomic_write(cache, result.stdout)
        elif not cache.exists() or now.timestamp() - cache.stat().st_mtime > 86400:
            raise RuntimeError('Calendar refresh failed and cache is unavailable or expired')
    return Calendar.from_ical(cache.read_bytes())


def is_outing(event, email=''):
    if str(event.get('STATUS', '')).upper() == 'CANCELLED':
        return False
    attendees = event.get('ATTENDEE', [])
    if not isinstance(attendees, list):
        attendees = [attendees]
    for attendee in attendees:
        if email and str(attendee).lower() == 'mailto:' + email.lower() and str(attendee.params.get('PARTSTAT', '')).upper() == 'DECLINED':
            return False
    title = str(event.get('SUMMARY', ''))
    location = str(event.get('LOCATION', '')).strip()
    if '[충전제외]' in title:
        return False
    if '[외출]' in title or '[출발]' in title:
        return True
    if re.search(r'온라인|이러닝|녹강|비대면|마감|제출|환전|LeetCode|Zoom|Google Meet', title, re.I):
        return False
    if re.search(r'온라인|비대면|https?://|zoom|meet\.google', location, re.I):
        return False
    return bool(re.search(r'\[학교\]|\[수업\]|\[시험\]', title) or (location and location not in ('집', '자택', '온라인', '추후 공지')))


def departures(calendar, now, commute=55, lead=180, email=''):
    midnight = datetime.combine(now.date(), time.min, TZ)
    first = {}
    for event in recurring_ical_events.of(calendar).between(midnight - timedelta(days=1), midnight + timedelta(days=9)):
        start = event.decoded('DTSTART')
        if not isinstance(start, datetime) or not is_outing(event, email):
            continue
        start = start.replace(tzinfo=TZ) if start.tzinfo is None else start.astimezone(TZ)
        title = str(event.get('SUMMARY', ''))
        departure = start if '[출발]' in title else start - timedelta(minutes=commute)
        override = re.search(r'(?:^|\n)출발\s*[:：]\s*([01]?\d|2[0-3]):([0-5]\d)(?:\s|$)', str(event.get('DESCRIPTION', '')))
        if override:
            departure = start.replace(hour=int(override[1]), minute=int(override[2]), second=0)
            if departure > start:
                departure -= timedelta(days=1)
        end = event.decoded('DTEND', start + timedelta(hours=1))
        if not isinstance(end, datetime):
            end = start + timedelta(hours=1)
        end = end.replace(tzinfo=TZ) if end.tzinfo is None else end.astimezone(TZ)
        day = departure.date().isoformat()
        item = {'date': day, 'title': title, 'event_start': start.isoformat(), 'departure': departure.isoformat(),
                'charge_start': (departure - timedelta(minutes=lead)).isoformat(), 'hold_until': max(end, departure + timedelta(hours=1)).isoformat()}
        if day not in first or item['departure'] < first[day]['departure']:
            first[day] = item
    return sorted(first.values(), key=lambda x: x['departure'])


def choose_mode(plans, now, completed_date=''):
    for p in plans:
        if p['date'] == completed_date:
            continue
        if datetime.fromisoformat(p['charge_start']) <= now <= datetime.fromisoformat(p['hold_until']):
            return 'prepare'
    return 'home'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--mode', action='store_true')
    ap.add_argument('--refresh', action='store_true')
    ap.add_argument('--commute', type=int, default=55)
    ap.add_argument('--lead', type=int, default=180)
    ap.add_argument('--completed-date', default='')
    args = ap.parse_args()
    now = datetime.now(TZ)
    try:
        calendar = read_calendar(now, args.refresh)
        email = (BASE / 'calendar-owner').read_text().strip() if (BASE / 'calendar-owner').exists() else ''
        plans = departures(calendar, now, args.commute, args.lead, email)
        next_wake = next((p['charge_start'] for p in plans if datetime.fromisoformat(p['charge_start']) > now), '')
        report = {'updated_at': now.isoformat(), 'mode': choose_mode(plans, now, args.completed_date),
                  'commute_minutes': args.commute, 'charge_lead_minutes': args.lead, 'next_wake': next_wake, 'plans': plans}
        atomic_write(BASE / 'plan.json', json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(report['mode'] if args.mode else json.dumps(report, ensure_ascii=False, indent=2))
    except Exception as e:
        # Exception strings may contain private feed URLs. Log only the error class.
        if args.mode:
            print('unknown')
        else:
            print(json.dumps({'error': type(e).__name__}))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
