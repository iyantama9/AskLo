import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/theme.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
// Admin screens are deferred so dart2js splits them out of the initial
// bundle; regular users never download or parse them.
import 'screens/admin/admin_dashboard_screen.dart' deferred as admin_dashboard;
import 'screens/admin/models_management_screen.dart' deferred as admin_models;
import 'screens/admin/router_config_screen.dart'
    deferred as admin_router;
import 'screens/admin/promotions_management_screen.dart'
    deferred as admin_promotions;
import 'screens/admin/admin_shell.dart';
import 'screens/admin/users_management_screen.dart'
    deferred as admin_users;
import 'screens/admin/settings_screen.dart' deferred as admin_settings;
import 'services/api_service.dart';

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  await api.loadToken();
  runApp(AskLoApp(isLoggedIn: api.isLoggedIn));
}

class AskLoApp extends StatefulWidget {
  final bool isLoggedIn;

  const AskLoApp({super.key, required this.isLoggedIn});

  static AskLoAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<AskLoAppState>();

  @override
  State<AskLoApp> createState() => AskLoAppState();
}

class AskLoAppState extends State<AskLoApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  late bool _isLoggedIn;

  ThemeMode get themeMode => _themeMode;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = widget.isLoggedIn;
  }

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  void _handleLoginSuccess() {
    setState(() => _isLoggedIn = true);
  }

  void _handleLogout() async {
    await ApiService().clearToken();
    setState(() => _isLoggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    // AdminSectionController.navigatorKey is wired here so admin section
    // navigation can push named routes (module URLs) without needing a
    // specific BuildContext from inside AdminShell.
    return MaterialApp(
      title: 'AskLo',
      debugShowCheckedModeBanner: false,
      navigatorKey: AdminSectionController.navigatorKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: _isLoggedIn
          ? ChatScreen(onLogout: _handleLogout)
          : LoginScreen(onLoginSuccess: _handleLoginSuccess),
      // Every /admin/* module is generated here (instant, no transition) so
      // each module keeps its own slash URL while switching stays animation-
      // free — matching the original index-swap feel. Non-admin paths fall
      // back to onUnknownRoute / home.
      onGenerateRoute: _onGenerateRoute,
      onUnknownRoute: _buildUnknownRoute,
    );
  }

  /// Generates admin module routes with a zero-duration, no-op transition so
  /// moving between modules is a hard cut (no fade/slide/zoom). Unknown
  /// /admin/* paths fall back to the overview dashboard.
  Route? _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    if (!name.startsWith('/admin')) return null;
    final section = _sectionForAdminPath(name);
    return PageRouteBuilder(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, a, b) => _buildAdminPage(section),
      // Render the page directly — no animation, no background fade.
      transitionsBuilder: (context, a, b, child) => child,
    );
  }

  /// Maps an admin URL to its section; unknown /admin/* → overview.
  String _sectionForAdminPath(String path) {
    switch (path) {
      case '/admin/models':
        return 'models';
      case '/admin/router':
        return 'router';
      case '/admin/promotions':
        return 'promotions';
      case '/admin/users':
        return 'users';
      case '/admin/settings':
        return 'settings';
      default:
        // '/admin', '/admin/', and any unknown /admin/* deep link.
        return 'overview';
    }
  }

  /// Builds the admin screen for a module, gated behind the admin check.
  /// Each module is its own named route so it has a distinct, addressable URL.
  Widget _buildAdminPage(String section) {
    switch (section) {
      case 'overview':
        return _AdminGate(
          child: _DeferredPage(
            loader: admin_dashboard.loadLibrary,
            builder: () => admin_dashboard.AdminDashboardScreen(),
          ),
        );
      case 'models':
        return _AdminGate(
          child: _DeferredPage(
            loader: admin_models.loadLibrary,
            builder: () => admin_models.ModelsManagementScreen(),
          ),
        );
      case 'router':
        return _AdminGate(
          child: _DeferredPage(
            loader: admin_router.loadLibrary,
            builder: () => admin_router.RouterConfigScreen(),
          ),
        );
      case 'promotions':
        return _AdminGate(
          child: _DeferredPage(
            loader: admin_promotions.loadLibrary,
            builder: () => admin_promotions.PromotionsManagementScreen(),
          ),
        );
      case 'users':
        return _AdminGate(
          child: _DeferredPage(
            loader: admin_users.loadLibrary,
            builder: () => admin_users.UsersManagementScreen(),
          ),
        );
      case 'settings':
        return _AdminGate(
          child: _DeferredPage(
            loader: admin_settings.loadLibrary,
            builder: () => admin_settings.AdminSettingsScreen(),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// Unknown /admin/* deep links fall back to the overview dashboard; any
  /// other unknown top-level path falls back to the main entry so the app
  /// never shows Flutter's "no route found" error widget.
  Route _buildUnknownRoute(RouteSettings settings) {
    final path = settings.name ?? '/';
    final Widget page = path.startsWith('/admin')
        ? _buildAdminPage('overview')
        : (_isLoggedIn
            ? ChatScreen(onLogout: _handleLogout)
            : LoginScreen(onLoginSuccess: _handleLoginSuccess));
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }

}

/// Requires the visitor to be logged in with the admin role before showing
/// the wrapped admin screen; otherwise shows the login screen. Rebuilds
/// automatically when the login state changes so the gate doesn't get stuck.
class _AdminGate extends StatefulWidget {
  final Widget child;

  const _AdminGate({required this.child});

  @override
  State<_AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<_AdminGate> {
  int _authGeneration = 0;

  @override
  Widget build(BuildContext context) {
    final api = ApiService();

    if (!api.isLoggedIn) {
      // A fresh widget identity per login attempt so the gate re-evaluates
      // the admin check immediately after successful login.
      return LoginScreen(
        key: ValueKey('admin-login-$_authGeneration'),
        onLoginSuccess: () => setState(() => _authGeneration++),
      );
    }

    if (!api.isAdmin) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline,
                    size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Akses ditolak',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Akun ini tidak memiliki hak admin.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}

/// Loads a deferred library before showing its screen. The future is cached
/// in state so the already-loaded case renders without flicker.
class _DeferredPage extends StatefulWidget {
  final Future<void> Function() loader;
  final Widget Function() builder;

  const _DeferredPage({required this.loader, required this.builder});

  @override
  State<_DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<_DeferredPage> {
  late final Future<void> _library = widget.loader();

  @override
  Widget build(BuildContext context) {
    // While the deferred chunk is still downloading, render nothing instead
    // of a full-screen spinner scaffold — a blank instant swap reads far less
    // like a "zoom" than the spinner->content flash. The already-loaded case
    // is handled synchronously with no waiting.
    return FutureBuilder<void>(
      future: _library,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return widget.builder();
      },
    );
  }
}
