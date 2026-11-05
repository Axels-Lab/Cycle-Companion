import 'package:cloud_firestore/cloud_firestore.dart';

class DailyLog {
  const DailyLog({
    required this.dateKey,
    required this.isPeriodDay,
    required this.mood,
    required this.symptoms,
    required this.notes,
    this.moodTags = const [],
    this.flow,
    this.painLevel,
    this.updatedAt,
  });

  static const moods = <String, String>{
    'great': 'Great',
    'good': 'Good',
    'okay': 'Okay',
    'low': 'Low',
    'rough': 'Rough',
    'calm': 'Calm',
    'content': 'Content',
    'hopeful': 'Hopeful',
    'affectionate': 'Affectionate',
    'energized': 'Energized',
    'focused': 'Focused',
    'playful': 'Playful',
    'tired': 'Tired',
    'low_energy': 'Low energy',
    'sad': 'Sad',
    'anxious': 'Anxious',
    'worried': 'Worried',
    'irritable': 'Irritable',
    'frustrated': 'Frustrated',
    'cranky': 'Cranky',
    'grumpy': 'Grumpy',
    'overwhelmed': 'Overwhelmed',
    'sensitive': 'Sensitive',
    'lonely': 'Lonely',
    'restless': 'Restless',
    'numb': 'Numb',
    'mixed': 'Mixed / unsure',
    'dont_talk_to_me': "Don't talk to me",
    'leave_me_alone': 'Leave me alone',
    'need_space': 'I need some space',
    'not_ready_to_talk': 'Not ready to talk',
    'check_in_later': 'Please check in later',
    'want_company': 'I want company',
    'need_comfort': 'I need comfort',
    'need_reassurance': 'I need reassurance',
    'need_support': 'I need support',
    'overstimulated': 'Overstimulated',
    'socially_drained': 'Socially drained',
  };

  static const symptomOptions = <String>[
    'Cramps',
    'Headache',
    'Fatigue',
    'Bloating',
    'Tenderness',
    'Backache',
    'Nausea',
    'Other',
  ];

  static const flowOptions = <String, String>{
    'spotting': 'Spotting',
    'light': 'Light',
    'medium': 'Medium',
    'heavy': 'Heavy',
  };

  final String dateKey;
  final bool isPeriodDay;
  final String? mood;
  final List<String> moodTags;
  final List<String> symptoms;
  final String notes;
  final String? flow;
  final int? painLevel;
  final DateTime? updatedAt;

  DateTime get date => DateTime.parse(dateKey);

  List<String> get selectedMoods =>
      moodTags.isNotEmpty ? moodTags : (mood == null ? const [] : [mood!]);

  bool get isEmpty =>
      !isPeriodDay &&
      selectedMoods.isEmpty &&
      symptoms.isEmpty &&
      notes.trim().isEmpty &&
      flow == null &&
      painLevel == null;

  factory DailyLog.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) => DailyLog.fromData(document.id, document.data());

  factory DailyLog.fromData(String dateKey, Map<String, dynamic> data) {
    final legacyMood = data['mood'] as String?;
    return DailyLog(
      dateKey: dateKey,
      isPeriodDay: data['isPeriodDay'] as bool,
      mood: legacyMood,
      moodTags: List<String>.from(
        data['moodTags'] as List<dynamic>? ??
            (legacyMood == null ? const [] : [legacyMood]),
      ),
      symptoms: List<String>.from(
        data['symptoms'] as List<dynamic>? ?? const [],
      ),
      notes: data['notes'] as String,
      flow: data['flow'] as String?,
      painLevel: data['painLevel'] as int?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, Object?> toFirestore() => {
    'dateKey': dateKey,
    'isPeriodDay': isPeriodDay,
    'mood': selectedMoods.isEmpty ? null : selectedMoods.first,
    'moodTags': selectedMoods,
    'symptoms': symptoms,
    'notes': notes.trim(),
    'flow': flow,
    'painLevel': painLevel,
  };

  static String keyFor(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class DailyLogRevision {
  const DailyLogRevision({required this.log});

  final DailyLog log;

  factory DailyLogRevision.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return DailyLogRevision(
      log: DailyLog.fromData(data['dateKey'] as String, data),
    );
  }
}

class PeriodEpisode {
  const PeriodEpisode({
    required this.startDate,
    required this.lastLoggedDate,
    required this.loggedDays,
  });

  final DateTime startDate;
  final DateTime lastLoggedDate;
  final int loggedDays;
}

class CycleHistory {
  const CycleHistory._(this.periods);

  final List<PeriodEpisode> periods;

  int? get averageCycleLengthDays {
    if (periods.length < 2) return null;
    final lengths = <int>[
      for (var index = 1; index < periods.length; index++)
        _daysBetween(periods[index - 1].startDate, periods[index].startDate),
    ];
    return (lengths.reduce((a, b) => a + b) / lengths.length).round();
  }

  static CycleHistory fromLogs(Iterable<DailyLog> logs) {
    final periodDates =
        logs
            .where((log) => log.isPeriodDay)
            .map((log) => log.dateKey)
            .toSet()
            .toList()
          ..sort();
    if (periodDates.isEmpty) return const CycleHistory._([]);

    final periods = <PeriodEpisode>[];
    var startDate = DateTime.parse(periodDates.first);
    var lastLoggedDate = startDate;
    var loggedDays = 1;

    for (final dateKey in periodDates.skip(1)) {
      final date = DateTime.parse(dateKey);
      if (_daysBetween(lastLoggedDate, date) == 1) {
        loggedDays++;
      } else {
        periods.add(
          PeriodEpisode(
            startDate: startDate,
            lastLoggedDate: lastLoggedDate,
            loggedDays: loggedDays,
          ),
        );
        startDate = date;
        loggedDays = 1;
      }
      lastLoggedDate = date;
    }

    periods.add(
      PeriodEpisode(
        startDate: startDate,
        lastLoggedDate: lastLoggedDate,
        loggedDays: loggedDays,
      ),
    );
    return CycleHistory._(List.unmodifiable(periods));
  }

  static int _daysBetween(DateTime first, DateTime second) {
    final firstUtc = DateTime.utc(first.year, first.month, first.day);
    final secondUtc = DateTime.utc(second.year, second.month, second.day);
    return secondUtc.difference(firstUtc).inDays;
  }
}
