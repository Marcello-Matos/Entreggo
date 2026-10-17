import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/auth_service.dart';
import '../billing/billing_service.dart';
import '../routing/location.dart';
import '../theme.dart';
import '../widgets/logo.dart';
import '../widgets/paywall_sheet.dart';
import '../widgets/profile_avatar.dart';
import 'history_screen.dart';
import 'map_screen.dart';
import 'route_screen.dart';

/// Tela inicial: desempenho do dia, escanear pacotes, rota atual e histórico.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.theme,
    required this.onSignOut,
  });

  final ApiClient api;
  final AuthService auth;
  final ThemeController theme;
  final VoidCallback onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Dashboard> _dashboard = widget.api.dashboard();
  late Future<Subscription> _subscription = widget.api.subscription();
  late Future<WeeklyStats> _weekly = widget.api.weekly();
  late final BillingService _billing = BillingService(widget.api);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _billing.init();
  }

  @override
  void dispose() {
    _billing.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _dashboard = widget.api.dashboard();
    _subscription = widget.api.subscription();
    _weekly = widget.api.weekly();
  });

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  /// Continua escaneando na rota de hoje; se não houver, cria uma nova.
  Future<void> _scan(Dashboard? dash) async {
    var routeId = dash?.activeRouteId;
    if (routeId == null) {
      setState(() => _busy = true);
      try {
        final now = DateTime.now();
        routeId = (await widget.api.createRoute(
          'Entregas ${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}',
        )).id;
      } on ApiException catch (e) {
        _toast(e.message);
      } catch (e) {
        _toast('Falha de conexão: $e');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (routeId == null || !mounted) return;
    await _push(
      RouteScreen(api: widget.api, routeId: routeId, startScanning: true),
    );
  }

  void _openActive(Dashboard dash) => _push(
    dash.activeOptimized
        ? MapScreen(api: widget.api, routeId: dash.activeRouteId!)
        : RouteScreen(api: widget.api, routeId: dash.activeRouteId!),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: FutureBuilder<Dashboard>(
            future: _dashboard,
            builder: (context, snap) {
              final dash = snap.data;
              final loading = snap.connectionState != ConnectionState.done;
              final hasActive = dash?.activeRouteId != null;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _Header(
                    api: widget.api,
                    auth: widget.auth,
                    theme: widget.theme,
                    onSignOut: widget.onSignOut,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.bar_chart_rounded,
                                size: 20,
                                color: EntreggoColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Resumo de hoje',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (snap.hasError)
                            _ErrorBox(error: snap.error!, onRetry: _reload)
                          else
                            _Summary(dash: dash ?? const Dashboard()),
                        ],
                      ),
                    ),
                  ),
                  FutureBuilder<Subscription>(
                    future: _subscription,
                    builder: (context, s) {
                      final sub = s.data;
                      if (sub == null || (sub.isPro && !sub.isTrial)) {
                        return const SizedBox.shrink();
                      }
                      return _PlanBanner(
                        sub: sub,
                        onTap: () async {
                          await showPaywall(context, _billing);
                          _reload();
                        },
                      );
                    },
                  ),
                  if (hasActive) ...[
                    const SizedBox(height: 12),
                    _NextStopCard(dash: dash!, onTap: () => _openActive(dash)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatChip(
                          icon: Icons.route_outlined,
                          label:
                              '${dash.activeRemaining} '
                              '${dash.activeRemaining == 1 ? 'parada restante' : 'paradas restantes'}',
                        ),
                        const SizedBox(width: 12),
                        if (dash.remainingLabel.isNotEmpty)
                          _StatChip(
                            icon: Icons.schedule,
                            label: '${dash.remainingLabel} restante',
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => _openActive(dash),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(
                        dash.activeOptimized
                            ? 'Ver mapa e continuar'
                            : 'Continuar montando a rota',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _busy || loading ? null : () => _scan(dash),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Escanear mais pacotes'),
                    ),
                  ] else ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _busy || loading ? null : () => _scan(dash),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Escanear pacotes'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FutureBuilder<WeeklyStats>(
                    future: _weekly,
                    builder: (context, s) => s.hasData
                        ? _WeeklyCard(stats: s.data!)
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 14),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _MenuTile(
                      icon: Icons.history,
                      title: 'Histórico de entregas',
                      subtitle: 'Consulte suas rotas anteriores',
                      onTap: () => _push(HistoryScreen(api: widget.api)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.api,
    required this.auth,
    required this.theme,
    required this.onSignOut,
  });

  final ApiClient api;
  final AuthService auth;
  final ThemeController theme;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const EntreggoMark(width: 36),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Entreggo',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'Sua operação de entregas',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: EntreggoColors.slate),
              ),
            ],
          ),
        ),
        ProfileAvatar(api: api, auth: auth),
        PopupMenuButton<String>(
          tooltip: 'Opções',
          icon: const Icon(Icons.tune),
          onSelected: (value) {
            if (value == 'logout') {
              onSignOut();
            } else {
              theme.set(ThemeMode.values.asNameMap()[value]!);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              enabled: false,
              height: 32,
              child: Text(
                'APARÊNCIA',
                style: TextStyle(fontSize: 12, color: EntreggoColors.slate),
              ),
            ),
            CheckedPopupMenuItem(
              value: 'system',
              checked: theme.mode == ThemeMode.system,
              child: const Text('Automático'),
            ),
            CheckedPopupMenuItem(
              value: 'light',
              checked: theme.mode == ThemeMode.light,
              child: const Text('Claro'),
            ),
            CheckedPopupMenuItem(
              value: 'dark',
              checked: theme.mode == ThemeMode.dark,
              child: const Text('Escuro'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'logout',
              child: ListTile(leading: Icon(Icons.logout), title: Text('Sair')),
            ),
          ],
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.dash});

  final Dashboard dash;

  @override
  Widget build(BuildContext context) {
    final percent = (dash.progress * 100).round();
    final others = [
      if (dash.failed > 0) '${dash.failed} não entregue(s)',
      if (dash.skipped > 0) '${dash.skipped} pulada(s)',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Tile(
              label: 'Pacotes',
              value: '${dash.packages}',
              color: const Color(0xFF1D6FD8),
              background: const Color(0xFFEAF2FE),
            ),
            const SizedBox(width: 12),
            _Tile(
              label: 'Entregues',
              value: '${dash.delivered}',
              color: const Color(0xFF15803D),
              background: const Color(0xFFE9F9EE),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Tile(
              label: 'Pendentes',
              value: '${dash.pending}',
              color: const Color(0xFFC2410C),
              background: const Color(0xFFFFF4E5),
            ),
            const SizedBox(width: 12),
            _RingTile(progress: dash.progress, percent: percent),
          ],
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: dash.progress,
          minHeight: 10,
          borderRadius: BorderRadius.circular(10),
          backgroundColor: const Color(0xFFE2E8F0),
        ),
        const SizedBox(height: 10),
        Text(
          dash.packages == 0
              ? 'Nenhum pacote hoje ainda. Escaneie para começar.'
              : others.isEmpty
              ? '${dash.delivered + dash.failed + dash.skipped} de ${dash.packages} pacotes concluídos.'
              : others.join(' • '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Anel de progresso: percentual grande com a legenda "do dia".
class _RingTile extends StatelessWidget {
  const _RingTile({required this.progress, required this.percent});

  final double progress;
  final int percent;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EEFE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 5.5,
                    backgroundColor: const Color(0xFFDCCFFA),
                    color: const Color(0xFF7C3AED),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                // FittedBox reduz a fonte quando cabem 3 dígitos ("100%")
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: FittedBox(
                    child: Text(
                      '$percent%',
                      style: const TextStyle(
                        color: Color(0xFF7C3AED),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Progresso\ndo dia',
              style: TextStyle(color: Color(0xFF7C3AED), fontSize: 15),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Card "Próxima parada": endereço + distância em linha reta e tempo
/// estimado de deslocamento (~30 km/h), como no mockup.
class _NextStopCard extends StatefulWidget {
  const _NextStopCard({required this.dash, required this.onTap});

  final Dashboard dash;
  final VoidCallback onTap;

  @override
  State<_NextStopCard> createState() => _NextStopCardState();
}

class _NextStopCardState extends State<_NextStopCard> {
  double? _distanceM;

  @override
  void initState() {
    super.initState();
    final lat = widget.dash.nextLat;
    final lng = widget.dash.nextLng;
    if (lat == null || lng == null) return;
    currentPosition().then((pos) {
      if (pos != null && mounted) {
        setState(() {
          _distanceM = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            lat,
            lng,
          );
        });
      }
    });
  }

  String get _distanceLabel {
    final m = _distanceM;
    if (m == null) return '';
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  String get _etaLabel {
    final m = _distanceM;
    if (m == null) return '';
    // ~30 km/h média urbana — estimativa de deslocamento
    final min = (m / 500).round().clamp(1, 999);
    return '~$min min';
  }

  @override
  Widget build(BuildContext context) {
    final dash = widget.dash;
    final distance = [
      if (_distanceLabel.isNotEmpty) _distanceLabel,
      if (_etaLabel.isNotEmpty) _etaLabel,
    ].join(' • ');
    return Material(
      color: const Color(0xFFE9F9EE),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF15803D).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF15803D),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Próxima parada',
                      style: TextStyle(
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      dash.nextAddress ?? dash.activeRouteTitle ?? 'Parada',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (distance.isNotEmpty)
                      Text(
                        distance,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF15803D)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip de estatística com ícone ("11 paradas restantes", "1h42 restante").
class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: EntreggoColors.slate),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: EntreggoColors.navy,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    leading: Icon(icon, color: EntreggoColors.primary),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
    ),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    enabled: onTap != null,
    onTap: onTap,
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'Não foi possível carregar o resumo. O servidor pode estar '
        'iniciando (até 1 minuto).',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.orange.shade800),
      ),
      TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
    ],
  );
}

/// Banner de assinatura: dias de trial restantes ou aviso de teste expirado.
class _PlanBanner extends StatelessWidget {
  const _PlanBanner({required this.sub, required this.onTap});

  final Subscription sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final expired = sub.trialExpired;
    final (icon, color, title, subtitle) = expired
        ? (
            Icons.lock_clock,
            Colors.orange.shade800,
            'Seu período de teste acabou',
            'Assine o Pro para continuar com rotas grandes',
          )
        : (
            Icons.workspace_premium_outlined,
            EntreggoColors.accent,
            'Teste Pro: ${sub.trialDaysLeft} ${sub.trialDaysLeft == 1 ? 'dia restante' : 'dias restantes'}',
            'Depois, R\$ 29,90/mês pela Google Play',
          );
    return Card(
      color: color.withValues(alpha: 0.1),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Gráfico dos últimos 7 dias: barras empilhadas (entregue/falha/pulado)
/// e taxa de sucesso do período.
class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.stats});

  final WeeklyStats stats;

  static const _weekday = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  @override
  Widget build(BuildContext context) {
    final maxY = stats.days
        .map((d) => d.delivered + d.failed + d.skipped)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.insights_outlined,
                  size: 20,
                  color: EntreggoColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Últimos 7 dias',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (stats.total > 0)
                  Text(
                    '${(stats.successRate * 100).round()}% de sucesso',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16A34A),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            stats.total == 0
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Sem entregas registradas nos últimos 7 dias.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: EntreggoColors.slate),
                    ),
                  )
                : SizedBox(
                    height: 110,
                    child: BarChart(
                      BarChartData(
                        maxY: maxY * 1.15,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(enabled: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          leftTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              getTitlesWidget: (v, _) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _weekday[stats.days[v.toInt()].date.weekday -
                                      1],
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: EntreggoColors.slate,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < stats.days.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY:
                                      (stats.days[i].delivered +
                                              stats.days[i].failed +
                                              stats.days[i].skipped)
                                          .toDouble(),
                                  width: 16,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                  rodStackItems: [
                                    BarChartRodStackItem(
                                      0,
                                      stats.days[i].delivered.toDouble(),
                                      const Color(0xFF16A34A),
                                    ),
                                    BarChartRodStackItem(
                                      stats.days[i].delivered.toDouble(),
                                      (stats.days[i].delivered +
                                              stats.days[i].failed)
                                          .toDouble(),
                                      Colors.orange,
                                    ),
                                    BarChartRodStackItem(
                                      (stats.days[i].delivered +
                                              stats.days[i].failed)
                                          .toDouble(),
                                      (stats.days[i].delivered +
                                              stats.days[i].failed +
                                              stats.days[i].skipped)
                                          .toDouble(),
                                      EntreggoColors.slate,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
            if (stats.total > 0) ...[
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendDot(Color(0xFF16A34A), 'entregue'),
                  SizedBox(width: 12),
                  _LegendDot(Colors.orange, 'falha'),
                  SizedBox(width: 12),
                  _LegendDot(EntreggoColors.slate, 'pulado'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: EntreggoColors.slate),
      ),
    ],
  );
}
