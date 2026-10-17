import importlib.util
from datetime import datetime
from pathlib import Path
import unittest
from icalendar import Calendar

spec = importlib.util.spec_from_file_location('plan', Path(__file__).with_name('calendar-plan.py'))
plan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plan)


def calendar(*events):
    return Calendar.from_ical('BEGIN:VCALENDAR\nVERSION:2.0\n' + ''.join('BEGIN:VEVENT\n' + e + '\nEND:VEVENT\n' for e in events) + 'END:VCALENDAR\n')


def event(uid='school', title='[학교] 수업', start='20261020T001000Z', extra=''):
    return f'UID:{uid}\nDTSTART:{start}\nDURATION:PT1H\nSUMMARY:{title}\n{extra}'


class DepartureContract(unittest.TestCase):
    now = datetime(2026, 10, 20, 0, tzinfo=plan.TZ)

    def test_first_school_is_ready_55_minutes_before_start(self):
        result = plan.departures(calendar(event(), event('later', start='20261020T030000Z')), self.now)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['departure'], '2026-10-20T08:15:00+09:00')
        self.assertEqual(result[0]['charge_start'], '2026-10-20T05:15:00+09:00')
        self.assertEqual(plan.choose_mode(result, self.now.replace(hour=5, minute=15)), 'prepare')
        self.assertEqual(plan.choose_mode(result, self.now.replace(hour=5, minute=14)), 'home')

    def test_deadlines_online_cancelled_declined_and_all_day_are_excluded(self):
        c = calendar(event('deadline', '[마감] 학교 과제 제출'), event('online', '[학교] 온라인 수업'),
                     event('cancelled', extra='STATUS:CANCELLED'),
                     event('declined', extra='ATTENDEE;PARTSTAT=DECLINED:mailto:owner@example.test'),
                     'UID:all-day\nDTSTART;VALUE=DATE:20261020\nSUMMARY:[학교] 행사')
        self.assertEqual(plan.departures(c, self.now, email='owner@example.test'), [])

    def test_recurring_exception_moves_only_that_occurrence(self):
        c = calendar(event(extra='RRULE:FREQ=DAILY;COUNT=3'),
                     event(start='20261021T020000Z', extra='RECURRENCE-ID:20261021T001000Z'))
        results = plan.departures(c, self.now)
        self.assertEqual([r['departure'] for r in results], ['2026-10-20T08:15:00+09:00', '2026-10-21T10:05:00+09:00', '2026-10-22T08:15:00+09:00'])

    def test_cancelled_recurring_exception_is_not_a_departure(self):
        c = calendar(event(extra='RRULE:FREQ=DAILY;COUNT=2'),
                     event(start='20261021T001000Z', extra='RECURRENCE-ID:20261021T001000Z\nSTATUS:CANCELLED'))
        self.assertEqual(len(plan.departures(c, self.now)), 1)

    def test_midnight_crossing_uses_departure_day(self):
        c = calendar(event(start='20261020T153000Z'))
        result = plan.departures(c, self.now)[0]
        self.assertEqual(result['departure'], '2026-10-20T23:35:00+09:00')
        self.assertEqual(plan.choose_mode([result], self.now.replace(hour=23)), 'prepare')

    def test_explicit_departure_and_exclusion_tags(self):
        c = calendar(event('outing', '[外出] test', extra='LOCATION:카페\nDESCRIPTION:출발: 08:00'),
                     event('skip', '[학교][충전제외]', start='20261020T000000Z'))
        self.assertEqual(plan.departures(c, self.now)[0]['departure'], '2026-10-20T08:00:00+09:00')
        self.assertTrue(plan.is_outing(Calendar.from_ical('BEGIN:VEVENT\nSUMMARY:[외출] 친구 약속\nEND:VEVENT')))

    def test_first_outing_completed_does_not_prepare_for_second(self):
        results = plan.departures(calendar(event(), event('later', start='20261020T060000Z')), self.now)
        self.assertEqual(plan.choose_mode(results, self.now.replace(hour=6), '2026-10-20'), 'home')
        self.assertEqual(plan.choose_mode(results, self.now.replace(hour=15)), 'home')


if __name__ == '__main__':
    unittest.main()
