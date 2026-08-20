import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/loyalty_controller.dart';
import '../models/models.dart';
import '../services/app_config_service.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';

/// Screen 18 — Rewards (المكافآت).
///
/// End-to-end wired against the API:
///   * balance / rules / ledger → `GET /loyalty`
///   * catalogue → `GET /loyalty/rewards` (admin-managed via RewardResource)
///   * redeem → `POST /loyalty/redeem { reward_id }` — server debits points
///     and returns a personal single-use promo code the customer applies at
///     checkout.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});
  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  String? _redeemingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = context.read<LoyaltyController>();
      if (!ctrl.hasLoaded && !ctrl.loading) ctrl.load();
      // Refetch the public config so an admin's edit to the loyalty notice
      // (`business.loyalty.notice_ar`) shows up the moment this screen
      // mounts, without needing to background/foreground the app or bounce
      // through the Cart tab. Fire-and-forget: AppConfigService.load()
      // silently keeps prior values on failure and notifyListeners() on
      // success — the notice card rebuilds automatically via context.watch.
      unawaited(context.read<AppConfigService>().load());
    });
  }

  Future<void> _openConfirm(Reward r) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _RedeemConfirmSheet(reward: r),
    );
    if (ok != true || !mounted) return;

    setState(() => _redeemingId = r.id);
    HapticFeedback.mediumImpact();

    try {
      final result = await context.read<LoyaltyController>().redeem(r.id);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      await _showSuccessSheet(r, result.couponCode);
    } catch (_) {
      if (!mounted) return;
      _showError('ما قدرنا نستبدل — جرّب مرة تانية');
    } finally {
      if (mounted) setState(() => _redeemingId = null);
    }
  }

  Future<void> _showSuccessSheet(Reward r, String couponCode) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        builder: (_) => _RedeemSuccessSheet(reward: r, couponCode: couponCode),
      );

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: CH.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(seconds: 3),
      ));
  }

  Future<void> _openHistory() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        builder: (_) => const _HistorySheet(),
      );

  // ─── Build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ctrl     = context.watch<LoyaltyController>();
    final balance  = ctrl.balance;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    // Catalogue comes from `GET /loyalty/rewards`, ordered by admin's
    // sort_order + points_cost. When empty (nothing seeded / all inactive)
    // the "no rewards yet" empty state renders below.
    final rewards = List<Reward>.of(ctrl.rewards)
      ..sort((a, b) => a.pointsCost.compareTo(b.pointsCost));

    final Reward? nextLocked = rewards.isEmpty
        ? null
        : rewards.firstWhere(
            (r) => r.pointsCost > balance,
            orElse: () => rewards.last,
          );
    final nextCost = nextLocked?.pointsCost ?? 0;
    final progress = nextCost == 0 ? 1.0 : (balance / nextCost).clamp(0.0, 1.0);
    final atTopTier = rewards.isNotEmpty && balance >= rewards.last.pointsCost;
    final firstAffordable = rewards.indexWhere((r) => r.pointsCost <= balance);
    final affordableCount = rewards.where((r) => r.pointsCost <= balance).length;

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
          body: RefreshIndicator(
            color: CH.hot,
            onRefresh: () => ctrl.refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 26),
              children: [
                _PointsHeader(
                  balance:     balance,
                  progress:    progress,
                  nextCost:    nextCost,
                  nextName:    nextLocked?.nameAr ?? '',
                  atTopTier:   atTopTier,
                  loading:     ctrl.loading && !ctrl.hasLoaded,
                  onBack:      () => Navigator.of(context).maybePop(),
                  onHistory:   _openHistory,
                  isArabic:    isArabic,
                ),

                // Admin-editable notice from `/api/v1/config` (business.
                // loyalty_notice_ar). Shown right below the header so it's
                // the first content the customer reads on the rewards page.
                // Hidden entirely when the admin left it empty.
                if (context.watch<AppConfigService>().loyaltyNoticeAr.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                    child: _LoyaltyNoticeCard(
                      text: context.watch<AppConfigService>().loyaltyNoticeAr,
                    ),
                  ),

                if (ctrl.error != null && !ctrl.loading)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                    child: _ErrorCard(msg: ctrl.error!, onRetry: () => ctrl.refresh()),
                  ),

                // ── Wallet: the customer's active coupons from past
                //    redemptions. Shown first so a returning user sees what
                //    they already own before browsing the catalogue.
                if (ctrl.activeCoupons.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 10),
                    child: Row(children: [
                      Text('كوبوناتك جاهزة للاستخدام',
                        style: GoogleFonts.changa(
                          fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: CH.hot,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('${ctrl.activeCoupons.length}',
                          style: GoogleFonts.cairo(
                            fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ]),
                  ),
                  for (final c in ctrl.activeCoupons)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
                      child: _WalletCouponCard(coupon: c),
                    ),
                  const SizedBox(height: 10),
                ],

                // Section title
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 10),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('استبدل نقاطك',
                      style: GoogleFonts.changa(
                        fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink)),
                  ),
                ),

                // Reward rows — server-driven catalogue.
                if (rewards.isEmpty && !ctrl.rewardsLoading)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 0),
                    child: Text(
                      'لا توجد مكافآت متاحة حالياً — تابعنا للجديد.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w700, color: CH.muted),
                    ),
                  )
                else
                  for (int i = 0; i < rewards.length; i++)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                      child: _RewardRow(
                        reward:   rewards[i],
                        unlocked: rewards[i].pointsCost <= balance,
                        missing:  (rewards[i].pointsCost - balance).clamp(0, 1 << 62),
                        busy:     _redeemingId == rewards[i].id,
                        showClosest:
                            i == firstAffordable && affordableCount > 1,
                        onRedeem: rewards[i].pointsCost <= balance
                            ? () => _openConfirm(rewards[i])
                            : null,
                      ),
                    ),

                // Earn-rate note
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
                  child: _EarnRateNote(
                    rules:  ctrl.status.rules,
                    expiringSoon: ctrl.status.expiringWithin(const Duration(days: 30)),
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

// Rewards catalogue now comes from `GET /loyalty/rewards`. The old
// hardcoded `_launchRewards` list was removed — admin edits the list via
// Filament's RewardResource.

// ══════════════════════════════════════════════════════════════════
//  Points header — dark card with balance, progress, next hint
// ══════════════════════════════════════════════════════════════════
class _PointsHeader extends StatelessWidget {
  final int    balance;
  final double progress;
  final int    nextCost;
  final String nextName;
  final bool   atTopTier;
  final bool   loading;
  final bool   isArabic;
  final VoidCallback onBack;
  final VoidCallback onHistory;

  const _PointsHeader({
    required this.balance,   required this.progress,
    required this.nextCost,  required this.nextName,
    required this.atTopTier, required this.loading,
    required this.isArabic,
    required this.onBack,    required this.onHistory,
  });

  String _pointsLabel(int n) {
    if (n == 0) return 'نقطة متاحة';
    if (n == 1) return 'نقطة متاحة';
    if (n == 2) return 'نقطتان متاحتان';
    if (n >= 3 && n <= 10) return 'نقاط متاحة';
    return 'نقطة متاحة';
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final missing = (nextCost - balance).clamp(0, 1 << 62);
    final hint = atTopTier
        ? 'عندك نقاط تكفي لأفضل مكافأة 🎉'
        : '$missing نقطة كمان لتحصل على $nextName';

    final semanticsLabel = atTopTier
        ? '$balance ${_pointsLabel(balance)}، عندك نقاط تكفي لأفضل مكافأة'
        : '$balance ${_pointsLabel(balance)}، $missing نقطة للمكافأة التالية';

    return Container(
      decoration: const BoxDecoration(
        color: CH.char,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Stack(
        children: [
          // Radial glow — spec §3.
          const PositionedDirectional(
            top: -30, end: -30, width: 260, height: 260,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x38FFC02E), Colors.transparent],
                    stops: [0.0, 0.65],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _GlassBack(glyph: isArabic ? '→' : '←', onTap: onBack),
                    const SizedBox(width: 12),
                    Text('نقاط المكافآت',
                      style: GoogleFonts.changa(
                        fontSize: 23, fontWeight: FontWeight.w800, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 18),
                Semantics(
                  liveRegion: true,
                  label: semanticsLabel,
                  child: Column(
                    children: [
                      // Count-up balance
                      _CountUpBalance(target: balance),
                      const SizedBox(height: 6),
                      Text(_pointsLabel(balance),
                        style: GoogleFonts.cairo(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: const Color(0xFFC9B6A6))),
                      const SizedBox(height: 18),
                      _ProgressBar(target: progress),
                      const SizedBox(height: 8),
                      Text(hint,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: const Color(0xFFA89684))),
                      const SizedBox(height: 4),
                      Semantics(
                        button: true, label: 'سجل النقاط',
                        child: TextButton(
                          onPressed: onHistory,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: const Size(44, 44),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('سجل النقاط',
                            style: GoogleFonts.cairo(
                              fontSize: 12, fontWeight: FontWeight.w800,
                              color: CH.hotSoft)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassBack extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  const _GlassBack({required this.glyph, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'رجوع',
        child: SizedBox(
          width: 40, height: 40,
          child: Material(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(glyph,
                  style: GoogleFonts.cairo(
                    fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ),
        ),
      );
}

class _CountUpBalance extends StatelessWidget {
  final int target;
  const _CountUpBalance({required this.target});
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: target),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          builder: (context, value, _) => Text(
            '$value',
            style: GoogleFonts.changa(
              fontSize: 52, fontWeight: FontWeight.w800,
              color: CH.yellow, height: 1.0),
          ),
        ),
      );
}

class _ProgressBar extends StatelessWidget {
  final double target;
  const _ProgressBar({required this.target});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      builder: (context, val, _) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 10,
          color: Colors.white.withValues(alpha: 0.14),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: val,
              heightFactor: 1.0,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end:   AlignmentDirectional.centerEnd,
                    colors: [CH.yellow, CH.hot],
                  ),
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
//  Reward row
// ══════════════════════════════════════════════════════════════════
class _RewardRow extends StatelessWidget {
  final Reward reward;
  final bool   unlocked;
  final int    missing;
  final bool   busy;
  final bool   showClosest;
  final VoidCallback? onRedeem;

  const _RewardRow({
    required this.reward, required this.unlocked,
    required this.missing, required this.busy,
    required this.showClosest, required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onRedeem != null,
      enabled: unlocked,
      label: unlocked
          ? '${reward.nameAr}، ${reward.pointsCost} نقطة'
          : '${reward.nameAr}، ${reward.pointsCost} نقطة، مقفل، باقي $missing نقطة',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onRedeem,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: SizedBox(
                    width: 52, height: 52,
                    child: (reward.imageUrl == null || reward.imageUrl!.isEmpty)
                        ? Container(
                            color: CH.cream,
                            alignment: Alignment.center,
                            child: Text(reward.emoji, style: const TextStyle(fontSize: 24)),
                          )
                        : Image.network(
                            reward.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: CH.cream,
                              alignment: Alignment.center,
                              child: Text(reward.emoji, style: const TextStyle(fontSize: 24)),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(reward.nameAr,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
                          ),
                          if (showClosest) ...[
                            const SizedBox(width: 8),
                            _ClosestBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          unlocked
                              ? '⭐ ${reward.pointsCost} نقطة'
                              : 'باقي $missing نقطة',
                          style: GoogleFonts.cairo(
                            fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _ActionBtn(
                  unlocked: unlocked, busy: busy, onTap: onRedeem,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClosestBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: CH.yellow, borderRadius: BorderRadius.circular(999)),
        child: Text('الأقرب',
          style: GoogleFonts.cairo(
            fontSize: 11, fontWeight: FontWeight.w800, color: CH.char)),
      );
}

class _ActionBtn extends StatelessWidget {
  final bool unlocked;
  final bool busy;
  final VoidCallback? onTap;
  const _ActionBtn({required this.unlocked, required this.busy, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final active = unlocked && !busy;
    return SizedBox(
      height: 44,
      child: Material(
        color: !unlocked ? const Color(0xFFF4EAE0) : CH.hot,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: active ? onTap : null,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(unlocked ? 'استبدل' : 'مقفل',
                      style: GoogleFonts.cairo(
                        fontSize: 12, fontWeight: FontWeight.w800,
                        color: unlocked ? Colors.white : const Color(0xFFB3A396))),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Earn-rate note (§6)
// ══════════════════════════════════════════════════════════════════
class _EarnRateNote extends StatelessWidget {
  final LoyaltyRules rules;
  final List<LoyaltyLedgerEntry> expiringSoon;
  const _EarnRateNote({required this.rules, required this.expiringSoon});

  @override
  Widget build(BuildContext context) {
    final expiringPoints = expiringSoon.fold<int>(0, (s, e) => s + e.points.abs());
    final nearest = expiringSoon
      ..sort((a, b) => (a.expiresAt ?? DateTime.now())
          .compareTo(b.expiresAt ?? DateTime.now()));
    final expiryText = expiringPoints > 0 && nearest.first.expiresAt != null
        ? '$expiringPoints نقطة بتنتهي ${_fmtDate(nearest.first.expiresAt!)}'
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CH.cream2, borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🎁', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'كل 1,000 ل.س من طلبك = ${rules.earnRatePer1000Syp} نقاط. '
                  'النقاط تنتهي بعد ${rules.expiryDays ~/ 30} شهر.',
                  style: GoogleFonts.cairo(
                    fontSize: 13, height: 1.7, color: const Color(0xFF6D5D51)),
                ),
                if (expiryText != null) ...[
                  const SizedBox(height: 6),
                  Text(expiryText,
                    style: GoogleFonts.cairo(
                      fontSize: 12, fontWeight: FontWeight.w700, color: CH.red)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime t) {
    // "12 أيلول" — Levantine month names.
    const months = [
      '', 'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
      'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
    ];
    return '${t.day} ${months[t.month]}';
  }
}

// ══════════════════════════════════════════════════════════════════
//  Confirm sheet (§5)
// ══════════════════════════════════════════════════════════════════
class _RedeemConfirmSheet extends StatelessWidget {
  final Reward reward;
  const _RedeemConfirmSheet({required this.reward});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: 20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: CH.line, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 18),
          Center(child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 64, height: 64,
              child: (reward.imageUrl == null || reward.imageUrl!.isEmpty)
                  ? Container(
                      color: CH.cream,
                      alignment: Alignment.center,
                      child: Text(reward.emoji, style: const TextStyle(fontSize: 30)),
                    )
                  : Image.network(reward.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: CH.cream,
                        alignment: Alignment.center,
                        child: Text(reward.emoji, style: const TextStyle(fontSize: 30)),
                      ),
                    ),
            ),
          )),
          const SizedBox(height: 12),
          Text(reward.nameAr,
            textAlign: TextAlign.center,
            style: GoogleFonts.changa(
              fontSize: 20, fontWeight: FontWeight.w800, color: CH.ink)),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('⭐ ${reward.pointsCost} نقطة',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.w600, color: CH.muted)),
          ),
          const SizedBox(height: 14),
          Text(
            'رح ينخصم ${reward.pointsCost} نقطة ويصير عندك كوبون صالح ${reward.couponValidDays} يوم.',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 14, height: 1.6, color: const Color(0xFF6D5D51)),
          ),
          const SizedBox(height: 20),
          _SheetPrimary(
            label: 'أكّد الاستبدال',
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('إلغاء',
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w800, color: CH.muted)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Success sheet — coupon in dashed box + two actions
// ══════════════════════════════════════════════════════════════════
class _RedeemSuccessSheet extends StatelessWidget {
  final Reward reward;
  final String couponCode;
  const _RedeemSuccessSheet({required this.reward, required this.couponCode});

  @override
  Widget build(BuildContext context) {
    final code = couponCode;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: 20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: CH.line, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 20),
          const Center(child: Text('✅', style: TextStyle(fontSize: 48))),
          const SizedBox(height: 12),
          Text('تم! كوبونك جاهز',
            textAlign: TextAlign.center,
            style: GoogleFonts.changa(
              fontSize: 20, fontWeight: FontWeight.w800, color: CH.ink)),
          const SizedBox(height: 8),
          Text('محفوظ في «كوبوناتك» فوق. طبّقه بلمسة عند إتمام الطلب.',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 13, fontWeight: FontWeight.w700, color: CH.muted)),
          const SizedBox(height: 14),
          _CouponBox(code: code),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!context.mounted) return;
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content: Text('نسخنا الكود',
                      style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    backgroundColor: CH.char,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    duration: const Duration(milliseconds: 1500),
                  ));
              },
              icon: const Icon(Icons.copy_rounded, size: 16, color: CH.hot),
              label: Text('نسخ الكود',
                style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w800, color: CH.hot)),
            ),
          ),
          const SizedBox(height: 12),
          _SheetPrimary(
            label: 'تمام',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _CouponBox extends StatelessWidget {
  final String code;
  const _CouponBox({required this.code});
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashedRRectPainter(
          color: CH.hot, radius: 14, strokeWidth: 1.5,
          dashLength: 6, gapLength: 4,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(code,
                style: GoogleFonts.changa(
                  fontSize: 20, fontWeight: FontWeight.w800,
                  color: CH.hot, letterSpacing: 2)),
            ),
          ),
        ),
      );
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius, strokeWidth, dashLength, gapLength;
  _DashedRRectPainter({
    required this.color, required this.radius, required this.strokeWidth,
    required this.dashLength, required this.gapLength,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color..strokeWidth = strokeWidth..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += dashLength + gapLength;
      }
    }
  }
  @override
  bool shouldRepaint(_DashedRRectPainter o) =>
      o.color != color || o.radius != radius || o.strokeWidth != strokeWidth ||
      o.dashLength != dashLength || o.gapLength != gapLength;
}

// ══════════════════════════════════════════════════════════════════
//  History sheet (§7)
// ══════════════════════════════════════════════════════════════════
class _HistorySheet extends StatelessWidget {
  const _HistorySheet();
  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LoyaltyController>().status.ledger;
    final maxH   = MediaQuery.sizeOf(context).height * 0.80;

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
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: CH.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('سجل النقاط',
                    style: GoogleFonts.changa(
                      fontSize: 20, fontWeight: FontWeight.w800, color: CH.ink)),
                ),
                InkResponse(
                  onTap: () => Navigator.of(context).pop(),
                  radius: 20,
                  child: const Icon(Icons.close_rounded, color: CH.muted),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: CH.line),
          Flexible(
            child: ledger.isEmpty
                ? _EmptyHistory()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: ledger.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _HistoryRow(entry: ledger[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final LoyaltyLedgerEntry entry;
  const _HistoryRow({required this.entry});
  @override
  Widget build(BuildContext context) {
    final (bg, icon, amountColor, sign) = switch (entry.type) {
      LoyaltyEntryType.earned  => (CH.cream, '🎁', CH.green, '+'),
      LoyaltyEntryType.spent   => (const Color(0xFFFFF4D6), '⭐', CH.hot, '−'),
      LoyaltyEntryType.expired => (CH.cream, '⏱', CH.muted, '−'),
      LoyaltyEntryType.other   => (CH.cream, '•', CH.muted, ''),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text(icon, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(entry.note ?? _defaultLabel(entry.type),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w700, color: CH.ink)),
              const SizedBox(height: 2),
              Text(_fmt(entry.createdAt),
                style: GoogleFonts.cairo(
                  fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
            ],
          ),
        ),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text('$sign${entry.points.abs()}',
            style: GoogleFonts.changa(
              fontSize: 14, fontWeight: FontWeight.w800, color: amountColor)),
        ),
      ],
    );
  }

  static String _defaultLabel(LoyaltyEntryType t) => switch (t) {
        LoyaltyEntryType.earned  => 'كسب نقاط',
        LoyaltyEntryType.spent   => 'استبدال نقاط',
        LoyaltyEntryType.expired => 'انتهت الصلاحية',
        LoyaltyEntryType.other   => '',
      };

  static String _fmt(DateTime t) {
    const months = [
      '', 'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
      'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
    ];
    return '${t.day} ${months[t.month]}';
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📭', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            Text('ما في حركات بعد',
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w700, color: CH.muted)),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Small helpers
// ══════════════════════════════════════════════════════════════════
class _SheetPrimary extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SheetPrimary({required this.label, required this.onTap});
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
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Center(
                child: Text(label,
                  style: GoogleFonts.changa(
                    fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Wallet coupon card — a coupon the customer already redeemed with
//  points. Tap to copy the code to clipboard (customer pastes it at
//  checkout, or one-tap applies it directly from the checkout wallet).
// ══════════════════════════════════════════════════════════════════
class _WalletCouponCard extends StatelessWidget {
  final MyCoupon coupon;
  const _WalletCouponCard({required this.coupon});

  Future<void> _copy(BuildContext context) async {
    final code = coupon.code;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('نسخنا الكود — ألصقه في السلة',
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(milliseconds: 1800),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final expiresIn = coupon.expiresAt?.difference(DateTime.now()).inDays;
    final expiryLabel = expiresIn == null
        ? null
        : (expiresIn <= 0 ? 'ينتهي اليوم'
            : expiresIn == 1 ? 'ينتهي غداً'
            : 'باقي $expiresIn يوم');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _copy(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
              color: const Color(0xFF2E1D12).withValues(alpha: 0.05),
              offset: const Offset(0, 6), blurRadius: 18)],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 48, height: 48,
                  child: (coupon.rewardImageUrl == null || coupon.rewardImageUrl!.isEmpty)
                      ? Container(
                          color: CH.cream,
                          alignment: Alignment.center,
                          child: Text(coupon.rewardEmoji, style: const TextStyle(fontSize: 22)),
                        )
                      : Image.network(coupon.rewardImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: CH.cream,
                            alignment: Alignment.center,
                            child: Text(coupon.rewardEmoji, style: const TextStyle(fontSize: 22)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(coupon.rewardName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
                    const SizedBox(height: 3),
                    Text('يخصم ${ChMoney.format(coupon.discountSyp)} من طلبك',
                      style: GoogleFonts.cairo(
                        fontSize: 12, fontWeight: FontWeight.w700, color: CH.green)),
                    if (expiryLabel != null) ...[
                      const SizedBox(height: 3),
                      Text('⏳ $expiryLabel',
                        style: GoogleFonts.cairo(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: (expiresIn != null && expiresIn <= 2) ? CH.red : CH.muted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // The code itself + copy hint — a dashed pill in the same
              // language as the coupon rows on the Offers screen so users
              // recognise it instantly.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: CH.hot.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CH.hot, width: 1.2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(coupon.code ?? '',
                        style: GoogleFonts.cairo(
                          fontSize: 12, fontWeight: FontWeight.w800,
                          color: CH.hot, letterSpacing: 0.5)),
                    ),
                    const SizedBox(height: 2),
                    Text('نسخ',
                      style: GoogleFonts.cairo(
                        fontSize: 9, fontWeight: FontWeight.w800, color: CH.hot)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _ErrorCard({required this.msg, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x1AE11D2A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(msg,
                style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w700, color: CH.red)),
            ),
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
//  Loyalty notice card — admin-editable free-text banner
// ══════════════════════════════════════════════════════════════════
class _LoyaltyNoticeCard extends StatelessWidget {
  final String text;
  const _LoyaltyNoticeCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6), // soft yellow — matches the ⭐ theme
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3D06B), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⭐', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: CH.ink,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
