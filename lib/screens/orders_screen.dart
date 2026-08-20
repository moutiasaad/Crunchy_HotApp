import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../controllers/cart_controller.dart';
import '../controllers/orders_controller.dart';
import '../models/models.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import '../utils/ch_routes.dart';
import '../widgets/widgets.dart';
import 'app_shell.dart';
import 'login_screen.dart';
import 'rating_screen.dart';
import 'tracking_screen.dart';

/// Screen 17 — Order history (طلباتي). Tab 4 of 5.
///
/// Guest → sign-in prompt. Signed-in → active-order banner (if live) +
/// history list grouped by month, each row Rate / Reorder-able + tappable
/// for the details sheet.
class OrdersScreen extends StatefulWidget {
  /// `true` when pushed from Profile (adds a back button); `false` when
  /// entered via the bottom tab.
  final bool pushed;
  const OrdersScreen({super.key, this.pushed = false});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final ScrollController _scroll = ScrollController();
  ChangeNotifier? _retap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLoad();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = TabRetap.of(context);
    if (current != _retap) {
      _retap?.removeListener(_scrollToTop);
      _retap = current;
      _retap?.addListener(_scrollToTop);
    }
  }

  @override
  void dispose() {
    _retap?.removeListener(_scrollToTop);
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  void _maybeLoad() {
    final auth   = context.read<AuthController>();
    final orders = context.read<OrdersController>();
    // Always refetch on mount so history reflects orders placed during this
    // session (Checkout also nudges a background refresh, but this covers
    // the case where the user was on another tab when it fired).
    if (auth.isSignedIn && !orders.loading) {
      orders.load();
    }
  }

  Future<void> _promptSignIn() async {
    final signed = await Navigator.of(context).push<bool>(
      ChRoutes.slideUpFade(
        (_) => const LoginScreen(returnOnSuccess: true),
        fullscreenDialog: true,
      ),
    );
    if (signed == true && mounted) {
      _maybeLoad();
    }
  }

  Future<void> _onReorder(Order o) async {
    if (!o.canReorder) return;
    HapticFeedback.selectionClick();

    final cart = context.read<CartController>();
    for (final line in o.lines) {
      cart.add(
        line.product,
        quantity: line.quantity,
        spice:    line.spice,
        addons:   line.addons,
        note:     line.note,
      );
    }
    if (!mounted) return;

    AppShell.switchTo(context, 2);
  }

  void _onRate(Order o) {
    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => RatingScreen(
        orderId:       o.orderNumber,
        mode:          o.mode,
        paymentIsCash: o.paymentMethod == PayMethod.cash,
        heroEmoji:     o.lines.first.product.emoji,
      )),
    );
  }

  void _onOpenActive(Order o) {
    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => TrackingScreen(
        orderId: o.orderNumber,
        mode:    o.mode,
        branch:  o.branch ?? const Branch(
          id: 'default', nameAr: '', nameEn: '', shortNameAr: '',
          addressAr: '', phone: '', isOpen: true, hoursText: '',
          lat: 0, lng: 0),
        deliveryAddress: o.addressLine,
      )),
    );
  }

  Future<void> _openDetails(Order o) => showOrderDetailsSheet(
        context, o,
        onReorder: () => _onReorder(o),
      );

  // ─────────────────── Build ───────────────────
  @override
  Widget build(BuildContext context) {
    final isSignedIn = context.watch<AuthController>().isSignedIn;
    final topInset   = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Scaffold(
          backgroundColor: CH.cream,
          body: SafeArea(
            bottom: false,
            child: !isSignedIn
                ? _GuestState(onSignIn: _promptSignIn)
                : _SignedInBody(
                    scroll:    _scroll,
                    pushed:    widget.pushed,
                    topInset:  topInset,
                    onRate:    _onRate,
                    onReorder: _onReorder,
                    onOpenActive: _onOpenActive,
                    onOpenDetails: _openDetails,
                    onBrowseMenu: () => AppShell.switchTo(context, 1),
                  ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Guest state
// ══════════════════════════════════════════════════════════════════
class _GuestState extends StatelessWidget {
  final VoidCallback onSignIn;
  const _GuestState({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👤', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            Text('سجّل دخولك لتشوف طلباتك',
              textAlign: TextAlign.center,
              style: GoogleFonts.changa(
                fontSize: 18, fontWeight: FontWeight.w800, color: CH.ink)),
            const SizedBox(height: 6),
            Text('لما تدخل، رح تلاقي كل طلباتك السابقة هون.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 14, color: CH.muted, height: 1.6)),
            const SizedBox(height: 20),
            _PrimaryPill(label: 'تسجيل الدخول', onTap: onSignIn),
          ],
        ),
      ),
    );
  }
}

class _PrimaryPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryPill({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: ChShadows.primaryButton,
        ),
        child: Material(
          color: CH.hot,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              child: Text(label,
                style: GoogleFonts.changa(
                  fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Signed-in body — active + history list
// ══════════════════════════════════════════════════════════════════
class _SignedInBody extends StatelessWidget {
  final ScrollController scroll;
  final bool             pushed;
  final double           topInset;
  final void Function(Order) onRate;
  final void Function(Order) onReorder;
  final void Function(Order) onOpenActive;
  final void Function(Order) onOpenDetails;
  final VoidCallback         onBrowseMenu;

  const _SignedInBody({
    required this.scroll, required this.pushed, required this.topInset,
    required this.onRate, required this.onReorder,
    required this.onOpenActive, required this.onOpenDetails,
    required this.onBrowseMenu,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<OrdersController>();

    return RefreshIndicator(
      color: CH.hot,
      onRefresh: () => context.read<OrdersController>().refresh(),
      child: CustomScrollView(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: 8, bottom: 14),
            sliver: SliverToBoxAdapter(child: _Header(pushed: pushed)),
          ),
          if (ctrl.loading && !ctrl.hasLoaded)
            const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: _LoadingList()),
            )
          else if (ctrl.error != null && ctrl.orders.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _OrdersErrorState(
                msg: ctrl.error!,
                onRetry: () => context.read<OrdersController>().refresh(),
              ),
            )
          else if (ctrl.orders.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(onBrowse: onBrowseMenu),
            )
          else
            ..._buildPopulatedSlivers(ctrl),
          const SliverPadding(padding: EdgeInsets.only(bottom: 26)),
        ],
      ),
    );
  }

  List<Widget> _buildPopulatedSlivers(OrdersController ctrl) {
    final active  = ctrl.activeOrder;
    final history = ctrl.historyOrders
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final entries = <Widget>[];

    if (active != null) {
      entries.add(SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
        sliver: SliverToBoxAdapter(child: _ActiveOrderCard(
          order: active,
          onTap: () => onOpenActive(active),
        )),
      ));
    }

    // Group history by (year, month) → labels between groups.
    String? currentGroup;
    int visibleIndex = 0;
    for (final o in history) {
      final group = _groupLabel(o.createdAt);
      if (group != currentGroup) {
        currentGroup = group;
        entries.add(SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Text(group,
              style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
          ),
        ));
      }
      entries.add(SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
        sliver: SliverToBoxAdapter(
          child: _StaggeredEnter(
            index: visibleIndex,
            child: _OrderCard(
              order:     o,
              onTap:     () => onOpenDetails(o),
              onRate:    o.canRate    ? () => onRate(o)    : null,
              onReorder: o.canReorder ? () => onReorder(o) : null,
            ),
          ),
        ),
      ));
      visibleIndex++;
    }
    return entries;
  }

  /// "هذا الشهر" for current month, else "تموز 2026" with Levantine names.
  static String _groupLabel(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month) return 'هذا الشهر';
    return '${_monthName(t.month)} ${t.year}';
  }

  static String _monthName(int m) => switch (m) {
        1  => 'كانون الثاني',
        2  => 'شباط',
        3  => 'آذار',
        4  => 'نيسان',
        5  => 'أيار',
        6  => 'حزيران',
        7  => 'تموز',
        8  => 'آب',
        9  => 'أيلول',
        10 => 'تشرين الأول',
        11 => 'تشرين الثاني',
        12 => 'كانون الأول',
        _  => '',
      };
}

// ══════════════════════════════════════════════════════════════════
//  Header
// ══════════════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  final bool pushed;
  const _Header({required this.pushed});

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
      child: Row(
        children: [
          if (pushed) ...[
            _IconBoxButton(
              glyph: isArabic ? '→' : '←',
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
          ],
          Text('طلباتي',
            style: GoogleFonts.changa(
              fontSize: 25, fontWeight: FontWeight.w800, color: CH.ink)),
        ],
      ),
    );
  }
}

class _IconBoxButton extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  const _IconBoxButton({required this.glyph, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'رجوع',
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

// ══════════════════════════════════════════════════════════════════
//  Error state
// ══════════════════════════════════════════════════════════════════
class _OrdersErrorState extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _OrdersErrorState({required this.msg, required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 14),
              Text(msg,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w700, color: CH.ink, height: 1.6)),
              const SizedBox(height: 16),
              ChDarkButton(
                label: 'إعادة المحاولة',
                onPressed: onRetry,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ],
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Empty state
// ══════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final VoidCallback onBrowse;
  const _EmptyState({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 60, 40, 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧾', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            Text('ما عندك طلبات بعد',
              textAlign: TextAlign.center,
              style: GoogleFonts.changa(
                fontSize: 18, fontWeight: FontWeight.w800, color: CH.ink)),
            const SizedBox(height: 6),
            Text('أول طلب على بُعد ضغطة.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 14, color: CH.muted, height: 1.6)),
            const SizedBox(height: 18),
            ChDarkButton(
              label: 'تصفّح المنيو',
              onPressed: onBrowse,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Loading skeleton — 4 fake cards
// ══════════════════════════════════════════════════════════════════
class _LoadingList extends StatelessWidget {
  const _LoadingList();
  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (int i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CardSkeleton(),
            ),
        ],
      );
}

class _CardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          color: const Color(0xFF2E1D12).withValues(alpha: 0.05),
          offset: const Offset(0, 6), blurRadius: 18)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: CH.cream2, borderRadius: BorderRadius.circular(14)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 14, width: 200, color: CH.cream2),
                    const SizedBox(height: 8),
                    Container(height: 10, width: 120, color: CH.cream2),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: CH.cream2),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(height: 14, width: 80, color: CH.cream2),
              Row(children: [
                Container(height: 30, width: 60, color: CH.cream2),
                const SizedBox(width: 8),
                Container(height: 30, width: 80, color: CH.cream2),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Active order card
// ══════════════════════════════════════════════════════════════════
class _ActiveOrderCard extends StatefulWidget {
  final Order order;
  final VoidCallback onTap;
  const _ActiveOrderCard({required this.order, required this.onTap});
  @override
  State<_ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends State<_ActiveOrderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _statusTitle(OrderStatus s) => switch (s) {
        OrderStatus.received  => 'تم استلام طلبك',
        OrderStatus.preparing => 'جاري تحضير طلبك',
        OrderStatus.onTheWay  => 'طلبك بالطريق',
        _                      => '',
      };

  int _etaMinutes(OrderStatus s) => switch (s) {
        OrderStatus.received  => 25,
        OrderStatus.preparing => 15,
        OrderStatus.onTheWay  => 8,
        _                      => 0,
      };

  @override
  Widget build(BuildContext context) {
    final o        = widget.order;
    final title    = _statusTitle(o.status);
    final eta      = _etaMinutes(o.status);
    final subLine  = '#${o.orderNumber} · وصول خلال ~$eta دقيقة';
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true, liveRegion: true,
      label: '$title, $subLine',
      child: Material(
        color: CH.char,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        // 0.10 ↔ 0.18 opacity per spec §3.
                        final t = reduceMotion ? 0.0 : Curves.easeInOut.transform(_pulse.value);
                        final a = 0.10 + 0.08 * t;
                        return Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: a),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: child,
                        );
                      },
                      child: const Text('🛵', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.changa(
                              fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(subLine,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: const Color(0xFFA89684))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(isArabic ? '‹' : '›',
                      style: GoogleFonts.changa(
                        fontSize: 24, fontWeight: FontWeight.w800, color: CH.hot)),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress track
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    height: 4,
                    color: Colors.white.withValues(alpha: 0.14),
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: o.progress.clamp(0.0, 1.0),
                      child: Container(color: CH.hot),
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

// ══════════════════════════════════════════════════════════════════
//  Order card (history)
// ══════════════════════════════════════════════════════════════════
class _OrderCard extends StatefulWidget {
  final Order        order;
  final VoidCallback onTap;
  final VoidCallback? onRate;
  final VoidCallback? onReorder;

  const _OrderCard({
    required this.order, required this.onTap,
    required this.onRate, required this.onReorder,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.order;

    return Semantics(
      button: true,
      label: '${o.displayItems}, ${_dateAndTime(o.createdAt)}, ${_statusLabel(o.status)}, الإجمالي ${ChMoney.format(o.total)}',
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 0.98 : 1.0,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(
                  color: const Color(0xFF2E1D12).withValues(alpha: 0.05),
                  offset: const Offset(0, 6), blurRadius: 18)],
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _Thumb(order: o),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(o.displayItems,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
                            const SizedBox(height: 3),
                            Text(_dateAndTime(o.createdAt),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusTag(status: o.status),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 12),
                    child: _DashedHLine(),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(ChMoney.format(o.total),
                          style: GoogleFonts.changa(
                            fontSize: 16, fontWeight: FontWeight.w800, color: CH.ink)),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (o.rating != null)
                            _RatedPill(rating: o.rating!)
                          else if (widget.onRate != null)
                            _RateBtn(onTap: widget.onRate!),
                          if (widget.onReorder != null) ...[
                            const SizedBox(width: 8),
                            _ReorderBtn(onTap: widget.onReorder!),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // "5 تموز · 3:40 م"
  static String _dateAndTime(DateTime t) {
    final month = _SignedInBody._monthName(t.month);
    final hour12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final minute = t.minute.toString().padLeft(2, '0');
    final mer    = t.hour < 12 ? 'ص' : 'م';
    return '${t.day} $month · $hour12:$minute $mer';
  }

  static String _statusLabel(OrderStatus s) => switch (s) {
        OrderStatus.delivered => 'تم التوصيل',
        OrderStatus.cancelled => 'ملغى',
        OrderStatus.onTheWay  => 'بالطريق',
        OrderStatus.preparing => 'قيد التحضير',
        OrderStatus.received  => 'تم الاستلام',
      };
}

// ─── Thumb: single or 2×2 mosaic ─────────────────────────────
class _Thumb extends StatelessWidget {
  final Order order;
  const _Thumb({required this.order});

  @override
  Widget build(BuildContext context) {
    final lines = order.lines.take(4).toList();
    if (lines.length == 1) {
      return _ThumbTile(product: lines.first.product, size: 56);
    }
    return SizedBox(
      width: 56, height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 2, crossAxisSpacing: 2,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final l in lines) _ThumbTile(product: l.product, size: 27),
            // Pad to 4 if fewer items
            for (int i = lines.length; i < 4; i++)
              Container(color: CH.cream2),
          ],
        ),
      ),
    );
  }
}

class _ThumbTile extends StatelessWidget {
  final Product product;
  final double  size;
  const _ThumbTile({required this.product, required this.size});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: CH.cream2,
        borderRadius: size >= 40 ? BorderRadius.circular(14) : null,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: (product.imageUrl == null || product.imageUrl!.isEmpty)
          ? Text(product.emoji, style: TextStyle(fontSize: size * 0.55))
          : Image.network(
              product.imageUrl!,
              fit: BoxFit.cover, width: size, height: size,
              errorBuilder: (_, __, ___) =>
                  Text(product.emoji, style: TextStyle(fontSize: size * 0.55)),
            ),
    );
  }
}

// ─── Status tag ─────────────────────────────────────────────
class _StatusTag extends StatelessWidget {
  final OrderStatus status;
  const _StatusTag({required this.status});
  @override
  Widget build(BuildContext context) {
    final (bg, fg, text) = switch (status) {
      OrderStatus.delivered => (const Color(0x1F2FA84F), CH.green, 'تم التوصيل'),
      OrderStatus.cancelled => (const Color(0x1AE11D2A), CH.red,   'ملغى'),
      OrderStatus.onTheWay  => (const Color(0x1FEE4E1B), CH.hot,   'بالطريق'),
      OrderStatus.preparing => (const Color(0x1FEE4E1B), CH.hot,   'قيد التحضير'),
      OrderStatus.received  => (const Color(0x1F8A7A6E), CH.muted, 'تم الاستلام'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
        style: GoogleFonts.cairo(
          fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

// ─── Rate / Reorder / Rated pill buttons ────────────────────
class _RateBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _RateBtn({required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'تقييم',
        child: SizedBox(
          height: 44,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(11),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: CH.line, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text('تقييم',
                  style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w800, color: CH.ink)),
              ),
            ),
          ),
        ),
      );
}

class _ReorderBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _ReorderBtn({required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'أعد الطلب',
        child: SizedBox(
          height: 44,
          child: Material(
            color: CH.hot,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(11),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Center(
                  child: Text('أعد الطلب',
                    style: GoogleFonts.cairo(
                      fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      );
}

class _RatedPill extends StatelessWidget {
  final int rating;
  const _RatedPill({required this.rating});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('⭐ $rating',
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
      );
}

// ─── Dashed 1-px horizontal divider ─────────────────────────
class _DashedHLine extends StatelessWidget {
  const _DashedHLine();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1,
        child: CustomPaint(
          painter: _DashedHLinePainter(
            color: const Color(0xFFF0E4D6),
            dashLength: 5, gapLength: 4, strokeWidth: 1,
          ),
          child: const SizedBox.expand(),
        ),
      );
}

class _DashedHLinePainter extends CustomPainter {
  final Color  color;
  final double dashLength;
  final double gapLength;
  final double strokeWidth;
  _DashedHLinePainter({
    required this.color, required this.dashLength,
    required this.gapLength, required this.strokeWidth,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = strokeWidth;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dashLength).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += dashLength + gapLength;
    }
  }
  @override
  bool shouldRepaint(_DashedHLinePainter o) =>
      o.color != color || o.dashLength != dashLength ||
      o.gapLength != gapLength || o.strokeWidth != strokeWidth;
}

// ══════════════════════════════════════════════════════════════════
//  Staggered enter — fade up 8dp, first 6 rows only per spec §8
// ══════════════════════════════════════════════════════════════════
class _StaggeredEnter extends StatefulWidget {
  final int    index;
  final Widget child;
  const _StaggeredEnter({required this.index, required this.child});
  @override
  State<_StaggeredEnter> createState() => _StaggeredEnterState();
}

class _StaggeredEnterState extends State<_StaggeredEnter> {
  double _o  = 0;
  double _dy = 8;

  @override
  void initState() {
    super.initState();
    // Only stagger the first 6 items (spec §8).
    if (widget.index >= 6) {
      _o = 1;
      _dy = 0;
      return;
    }
    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) setState(() { _o = 1; _dy = 0; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) return widget.child;
    return AnimatedOpacity(
      opacity: _o,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: Offset(0, _dy / 100),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Details sheet
// ══════════════════════════════════════════════════════════════════
Future<void> showOrderDetailsSheet(
  BuildContext context,
  Order order, {
  required VoidCallback onReorder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _OrderDetailsSheet(order: order, onReorder: onReorder),
  );
}

class _OrderDetailsSheet extends StatelessWidget {
  final Order order;
  final VoidCallback onReorder;
  const _OrderDetailsSheet({required this.order, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: CH.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                // Head
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text('#${order.orderNumber}',
                          style: GoogleFonts.changa(
                            fontSize: 20, fontWeight: FontWeight.w800, color: CH.ink)),
                      ),
                    ),
                    _StatusTag(status: order.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_OrderCardState._dateAndTime(order.createdAt),
                  style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
                const SizedBox(height: 22),

                // Lines
                for (final l in order.lines) ...[
                  _DetailLine(line: l),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 12),

                // Fulfilment
                _DetailBlock(
                  emoji: order.isPickup ? '🏬' : '📍',
                  title: order.isPickup ? 'الاستلام من' : 'التوصيل إلى',
                  body: order.isPickup
                      ? (order.branch?.nameAr ?? '—')
                      : (order.addressLine ?? '—'),
                ),
                const SizedBox(height: 12),

                // Payment
                _DetailBlock(
                  emoji: order.paymentMethod.emoji,
                  title: 'الدفع',
                  body:  order.paymentMethod == PayMethod.cash
                      ? '${order.paymentMethod.labelAr} · مدفوع نقداً'
                      : order.paymentMethod.labelAr,
                ),
                const SizedBox(height: 22),

                // Totals
                _TotalsBlock(order: order),
                const SizedBox(height: 22),

                // Actions
                if (order.canReorder)
                  _PrimaryFull(label: 'أعد الطلب', onTap: () {
                    Navigator.of(context).pop();
                    onReorder();
                  }),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _todo(context, 'واتساب الدعم قريباً');
                      },
                      child: Text('تواصل مع الدعم',
                        style: GoogleFonts.cairo(
                          fontSize: 13, fontWeight: FontWeight.w800, color: CH.hot)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _todo(context, 'الفاتورة قريباً');
                      },
                      child: Text('الفاتورة',
                        style: GoogleFonts.cairo(
                          fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _todo(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        duration: const Duration(milliseconds: 2000),
      ));
  }
}

class _DetailLine extends StatelessWidget {
  final OrderLine line;
  const _DetailLine({required this.line});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ThumbTile(product: line.product, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(line.product.nameAr,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
              if (line.optionsNote.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(line.optionsNote,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 11, fontWeight: FontWeight.w600, color: CH.muted)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text('${line.quantity} × ${ChMoney.format(line.lineTotal)}',
            style: GoogleFonts.changa(
              fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
        ),
      ],
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  const _DetailBlock({required this.emoji, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: CH.cream, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
              const SizedBox(height: 2),
              Text(body,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w700, color: CH.ink, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TotalsBlock extends StatelessWidget {
  final Order order;
  const _TotalsBlock({required this.order});
  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {bool green = false, bool bold = false}) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF6D5D51))),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(value,
                style: bold
                    ? GoogleFonts.changa(
                        fontSize: 17, fontWeight: FontWeight.w800, color: CH.hot)
                    : GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: green ? CH.green : const Color(0xFF6D5D51))),
            ),
          ],
        );

    final feeLabel = order.isPickup ? 'الاستلام من الفرع' : 'رسوم التوصيل';
    final feeText  = order.deliveryFee == 0 ? 'مجاناً' : ChMoney.format(order.deliveryFee);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CH.cream,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('المجموع الفرعي', ChMoney.format(order.subtotal)),
          const SizedBox(height: 8),
          row(feeLabel, feeText, green: order.deliveryFee == 0),
          if (order.discount > 0) ...[
            const SizedBox(height: 8),
            row('الخصم', '− ${ChMoney.format(order.discount)}', green: true),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 12),
            child: _DashedHLine(),
          ),
          row('الإجمالي', ChMoney.format(order.total), bold: true),
        ],
      ),
    );
  }
}

class _PrimaryFull extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryFull({required this.label, required this.onTap});
  @override
  State<_PrimaryFull> createState() => _PrimaryFullState();
}

class _PrimaryFullState extends State<_PrimaryFull> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: ChShadows.primaryButton,
        ),
        child: Material(
          color: _pressed ? CH.hotDeep : CH.hot,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Center(
                child: Text(widget.label,
                  style: GoogleFonts.changa(
                    fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
