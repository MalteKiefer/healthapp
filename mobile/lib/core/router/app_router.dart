import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../../screens/login/login_screen.dart';
import '../../screens/shell/app_shell.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/vitals/vitals_screen.dart';
import '../../screens/labs/labs_screen.dart';
import '../../screens/medications/medications_screen.dart';
import '../../screens/more/more_screen.dart';
import '../../screens/allergies/allergies_screen.dart';
import '../../screens/appointments/appointments_screen.dart';
import '../../screens/diagnoses/diagnoses_screen.dart';
import '../../screens/vaccinations/vaccinations_screen.dart';
import '../../screens/contacts/contacts_screen.dart';
import '../../screens/diary/diary_screen.dart';
import '../../screens/symptoms/symptoms_screen.dart';
import '../../screens/tasks/tasks_screen.dart';
import '../../screens/documents/documents_screen.dart';
import '../../screens/about/about_screen.dart';
import '../../screens/settings/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) async {
    final isAuthenticated = await AuthService.loadCredentials() != null;
    final location = state.uri.toString();
    final isOnLogin = location == '/login';
    final isOnSplash = location == '/splash';

    // Splash always redirects based on auth state
    if (isOnSplash) {
      return isAuthenticated ? '/home' : '/login';
    }

    // Unauthenticated users can only access /login
    if (!isAuthenticated && !isOnLogin) {
      return '/login';
    }

    // Authenticated users should not stay on /login
    if (isAuthenticated && isOnLogin) {
      return '/home';
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (_, __) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    ),
    GoRoute(
      path: '/login',
      builder: (_, __) => const LoginScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/vitals/:profileId',
          builder: (_, state) =>
              VitalsScreen(profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/labs/:profileId',
          builder: (_, state) =>
              LabsScreen(profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/medications/:profileId',
          builder: (_, state) =>
              MedicationsScreen(profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/more',
          builder: (_, __) => const MoreScreen(),
        ),
        GoRoute(
          path: '/about',
          builder: (_, __) => const AboutScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/allergies/:profileId',
          builder: (_, state) =>
              AllergiesScreen(profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/appointments/:profileId',
          builder: (_, state) => AppointmentsScreen(
              profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/diagnoses/:profileId',
          builder: (_, state) =>
              DiagnosesScreen(profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/vaccinations/:profileId',
          builder: (_, state) => VaccinationsScreen(
              profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/contacts/:profileId',
          builder: (_, state) =>
              ContactsScreen(profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/diary/:profileId',
          builder: (_, state) =>
              DiaryScreen(profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/symptoms/:profileId',
          builder: (_, state) =>
              SymptomsScreen(profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/tasks/:profileId',
          builder: (_, state) =>
              TasksScreen(profileId: state.pathParameters['profileId']!),
        ),
        GoRoute(
          path: '/documents/:profileId',
          builder: (_, state) =>
              DocumentsScreen(profileId: state.pathParameters['profileId']!),
        ),
      ],
    ),
  ],
);
