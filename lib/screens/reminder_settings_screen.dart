import 'dart:async';

import 'package:flutter/material.dart';

import '../services/local_reminder_service.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  final _service = LocalReminderService();
  ReminderPreferences? _preferences;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (LocalReminderService.isSupported) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.initialize();
      final preferences = await _service.readPreferences();
      if (mounted) setState(() => _preferences = preferences);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load reminders: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    final current = _preferences;
    if (current == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (enabled) {
        final granted = await _service.enableAt(current.hour, current.minute);
        if (!granted) {
          _showMessage(
            'Allow notifications in Android settings to receive reminders.',
          );
          return;
        }
      } else {
        await _service.disable();
      }
      if (mounted) {
        setState(
          () => _preferences = ReminderPreferences(
            enabled: enabled,
            hour: current.hour,
            minute: current.minute,
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not update reminder: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseTime() async {
    final current = _preferences;
    if (current == null) return;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (selected == null || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (current.enabled) {
        final granted = await _service.enableAt(selected.hour, selected.minute);
        if (!granted) {
          _showMessage(
            'Allow notifications in Android settings to receive reminders.',
          );
          return;
        }
      } else {
        await _service.saveTime(selected.hour, selected.minute);
      }
      if (mounted) {
        setState(
          () => _preferences = ReminderPreferences(
            enabled: current.enabled,
            hour: selected.hour,
            minute: selected.minute,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save reminder time: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Daily reminders')),
      body: !LocalReminderService.isSupported
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'On-device reminders are available in the Android app. '
                  'Browser reminders cannot be guaranteed when the app is closed.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    title: const Text('Daily check-in reminder'),
                    subtitle: const Text(
                      'A private notification on this device. Nothing is sent to your partner.',
                    ),
                    value: _preferences!.enabled,
                    onChanged: _saving ? null : _setEnabled,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('Reminder time'),
                    subtitle: Text(
                      TimeOfDay(
                        hour: _preferences!.hour,
                        minute: _preferences!.minute,
                      ).format(context),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !_saving,
                    onTap: _saving ? null : _chooseTime,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The reminder is stored locally and scheduled by Android. '
                  'The default time is 8:00 PM; you can change it anytime.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}
