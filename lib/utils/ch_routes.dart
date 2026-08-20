import 'package:flutter/material.dart';

/// Page-transition helpers.
///
/// The default Android `MaterialPageRoute` slides pages in from the trailing
/// edge — fine for stock apps but feels choppy when the shell owns the frame
/// and only the content should transition. These builders give every push a
/// consistent "shared-axis Y" feel: a short fade combined with a subtle
/// slide-up, so opening Detail / Rewards / Cart from any tab reads like a
/// modern app instead of a system push.
///
/// Hero animations still work — `PageRouteBuilder` participates in the
/// enclosing `HeroController` the same as `MaterialPageRoute`.
class ChRoutes {
  ChRoutes._();

  /// 260 ms fade + 20 dp slide-up. The go-to for opening a detail-ish screen
  /// (item detail, rewards, offers, address list, branches, favourites).
  static Route<T> slideUpFade<T extends Object?>(
    WidgetBuilder builder, {
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      transitionDuration:        const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => builder(ctx),
      transitionsBuilder: (ctx, anim, __, child) {
        // Reduce-motion aware — fall back to a plain fade for accessibility.
        final reduce = MediaQuery.disableAnimationsOf(ctx);
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        if (reduce) {
          return FadeTransition(opacity: curved, child: child);
        }
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end:   Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Plain 200 ms crossfade — right for overlays that shouldn't move (Search,
  /// Login-as-modal, Register-as-modal).
  static Route<T> fade<T extends Object?>(
    WidgetBuilder builder, {
    RouteSettings? settings,
    bool fullscreenDialog = false,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      transitionDuration:        duration,
      reverseTransitionDuration: duration,
      pageBuilder: (ctx, _, __) => builder(ctx),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }
}
