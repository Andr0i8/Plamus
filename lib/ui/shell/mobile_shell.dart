import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/library_service.dart';
import '../screens/history_screen.dart';
import '../screens/home_library_screen.dart';
import '../screens/import_screen.dart';
import '../screens/liked_screen.dart';
import '../screens/playlists_screen.dart';
import '../widgets/mobile_player_bar.dart';

/// Android root shell: NavigationBar (Material 3) + persistent mini-player.
///
/// Each tab is wrapped in its own [Navigator] so deep navigation (e.g. tapping
/// into a playlist) doesn't replace the bottom nav and doesn't leak across
/// tabs. The Android system back button pops the active tab's stack first,
/// then defers to the OS to close the app — handled by [PopScope] below.
///
/// All five tabs from the Windows shell are kept: Library (home), Liked,
/// History, Playlists, and Import (instead of the desktop "Search / import"
/// which doubles as a search field).
class MobileShell extends StatefulWidget {
  /// Creates the mobile shell.
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  /// Index of the currently selected bottom tab.
  int _index = 0;

  /// Per-tab navigator keys so each tab keeps its own back stack.
  final List<GlobalKey<NavigatorState>> _navKeys =
      List.generate(5, (_) => GlobalKey<NavigatorState>());

  static const _tabs = <_MobileTab>[
    _MobileTab(
      label: 'Library',
      icon: Icons.library_music_outlined,
      activeIcon: Icons.library_music,
    ),
    _MobileTab(
      label: 'Liked',
      icon: Icons.favorite_border,
      activeIcon: Icons.favorite,
    ),
    _MobileTab(
      label: 'History',
      icon: Icons.history_outlined,
      activeIcon: Icons.history,
    ),
    _MobileTab(
      label: 'Playlists',
      icon: Icons.queue_music_outlined,
      activeIcon: Icons.queue_music,
    ),
    _MobileTab(
      label: 'Import',
      icon: Icons.add_circle_outline,
      activeIcon: Icons.add_circle,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LibraryService>().refreshAll();
    });
  }

  Widget _rootForTab(int i) {
    return switch (i) {
      0 => const HomeLibraryScreen(),
      1 => const LikedScreen(),
      2 => const HistoryScreen(),
      3 => const PlaylistsScreen(),
      4 => const ImportScreen(),
      _ => const SizedBox.shrink(),
    };
  }

  Future<bool> _onWillPop() async {
    // First, try popping the inner-tab navigator. If it can pop, consume the
    // back gesture. Otherwise, let the system close the app.
    final nav = _navKeys[_index].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onWillPop();
        // We intentionally do not auto-exit on the second back press;
        // letting the user press back again triggers the OS-level pop.
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: List.generate(_tabs.length, (i) {
              return Navigator(
                key: _navKeys[i],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  builder: (_) => _rootForTab(i),
                  settings: settings,
                ),
              );
            }),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MobilePlayerBar(),
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final t in _tabs)
                    NavigationDestination(
                      icon: Icon(t.icon),
                      selectedIcon: Icon(t.activeIcon),
                      label: t.label,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTab {
  const _MobileTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}
