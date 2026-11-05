import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/daily_log.dart';
import 'package:flutter_application_1/services/couple_service.dart';
import 'package:flutter_application_1/services/daily_log_notification_summary.dart';

void main() {
  group('DailyLog', () {
    test('includes boundary and support moods in the mood choices', () {
      expect(DailyLog.moods['dont_talk_to_me'], "Don't talk to me");
      expect(DailyLog.moods['leave_me_alone'], 'Leave me alone');
      expect(DailyLog.moods['need_space'], 'I need some space');
      expect(DailyLog.moods['want_company'], 'I want company');
      expect(DailyLog.moods['need_support'], 'I need support');
    });

    test('creates a stable local date key', () {
      expect(DailyLog.keyFor(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('treats a cleared check-in as empty', () {
      const log = DailyLog(
        dateKey: '2026-03-05',
        isPeriodDay: false,
        mood: null,
        symptoms: [],
        notes: '  ',
      );

      expect(log.isEmpty, isTrue);
    });

    test('serializes the complete daily check-in', () {
      const log = DailyLog(
        dateKey: '2026-03-05',
        isPeriodDay: true,
        mood: 'low',
        symptoms: ['Cramps'],
        notes: 'Taking it slow',
        flow: 'light',
        painLevel: 4,
      );

      expect(log.toFirestore(), {
        'dateKey': '2026-03-05',
        'isPeriodDay': true,
        'mood': 'low',
        'moodTags': ['low'],
        'symptoms': ['Cramps'],
        'notes': 'Taking it slow',
        'flow': 'light',
        'painLevel': 4,
      });
    });

    test(
      'serializes multiple moods while retaining the legacy primary mood',
      () {
        const log = DailyLog(
          dateKey: '2026-03-05',
          isPeriodDay: false,
          mood: 'anxious',
          moodTags: ['anxious', 'overwhelmed'],
          symptoms: [],
          notes: '',
        );

        expect(log.selectedMoods, ['anxious', 'overwhelmed']);
        expect(log.toFirestore()['mood'], 'anxious');
        expect(log.toFirestore()['moodTags'], ['anxious', 'overwhelmed']);
      },
    );

    test('reads older entries without mood tags', () {
      final log = DailyLog.fromData('2026-03-05', {
        'isPeriodDay': false,
        'mood': 'low',
        'symptoms': <String>[],
        'notes': '',
      });

      expect(log.selectedMoods, ['low']);
    });

    test('keeps an optional pain-only entry', () {
      const log = DailyLog(
        dateKey: '2026-03-05',
        isPeriodDay: false,
        mood: null,
        symptoms: [],
        notes: '',
        painLevel: 4,
      );

      expect(log.isEmpty, isFalse);
      expect(log.toFirestore()['painLevel'], 4);
    });

    test('groups consecutive period days and calculates cycle length', () {
      DailyLog periodDay(String dateKey) => DailyLog(
        dateKey: dateKey,
        isPeriodDay: true,
        mood: null,
        symptoms: const [],
        notes: '',
      );

      final history = CycleHistory.fromLogs([
        periodDay('2026-03-01'),
        periodDay('2026-03-02'),
        periodDay('2026-02-03'),
        periodDay('2026-02-01'),
        periodDay('2026-02-02'),
        periodDay('2026-02-02'),
      ]);

      expect(history.periods, hasLength(2));
      expect(history.periods.first.loggedDays, 3);
      expect(history.periods.first.lastLoggedDate, DateTime(2026, 2, 3));
      expect(history.averageCycleLengthDays, 28);
    });

    test('returns an empty history without period days', () {
      expect(CycleHistory.fromLogs(const []).periods, isEmpty);
      expect(CycleHistory.fromLogs(const []).averageCycleLengthDays, isNull);
    });
  });

  group('DailyLogNotificationSummary', () {
    test('describes fields changed without including note contents', () {
      final summary = DailyLogNotificationSummary.forChange(
        dateKey: '2026-03-05',
        previousData: {
          'isPeriodDay': false,
          'mood': null,
          'symptoms': <String>[],
          'notes': '',
          'flow': null,
          'painLevel': null,
        },
        nextLog: const DailyLog(
          dateKey: '2026-03-05',
          isPeriodDay: true,
          mood: 'anxious',
          symptoms: ['Cramps'],
          notes: 'private note text',
          flow: 'light',
          painLevel: 4,
        ),
      );

      expect(summary.title, 'Daily entry updated');
      expect(summary.body, contains('Mar 5'));
      expect(summary.body, contains('period day logged'));
      expect(summary.body, contains('Mood: Anxious'));
      expect(summary.body, contains('symptoms added: Cramps'));
      expect(summary.body, contains('Flow: Light'));
      expect(summary.body, contains('Pain level: 4/10'));
      expect(summary.body, contains('Note updated'));
      expect(summary.body, isNot(contains('private note text')));
    });

    test('labels a new entry and a deleted entry', () {
      final added = DailyLogNotificationSummary.forChange(
        dateKey: '2026-03-05',
        previousData: null,
        nextLog: const DailyLog(
          dateKey: '2026-03-05',
          isPeriodDay: false,
          mood: null,
          symptoms: [],
          notes: '',
        ),
      );
      final deleted = DailyLogNotificationSummary.forChange(
        dateKey: '2026-03-05',
        previousData: {
          'isPeriodDay': true,
          'symptoms': <String>[],
          'notes': '',
        },
        nextLog: null,
      );

      expect(added.title, 'Daily entry added');
      expect(deleted.title, 'Daily entry deleted');
      expect(deleted.body, 'Mar 5: daily entry deleted.');
    });

    test('limits notification body length', () {
      final summary = DailyLogNotificationSummary.forChange(
        dateKey: '2026-03-05',
        previousData: null,
        nextLog: DailyLog(
          dateKey: '2026-03-05',
          isPeriodDay: true,
          mood: null,
          symptoms: List.filled(20, 'Very long symptom description'),
          notes: '',
        ),
      );

      expect(summary.body.length, lessThanOrEqualTo(240));
    });
  });

  group('CoupleDetails', () {
    test('reports pairing state and the other member', () {
      const details = CoupleDetails(
        members: ['tracker-uid', 'partner-uid'],
        roles: {'tracker-uid': 'tracker', 'partner-uid': 'partner'},
        displayNames: {'tracker-uid': 'Alex', 'partner-uid': 'Sam'},
        inviteCode: null,
        createdAt: null,
        pairedAt: null,
      );

      expect(details.isPaired, isTrue);
      expect(details.partnerOf('tracker-uid'), 'partner-uid');
      expect(details.partnerOf('partner-uid'), 'tracker-uid');
      expect(details.partnerOf('unknown'), 'tracker-uid');
    });

    test('reports a waiting invitation', () {
      const details = CoupleDetails(
        members: ['tracker-uid'],
        roles: {'tracker-uid': 'tracker'},
        displayNames: {'tracker-uid': 'Alex'},
        inviteCode: 'ABCD2345',
        createdAt: null,
        pairedAt: null,
      );

      expect(details.isPaired, isFalse);
      expect(details.partnerOf('tracker-uid'), isNull);
      expect(details.inviteCode, 'ABCD2345');
    });
  });
}
