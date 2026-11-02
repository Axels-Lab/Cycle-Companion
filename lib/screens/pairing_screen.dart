import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/couple_service.dart';
import '../main.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _service = CoupleService();
  final _codeCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.displayName ?? '',
  );
  String? _inviteCode;
  String? _error;
  bool _busy = false;

  String _role = 'tracker';

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invite = await _service.createCouple(
        role: _role,
        displayName: _displayNameCtrl.text,
      );
      if (mounted) setState(() => _inviteCode = invite.code);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.joinCouple(
        code: _codeCtrl.text,
        displayName: _displayNameCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continue() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link your accounts')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _inviteCode == null
                ? 'Pair with your partner'
                : 'Your invite is ready',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Pairing shares cycle and mood entries between both accounts. '
            'Only pair with someone you want to share this information with. '
            'Your chosen name is visible to your paired partner.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_inviteCode != null) ...[
            const SizedBox(height: 24),
            const Text('Share this code with your partner:'),
            const SizedBox(height: 8),
            SelectableText(
              _inviteCode!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _inviteCode!));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite code copied.')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy invite code'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _continue,
              child: const Text('Continue to Cycle Companion'),
            ),
          ] else ...[
            const SizedBox(height: 24),
            TextField(
              controller: _displayNameCtrl,
              enabled: !_busy,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Your display name',
                hintText: 'How should your partner see you?',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text('If you create the invite, choose your role:'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'tracker',
                  label: Text('I will track'),
                  icon: Icon(Icons.edit_note),
                ),
                ButtonSegment(
                  value: 'partner',
                  label: Text('I will view'),
                  icon: Icon(Icons.favorite_outline),
                ),
              ],
              selected: {_role},
              onSelectionChanged: _busy
                  ? null
                  : (selection) => setState(() => _role = selection.first),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy || _displayNameCtrl.text.trim().isEmpty
                  ? null
                  : _create,
              child: const Text('Create an invite'),
            ),
            const Divider(height: 40),
            Text(
              'When you join, your role is set to the other role in the invite.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Enter your partner’s invite code',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed:
                  _busy ||
                      _displayNameCtrl.text.trim().isEmpty ||
                      _codeCtrl.text.trim().length != 8
                  ? null
                  : _join,
              child: const Text('Join and pair accounts'),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
