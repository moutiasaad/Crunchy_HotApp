import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';

import '../controllers/auth_controller.dart';
import '../controllers/cart_controller.dart';
import '../controllers/favourites_controller.dart';
import '../controllers/orders_controller.dart';
import '../models/models.dart';
import '../services/push_notifications_service.dart';
import '../theme/theme.dart';
import '../utils/ch_routes.dart';
import 'app_shell.dart';
import 'branches_screen.dart';
import 'edit_profile_screen.dart';
import 'favourites_screen.dart';
import 'login_screen.dart';
import 'offers_screen.dart';
import 'rewards_screen.dart';

/// Screen 19 — Profile (حسابي). Tab 5 of 5.
///
/// Identity → shortcuts → reorder → settings. Cache-first, no entry stagger
/// (spec §8) — should feel instant.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Notifications toggle — persist later when we wire the API.
  bool _notificationsOn = true;

  ChangeNotifier? _activate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth   = context.read<AuthController>();
      final orders = context.read<OrdersController>();
      if (auth.isSignedIn && !orders.hasLoaded && !orders.loading) {
        orders.load();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tab-activate: refresh Profile data (identity, points, orders,
    // favourites) each time the customer switches back to this tab.
    final activate = TabActivate.of(context);
    if (activate != _activate) {
      _activate?.removeListener(_refreshFromApi);
      _activate = activate;
      _activate?.addListener(_refreshFromApi);
    }
  }

  @override
  void dispose() {
    _activate?.removeListener(_refreshFromApi);
    super.dispose();
  }

  void _refreshFromApi() {
    if (!mounted) return;
    final auth = context.read<AuthController>();
    if (!auth.isSignedIn) return;    // guest → nothing to refresh
    // Fire-and-forget — the UI is Consumer/watch-driven and will rebuild
    // as each controller notifies. No spinner shown on this refresh.
    auth.refreshUser();
    context.read<OrdersController>().refresh();
    context.read<FavouritesController>().ensureLoaded();
  }

  // ─── Sign-in flow for guest header ──────────────────────
  Future<void> _pushLogin() async {
    final signed = await Navigator.of(context).push<bool>(
      ChRoutes.slideUpFade(
        (_) => const LoginScreen(returnOnSuccess: true),
        fullscreenDialog: true,
      ),
    );
    if (signed == true && mounted) {
      // The header is `context.watch`-driven, so it'll rebuild automatically.
      context.read<OrdersController>().load();
    }
  }

  // ─── Reorder from a past order ──────────────────────────
  Future<void> _reorder(Order o) async {
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

  // ─── Settings row actions ───────────────────────────────
  void _openBranches()  => Navigator.of(context).push(
        // Browse mode: no confirm CTA, no cart mutation — Profile is a
        // settings surface, not an order flow. Users can call / get
        // directions per branch and back out cleanly.
        ChRoutes.slideUpFade((_) => const BranchesScreen(pickerMode: false)),
      );
  void _openOrders()    => AppShell.switchTo(context, 3);
  void _openEditInfo()  => Navigator.of(context).push(
        ChRoutes.slideUpFade((_) => const EditProfileScreen()),
      );
  void _openFavourites() {
    // Prime the list so the screen opens with data instead of a spinner.
    context.read<FavouritesController>().ensureLoaded();
    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => const FavouritesScreen()),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('تسجيل الخروج',
          style: GoogleFonts.changa(
            fontSize: 18, fontWeight: FontWeight.w800, color: CH.ink)),
        content: Text(
          'رح ينحفظ سلتك محلياً وترجع لصفحة تسجيل الدخول.',
          style: GoogleFonts.cairo(
            fontSize: 14, color: const Color(0xFF6D5D51), height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('إلغاء',
              style: GoogleFonts.cairo(
                color: CH.muted, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text('تسجيل الخروج',
              style: GoogleFonts.cairo(
                color: CH.red, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Drop the FCM token from the backend BEFORE the Sanctum token dies —
    // /devices/{token} is authenticated. Best-effort; logout proceeds either
    // way. Fixes the "old device still gets pushes after sign-out" bug.
    await context.read<PushNotificationsService>().unregisterCurrentToken();
    if (!mounted) return;

    await context.read<AuthController>().logout();
    // Keep local cart, drop orders history for the account (still cached
    // locally on the guest identity, but not shown until sign-in returns it).
    if (!mounted) return;
    context.read<OrdersController>().reset();

    Navigator.of(context).pushAndRemoveUntil(
      ChRoutes.fade((_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(ApiConfig.privacyPolicyUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _todo('تعذّر فتح صفحة الخصوصية — تحقّق من الاتصال');
    }
  }

  void _todo(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(milliseconds: 2000),
      ));
  }

  // ─── Build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<AuthController>();
    final orders = context.watch<OrdersController>();

    final user      = auth.user;
    final isGuest   = !auth.isSignedIn;
    final recent    = orders.historyOrders
      .where((o) => o.isDelivered).take(2).toList();
    final hasActive = orders.activeOrder != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Scaffold(
          backgroundColor: CH.cream,
          extendBodyBehindAppBar: true,
          body: ListView(
            padding: const EdgeInsets.only(bottom: 26),
            children: [
              // ────── Identity header ──────
              _IdentityHeader(
                user: user,
                isGuest: isGuest,
                onSignIn: _pushLogin,
                onAvatarTap: isGuest
                    ? _pushLogin
                    : () => _todo('تعديل الملف الشخصي قريباً'),
                onPointsTap: isGuest
                    ? _pushLogin
                    : () => Navigator.of(context).push(
                          ChRoutes.slideUpFade((_) => const RewardsScreen()),
                        ),
              ),

              // ────── Shortcut tiles ──────
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(child: _ShortcutTile(
                      glyph: '🧾', label: 'طلباتي',
                      showDot: hasActive,
                      onTap: isGuest ? _pushLogin : _openOrders,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ShortcutTile(
                      glyph: '❤️', label: 'المفضلة',
                      onTap: isGuest ? _pushLogin : _openFavourites,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ShortcutTile(
                      glyph: '🎟️', label: 'العروض',
                      onTap: () => Navigator.of(context).push(
                        ChRoutes.slideUpFade((_) => const OffersScreen()),
                      ),
                    )),
                  ],
                ),
              ),

              // ────── Reorder section ──────
              if (recent.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('اطلب مجدداً',
                      style: GoogleFonts.changa(
                        fontSize: 16, fontWeight: FontWeight.w800, color: CH.ink)),
                  ),
                ),
                for (final o in recent)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                    child: _ReorderCard(order: o, onReorder: () => _reorder(o)),
                  ),
              ],

              // ────── Settings group ──────
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 20),
                child: _SettingsGroup(rows: [
                  if (!isGuest)
                    _SettingsRow(
                      glyph: '✏️', label: 'معلوماتي',
                      onTap: _openEditInfo,
                    ),
                  _SettingsRow(
                    glyph: '💳', label: 'طرق الدفع',
                    onTap: () => _todo('طرق الدفع قريباً'),
                  ),
                  _SettingsRow(
                    // Renamed from "اختر الفرع" — that verb implies changing
                    // pickup selection, which this row no longer does.
                    glyph: '🏬', label: 'فروعنا',
                    onTap: _openBranches,
                  ),
                  _SettingsRow(
                    glyph: '🔔', label: 'الإشعارات',
                    trailingSwitch: _notificationsOn,
                    onToggle: (v) => setState(() => _notificationsOn = v),
                  ),
                  if (!isGuest)
                    _SettingsRow(
                      glyph: '↩︎', label: 'تسجيل الخروج',
                      danger: true,
                      onTap: _confirmLogout,
                    )
                  else
                    _SettingsRow(
                      glyph: '↩︎', label: 'تسجيل الدخول',
                      hot: true,
                      onTap: _pushLogin,
                    ),
                ]),
              ),

              // ────── Footer buttons ──────
              _FooterButtons(
                onContact: () => _todo('واتساب الدعم قريباً'),
                onTerms:   _openPrivacyPolicy,
              ),
              const SizedBox(height: 10),
              const Center(child: _VersionLabel(version: '1.0.0')),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Identity header — char fill, bottom radius 26
// ══════════════════════════════════════════════════════════════════
class _IdentityHeader extends StatelessWidget {
  final User? user;
  final bool  isGuest;
  final VoidCallback onSignIn;
  final VoidCallback onAvatarTap;
  final VoidCallback onPointsTap;

  const _IdentityHeader({
    required this.user, required this.isGuest,
    required this.onSignIn,
    required this.onAvatarTap,
    required this.onPointsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: CH.char,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(user: user, isGuest: isGuest, onTap: onAvatarTap),
              const SizedBox(width: 14),
              Expanded(child: _HeaderBody(user: user, isGuest: isGuest)),
              const SizedBox(width: 10),
              isGuest
                ? _SignInPill(onTap: onSignIn)
                : _PointsPill(
                    points: user?.loyaltyPoints ?? 0,
                    onTap:  onPointsTap,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final User? user;
  final bool  isGuest;
  final VoidCallback onTap;
  const _Avatar({required this.user, required this.isGuest, required this.onTap});

  String get _initial {
    final name = user?.name ?? '';
    if (name.isEmpty) return '👤';
    return name.characters.first;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, label: 'الصورة الشخصية',
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Container(
          width: 62, height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CH.cream2,
            border: Border.all(color: CH.hot, width: 2),
          ),
          alignment: Alignment.center,
          child: isGuest
              ? const Text('👤', style: TextStyle(fontSize: 26))
              : Text(_initial,
                  style: GoogleFonts.changa(
                    fontSize: 24, fontWeight: FontWeight.w800, color: CH.muted)),
        ),
      ),
    );
  }
}

class _HeaderBody extends StatelessWidget {
  final User? user;
  final bool isGuest;
  const _HeaderBody({required this.user, required this.isGuest});

  String get _greeting {
    if (isGuest) return 'أهلاً بك';
    final name = user?.name?.trim() ?? '';
    if (name.isEmpty) return 'أهلاً بك 👋';
    final first = name.split(RegExp(r'\s+')).first;
    return 'أهلاً $first 👋';
  }

  String get _subLine {
    if (isGuest) return 'سجّل دخولك لتحفظ طلباتك ونقاطك';
    return user?.phone ?? user?.email ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_greeting,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.changa(
            fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 4),
        // Phone / email are LTR runs — digits and `@` shouldn't reverse.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(_subLine,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 13, fontWeight: FontWeight.w400,
              color: const Color(0xFFA89684))),
        ),
      ],
    );
  }
}

class _PointsPill extends StatelessWidget {
  final int points;
  final VoidCallback onTap;
  const _PointsPill({required this.points, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, label: 'نقاطك $points، افتح المكافآت',
      child: Material(
        color: CH.yellow,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⭐', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('$points',
                    style: GoogleFonts.cairo(
                      fontSize: 12, fontWeight: FontWeight.w800, color: CH.char)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInPill extends StatelessWidget {
  final VoidCallback onTap;
  const _SignInPill({required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'تسجيل الدخول',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: ChShadows.primaryButton,
          ),
          child: Material(
            color: CH.hot,
            shape: const StadiumBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text('تسجيل الدخول',
                  style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Shortcut tile
// ══════════════════════════════════════════════════════════════════
class _ShortcutTile extends StatefulWidget {
  final String glyph;
  final String label;
  final bool   showDot;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.glyph, required this.label,
    this.showDot = false, required this.onTap,
  });

  @override
  State<_ShortcutTile> createState() => _ShortcutTileState();
}

class _ShortcutTileState extends State<_ShortcutTile> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final semanticsLabel = widget.showDot
        ? '${widget.label} — جديد'
        : widget.label;
    return Semantics(
      button: true, label: semanticsLabel,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: BorderRadius.circular(16),
            splashColor: CH.hot.withValues(alpha: 0.06),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                  color: const Color(0xFF2E1D12).withValues(alpha: 0.05),
                  offset: const Offset(0, 6), blurRadius: 16)],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.glyph, style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 6),
                      Text(widget.label,
                        style: GoogleFonts.cairo(
                          fontSize: 12, fontWeight: FontWeight.w800, color: CH.ink)),
                    ],
                  ),
                  if (widget.showDot)
                    const PositionedDirectional(
                      top: -2, end: -2,
                      child: _NewDot(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewDot extends StatelessWidget {
  const _NewDot();
  @override
  Widget build(BuildContext context) => Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle, color: CH.hot,
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Reorder card (recent delivered order)
// ══════════════════════════════════════════════════════════════════
class _ReorderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onReorder;
  const _ReorderCard({required this.order, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onReorder,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
              color: const Color(0xFF2E1D12).withValues(alpha: 0.05),
              offset: const Offset(0, 6), blurRadius: 16)],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _MiniThumb(order: order),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(order.displayItems,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
                    const SizedBox(height: 2),
                    Text('${order.itemCount} أصناف · ${_fmtDate(order.createdAt)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ReorderPill(onTap: onReorder),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime t) {
    // Terse: "5 تموز"
    return '${t.day} ${_month(t.month)}';
  }

  static String _month(int m) => switch (m) {
        1  => 'كانون الثاني', 2  => 'شباط',      3  => 'آذار',
        4  => 'نيسان',        5  => 'أيار',      6  => 'حزيران',
        7  => 'تموز',         8  => 'آب',        9  => 'أيلول',
        10 => 'تشرين الأول',  11 => 'تشرين الثاني', 12 => 'كانون الأول',
        _  => '',
      };
}

class _MiniThumb extends StatelessWidget {
  final Order order;
  const _MiniThumb({required this.order});
  @override
  Widget build(BuildContext context) {
    final lines = order.lines.take(4).toList();
    if (lines.length == 1) {
      return _MiniTile(product: lines.first.product, size: 56);
    }
    return SizedBox(
      width: 56, height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 2, crossAxisSpacing: 2,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final l in lines) _MiniTile(product: l.product, size: 27),
            for (int i = lines.length; i < 4; i++)
              Container(color: CH.cream2),
          ],
        ),
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  final Product product;
  final double size;
  const _MiniTile({required this.product, required this.size});
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: CH.cream2,
          borderRadius: size >= 40 ? BorderRadius.circular(13) : null,
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

class _ReorderPill extends StatelessWidget {
  final VoidCallback onTap;
  const _ReorderPill({required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'أعد الطلب',
        child: Material(
          color: CH.hot,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              child: Text('أعد الطلب',
                style: GoogleFonts.cairo(
                  fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Settings group — first / middle / last radii, 2 dp gap between rows
// ══════════════════════════════════════════════════════════════════
class _SettingsGroup extends StatelessWidget {
  final List<_SettingsRow> rows;
  const _SettingsGroup({required this.rows});

  BorderRadius _radiusFor(int i, int n) {
    if (n == 1) return BorderRadius.circular(16);
    if (i == 0) {
      return const BorderRadius.only(
        topLeft:  Radius.circular(16), topRight: Radius.circular(16),
        bottomLeft: Radius.circular(4), bottomRight: Radius.circular(4),
      );
    }
    if (i == n - 1) {
      return const BorderRadius.only(
        topLeft:  Radius.circular(4), topRight: Radius.circular(4),
        bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16),
      );
    }
    return BorderRadius.circular(4);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          _RowShell(radius: _radiusFor(i, rows.length), row: rows[i]),
          if (i != rows.length - 1) const SizedBox(height: 2),
        ],
      ],
    );
  }
}

class _SettingsRow {
  final String glyph;
  final String label;
  final VoidCallback? onTap;
  final bool?   trailingSwitch;
  final ValueChanged<bool>? onToggle;
  final bool    danger;
  final bool    hot;

  const _SettingsRow({
    required this.glyph, required this.label,
    this.onTap,
    this.trailingSwitch,
    this.onToggle,
    this.danger = false,
    this.hot    = false,
  });
}

class _RowShell extends StatefulWidget {
  final BorderRadius radius;
  final _SettingsRow row;
  const _RowShell({required this.radius, required this.row});
  @override
  State<_RowShell> createState() => _RowShellState();
}

class _RowShellState extends State<_RowShell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final r        = widget.row;
    final labelColor = r.danger ? CH.red : (r.hot ? CH.hot : CH.ink);

    Widget content = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(r.glyph, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(r.label,
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w700, color: labelColor)),
          ),
          if (r.trailingSwitch != null) ...[
            _MiniSwitch(
              on: r.trailingSwitch!,
              onChanged: r.onToggle ?? (_) {},
            ),
          ] else if (!r.danger) ...[
            Text(isArabic ? '‹' : '›',
              style: GoogleFonts.changa(
                fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFFC9B6A6))),
          ],
        ],
      ),
    );

    return Semantics(
      button: r.onTap != null,
      toggled: r.trailingSwitch,
      hint: r.danger ? 'يفتح تأكيد' : null,
      label: r.label,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Material(
          color: Colors.white,
          borderRadius: widget.radius,
          child: InkWell(
            onTap: r.onTap ?? (r.onToggle != null
                ? () => r.onToggle!(!(r.trailingSwitch ?? false))
                : null),
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: widget.radius,
            splashColor: CH.hot.withValues(alpha: 0.06),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: widget.radius,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniSwitch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const _MiniSwitch({required this.on, required this.onChanged});
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 46, height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: on ? CH.green : const Color(0xFFE2D3C3),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: on
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: Container(
              width: 20, height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Colors.white,
                boxShadow: [BoxShadow(
                  color: Color(0x33000000), offset: Offset(0, 1), blurRadius: 2)],
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Footer buttons + version label
// ══════════════════════════════════════════════════════════════════
class _FooterButtons extends StatelessWidget {
  final VoidCallback onContact;
  final VoidCallback onTerms;
  const _FooterButtons({required this.onContact, required this.onTerms});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _FooterBtn(label: 'تواصل معنا',      onTap: onContact),
            _FooterBtn(label: 'الشروط والخصوصية', onTap: onTerms),
          ],
        ),
      );
}

class _FooterBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FooterBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label,
          style: GoogleFonts.cairo(
            fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
      );
}

class _VersionLabel extends StatelessWidget {
  final String version;
  const _VersionLabel({required this.version});
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text('الإصدار $version',
          style: GoogleFonts.cairo(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: const Color(0xFFB3A396))),
      );
}
