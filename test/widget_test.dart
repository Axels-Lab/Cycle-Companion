import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/daily_log.dart';
import 'package:flutter_application_1/services/couple_service.dart';

void main() {
  group('DailyLog', () {
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
