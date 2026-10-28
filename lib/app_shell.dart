import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/actions/presentation/screens/planned_actions_screen.dart';
import 'features/plants/presentation/screens/home_screen.dart';
import 'features/scanner/presentation/screens/scanner_screen.dart';
import 'features/sensors/presentation/screens/sensor_screen.dart';
import 'features/spaces/presentation/providers/space_provider.dart';
import 'core/config/app_config.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _idx = 0;
  final _screens = const [
    HomeScreen(),
    PlannedActionsScreen(),
    SensorScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      bottomNavigationBar: _bar(),
    );
  }

  Widget _bar() => Container(
        decoration: BoxDecoration(color: Colors.white, boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4))
        ]),
        child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          _betaStrip(),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(children: [
                Expanded(
                  child: _navItem(
                    0,
                    Icons.home_outlined,
                    Icons.home,
                    'Plantes',
                  ),
                ),
                Expanded(
                  child: _navItem(
                    1,
                    Icons.event_note_outlined,
                    Icons.event_note,
                    'À faire',
                  ),
                ),
                SizedBox(width: 62, child: Center(child: _scanBtn())),
                Expanded(
                  child: _navItem(
                    2,
                    Icons.grid_view_outlined,
                    Icons.grid_view,
                    'Espaces',
                  ),
                ),
                Expanded(
                  child: _navItem(
                    3,
                    Icons.settings_outlined,
                    Icons.settings,
                    'Réglages',
                  ),
                ),
              ])),
        ])),
      );

  Widget _betaStrip() => InkWell(
        onTap: () => setState(() => _idx = 3),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: const Color(0xFFE8F5E9),
          child: Text(
            '${AppConfig.shortLabel} - ${AppConfig.testerId}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF2E7D32),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final active = _idx == index;
    return InkWell(
        onTap: () {
          final changed = _idx != index;
          if (changed) setState(() => _idx = index);
          if (changed && index == 2) {
            unawaited(context.read<SpaceProvider>().refresh());
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(active ? activeIcon : icon,
                  color: active
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF9E9E9E),
                  size: 26),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: active
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF9E9E9E),
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
            ])));
  }

  Widget _scanBtn() => Semantics(
      button: true,
      label: 'Scanner un code QR',
      child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ScannerScreen())),
          child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]),
              child: const Icon(Icons.qr_code_scanner,
                  color: Colors.white, size: 26))));
}
