import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthapp/core/security/app_lock/app_lock_controller.dart';
import 'package:healthapp/core/security/security_state.dart';
import 'package:healthapp/screens/security/lock_screen.dart';
import 'package:healthapp/screens/security/migration_screen.dart';
import 'package:healthapp/screens/security/setup_pin_screen.dart';
import '../../providers/providers.dart';
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
import '../../screens/activity/activity_log_screen.dart';
import '../../screens/calendar/calendar_feeds_screen.dart';
import '../../screens/documents/document_bulk_upload_screen.dart';
import '../../screens/documents/document_search_screen.dart';
import '../../screens/emergency/emergency_access_screen.dart';
import '../../screens/export/export_schedules_screen.dart';
import '../../screens/export/export_screen.dart';
import '../../screens/sessions/sessions_screen.dart';
import '../../screens/shares/doctor_shares_screen.dart';
import '../../screens/appointments/upcoming_appointments_screen.dart';
import '../../screens/labs/lab_trends_screen.dart';
import '../../screens/medications/adherence_screen.dart';
import '../../screens/notifications/notification_preferences_screen.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/profiles/profile_edit_screen.dart';
import '../../screens/profiles/profile_list_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/security/two_factor_setup_screen.dart';
import '../../screens/symptoms/symptom_chart_screen.dart';
import '../../screens/tasks/open_tasks_screen.dart';
import '../../screens/vaccinations/vaccination_due_screen.dart';
import '../../screens/vitals/vital_thresholds_screen.dart';
import 'transitions.dart';

/// Riverpod-provided GoRouter so the `redirect` callback can read other
/// providers (AppLockController, AuthService, ...).
///
/// main.dart should wire this up via `routerConfig: ref.watch(appRouterProvider)`.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) async {
      // Deep-link path allowlist: only routes defined in this router are
      // safe to open from external sources. Anything else redirects to /home
      // (or /login when unauthenticated — that's handled by the gates below).
      const allowedPathPrefixes = <String>{
        '/splash', '/login', '/setup-pin', '/migrate', '/lock',
        '/home', '/vitals', '/labs', '/medications', '/more', '/about',
        '/settings', '/allergies', '/appointments', '/diagnoses',
        '/vaccinations', '/contacts', '/diary', '/symptoms', '/tasks',
        '/documents', '/profiles', '/search', '/notifications', '/2fa',
        '/shares', '/calendar-feeds', '/emergency', '/export', '/activity',
        '/sessions',
      };
      final incomingPath = state.matchedLocation;
      final isAllowed = allowedPathPrefixes.any(
        (p) => incomingPath == p || incomingPath.startsWith('$p/'),
      );
      if (!isAllowed) {
        return '/home';
      }

      final path = state.matchedLocation;

      // --- Security-state gate (runs before auth logic) ---
      final securityState = ref.read(appLockControllerProvider);

      if (securityState == SecurityState.migrationPending) {
        return path == '/migrate' ? null : '/migrate';
      }
      if (securityState == SecurityState.loggedInNoPin) {
        return path == '/setup-pin' ? null : '/setup-pin';
      }
      if (securityState == SecurityState.locked ||
          securityState == SecurityState.unlocking) {
        return path == '/lock' ? null : '/lock';
      }
      if (securityState == SecurityState.unregistered ||
          securityState == SecurityState.wiped) {
        return path == '/login' ? null : '/login';
      }

      // --- Legacy auth gate ---
      // Task 19 refactored AuthService.loadCredentials() to an instance method
      // exposed via authServiceProvider (defined in Task 21).
      final authService = ref.read(authServiceProvider);
      final creds = await authService.loadCredentials();
      final isAuthenticated = creds != null;
      final isOnLogin = path == '/login';
      final isOnSplash = path == '/splash';

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
      GoRoute(
        path: '/setup-pin',
        pageBuilder: (_, state) =>
            AppTransitions.fade(child: const SetupPinScreen()),
      ),
      GoRoute(
        path: '/migrate',
        pageBuilder: (_, state) =>
            AppTransitions.fade(child: const MigrationScreen()),
      ),
      GoRoute(
        path: '/lock',
        pageBuilder: (_, state) =>
            AppTransitions.fade(child: const LockScreen()),
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
            builder: (_, state) => MedicationsScreen(
                profileId: state.pathParameters['profileId']!),
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

          // --- Sprint 2 feature-parity routes ---
          GoRoute(
            path: '/profiles',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const ProfileListScreen()),
          ),
          GoRoute(
            path: '/profiles/new',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const ProfileEditScreen()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const SearchScreen()),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const NotificationsScreen()),
          ),
          GoRoute(
            path: '/notifications/preferences',
            pageBuilder: (_, state) => AppTransitions.slideX(
                child: const NotificationPreferencesScreen()),
          ),
          GoRoute(
            path: '/2fa/setup',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const TwoFactorSetupScreen()),
          ),
          GoRoute(
            path: '/vitals/:profileId/thresholds',
            builder: (_, state) => VitalThresholdsScreen(
                profileId: state.pathParameters['profileId']!),
          ),
          GoRoute(
            path: '/labs/:profileId/trends',
            builder: (_, state) => LabTrendsScreen(
                profileId: state.pathParameters['profileId']!),
          ),
          GoRoute(
            path: '/medications/:profileId/adherence',
            builder: (_, state) => AdherenceScreen(
                profileId: state.pathParameters['profileId']!),
          ),
          GoRoute(
            path: '/vaccinations/:profileId/due',
            builder: (_, state) => VaccinationDueScreen(
                profileId: state.pathParameters['profileId']!),
          ),
          GoRoute(
            path: '/appointments/:profileId/upcoming',
            builder: (_, state) => UpcomingAppointmentsScreen(
                profileId: state.pathParameters['profileId']!),
          ),
          GoRoute(
            path: '/tasks/:profileId/open',
            builder: (_, state) => OpenTasksScreen(
                profileId: state.pathParameters['profileId']!),
          ),
          GoRoute(
            path: '/symptoms/:profileId/chart',
            builder: (_, __) => const SymptomChartScreen(),
          ),

          // --- Sprint 3 feature-parity routes ---
          GoRoute(
            path: '/shares/:profileId',
            pageBuilder: (_, state) => AppTransitions.slideX(
                child: DoctorSharesScreen(
                    profileId: state.pathParameters['profileId']!)),
          ),
          GoRoute(
            path: '/calendar-feeds',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const CalendarFeedsScreen()),
          ),
          GoRoute(
            path: '/emergency/:profileId',
            pageBuilder: (_, state) => AppTransitions.slideX(
                child: EmergencyAccessScreen(
                    profileId: state.pathParameters['profileId']!)),
          ),
          GoRoute(
            path: '/export/:profileId',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const ExportScreen()),
          ),
          GoRoute(
            path: '/export/schedules',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const ExportSchedulesScreen()),
          ),
          GoRoute(
            path: '/activity/:profileId',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const ActivityLogScreen()),
          ),
          GoRoute(
            path: '/documents/:profileId/bulk',
            pageBuilder: (_, state) => AppTransitions.slideX(
                child: DocumentBulkUploadScreen(
                    profileId: state.pathParameters['profileId']!)),
          ),
          GoRoute(
            path: '/documents/:profileId/search',
            pageBuilder: (_, state) => AppTransitions.slideX(
                child: DocumentSearchScreen(
                    profileId: state.pathParameters['profileId']!)),
          ),
          GoRoute(
            path: '/sessions',
            pageBuilder: (_, state) =>
                AppTransitions.slideX(child: const SessionsScreen()),
          ),
        ],
      ),
    ],
  );
});
