import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/daily_log.dart';
import '../services/couple_service.dart';
import '../services/daily_log_service.dart';
import 'profile_screen.dart';
import 'reminder_settings_screen.dart';

class CycleHomeScreen extends StatefulWidget {
  const CycleHomeScreen({
    required this.coupleId,
    required this.isTracker,
    super.key,
  });

  final String coupleId;
  final bool isTracker;

  @override
  State<CycleHomeScreen> createState() => _CycleHomeScreenState();
}

class _CycleHomeScreenState extends State<CycleHomeScreen> {
  final _service = DailyLogService();
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  Future<void> _openEditor(DailyLog? log) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DailyLogEditor(
        date: _selectedDay,
        initialLog: log,
        onSave: (entry) => _service.saveLog(widget.coupleId, entry),
      ),
    );
  }

  Future<void> _openHistory(String dateKey) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EntryHistorySheet(
        dateKey: dateKey,
        revisions: _service.watchRevisions(widget.coupleId, dateKey),
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not sign out.')),
      );
    }
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(coupleId: widget.coupleId),
      ),
    );
  }

  Future<void> _openReminders() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReminderSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle Companion'),
        actions: [
          if (widget.isTracker)
            IconButton(
              tooltip: 'Daily reminders',
              onPressed: _openReminders,
              icon: const Icon(Icons.notifications_outlined),
            ),
          IconButton(
            tooltip: 'Account and settings',
            onPressed: _openProfile,
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<List<DailyLog>>(
        stream: _service.watchLogs(widget.coupleId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorMessage(
              message: 'Could not load shared entries: ${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data!;
          final cycleHistory = CycleHistory.fromLogs(logs);
          final logsByDate = {for (final log in logs) log.dateKey: log};
          final selectedLog = logsByDate[DailyLog.keyFor(_selectedDay)];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _WelcomeCard(isTracker: widget.isTracker),
              const SizedBox(height: 16),
              _LiveSharingBanner(coupleId: widget.coupleId),
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: TableCalendar<DailyLog>(
                    firstDay: DateTime(2020),
                    lastDay: DateTime(2100),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) =>
                        DailyLog.keyFor(day) == DailyLog.keyFor(_selectedDay),
                    eventLoader: (day) {
                      final log = logsByDate[DailyLog.keyFor(day)];
                      return log == null ? const [] : [log];
                    },
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    onPageChanged: (focusedDay) =>
                        setState(() => _focusedDay = focusedDay),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                    calendarStyle: CalendarStyle(
                      markerDecoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _SelectedDayCard(
                date: _selectedDay,
                log: selectedLog,
                isTracker: widget.isTracker,
                onEdit: () => _openEditor(selectedLog),
                onHistory: () => _openHistory(DailyLog.keyFor(_selectedDay)),
                hasHistory: selectedLog == null
                    ? null
                    : _service.watchHasRevisions(
                        widget.coupleId,
                        DailyLog.keyFor(_selectedDay),
                      ),
              ),
              const SizedBox(height: 16),
              _CycleHistoryCard(history: cycleHistory),
              const SizedBox(height: 24),
              Text(
                'Recent entries',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (logs.isEmpty)
                const _EmptyEntries()
              else
                ...logs
                    .take(7)
                    .map(
                      (log) => _RecentEntryTile(
                        log: log,
                        onTap: () => setState(() {
                          _selectedDay = log.date;
                          _focusedDay = log.date;
                        }),
                      ),
                    ),
              if (logs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${logs.where((log) => log.isPeriodDay).length} period days logged',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.isTracker});

  final bool isTracker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isTracker ? 'Your cycle, gently tracked.' : 'Here for each other.',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isTracker
              ? 'Add a daily note whenever it feels right.'
              : 'See your partner’s updates as they happen.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LiveSharingBanner extends StatelessWidget {
  const _LiveSharingBanner({required this.coupleId});

  final String coupleId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<CoupleDetails>(
      stream: CoupleService().watchCoupleDetails(coupleId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SharingStatusCard(
            icon: Icons.error_outline,
            text: 'Could not load your partner connection.',
            color: theme.colorScheme.errorContainer,
            foreground: theme.colorScheme.onErrorContainer,
          );
        }
        if (!snapshot.hasData) {
          return const _SharingStatusCard(
            icon: Icons.sync,
            text: 'Checking your partner connection…',
          );
        }

        final details = snapshot.data!;
        if (details.isPaired) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          final partnerUid = uid == null ? null : details.partnerOf(uid);
          final partnerName = partnerUid == null
              ? null
              : details.displayNames[partnerUid];
          return _SharingStatusCard(
            icon: Icons.sync,
            text: partnerName == null || partnerName.isEmpty
                ? 'Connected. Shared entries update live.'
                : 'Connected with $partnerName. Entries update live.',
          );
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.hourglass_top,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Waiting for your partner to join',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (details.inviteCode case final code?) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        code,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy invite code',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite code copied.')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
                Text(
                  'Your invite is also saved in Account & Settings.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SharingStatusCard extends StatelessWidget {
  const _SharingStatusCard({
    required this.icon,
    required this.text,
    this.color,
    this.foreground,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = color ?? theme.colorScheme.secondaryContainer;
    final contentColor = foreground ?? theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: contentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: contentColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedDayCard extends StatelessWidget {
  const _SelectedDayCard({
    required this.date,
    required this.log,
    required this.isTracker,
    required this.onEdit,
    required this.onHistory,
    required this.hasHistory,
  });

  final DateTime date;
  final DailyLog? log;
  final bool isTracker;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final Stream<bool>? hasHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedDate = MaterialLocalizations.of(context)
        .formatMediumDate(date);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formattedDate, style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            if (log == null)
              Text(
                'No entry for this day yet.',
                style: theme.textTheme.bodyMedium,
              )
            else
              _LogDetails(log: log!),
            if (log != null && hasHistory != null)
              StreamBuilder<bool>(
                stream: hasHistory,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Could not check edit history: ${snapshot.error}',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    );
                  }
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onHistory,
                      icon: const Icon(Icons.history),
                      label: const Text('View edit history'),
                    ),
                  );
                },
              ),
            if (isTracker) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_note),
                  label: Text(log == null ? 'Add an entry' : 'Edit entry'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CycleHistoryCard extends StatelessWidget {
  const _CycleHistoryCard({required this.history});

  final CycleHistory history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final periods = history.periods.reversed.take(5).toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cycle history', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            if (history.averageCycleLengthDays case final average?)
              Text('Average logged cycle: $average days')
            else
              const Text('Log at least two period starts to see cycle length.'),
            if (periods.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Period days you log will appear here.'),
              )
            else ...[
              const SizedBox(height: 8),
              for (final period in periods)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.water_drop_outlined, size: 19),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${MaterialLocalizations.of(context).formatShortDate(period.startDate)}'
                          ' – ${MaterialLocalizations.of(context).formatShortDate(period.lastLoggedDate)}'
                          ' · ${period.loggedDays} ${period.loggedDays == 1 ? 'day' : 'days'} logged',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              'History is based on consecutive dates marked as period; it does not predict future cycles.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryHistorySheet extends StatelessWidget {
  const _EntryHistorySheet({required this.dateKey, required this.revisions});

  final String dateKey;
  final Stream<List<DailyLogRevision>> revisions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(DateTime.parse(dateKey));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit history', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(date),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<List<DailyLogRevision>>(
                  stream: revisions,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Could not load edit history: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final entries = snapshot.data!;
                    if (entries.isEmpty) {
                      return const Center(
                        child: Text('There are no earlier saved versions.'),
                      );
                    }
                    return ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final revision = entries[index];
                        final entry = revision.log;
                        final savedAt = entry.updatedAt;
                        final entryTimestamp = savedAt == null
                            ? 'Entry time unavailable'
                            : '${MaterialLocalizations.of(context).formatMediumDate(entry.date)} · '
                                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(savedAt))}';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entryTimestamp,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              _LogDetails(log: entry),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogDetails extends StatelessWidget {
  const _LogDetails({required this.log});

  final DailyLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (log.isPeriodDay)
          const _DetailLine(
            icon: Icons.water_drop_outlined,
            label: 'Period day',
          ),
        if (log.flow != null)
          _DetailLine(
            icon: Icons.opacity_outlined,
            label: 'Flow: ${DailyLog.flowOptions[log.flow] ?? log.flow}',
          ),
        if (log.painLevel != null)
          _DetailLine(
            icon: Icons.healing_outlined,
            label: 'Pain: ${log.painLevel}/10',
          ),
        if (log.selectedMoods.isNotEmpty)
          _DetailLine(
            icon: Icons.mood_outlined,
            label:
                'Mood: ${log.selectedMoods.map((mood) => DailyLog.moods[mood] ?? mood).join(' · ')}',
          ),
        if (log.symptoms.isNotEmpty)
          _DetailLine(
            icon: Icons.healing_outlined,
            label: log.symptoms.join(' · '),
          ),
        if (log.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(log.notes, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _RecentEntryTile extends StatelessWidget {
  const _RecentEntryTile({required this.log, required this.onTap});

  final DailyLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formattedDate = MaterialLocalizations.of(context)
        .formatShortDate(log.date);
    final savedAt = log.updatedAt;
    final timestamp = savedAt == null
        ? null
        : MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(savedAt));
    final details = <String>[
      if (log.isPeriodDay) 'Period',
      if (log.flow != null) DailyLog.flowOptions[log.flow] ?? log.flow!,
      if (log.painLevel != null) 'Pain ${log.painLevel}/10',
      if (log.selectedMoods.isNotEmpty)
        log.selectedMoods
            .map((mood) => DailyLog.moods[mood] ?? mood)
            .join(', '),
      ...log.symptoms,
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          log.isPeriodDay ? Icons.water_drop_outlined : Icons.event_note,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        timestamp == null ? formattedDate : '$formattedDate at $timestamp',
      ),
      subtitle: Text(
        [
          if (details.isNotEmpty) details.join(' · '),
          if (log.notes.isNotEmpty) log.notes,
        ].join(' · '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

class _EmptyEntries extends StatelessWidget {
  const _EmptyEntries();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        'Cycle and mood entries will appear here.',
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class DailyLogEditor extends StatefulWidget {
  const DailyLogEditor({
    required this.date,
    required this.initialLog,
    required this.onSave,
    super.key,
  });

  final DateTime date;
  final DailyLog? initialLog;
  final Future<void> Function(DailyLog log) onSave;

  @override
  State<DailyLogEditor> createState() => _DailyLogEditorState();
}

class _DailyLogEditorState extends State<DailyLogEditor> {
  late bool _isPeriodDay;
  late Set<String> _moods;
  late Set<String> _symptoms;
  late String? _flow;
  late int? _painLevel;
  late final TextEditingController _notes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _isPeriodDay = widget.initialLog?.isPeriodDay ?? false;
    _moods = {...?widget.initialLog?.selectedMoods};
    _symptoms = {...?widget.initialLog?.symptoms};
    _flow = widget.initialLog?.flow;
    _painLevel = widget.initialLog?.painLevel;
    _notes = TextEditingController(text: widget.initialLog?.notes ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final entry = DailyLog(
      dateKey: DailyLog.keyFor(widget.date),
      isPeriodDay: _isPeriodDay,
      mood: _moods.isEmpty ? null : (_moods.toList()..sort()).first,
      moodTags: _moods.toList()..sort(),
      symptoms: _symptoms.toList()..sort(),
      notes: _notes.text.trim(),
      flow: _flow,
      painLevel: _painLevel,
    );
    try {
      await widget.onSave(entry);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save this entry: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseMoods() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MoodPickerSheet(selectedMoods: _moods),
    );
    if (selected == null || !mounted) return;
    setState(() => _moods = selected);
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = MaterialLocalizations.of(context)
        .formatMediumDate(widget.date);
    final noContent =
        !_isPeriodDay &&
        _moods.isEmpty &&
        _symptoms.isEmpty &&
        _notes.text.trim().isEmpty &&
        _flow == null &&
        _painLevel == null;
    final canRemove = widget.initialLog != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Daily check-in',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(formattedDate),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Period day'),
                value: _isPeriodDay,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _isPeriodDay = value;
                        if (!value) _flow = null;
                      }),
              ),
              if (_isPeriodDay) ...[
                const SizedBox(height: 4),
                Text(
                  'Flow (optional)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: DailyLog.flowOptions.entries.map((entry) {
                    return ChoiceChip(
                      label: Text(entry.value),
                      selected: _flow == entry.key,
                      onSelected: _saving
                          ? null
                          : (selected) => setState(
                              () => _flow = selected ? entry.key : null,
                            ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Track pain level'),
                value: _painLevel != null,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _painLevel = value ? 1 : null),
              ),
              if (_painLevel != null) ...[
                Text(
                  'Pain intensity: $_painLevel/10',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Slider(
                  value: _painLevel!.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$_painLevel',
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _painLevel = value.round()),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'How are you feeling? Choose any that fit.',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _chooseMoods,
                icon: const Icon(Icons.mood_outlined),
                label: Text(
                  _moods.isEmpty
                      ? 'Choose moods'
                      : 'Edit moods (${_moods.length})',
                ),
              ),
              if (_moods.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  (_moods.toList()..sort())
                      .map((mood) => DailyLog.moods[mood] ?? mood)
                      .join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Feelings can overlap and aren’t necessarily caused by your cycle.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Symptoms or feelings',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: DailyLog.symptomOptions.map((symptom) {
                  return FilterChip(
                    label: Text(symptom),
                    selected: _symptoms.contains(symptom),
                    onSelected: _saving
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              _symptoms.add(symptom);
                            } else {
                              _symptoms.remove(symptom);
                            }
                          }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                enabled: !_saving,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Anything else?',
                  hintText: 'Add a note about how today feels',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              Text(
                'This entry is shared with your paired partner.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving || (noContent && !canRemove)
                        ? null
                        : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(noContent ? 'Remove entry' : 'Save entry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoodPickerSheet extends StatefulWidget {
  const _MoodPickerSheet({required this.selectedMoods});

  final Set<String> selectedMoods;

  @override
  State<_MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<_MoodPickerSheet> {
  static const _groups = <String, List<String>>{
    'Positive & steady': [
      'great',
      'good',
      'calm',
      'content',
      'hopeful',
      'affectionate',
      'energized',
      'focused',
      'playful',
    ],
    'Low energy & down': ['tired', 'low_energy', 'sad', 'lonely', 'numb'],
    'Tense & unsettled': [
      'anxious',
      'worried',
      'irritable',
      'frustrated',
      'overwhelmed',
      'sensitive',
      'restless',
      'low',
      'rough',
    ],
    'Neutral & mixed': ['okay', 'mixed'],
  };

  late final Set<String> _selected = {...widget.selectedMoods};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose moods', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Select all that feel right. You can change these anytime.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final group in _groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            group.key,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final mood in group.value)
                              FilterChip(
                                label: Text(DailyLog.moods[mood]!),
                                selected: _selected.contains(mood),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selected.add(mood);
                                    } else {
                                      _selected.remove(mood);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(Set<String>.of(_selected)),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
