import '../models/daily_log.dart';

class DailyLogNotificationSummary {
  const DailyLogNotificationSummary({required this.title, required this.body});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final String title;
  final String body;

  factory DailyLogNotificationSummary.forChange({
    required String dateKey,
    required Map<String, dynamic>? previousData,
    required DailyLog? nextLog,
  }) {
    final date = DateTime.parse(dateKey);
    final dateLabel = '${_months[date.month - 1]} ${date.day}';
    if (nextLog == null) {
      return DailyLogNotificationSummary(
        title: 'Daily entry deleted',
        body: '$dateLabel: daily entry deleted.',
      );
    }

    final previous = previousData == null
        ? null
        : DailyLog.fromData(dateKey, previousData);
    final changes = <String>[];

    if (previous?.isPeriodDay != nextLog.isPeriodDay) {
      changes.add(
        nextLog.isPeriodDay ? 'period day logged' : 'period day removed',
      );
    }

    final previousMoods = previous?.selectedMoods.toSet() ?? <String>{};
    final nextMoods = nextLog.selectedMoods.toSet();
    if (!previousMoods.containsAll(nextMoods) ||
        !nextMoods.containsAll(previousMoods)) {
      changes.add(
        nextMoods.isEmpty
            ? 'Mood cleared'
            : 'Mood: ${_moodNames(nextLog.selectedMoods)}',
      );
    }

    final previousSymptoms = previous?.symptoms.toSet() ?? <String>{};
    final nextSymptoms = nextLog.symptoms.toSet();
    final addedSymptoms = nextSymptoms.difference(previousSymptoms).toList()
      ..sort();
    final removedSymptoms = previousSymptoms.difference(nextSymptoms).toList()
      ..sort();
    if (addedSymptoms.isNotEmpty) {
      changes.add('symptoms added: ${addedSymptoms.join(', ')}');
    }
    if (removedSymptoms.isNotEmpty) {
      changes.add('symptoms removed: ${removedSymptoms.join(', ')}');
    }

    if (previous?.flow != nextLog.flow) {
      changes.add(
        nextLog.flow == null
            ? 'Flow cleared'
            : 'Flow: ${DailyLog.flowOptions[nextLog.flow] ?? nextLog.flow}',
      );
    }
    if (previous?.painLevel != nextLog.painLevel) {
      changes.add(
        nextLog.painLevel == null
            ? 'Pain level cleared'
            : 'Pain level: ${nextLog.painLevel}/10',
      );
    }
    if ((previous?.notes.trim() ?? '') != nextLog.notes.trim()) {
      changes.add('Note updated');
    }

    final details = changes.isEmpty
        ? 'daily entry updated'
        : changes.join('; ');
    final body = '$dateLabel: $details.';
    return DailyLogNotificationSummary(
      title: previous == null ? 'Daily entry added' : 'Daily entry updated',
      body: body.length <= 240 ? body : '${body.substring(0, 237)}...',
    );
  }

  static String _moodNames(List<String> moods) =>
      moods.map((mood) => DailyLog.moods[mood] ?? mood).join(', ');
}
