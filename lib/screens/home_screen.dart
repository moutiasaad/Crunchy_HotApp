import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../controllers/cart_controller.dart';
import '../controllers/home_controller.dart';
import '../models/models.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import '../utils/ch_routes.dart';
import '../widgets/widgets.dart';
import 'app_shell.dart';
import 'detail_screen.dart';
import 'offer_detail_screen.dart';
import 'rewards_screen.dart';
import 'search_screen.dart';

/// Screen 05 — Home (الرئيسية). MVCS-wired.
///
/// Menu / offer / featured data come from [HomeController]; the cart-tab
/// badge + add-to-cart go through [CartController]. This widget keeps only
/// UI-local state (scroll controller, active bottom-nav tab).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  ChangeNotifier? _retap;
  ChangeNotifier? _activate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeController>().load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-tap pulse → scroll to top.
    final retap = TabRetap.of(context);
    if (retap != _retap) {
      _retap?.removeListener(_scrollToTop);
      _retap = retap;
      _retap?.addListener(_scrollToTop);
    }
    // Tab-activate pulse → refresh from API so admin changes appear.
    final activate = TabActivate.of(context);
    if (activate != _activate) {
      _activate?.removeListener(_refreshFromApi);
      _activate = activate;
      _activate?.addListener(_refreshFromApi);
    }
  }

  @override
  void dispose() {
    _retap?.removeListener(_scrollToTop);
    _activate?.removeListener(_refreshFromApi);
    _scroll.dispose();
    super.dispose();
  }

  void _refreshFromApi() {
    if (!mounted) return;
    context.read<HomeController>().refresh();
    // Also refresh the signed-in user's profile so the header's loyalty
    // pill reflects points earned from orders completed on other devices.
    final auth = context.read<AuthController>();
    if (auth.isSignedIn) {
      auth.refreshUser();
    }
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0, duration: const Duration(milliseconds: 320), curve: Curves.easeOut,
    );
  }

  void _addToCart(Product p) {
    HapticFeedback.lightImpact();
    context.read<CartController>().add(p);

    // Cart snackbar (spec §8) — char fill, radius 14, action "عرض السلة" in hot.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          'أُضيف ${p.nameAr} للسلة',
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(milliseconds: 2500),
        action: SnackBarAction(
          label: 'عرض السلة',
          textColor: CH.hot,
          onPressed: () => AppShell.switchTo(context, 2),
        ),
      ));
  }

  void _openMenu({String? categorySlug}) {
    // Category chips deep-link into Menu — jump to the Menu tab in the shell,
    // then hand the slug to the MenuController so the right chip opens.
    AppShell.switchTo(context, 1);
    // Deep-linking into a specific category is a nice-to-have TODO now that
    // Menu is a tab; today the tab just opens on its last category.
  }

  Future<void> _refresh() async {
    await context.read<HomeController>().refresh();
  }

  void _openDetail(Product p) {
    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => DetailScreen(product: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home    = context.watch<HomeController>();
    final user    = context.watch<AuthController>().user;
    final points  = user?.loyaltyPoints ?? 0;
    final showError = home.error != null &&
        home.featured.isEmpty && home.categories.isEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: CH.cream,
        extendBodyBehindAppBar: true,
        body: RefreshIndicator(
          color: CH.hot,
          backgroundColor: Colors.white,
          onRefresh: _refresh,
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: 26),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // ────── 1) Dark header block ──────
              _HomeHeader(
                onPointsTap:   () => Navigator.of(context).push(
                  ChRoutes.slideUpFade((_) => const RewardsScreen()),
                ),
                onSearchTap:   () => Navigator.of(context).push(
                  ChRoutes.fade((_) => const SearchScreen()),
                ),
                points: points,
              ),

              // ────── Error card (only when we have nothing to show) ──────
              if (showError)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
                  child: _HomeErrorCard(
                    msg: home.error!,
                    onRetry: () => context.read<HomeController>().refresh(),
                  ),
                ),

              // ────── 2) Offer banner ──────
              if (home.weeklyOffer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _HomeOfferBanner(
                    offer: home.weeklyOffer!,
                    onTap: () => Navigator.of(context).push(
                      ChRoutes.slideUpFade((_) => OfferDetailScreen(offer: home.weeklyOffer!)),
                    ),
                  ),
                ),

              // ────── 3) Category chip rail ──────
              if (home.categories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 6),
                  child: SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                      itemCount: home.categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final c = home.categories[i];
                        return ChChip(
                          label: c.labelAr,
                          emoji: c.emoji,
                          selected: false,
                          onTap: () => _openMenu(categorySlug: c.slug),
                        );
                      },
                    ),
                  ),
                ),

              // ────── 4) Section head ──────
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('نجوم المنيو 🔥',
                      style: GoogleFonts.changa(
                        fontSize: 20, fontWeight: FontWeight.w800, color: CH.ink),
                    ),
                    _SeeAllButton(onTap: () => _openMenu()),
                  ],
                ),
              ),

              // ────── 5) Featured cards / loading skeletons ──────
              if (home.loading && home.featured.isEmpty)
                ...List.generate(2, (_) => const _FeaturedSkeleton())
              else
                for (int i = 0; i < home.featured.length; i++)
                  _StaggeredEnter(
                    delay: Duration(milliseconds: 40 * i),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
                      child: _HomeFeaturedCard(
                        product: home.featured[i],
                        onTap:   () => _openDetail(home.featured[i]),
                        onAdd:   () => _addToCart(home.featured[i]),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Home error card — shown when the initial catalog fetch fails
//  and there's nothing cached to render.
// ══════════════════════════════════════════════════════════════════
class _HomeErrorCard extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _HomeErrorCard({required this.msg, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x1AE11D2A),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg,
                style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w700, color: CH.red)),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              child: Text('إعادة المحاولة',
                style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w800, color: CH.hot)),
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Dark header block — location · [points · logo] + search button
// ══════════════════════════════════════════════════════════════════
class _HomeHeader extends StatelessWidget {
  final int    points;
  final VoidCallback onPointsTap;
  final VoidCallback onSearchTap;

  const _HomeHeader({
    required this.points,
    required this.onPointsTap,
    required this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: CH.char,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          const Text('📍', style: TextStyle(fontSize: 17, color: CH.hotSoft)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('التوصيل إلى',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11, fontWeight: FontWeight.w600,
                                    color: CH.darkHeaderMuted, height: 1.25)),
                                Text('حلب',
                                  style: GoogleFonts.cairo(
                                    fontSize: 14, fontWeight: FontWeight.w800,
                                    color: Colors.white, height: 1.25),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ChPointsPill(points: points, onTap: onPointsTap),
                  const SizedBox(width: 10),
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Image.asset('assets/crunchy-hot-logo.jpg', fit: BoxFit.contain),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: onSearchTap,
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x1FFFFFFF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(children: [
                    const Icon(Icons.search, color: Color(0xFFC9B6A6), size: 20),
                    const SizedBox(width: 10),
                    Text('دور على وجبتك المفضلة…',
                      style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: const Color(0xFFC9B6A6))),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Offer banner — reads from Offer model
// ══════════════════════════════════════════════════════════════════
class _HomeOfferBanner extends StatelessWidget {
  final Offer       offer;
  final VoidCallback onTap;

  const _HomeOfferBanner({required this.offer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CH.hot,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: CH.hotDeep.withValues(alpha: 0.25),
        child: Ink(
          decoration: BoxDecoration(color: CH.hot, borderRadius: BorderRadius.circular(20)),
          child: Stack(
            children: [
              const PositionedDirectional(
                bottom: -40, end: -40, width: 160, height: 160,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x40000000), Colors.transparent],
                        stops: [0.0, 0.9],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(offer.kickerAr,
                          style: GoogleFonts.cairo(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: const Color(0xFFFFE6D8))),
                        const SizedBox(height: 4),
                        Text(offer.titleAr,
                          style: GoogleFonts.changa(
                            fontSize: 23, fontWeight: FontWeight.w800,
                            color: Colors.white, height: 1.15),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 5),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(ChMoney.format(offer.price),
                            style: GoogleFonts.changa(
                              fontSize: 17, fontWeight: FontWeight.w800,
                              color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(color: CH.cream2, borderRadius: BorderRadius.circular(18)),
                    alignment: Alignment.center,
                    child: Text(offer.emoji, style: const TextStyle(fontSize: 46)),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Featured card — takes a domain Product now
// ══════════════════════════════════════════════════════════════════
class _HomeFeaturedCard extends StatelessWidget {
  final Product     product;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const _HomeFeaturedCard({
    required this.product, required this.onTap, required this.onAdd,
  });

  ChBadgeKind get _badgeKind => switch (product.badgeColor) {
        'red'    => ChBadgeKind.spicy,
        'yellow' => ChBadgeKind.popular,
        'green'  => ChBadgeKind.light,
        _        => ChBadgeKind.popular,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ChShadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(children: [
                Positioned.fill(
                  child: Hero(
                    tag: 'product-${product.id}',
                    child: (product.imageUrl == null || product.imageUrl!.isEmpty)
                        ? Container(
                            color: CH.cream2,
                            alignment: Alignment.center,
                            child: Text(product.emoji, style: const TextStyle(fontSize: 110)),
                          )
                        : Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: CH.cream2,
                              alignment: Alignment.center,
                              child: Text(product.emoji, style: const TextStyle(fontSize: 110)),
                            ),
                          ),
                  ),
                ),
                if (product.badgeLabel != null)
                  PositionedDirectional(
                    top: 10, end: 10,
                    child: ChBadge(kind: _badgeKind, label: product.badgeLabel!),
                  ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.nameAr,
                      style: GoogleFonts.changa(
                        fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(product.descriptionAr,
                      style: GoogleFonts.cairo(
                        fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(ChMoney.format(product.price),
                        style: GoogleFonts.changa(
                          fontSize: 16, fontWeight: FontWeight.w800, color: CH.hot)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: 'أضف ${product.nameAr} للسلة',
                child: SizedBox(
                  width: 44, height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 40, height: 40,
                      child: Material(
                        color: CH.char,
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          onTap: onAdd,
                          borderRadius: BorderRadius.circular(13),
                          child: const Icon(Icons.add, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Featured skeleton — shows while HomeController is loading
// ══════════════════════════════════════════════════════════════════
class _FeaturedSkeleton extends StatelessWidget {
  const _FeaturedSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: ChShadows.raised,
        ),
        child: Column(children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(color: CH.cream2),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Container(height: 14, color: CH.cream2)),
              const SizedBox(width: 12),
              Container(width: 40, height: 40,
                decoration: BoxDecoration(
                  color: CH.cream2,
                  borderRadius: BorderRadius.circular(13))),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  "شوف الكل" + stagger enter (unchanged)
// ══════════════════════════════════════════════════════════════════
class _SeeAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SeeAllButton({required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('شوف الكل',
            style: GoogleFonts.cairo(
              fontSize: 13, fontWeight: FontWeight.w800, color: CH.hot)),
        ),
      );
}

class _StaggeredEnter extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _StaggeredEnter({required this.child, this.delay = Duration.zero});

  @override
  State<_StaggeredEnter> createState() => _StaggeredEnterState();
}

class _StaggeredEnterState extends State<_StaggeredEnter> {
  double _opacity = 0;
  double _dy      = 8;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() { _opacity = 1; _dy = 0; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) return widget.child;
    return AnimatedOpacity(
      opacity: _opacity,
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
