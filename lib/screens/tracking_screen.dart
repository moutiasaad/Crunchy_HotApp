import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/orders_controller.dart';
import '../models/models.dart';
import '../services/order_service.dart';
import '../theme/theme.dart';
import 'rating_screen.dart';

void _tLog(String msg) {
  if (kDebugMode) debugPrint('[Tracking] $msg');
}

/// Screen 14 — Order tracking (تتبّع الطلب). Map-free variant.
///
/// The spec's live map is replaced with a hero card (matches the web
/// version's simpler layout) — same 190 dp footprint, cream2 backdrop,
/// big status emoji + label + ETA. Everything else follows the spec:
/// header title/sub reflect the current status, the 4-step timeline
/// animates as the status advances, and the driver bar sits fixed at
/// the bottom (branch info before assignment, driver after).
///
/// Demo: [_TrackingScreenState] progresses the status via a `Timer`
/// (8 s per step) so the flow can be exercised without a backend. Swap
/// the timer for an `OrderService.pollStatus()` stream when the API is
/// wired.
class TrackingScreen extends StatefulWidget {
  final String    orderId;
  final OrderMode mode;
  final Branch    branch;
  final String?   deliveryAddress;

  const TrackingScreen({
    super.key,
    required this.orderId,
    required this.mode,
    required this.branch,
    this.deliveryAddress,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  OrderStatus  _status  = OrderStatus.received;
  DateTime     _placedAt = DateTime.now();
  final Map<OrderStatus, DateTime> _timestamps = {};
  Timer?       _pollTimer;
  bool         _polling = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  /// Poll cadence — dropped from 20 s → 10 s so an admin's status change
  /// reaches the customer's screen within a reasonable window. If we ever
  /// wire a WebSocket / server-side FCM data push, this becomes a safety
  /// net rather than the primary channel.
  static const Duration _pollInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _placedAt = DateTime.now();
    _timestamps[OrderStatus.received] = _placedAt;

    // Poll immediately on mount, then every 10 s.
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());

    // iOS suspends Dart Timers when the app goes to background. Without
    // this, coming back to the screen after even a short lockscreen visit
    // shows a stale status until the next tick fires — which is the exact
    // "admin changed it but my app still says preparing" symptom.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Fresh eyes on the screen → force an immediate poll so any status
      // change made while we were backgrounded is picked up before the
      // periodic timer's next tick.
      _poll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// One `GET /orders/{number}` round-trip → server-authoritative status.
  Future<void> _poll() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final data = await context.read<OrderService>().show(widget.orderId);
      if (!mounted) return;
      final serverStatus = Order.parseStatus(data['status'] as String?);
      _tLog('poll → server status="${data['status']}"  → $serverStatus');

      if (serverStatus == _status) return;

      HapticFeedback.selectionClick();
      setState(() {
        _status = serverStatus;
        _timestamps.putIfAbsent(_status, () => DateTime.now());
      });

      if (_status == OrderStatus.delivered) {
        _pollTimer?.cancel();
        _onDelivered();
      }
    } catch (e) {
      _tLog('poll ✗ $e');
      // Silent — next tick will retry. Screen keeps the last known state.
    } finally {
      _polling = false;
    }
  }

  /// Demo shortcut — tapping a step in the timeline jumps the order there.
  /// Useful for reviewing the flow (and reaching the Rating handoff) without
  /// waiting for real server progression. Locally-only — server status
  /// will re-overwrite on the next poll.
  void _jumpTo(OrderStatus target) {
    if (_status == target) {
      if (target == OrderStatus.delivered) _onDelivered();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _status = target;
      _timestamps[_status] = DateTime.now();
    });
    if (target == OrderStatus.delivered) {
      _pollTimer?.cancel();
      _onDelivered();
    }
  }

  Future<void> _onDelivered() async {
    HapticFeedback.mediumImpact();

    // Server has flipped this order to delivered; sync the history list so
    // the Orders tab already shows it as complete by the time the user
    // finishes Rating and lands there. Fire-and-forget.
    unawaited(context.read<OrdersController>().refresh());

    // 1.2 s success flash on the tracking screen before handing off.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    // Spec §7 + Rating spec §1: fade-through 240 ms to Rating.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => RatingScreen(
          orderId:       widget.orderId,
          mode:          widget.mode,
          // TODO: thread real PayMethod from Checkout once orders API is wired.
          paymentIsCash: true,
        ),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  // ─────────────────── Derived data ───────────────────
  bool get _isPickup => widget.mode == OrderMode.pickup;
  bool get _driverAssigned =>
      _status == OrderStatus.onTheWay || _status == OrderStatus.delivered;

  /// Rough ETA in minutes, rounded to 5.
  int get _etaMinutes {
    if (_status == OrderStatus.delivered) return 0;
    final base = switch (_status) {
      OrderStatus.received   => 25,
      OrderStatus.preparing  => 15,
      OrderStatus.onTheWay   => 8,
      _                       => 0,
    };
    // Snap to nearest 5.
    return ((base / 5).round() * 5).clamp(0, 60);
  }

  String get _statusEmoji => switch (_status) {
        OrderStatus.received  => '📥',
        OrderStatus.preparing => '🍳',
        OrderStatus.onTheWay  => _isPickup ? '🛍️' : '🛵',
        OrderStatus.delivered => _isPickup ? '✅' : '🏠',
        _                      => '📦',
      };

  String get _titleAr => switch (_status) {
        OrderStatus.received  => 'تم استلام طلبك',
        OrderStatus.preparing => 'جاري تحضير طلبك',
        OrderStatus.onTheWay  => _isPickup ? 'طلبك جاهز للاستلام' : 'طلبك بالطريق',
        OrderStatus.delivered => _isPickup ? 'تم الاستلام 🎉' : 'وصل طلبك 🎉',
        _                      => 'طلبك',
      };

  String get _etaLine {
    if (_status == OrderStatus.delivered) return 'شكراً لطلبك من كرانشي هت';
    final eta = _etaMinutes;
    if (eta <= 0) return 'وصول قريباً جداً';
    return _isPickup
        ? 'الاستلام خلال ~$eta دقيقة'
        : 'الوصول خلال ~$eta دقيقة';
  }

  String get _subLine =>
      'طلب #${widget.orderId}  ·  $_etaLine';

  // ─────────────────── Timeline steps ───────────────────
  List<_Step> get _steps {
    _StepState st(int idx) {
      final ord = _status.index;
      if (ord > idx) return _StepState.done;
      if (ord == idx) return _StepState.current;
      return _StepState.upcoming;
    }

    final now = DateTime.now();

    String? metaFor(int idx, _StepState s) {
      if (s == _StepState.done) {
        final t = _timestamps[OrderStatus.values[idx]];
        return t == null ? null : _fmtTime(t);
      }
      if (s == _StepState.current) {
        return switch (OrderStatus.values[idx]) {
          OrderStatus.received  => 'استلمنا طلبك · ${_fmtTime(now)}',
          OrderStatus.preparing => 'المطبخ يجهّز طلبك الآن',
          OrderStatus.onTheWay  => _isPickup ? 'الطلب جاهز في الفرع' : 'السائق بالطريق إليك',
          OrderStatus.delivered => 'تم بنجاح',
          _                      => null,
        };
      }
      // upcoming — show estimate only for the next step
      final nextIndex = _status.index + 1;
      if (idx == nextIndex && _status != OrderStatus.delivered) {
        return '~ $_etaMinutes دقيقة';
      }
      return null;
    }

    // Order of statuses matches the vertical order of steps in the timeline.
    const stepOrder = [
      OrderStatus.received,
      OrderStatus.preparing,
      OrderStatus.onTheWay,
      OrderStatus.delivered,
    ];
    VoidCallback tapFor(int idx) => () => _jumpTo(stepOrder[idx]);

    return [
      _Step(
        labelAr: 'تم استلام الطلب',
        icon: '✓',
        state: st(0),
        metaAr: metaFor(0, st(0)),
        onTap: tapFor(0),
      ),
      _Step(
        labelAr: 'قيد التحضير',
        icon: '🍳',
        state: st(1),
        metaAr: metaFor(1, st(1)),
        onTap: tapFor(1),
      ),
      _Step(
        labelAr: _isPickup ? 'جاهز للاستلام' : 'في الطريق إليك',
        icon: _isPickup ? '🛍️' : '🛵',
        state: st(2),
        metaAr: metaFor(2, st(2)),
        onTap: tapFor(2),
      ),
      _Step(
        labelAr: _isPickup ? 'تم الاستلام' : 'تم التوصيل',
        icon: _isPickup ? '✅' : '🏠',
        state: st(3),
        metaAr: metaFor(3, st(3)),
        onTap: tapFor(3),
      ),
    ];
  }

  /// `3:14 م` / `10:22 ص`.
  static String _fmtTime(DateTime t) {
    final hour12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final minute = t.minute.toString().padLeft(2, '0');
    final mer    = t.hour < 12 ? 'ص' : 'م';
    return '$hour12:$minute $mer';
  }

  void _todoSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 108),
        duration: const Duration(milliseconds: 2000),
      ));
  }

  // ─────────────────── Build ───────────────────
  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: PopScope(
          // Back always goes Home (spec §1) — never back to Checkout.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
          child: Scaffold(
            backgroundColor: CH.cream,
            body: Column(
              children: [
                // ────── Header ──────
                Padding(
                  padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 14),
                  child: Row(
                    children: [
                      _IconBoxButton(
                        glyph: isArabic ? '→' : '←',
                        onTap: () => Navigator.of(context)
                            .popUntil((r) => r.isFirst),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (c, a) =>
                              FadeTransition(opacity: a, child: c),
                          child: Column(
                            key: ValueKey(_status),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_titleAr,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.changa(
                                  fontSize: 22, fontWeight: FontWeight.w800, color: CH.ink)),
                              const SizedBox(height: 2),
                              Text(_subLine,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(
                                  fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RefreshButton(spinning: _polling, onTap: _poll),
                    ],
                  ),
                ),

                // ────── Hero card (replaces the map) ──────
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                  child: _HeroCard(
                    emoji: _statusEmoji,
                    title: _titleAr,
                    etaLine: _etaLine,
                    delivered: _status == OrderStatus.delivered,
                  ),
                ),

                // ────── Timeline (pull-to-refresh forces an immediate poll) ──────
                Expanded(
                  child: RefreshIndicator(
                    color: CH.hot,
                    onRefresh: _poll,
                    child: SingleChildScrollView(
                      // AlwaysScrollable so the pull gesture works even when
                      // the timeline content is short.
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsetsDirectional.fromSTEB(20, 22, 20, 22),
                      child: _Timeline(steps: _steps, pulse: _pulse),
                    ),
                  ),
                ),

                // ────── Driver / branch bar ──────
                _DriverBar(
                  assigned:   _driverAssigned,
                  branch:     widget.branch,
                  onCallBranch: () => _todoSnack('الاتصال بالفرع (${widget.branch.phone}) قريباً'),
                  onCallDriver: () => _todoSnack('الاتصال بالسائق قريباً'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Step model
// ══════════════════════════════════════════════════════════════════
enum _StepState { done, current, upcoming }

class _Step {
  final String     labelAr;
  final String     icon;
  final _StepState state;
  final String?    metaAr;
  final VoidCallback? onTap;   // demo shortcut — jump to this step
  const _Step({
    required this.labelAr, required this.icon, required this.state,
    this.metaAr, this.onTap,
  });
}

// ══════════════════════════════════════════════════════════════════
//  Hero card — replaces the interactive map
// ══════════════════════════════════════════════════════════════════
class _HeroCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String etaLine;
  final bool   delivered;
  const _HeroCard({
    required this.emoji, required this.title,
    required this.etaLine, required this.delivered,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      height: 190,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: delivered ? const Color(0xFFE7F7EC) : CH.cream2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle radial highlight in the trailing-bottom corner.
          const PositionedDirectional(
            bottom: -30, end: -30, width: 120, height: 120,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x1AEE4E1B), Colors.transparent],
                    stops: [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // FittedBox lets the (emoji + title + eta) stack shrink to fit the
          // fixed 190-tall card if font metrics or text scaling push past it.
          // Was overflowing by ~12 px on some phones (SM A075F, textScale 1.0).
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (c, a) => ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1.0).animate(a),
                        child: FadeTransition(opacity: a, child: c),
                      ),
                      child: Text(
                        emoji,
                        key: ValueKey(emoji),
                        style: const TextStyle(fontSize: 64, height: 1.0),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(title,
                      style: GoogleFonts.changa(
                        fontSize: 18, fontWeight: FontWeight.w800,
                        color: delivered ? CH.green : CH.ink)),
                    const SizedBox(height: 4),
                    Text(etaLine,
                      style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w700, color: CH.muted)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Timeline — 4 vertical steps, connectors between them
// ══════════════════════════════════════════════════════════════════
class _Timeline extends StatelessWidget {
  final List<_Step> steps;
  final AnimationController pulse;
  const _Timeline({required this.steps, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'مراحل الطلب',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < steps.length; i++)
            _TimelineRow(
              step: steps[i],
              pulse: pulse,
              isLast: i == steps.length - 1,
              // Connector color per spec §5: green above completed steps,
              // #E6D6C6 otherwise. i.e. the connector between i and i+1
              // goes green when step[i] is done.
              connectorColor: steps[i].state == _StepState.done
                  ? CH.green
                  : const Color(0xFFE6D6C6),
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final _Step step;
  final AnimationController pulse;
  final bool isLast;
  final Color connectorColor;
  const _TimelineRow({
    required this.step, required this.pulse,
    required this.isLast, required this.connectorColor,
  });

  Color get _circleColor => switch (step.state) {
        _StepState.done     => CH.green,
        _StepState.current  => CH.hot,
        _StepState.upcoming => const Color(0xFFE6D6C6),
      };

  Color get _labelColor => switch (step.state) {
        _StepState.done     => CH.ink,
        _StepState.current  => CH.hot,
        _StepState.upcoming => const Color(0xFFB3A396),
      };

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: step.onTap != null,
      label: step.labelAr,
      hint: 'اضغط للانتقال لهذه المرحلة',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: step.onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: CH.hot.withValues(alpha: 0.06),
          child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Circle + connector column ───
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _StepCircle(
                  color: _circleColor,
                  icon: step.icon,
                  pulsing: step.state == _StepState.current && !reduceMotion,
                  pulse: pulse,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      constraints: const BoxConstraints(minHeight: 26),
                      color: connectorColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // ─── Label + meta ───
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: isLast ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(step.labelAr,
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _labelColor)),
                  if (step.metaAr != null) ...[
                    const SizedBox(height: 2),
                    Text(step.metaAr!,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CH.muted)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
          ),
        ),
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  final Color color;
  final String icon;
  final bool pulsing;
  final AnimationController pulse;
  const _StepCircle({
    required this.color, required this.icon,
    required this.pulsing, required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      width: 28, height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Text(icon,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white,
          fontFamilyFallback: const ['Cairo'],
          height: 1,
        )),
    );

    if (!pulsing) return inner;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        // 1 → 1.08 → 1 (via reverse-repeat)
        final t = Curves.easeInOut.transform(pulse.value);
        final scale = 1 + (0.08 * t);
        return Transform.scale(scale: scale, child: child);
      },
      child: inner,
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Driver / branch bar (fixed bottom)
// ══════════════════════════════════════════════════════════════════
class _DriverBar extends StatelessWidget {
  final bool     assigned;
  final Branch   branch;
  final VoidCallback onCallBranch;
  final VoidCallback onCallDriver;
  const _DriverBar({
    required this.assigned, required this.branch,
    required this.onCallBranch, required this.onCallDriver,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(
        top: 14, left: 20, right: 20,
        bottom: 20 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: CH.navTopBorder, width: 1)),
      ),
      child: assigned ? _DriverRow(onCall: onCallDriver) : _BranchRow(branch: branch, onCall: onCallBranch),
    );
  }
}

class _BranchRow extends StatelessWidget {
  final Branch branch;
  final VoidCallback onCall;
  const _BranchRow({required this.branch, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: CH.cream2, borderRadius: BorderRadius.circular(23)),
          alignment: Alignment.center,
          child: const Text('🐓', style: TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(branch.nameAr,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
              const SizedBox(height: 2),
              Text(branch.addressAr,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _CallButton(label: 'اتصل بالفرع', onTap: onCall),
      ],
    );
  }
}

class _DriverRow extends StatelessWidget {
  final VoidCallback onCall;
  const _DriverRow({required this.onCall});

  @override
  Widget build(BuildContext context) {
    // Demo driver until dispatch is wired.
    const name  = 'أبو أحمد — السائق';
    const meta  = 'دراجة نارية · لوحة 4821';
    const init  = 'أ';

    return Row(
      children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: CH.cream2, borderRadius: BorderRadius.circular(23)),
          alignment: Alignment.center,
          child: Text(init,
            style: GoogleFonts.changa(
              fontSize: 20, fontWeight: FontWeight.w800, color: CH.muted)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: _DriverText(name: name, meta: meta),
        ),
        const SizedBox(width: 10),
        _CallButton(label: 'اتصل بالسائق', onTap: onCall),
      ],
    );
  }
}

class _DriverText extends StatelessWidget {
  final String name;
  final String meta;
  const _DriverText({required this.name, required this.meta});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
          const SizedBox(height: 2),
          // meta = "دراجة نارية · لوحة 4821" — Arabic-primary. Leave in the
          // ambient RTL direction; the plate digits render as an LTR sub-run
          // automatically per Unicode bidi. Wrapping the whole string in
          // Directionality.ltr would flip the Arabic phrase's visual order.
          Text(meta,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
        ],
      );
}

class _CallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CallButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: label,
        child: SizedBox(
          width: 44, height: 44,
          child: Material(
            color: CH.green,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(13),
              child: const Center(
                child: Icon(Icons.phone_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Refresh button — forces an immediate `GET /orders/{n}` poll.
//  Spins the icon while a poll is in flight so users see feedback.
// ══════════════════════════════════════════════════════════════════
class _RefreshButton extends StatefulWidget {
  final bool spinning;
  final Future<void> Function() onTap;
  const _RefreshButton({required this.spinning, required this.onTap});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didUpdateWidget(covariant _RefreshButton old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.spinning && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'تحديث حالة الطلب',
      child: SizedBox(
        width: 40, height: 40,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => widget.onTap(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CH.line, width: 1.5),
              ),
              alignment: Alignment.center,
              child: RotationTransition(
                turns: _spin,
                child: const Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: CH.hot,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Top-bar icon button
// ══════════════════════════════════════════════════════════════════
class _IconBoxButton extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  const _IconBoxButton({required this.glyph, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'الرئيسية',
        child: SizedBox(
          width: 40, height: 40,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CH.line, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(glyph,
                  style: GoogleFonts.cairo(
                    fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink)),
              ),
            ),
          ),
        ),
      );
}
