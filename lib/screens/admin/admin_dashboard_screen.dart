import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/admin_service.dart';
import 'admin_shell.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  int _routerTotal = 0;
  int _routerActive = 0;
  int _modelTotal = 0;
  int _modelImage = 0;
  String? _defaultModel;
  String? _error;

  final ApiService _api = ApiService();
  late final AdminService _adminService;

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(_api.token ?? '');
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = _stats == null;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _adminService.getUserStats(),
        _adminService.getRouterConfigs(),
        _api.getModelCatalog(),
      ]);

      final users = (results[0] as Map<String, dynamic>)['stats']
          as Map<String, dynamic>?;
      final routers = results[1] as List<dynamic>;
      final catalog = results[2]
          as ({List<Map<String, dynamic>> models, String? defaultModel});

      setState(() {
        _stats = users;
        _routerTotal = routers.length;
        _routerActive =
            routers.where((r) => r['is_active'] == true).length;
        _modelTotal = catalog.models.length;
        _modelImage = catalog.models
            .where((m) => m['supports_image_generation'] == true)
            .length;
        _defaultModel = catalog.defaultModel;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = const Color(0xFF141520);
    final surfaceBorder = const Color(0xFF262738);

    return AdminShell(
      section: 'overview',
      onSectionSelected: _onSectionSelected,
      title: 'Overview',
      subtitle: 'Ringkasan sistem dan aktivitas',
      headerActions: IconButton(
        icon: const Icon(Icons.refresh, size: 20),
        tooltip: 'Refresh',
        onPressed: _loadStats,
        visualDensity: VisualDensity.compact,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(theme)
              : _buildOverview(theme, surface, surfaceBorder),
    );
  }

  void _onSectionSelected(String section) {
    AdminSectionController.select(section);
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.error_outline, color: Colors.redAccent),
          ),
          const SizedBox(height: 16),
          Text('Gagal memuat data',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(_error ?? '', style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadStats,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }

  Widget _buildOverview(
      ThemeData theme, Color surface, Color surfaceBorder) {
    final stats = _stats ?? {};
    final totalUsers = stats['total_users']?.toString() ?? '0';
    final active24h = stats['active_24h']?.toString() ?? '0';
    final active7d = stats['active_7d']?.toString() ?? '0';
    final new7d = stats['new_7d']?.toString() ?? '0';
    final accent = const Color(0xFFA78BFA);
    final textMuted = const Color(0xFF8B8CA0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        return SingleChildScrollView(
          padding: isNarrow
              ? const EdgeInsets.all(16)
              : const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stat cards — responsive grid
              GridView.count(
                crossAxisCount: isNarrow ? 2 : 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: isNarrow ? 10 : 16,
                childAspectRatio: isNarrow ? 1.6 : 2.2,
                children: [
                  _statCard('Total Users', totalUsers,
                      Icons.people_outline, accent, [0.2, 0.4, 0.6, 0.5, 0.8, 1.0]),
                  _statCard('Aktif (24 jam)', active24h,
                      Icons.schedule, const Color(0xFF38BDF8), [0.4, 0.6, 0.5, 0.8, 0.9, 0.7]),
                  _statCard('Aktif (7 hari)', active7d,
                      Icons.event, const Color(0xFFF472B6), [0.3, 0.5, 0.9, 0.7, 0.85, 1.0]),
                  _statCard('User Baru (7 hari)', new7d,
                      Icons.person_add, const Color(0xFF34D399), [0.1, 0.3, 0.2, 0.6, 0.5, 0.9]),
                ],
              ),
              SizedBox(height: isNarrow ? 12 : 16),

              // Chart + distribution — stack on narrow, side-by-side on wide
              if (isNarrow) ...[
                _activityChart(theme, surface, surfaceBorder, accent, textMuted),
                const SizedBox(height: 12),
                _modelDistributionCard(theme, surface, surfaceBorder, accent, textMuted),
              ] else
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _activityChart(theme, surface, surfaceBorder, accent, textMuted),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: _modelDistributionCard(theme, surface, surfaceBorder, accent, textMuted),
                    ),
                  ],
                ),
              SizedBox(height: isNarrow ? 12 : 16),

              // Infrastructure cards — responsive grid
              GridView.count(
                crossAxisCount: isNarrow ? 2 : 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: isNarrow ? 10 : 16,
                childAspectRatio: isNarrow ? 1.8 : 2.6,
                children: [
                  _infrastructureCard('Router Terkonfigurasi',
                      _routerTotal.toString(), Icons.router, accent),
                  _infrastructureCard('Router Aktif',
                      _routerActive.toString(), Icons.wifi, const Color(0xFF34D399),
                      showDot: true),
                  _infrastructureCard(
                      'Model Aktif', _modelTotal.toString(), Icons.memory,
                      const Color(0xFF38BDF8)),
                  _infrastructureCard('Model Image Gen',
                      _modelImage.toString(), Icons.image,
                      const Color(0xFFF472B6)),
                ],
              ),
              SizedBox(height: isNarrow ? 12 : 16),

              // Default model banner
              if (_defaultModel != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: surface,
                    border: Border.all(color: surfaceBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Color(0xFFFBBF24), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Model default',
                              style: TextStyle(color: textMuted, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _defaultModel!,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isNarrow ? 12 : 16),
              ],

              // Quick actions — responsive grid
              Text(
                'Aksi Cepat',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: isNarrow ? 2 : 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: isNarrow ? 10 : 12,
                childAspectRatio: isNarrow ? 2.0 : 2.8,
                children: [
                  _quickAction('Kelola Model', Icons.memory,
                      accent, surface, surfaceBorder, textMuted, 'models'),
                  _quickAction('Konfigurasi Router', Icons.router,
                      accent, surface, surfaceBorder, textMuted, 'router'),
                  _quickAction('Pengaturan', Icons.settings,
                      accent, surface, surfaceBorder, textMuted, 'settings'),
                  _quickAction('Kelola User', Icons.people,
                      accent, surface, surfaceBorder, textMuted, 'users'),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, Color accent,
      List<double> sparkline) {
    final textMuted = const Color(0xFF8B8CA0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141520),
        border: Border.all(color: const Color(0xFF262738)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: textMuted, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          height: 1),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.trending_up, size: 13, color: accent),
                        const SizedBox(width: 4),
                        Text('+0%',
                            style: TextStyle(
                                color: accent, fontSize: 12, height: 1)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 72,
                height: 32,
                child: CustomPaint(
                  painter: _SparklinePainter(sparkline, accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activityChart(
      ThemeData theme, Color surface, Color surfaceBorder, Color accent,
      Color textMuted) {
    // Sample 7-day activity (replace with real data when available)
    const active = [1, 2, 3, 5, 8, 4, 3];
    const newUser = [0, 1, 2, 3, 5, 2, 1];
    const labels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    const maxVal = 8;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: surfaceBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Aktivitas Pengguna',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  _timeChip('7 Hari', true, accent, surfaceBorder),
                  const SizedBox(width: 6),
                  _timeChip('30 Hari', false, accent, surfaceBorder),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: CustomPaint(
              size: const Size(double.infinity, 180),
              painter: _ActivityLineChartPainter(
                active: active,
                newUser: newUser,
                maxVal: maxVal,
                activeColor: accent,
                newUserColor: const Color(0xFF38BDF8),
                gridColor: surfaceBorder,
                labelColor: textMuted,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _legendDot(accent, 'Aktif'),
              const SizedBox(width: 16),
              _legendDot(const Color(0xFF38BDF8), 'User Baru'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map((l) => Text(l,
                    style: TextStyle(color: textMuted, fontSize: 11)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _timeChip(String label, bool active, Color accent, Color border) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(color: active ? accent : border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: active ? Colors.white : const Color(0xFF8B8CA0),
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: Color(0xFF8B8CA0), fontSize: 12)),
      ],
    );
  }

  Widget _modelDistributionCard(
      ThemeData theme, Color surface, Color surfaceBorder, Color accent,
      Color textMuted) {
    final total = _modelTotal;
    final image = _modelImage;
    final chat = total - image;
    final imagePct = total > 0 ? image / total : 0.0;
    final chatPct = 1.0 - imagePct;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: surfaceBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Distribusi Model',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    imagePct: imagePct,
                    chatPct: chatPct,
                    imageColor: accent,
                    chatColor: const Color(0xFF38BDF8),
                    centerValue: total.toString(),
                    centerLabel: 'Model Aktif',
                    bgColor: surface,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    _distributionRow(
                        Icons.memory, 'Model Image Gen', image.toString(),
                        '${(imagePct * 100).round()}%', accent, textMuted),
                    const SizedBox(height: 16),
                    _distributionRow(Icons.layers, 'Model Lain',
                        chat.toString(), '${(chatPct * 100).round()}%',
                        const Color(0xFF38BDF8), textMuted),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _distributionRow(IconData icon, String label, String value,
      String pct, Color accent, Color textMuted) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: accent, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: textMuted, fontSize: 12)),
              Text(
                value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Text(
          pct,
          style: TextStyle(
              color: accent, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _infrastructureCard(
      String label, String value, IconData icon, Color accent,
      {bool showDot = false}) {
    final textMuted = const Color(0xFF8B8CA0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141520),
        border: Border.all(color: const Color(0xFF262738)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: accent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(color: textMuted, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis),
              ),
              if (showDot)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34D399),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF34D399)
                              .withValues(alpha: 0.6),
                          blurRadius: 6),
                    ],
                  ),
                )
              else
                Icon(Icons.chevron_right, color: textMuted, size: 16),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(String label, IconData icon, Color accent, Color surface,
      Color surfaceBorder, Color textMuted, String section) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Swap in place via the shared controller — a named-route push
        // would run a route transition on top of the admin shell.
        onTap: () => AdminSectionController.select(section),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: surfaceBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right, color: textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV) == 0 ? 1 : maxV - minV;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final normalized = (values[i] - minV) / range;
      final y = size.height - (normalized * size.height * 0.9 + size.height * 0.1);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ActivityLineChartPainter extends CustomPainter {
  final List<int> active;
  final List<int> newUser;
  final int maxVal;
  final Color activeColor;
  final Color newUserColor;
  final Color gridColor;
  final Color labelColor;

  _ActivityLineChartPainter({
    required this.active,
    required this.newUser,
    required this.maxVal,
    required this.activeColor,
    required this.newUserColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 24.0;
    const bottomPad = 4.0;
    final plotW = size.width - leftPad;
    final plotH = size.height - bottomPad;

    // Gridlines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (int g = 0; g <= 4; g++) {
      final y = (g / 4) * plotH;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
    }

    final activePath = _buildPath(active, leftPad, plotW, plotH, maxVal);
    final newUserPath = _buildPath(newUser, leftPad, plotW, plotH, maxVal);

    final activeAreaPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x40A78BFA),
          Color(0x00A78BFA),
        ],
      ).createShader(
        Rect.fromLTWH(leftPad, 0, plotW, plotH));
    final activeArea = Path()
      ..addPath(activePath, const Offset(0, 0))
      ..lineTo(leftPad + plotW, plotH)
      ..lineTo(leftPad, plotH)
      ..close();
    canvas.drawPath(activeArea, activeAreaPaint);

    final newPaint = Paint()
      ..color = newUserColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final dashPaint = Paint()
      ..color = newUserColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(newUserPath, dashPaint);
    canvas.drawPath(activePath, newPaint..color = activeColor);

    // Dots
    for (int i = 0; i < active.length; i++) {
      final x = leftPad + (i / (active.length - 1)) * plotW;
      final y = plotH - (active[i] / maxVal) * plotH;
      canvas.drawCircle(
          Offset(x, y),
          3.5,
          Paint()
            ..color = activeColor
            ..style = PaintingStyle.fill);

      final yNew = plotH - (newUser[i] / maxVal) * plotH;
      canvas.drawCircle(
          Offset(x, yNew),
          3.5,
          Paint()
            ..color = newUserColor
            ..style = PaintingStyle.fill);
    }
  }

  Path _buildPath(List<int> values, double leftPad, double plotW,
      double plotH, int maxV) {
    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = leftPad + (i / (values.length - 1)) * plotW;
      final y = plotH - (values[i] / maxV) * plotH;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DonutChartPainter extends CustomPainter {
  final double imagePct;
  final double chatPct;
  final Color imageColor;
  final Color chatColor;
  final String centerValue;
  final String centerLabel;
  final Color bgColor;

  _DonutChartPainter({
    required this.imagePct,
    required this.chatPct,
    required this.imageColor,
    required this.chatColor,
    required this.centerValue,
    required this.centerLabel,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final strokeWidth = radius * 0.38;

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0xFF1A1B2E);
    canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);

    final sweep = 2 * math.pi;
    final imageSweep = sweep * imagePct;

    final paint1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = imageColor
      ..strokeCap = StrokeCap.butt;
    final paint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = chatColor
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        -math.pi / 2,
        imageSweep,
        false,
        paint1);
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        -math.pi / 2 + imageSweep,
        sweep - imageSweep,
        false,
        paint2);

    final valueStyle = TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.w700);
    final labelStyle = const TextStyle(
        color: Color(0xFF8B8CA0), fontSize: 11);

    final valueSpan = TextSpan(
      text: centerValue,
      style: valueStyle,
      children: [
        const TextSpan(text: '\n'),
        TextSpan(text: centerLabel, style: labelStyle),
      ],
    );
    final textPainter = TextPainter(
      text: valueSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2,
            center.dy - textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
