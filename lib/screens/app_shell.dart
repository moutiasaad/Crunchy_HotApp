import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/cart_controller.dart';
import '../theme/theme.dart';
import '../widgets/widgets.dart';
import 'cart_screen.dart';
import 'home_screen.dart';
import 'menu_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

/// The main navigation shell.
///
/// Home / Menu / Cart / Orders / Profile all live inside a single Scaffold —
/// switching tabs is a `setState` on the [IndexedStack] index, not a route
/// push. That way scroll positions, controllers and pagination state stay
/// alive when the user hops between tabs (Instagram / Twitter pattern).
///
/// Child screens (Detail, Rewards, Address, Branches, Offers, Favourites …)
/// still push on the root navigator — they render full-screen over the
/// shell — so `Navigator.pop(context)` returns to whichever tab was active.
///
/// Cross-tab jumps from anywhere: `AppShell.switchTo(context, 2)`.
class AppShell extends StatefulWidget {
  final int initialTab;
  const AppShell({super.key, this.initialTab = 0});

  /// Programmatically switch the shell to `index`. Walks up the widget tree
  /// looking for the nearest [_AppShellState]. No-op when the caller isn't
  /// inside a shell (e.g. from a modal-gated Login flow).
  static void switchTo(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_AppShellState>();
    state?._switchTab(index);
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _tab = widget.initialTab;

  /// Notifiers per tab so re-tapping the current tab can trigger a
  /// "scroll to top" from the tab's own state without needing keys or
  /// InheritedWidgets. Tabs listen to their own notifier.
  final Map<int, ChangeNotifier> _retap = {
    0: ChangeNotifier(),
    1: ChangeNotifier(),
    2: ChangeNotifier(),
    3: ChangeNotifier(),
    4: ChangeNotifier(),
  };

  /// Fires when the shell switches INTO a tab from a different tab. Tabs
  /// listen to their own notifier and refresh their data. Does NOT fire on
  /// re-tap (that's what [_retap] is for).
  final Map<int, ChangeNotifier> _activate = {
    0: ChangeNotifier(),
    1: ChangeNotifier(),
    2: ChangeNotifier(),
    3: ChangeNotifier(),
    4: ChangeNotifier(),
  };

  static const _shellTabRoot = '__ch_shell_tab__';

  @override
  void dispose() {
    for (final n in _retap.values) {
      n.dispose();
    }
    for (final n in _activate.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _switchTab(int index) {
    if (index == _tab) {
      // Re-tap on the currently-active tab → fire the "scroll to top" pulse.
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      _retap[index]!.notifyListeners();
      return;
    }
    setState(() => _tab = index);
    // Post-frame: the tab's `_TabActivateScope` provides `_activate[_tab]`,
    // and dependent screens (Cart, Home, Menu, Profile) re-subscribe to the
    // new notifier only after their `didChangeDependencies` fires — which
    // happens during the rebuild triggered by the setState above. Firing
    // synchronously here would beat the re-subscription and the tab we
    // just switched into would miss the pulse.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      _activate[index]!.notifyListeners();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: CH.cream,
        // extendBody so tab bodies with bottom-anchored CTAs don't fight
        // the shell's bottom nav — each tab decides its own bottom inset.
        body: _TabRetapScope(
          retap: _retap[_tab]!,
          child: _TabActivateScope(
            activate: _activate[_tab]!,
            child: IndexedStack(
            key: const PageStorageKey<String>(_shellTabRoot),
            index: _tab,
              children: const [
                _KeepAlive(child: HomeScreen()),
                _KeepAlive(child: MenuScreen()),
                _KeepAlive(child: CartScreen()),
                _KeepAlive(child: OrdersScreen()),
                _KeepAlive(child: ProfileScreen()),
              ],
            ),
          ),
        ),
        bottomNavigationBar: ChBottomNav(
          currentIndex: _tab,
          cartCount:    cart.count,
          onTap:        _switchTab,
        ),
      ),
    );
  }
}

/// Wraps a tab child so its `State` stays alive across `IndexedStack` index
/// changes. Without this an off-screen tab would still be built by the stack
/// but its `State` objects would be disposed on tab change.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Inherited notifier so tab bodies can listen for "re-tap" pulses from the
/// shell's bottom nav. Tabs read via `TabRetap.of(context)` and add a
/// listener to scroll-to-top / reset chip when it fires.
class _TabRetapScope extends InheritedNotifier<ChangeNotifier> {
  const _TabRetapScope({required ChangeNotifier retap, required super.child})
      : super(notifier: retap);
}

/// Public accessor for tab bodies:
///
/// ```dart
/// TabRetap.of(context)?.addListener(_scrollToTop);
/// ```
class TabRetap {
  TabRetap._();

  static ChangeNotifier? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_TabRetapScope>()
        ?.notifier;
  }
}

/// Inherited notifier that pulses when the shell switches INTO this tab
/// from a different tab. Home/Menu subscribe and call their controllers'
/// `refresh()` so the tab always shows fresh admin data on re-entry.
class _TabActivateScope extends InheritedNotifier<ChangeNotifier> {
  const _TabActivateScope({
    required ChangeNotifier activate,
    required super.child,
  }) : super(notifier: activate);
}

class TabActivate {
  TabActivate._();

  static ChangeNotifier? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_TabActivateScope>()
        ?.notifier;
  }
}
