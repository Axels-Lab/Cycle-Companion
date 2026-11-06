import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateService {
  static const _releaseApi =
      'https://api.github.com/repos/Axels-Lab/Cycle-Companion/releases/latest';
  static const _lastCheckKey = 'last_github_update_check';
  static const _checkInterval = Duration(hours: 24);

  Future<void> checkForUpdate(
    BuildContext context, {
    bool manual = false,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      final preferences = await SharedPreferences.getInstance();
      final lastCheck = preferences.getInt(_lastCheckKey);

      if (!manual && lastCheck != null) {
        final elapsed = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(lastCheck),
        );
        if (elapsed < _checkInterval) return;
      }

      final response = await http
          .get(
            Uri.parse(_releaseApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'Cycle-Companion-Android',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('GitHub returned HTTP ${response.statusCode}.');
      }

      final release = jsonDecode(response.body) as Map<String, dynamic>;
      if (release['draft'] == true || release['prerelease'] == true) return;

      final tag = release['tag_name'] as String?;
      if (tag == null || tag.isEmpty) {
        throw Exception('The latest release does not have a version tag.');
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final latestVersion = tag.replaceFirst(RegExp(r'^[vV]'), '');

      await preferences.setInt(
        _lastCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      if (_compareVersions(latestVersion, packageInfo.version) <= 0) {
        if (manual && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You are using the latest version (${packageInfo.version}).',
              ),
            ),
          );
        }
        return;
      }

      final assets = release['assets'] as List<dynamic>? ?? [];
      final apkAsset = assets.whereType<Map<String, dynamic>>().firstWhere(
        (asset) => asset['name'] == 'app-release.apk',
        orElse: () => <String, dynamic>{},
      );
      final downloadUrl = apkAsset['browser_download_url'] as String?;

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('The latest release does not contain app-release.apk.');
      }

      if (!context.mounted) return;

      final releaseNotes = (release['body'] as String?)?.trim() ?? '';
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update available'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Cycle Companion $latestVersion is available. '
                    'You currently have ${packageInfo.version}.',
                  ),
                  if (releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'What’s new',
                      style: Theme.of(dialogContext).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(releaseNotes),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Android may ask you to allow installs from Cycle Companion '
                    'the first time.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Update'),
            ),
          ],
        ),
      );

      if (shouldUpdate == true && context.mounted) {
        await _downloadAndInstall(context, Uri.parse(downloadUrl));
      }
    } catch (error, stackTrace) {
      debugPrint('GitHub update check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check for updates: $error')),
        );
      }
    }
  }

  int _compareVersions(String first, String second) {
    List<int> parts(String value) {
      final clean = value.replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
      return clean.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    }

    final a = parts(first);
    final b = parts(second);
    final length = a.length > b.length ? a.length : b.length;

    for (var i = 0; i < length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }

  Future<void> _downloadAndInstall(BuildContext context, Uri uri) async {
    final progress = ValueNotifier<double?>(null);
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Downloading update'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value == null
                    ? 'Connecting to GitHub…'
                    : '${(value * 100).toStringAsFixed(0)}%',
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: value),
            ],
          ),
        ),
      ),
    );

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 2));

      if (response.statusCode != 200) {
        throw Exception('APK download failed (HTTP ${response.statusCode}).');
      }

      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/cycle-companion-update.apk');
      final sink = apkFile.openWrite();
      var received = 0;
      final total = response.contentLength;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            progress.value = received / total;
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await dialogFuture;
      progress.dispose();

      final result = await OpenFilex.open(apkFile.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open APK installer: ${result.message}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await dialogFuture;
      progress.dispose();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not download update: $error')),
        );
      }
    } finally {
      client.close();
    }
  }
}
