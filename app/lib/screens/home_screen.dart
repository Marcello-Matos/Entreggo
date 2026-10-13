import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/auth_service.dart';
import '../theme.dart';
import '../widgets/logo.dart';
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
    required this.onSignOut,
  });

  final ApiClient api;
  final AuthService auth;
  final VoidCallback onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Dashboard> _dashboard = widget.api.dashboard();
  bool _busy = false;

  void _reload() => setState(() => _dashboard = widget.api.dashboard());

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
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _Header(
                    api: widget.api,
                    auth: widget.auth,
                    onSignOut: widget.onSignOut,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'RESUMO DE HOJE',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: EntreggoColors.slate,
                                  letterSpacing: 0.6,
                                ),
                          ),
                          const SizedBox(height: 14),
                          if (snap.hasError)
                            _ErrorBox(error: snap.error!, onRetry: _reload)
                          else
                            _Summary(dash: dash ?? const Dashboard()),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: _busy || loading
                                ? null
                                : () => _scan(dash),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Escanear pacotes'),
                          ),
                          const SizedBox(height: 14),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                _MenuTile(
                                  icon: Icons.route_outlined,
                                  title: 'Minha rota',
                                  subtitle: dash?.activeRouteId == null
                                      ? 'Nenhuma rota em andamento'
                                      : '${dash!.activeRemaining} '
                                            '${dash.activeRemaining == 1 ? 'parada restante' : 'paradas restantes'}',
                                  onTap: dash?.activeRouteId == null
                                      ? null
                                      : () => _openActive(dash!),
                                ),
                                const Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                                _MenuTile(
                                  icon: Icons.history,
                                  title: 'Histórico de entregas',
                                  subtitle: 'Consulte suas rotas anteriores',
                                  onTap: () =>
                                      _push(HistoryScreen(api: widget.api)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
    required this.onSignOut,
  });

  final ApiClient api;
  final AuthService auth;
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
          onSelected: (_) => onSignOut(),
          itemBuilder: (_) => const [
            PopupMenuItem(
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
            _Tile(
              label: 'Progresso',
              value: '$percent%',
              color: const Color(0xFF7C3AED),
              background: const Color(0xFFF3EEFE),
            ),
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
