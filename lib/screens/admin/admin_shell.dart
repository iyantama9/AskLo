import 'package:flutter/material.dart';
import '../../services/api_service.dart';

/// Bridges section selection from any AdminShell down to the owning
/// _AdminRoot without a Navigator. The root registers itself here on build;
/// each shell's onSectionSelected calls select() to swap the active index.
class AdminSectionController {
  /// Root navigator key, wired from [MaterialApp] in main.dart, so section
  /// navigation can update the URL without needing a specific BuildContext.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey();

  /// Navigates (push-and-replace) to the module's own route so the browser
  /// address bar always reflects the active admin module. Each module is a
  /// distinct named route, so this also keeps deep links and refresh working.
  static void select(String section) {
    final route = AdminSection.routeFor(section);
    // Replace (not push) so the address bar shows the module URL without
    // piling up admin modules in the back stack. The deferred chunk is
    // already cached by _DeferredPage after first load, so returning is
    // instant with no spinner/zoom.
    navigatorKey.currentState?.pushReplacementNamed(route);
  }
}

/// Shared shell for every admin page. Responsive: a fixed sidebar on wide
/// screens and a top bar + slide-in drawer on narrow (mobile) screens, so the
/// whole dashboard is usable on phones.
class AdminShell extends StatefulWidget {
  final String section;
  final String title;
  final String subtitle;
  final Widget? headerActions;
  final Widget body;
  final ValueChanged<String> onSectionSelected;

  const AdminShell({
    super.key,
    required this.section,
    this.title = '',
    this.subtitle = '',
    this.headerActions,
    required this.body,
    required this.onSectionSelected,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = AdminSection.valueOf(widget.section);
    final textMuted = const Color(0xFF8B8CA0);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    void selectTarget(AdminSection target) {
      if (target.name == widget.section) return;
      widget.onSectionSelected(target.name);
      if (!isWide) _scaffoldKey.currentState?.closeEndDrawer();
    }

    Widget contentColumn() => Column(
          children: [
            if (widget.title.isNotEmpty)
              _buildHeader(context, theme, textMuted),
            Expanded(child: widget.body),
          ],
        );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0B0C14),
      // Mobile: slide-in nav drawer on the leading side.
      drawer: isWide
          ? null
          : Drawer(
              backgroundColor: const Color(0xFF0E0F18),
              child: _buildNavList(active, selectTarget),
            ),
      // Wide: a persistent end-drawer so the sidebar also works via drawer.
      endDrawer: isWide
          ? Drawer(
              backgroundColor: const Color(0xFF0E0F18),
              child: _buildNavList(active, selectTarget),
            )
          : null,
      body: isWide
          ? Row(
              children: [
                _buildSidebar(active, selectTarget),
                Expanded(child: contentColumn()),
              ],
            )
          : contentColumn(),
      // Mobile top bar with menu + user chip + actions.
      appBar: isWide
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF0B0C14),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF8B8CA0)),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              title: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.hexagon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title.isNotEmpty ? widget.title : 'Admin',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              actions: [
                _buildUserChip(),
                if (widget.headerActions != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: widget.headerActions!,
                  ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Color(0xFF8B8CA0)),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ],
            ),
    );
  }

  Widget _buildNavList(AdminSection active, void Function(AdminSection) select) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 5)),
                  ],
                ),
                child: const Icon(Icons.hexagon, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                'AskLo Admin',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: AdminSection.all.map((s) {
              final selected = s == active;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => select(s),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF1F1B3A) : Colors.transparent,
                        border: Border.all(
                            color: selected ? const Color(0xFF7C3AED) : Colors.transparent,
                            width: selected ? 1.2 : 0),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                    color: const Color(0xFF7C3AED)
                                        .withValues(alpha: 0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4)),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            s.icon,
                            size: 18,
                            color: selected
                                ? const Color(0xFFA78BFA)
                                : const Color(0xFF8B8CA0),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            s.label,
                            style: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF8B8CA0),
                              fontSize: 14,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar(
      AdminSection active, void Function(AdminSection target) selectTarget) {
    return Container(
      width: 220,
      color: const Color(0xFF0E0F18),
      child: _buildNavList(active, selectTarget),
    );
  }

  /// Shared header shown at the top of every admin module. Keeping it
  /// uniform across all six modules is what makes the admin area feel
  /// consistent.
  Widget _buildHeader(BuildContext context, ThemeData theme, Color textMuted) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 24 : 16,
        vertical: 14,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E2030))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                if (widget.subtitle.isNotEmpty) const SizedBox(height: 2),
                if (widget.subtitle.isNotEmpty)
                  Text(widget.subtitle,
                      style: TextStyle(color: textMuted, fontSize: 13)),
              ],
            ),
          ),
          _buildUserChip(),
          if (widget.headerActions != null) ...[
            const SizedBox(width: 12),
            widget.headerActions!,
          ],
        ],
      ),
    );
  }

  /// Small signed-in user pill, shown on every module header so all six
  /// admin pages share the same chrome.
  Widget _buildUserChip() {
    final username = ApiService().username ?? 'Admin';
    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF141520),
        border: Border.all(color: const Color(0xFF262738)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF262738),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Color(0xFFA78BFA), size: 14),
          ),
          const SizedBox(width: 7),
          Text(
            username,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class AdminSection {
  final String name;
  final String label;
  final String route;
  final IconData icon;

  const AdminSection({
    required this.name,
    required this.label,
    required this.route,
    required this.icon,
  });

  static const List<AdminSection> all = [
    AdminSection(
        name: 'overview',
        label: 'Overview',
        route: '/admin',
        icon: Icons.dashboard),
    AdminSection(
        name: 'models',
        label: 'Models',
        route: '/admin/models',
        icon: Icons.memory),
    AdminSection(
        name: 'router',
        label: 'Router',
        route: '/admin/router',
        icon: Icons.router),
    AdminSection(
        name: 'promotions',
        label: 'Promotions',
        route: '/admin/promotions',
        icon: Icons.local_offer),
    AdminSection(
        name: 'users',
        label: 'Users',
        route: '/admin/users',
        icon: Icons.people),
    AdminSection(
        name: 'settings',
        label: 'Settings',
        route: '/admin/settings',
        icon: Icons.settings),
  ];

  static AdminSection valueOf(String section) {
    for (final s in all) {
      if (s.name == section) return s;
    }
    return all.first;
  }

  /// The addressable route for a module. Unknown sections fall back to the
  /// overview dashboard so a broken deep link never 404s inside the app.
  static String routeFor(String section) {
    for (final s in all) {
      if (s.name == section) return s.route;
    }
    return all.first.route;
  }
}
