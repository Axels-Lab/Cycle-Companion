import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_theme_controller.dart';
import '../services/couple_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.coupleId, super.key});

  final String coupleId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = CoupleService();
  final _nameController = TextEditingController();
  bool _nameInitialized = false;
  bool _savingName = false;
  bool _savingTheme = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    setState(() => _savingName = true);
    try {
      await _service.updateDisplayName(
        coupleId: widget.coupleId,
        displayName: _nameController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Display name updated.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update your name: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _copyInvite(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Invite code copied.')));
  }

  Future<void> _setThemeMode(ThemeMode? mode) async {
    if (mode == null || mode == appThemeController.themeMode) return;
    setState(() => _savingTheme = true);
    try {
      await appThemeController.setThemeMode(mode);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save appearance setting: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  String _roleLabel(String? role) => switch (role) {
    'tracker' => 'Cycle tracker',
    'partner' => 'Support partner',
    _ => 'Not set',
  };

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Account & Settings')),
      body: StreamBuilder<CoupleDetails>(
        stream: _service.watchCoupleDetails(widget.coupleId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load your pairing details: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final details = snapshot.data!;
          final uid = user?.uid;
          final ownName = uid == null ? null : details.displayNames[uid];
          if (!_nameInitialized) {
            _nameController.text = ownName ?? '';
            _nameInitialized = true;
          }
          final partnerUid = uid == null ? null : details.partnerOf(uid);
          final partnerName = partnerUid == null
              ? null
              : details.displayNames[partnerUid];
          final partnerRole = partnerUid == null
              ? null
              : details.roles[partnerUid];
          final createdDate = details.createdAt;
          final pairedDate = details.pairedAt;
          final dateFormat = MaterialLocalizations.of(context);
          final theme = Theme.of(context);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your account', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 14),
                      _ProfileDetail(
                        icon: Icons.email_outlined,
                        title: 'Email',
                        value: user?.email ?? 'Email not available',
                      ),
                      const SizedBox(height: 12),
                      _ProfileDetail(
                        icon: Icons.badge_outlined,
                        title: 'Your role',
                        value: _roleLabel(
                          uid == null ? null : details.roles[uid],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        enabled: !_savingName,
                        maxLength: 40,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          helperText: 'Visible to your paired partner.',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed:
                              _savingName || _nameController.text.trim().isEmpty
                              ? null
                              : _saveName,
                          child: _savingName
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save name'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Appearance', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        'Choose the theme',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ThemeMode>(
                        initialValue: appThemeController.themeMode,
                        decoration: const InputDecoration(
                          labelText: 'Theme',
                          prefixIcon: Icon(Icons.palette_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('System default'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text('Light'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Dark'),
                          ),
                        ],
                        onChanged: _savingTheme ? null : _setThemeMode,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Partner connection',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      _ConnectionStatus(isPaired: details.isPaired),
                      const SizedBox(height: 14),
                      if (details.isPaired) ...[
                        _ProfileDetail(
                          icon: Icons.favorite_outline,
                          title: 'Partner',
                          value: (partnerName == null || partnerName.isEmpty)
                              ? 'Name not set'
                              : partnerName,
                        ),
                        const SizedBox(height: 12),
                        _ProfileDetail(
                          icon: Icons.badge_outlined,
                          title: 'Their role',
                          value: _roleLabel(partnerRole),
                        ),
                        const SizedBox(height: 12),
                        _ProfileDetail(
                          icon: Icons.calendar_month_outlined,
                          title: 'Paired on',
                          value: pairedDate == null
                              ? 'Date not available'
                              : dateFormat.formatMediumDate(pairedDate),
                        ),
                      ] else ...[
                        _ProfileDetail(
                          icon: Icons.person_outline,
                          title: 'Invite created',
                          value: createdDate == null
                              ? 'Date not available'
                              : dateFormat.formatMediumDate(createdDate),
                        ),
                        const SizedBox(height: 14),
                        if (details.inviteCode case final code?) ...[
                          Text(
                            'Your partner can enter this code to connect:',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: SelectableText(
                              code,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _copyInvite(code),
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy invite code'),
                            ),
                          ),
                        ] else
                          Text(
                            'This invite is no longer active. Create a new '
                            'pairing from the sign-in screen if needed.',
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Cycle and mood entries are shared with the paired account. '
                'Your email is not shown to your partner.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.isPaired});

  final bool isPaired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isPaired
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(isPaired ? Icons.favorite : Icons.hourglass_top, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isPaired ? 'Connected' : 'Waiting for your partner',
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
