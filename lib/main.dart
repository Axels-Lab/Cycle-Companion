import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/cycle_home_screen.dart';
import 'screens/pairing_screen.dart';
import 'services/app_theme_controller.dart';
import 'services/couple_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await appThemeController.load();
  runApp(const CycleCompanionApp());
}

class CycleCompanionApp extends StatelessWidget {
  const CycleCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appThemeController,
      builder: (context, _) => MaterialApp(
        title: 'Cycle Companion',
        themeMode: appThemeController.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFB04662),
            surface: const Color(0xFFFFFAFA),
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFB04662),
            brightness: Brightness.dark,
            surface: const Color(0xFF171316),
          ),
          useMaterial3: true,
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data == null) return const AuthScreen();

        return FutureBuilder<CoupleMembership?>(
          future: CoupleService().getMembership(snap.data!.uid),
          builder: (context, coupleSnap) {
            if (coupleSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (coupleSnap.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load your account: ${coupleSnap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            final membership = coupleSnap.data;
            if (membership == null) return const PairingScreen();
            return CycleHomeScreen(
              coupleId: membership.coupleId,
              isTracker: membership.isTracker,
            );
          },
        );
      },
    );
  }
}
