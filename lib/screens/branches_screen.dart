import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/cart_controller.dart';
import '../models/models.dart';
import '../services/branch_service.dart';
import '../theme/theme.dart';
import '../utils/ch_routes.dart';
import 'checkout_screen.dart';

/// Screen 12 — Branches (الفروع).
///
/// Two modes:
/// - **pickerMode: true** (default, used by Cart's pickup flow): rows carry
///   a radio, confirming the selection stores it on `CartController` and
///   pushes directly to Checkout.
/// - **pickerMode: false** (used by Profile → "فروعنا"): browse-only. No
///   radio, no confirm CTA, tapping a row jumps straight to the call /
///   directions actions sheet. **Nothing mutates the cart** — critical
///   because Profile is a settings-ish surface, not an order flow.
class BranchesScreen extends StatefulWidget {
  final bool pickerMode;
  const BranchesScreen({super.key, this.pickerMode = true});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  String? _selectedId;
  final ScrollController _scroll = ScrollController();

  List<Branch> _branches = const [];
  bool         _loading  = true;
  String?      _fetchError;

  /// Once the location permission flow is wired, flip this and populate
  /// each branch with `distanceKm` — we then sort ascending, closed last.
  static const bool _hasLocation = true;

  @override
  void initState() {
    super.initState();
    // Only pre-select in picker mode — browse mode has no radio and shouldn't
    // hint at a "current" selection tied to the cart.
    if (widget.pickerMode) {
      _selectedId = context.read<CartController>().branch?.id;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _fetchError = null; });
    try {
      final list = await context.read<BranchService>().fetchAll();
      if (!mounted) return;
      setState(() {
        _branches = list;
        _loading = false;
        // Pre-select the previously chosen branch if it survived the refresh.
        if (_selectedId != null &&
            !_branches.any((b) => b.id == _selectedId)) {
          _selectedId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchError = 'ما قدرنا نجيب الفروع — تأكد من الاتصال ثم جرّب مجدداً';
      });
    }
  }

  List<Branch> get _sorted {
    final list = List<Branch>.from(_branches);
    list.sort((a, b) {
      // Closed branches sink regardless of distance (spec §5).
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      final da = a.distanceKm ?? double.infinity;
      final db = b.distanceKm ?? double.infinity;
      return da.compareTo(db);
    });
    return list;
  }

  Branch? get _selected {
    if (_selectedId == null) return null;
    for (final b in _branches) {
      if (b.id == _selectedId) return b;
    }
    return null;
  }

  bool get _canConfirm => _selected != null && _selected!.isOpen;

  void _select(String id) {
    HapticFeedback.selectionClick();
    setState(() => _selectedId = id);
  }

  /// Row tap dispatch:
  ///  - browse mode → open call/directions actions.
  ///  - picker mode + open branch → select it.
  ///  - picker mode + closed branch → open the "why this is closed" sheet
  ///    INSTEAD of silently selecting. This kills the confusing "why is the
  ///    confirm button greyed out?" pattern — the user hears a clear reason
  ///    the moment they tap.
  void _onRowTap(Branch b) {
    if (!widget.pickerMode) {
      _openActions(b);
      return;
    }
    if (!b.isOpen) {
      _showClosedBranchSheet(b);
      return;
    }
    _select(b.id);
  }

  /// Bottom sheet that explains why the tapped branch can't accept an order
  /// right now, offers to call it, and gently nudges the user to pick a
  /// different open branch instead. Never selects the closed branch, so the
  /// confirm CTA stays enabled for whatever open branch was selected before.
  Future<void> _showClosedBranchSheet(Branch b) async {
    HapticFeedback.lightImpact();
    final openAt = _openingTime(b.hoursText);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          top: 20, left: 20, right: 20,
          bottom: 24 + MediaQuery.paddingOf(sheetCtx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44, height: 4,
                decoration: BoxDecoration(
                  color: CH.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Center(child: Text('🕒', style: TextStyle(fontSize: 44))),
            const SizedBox(height: 10),
            Text('هذا الفرع مغلق حالياً',
              textAlign: TextAlign.center,
              style: GoogleFonts.changa(
                fontSize: 20, fontWeight: FontWeight.w800, color: CH.ink)),
            const SizedBox(height: 6),
            Text(b.nameAr,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w700, color: CH.muted)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: CH.cream2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Text('⏰', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'بيفتح الساعة $openAt',
                  style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: const Color(0xFF6D5D51)))),
              ]),
            ),
            const SizedBox(height: 8),
            Text(
              'اختر فرعاً مفتوحاً من القائمة، أو اتصل بالفرع للاستفسار.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted,
                height: 1.6),
            ),
            const SizedBox(height: 22),
            _SheetCallButton(
              phone: b.phone,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _todoSnack('الاتصال بـ ${b.phone} قريباً');
              },
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: Text('إغلاق',
                  style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Extract the first `HH:MM` from a `"HH:MM — HH:MM"` string. Shared with
  /// the inline `_ClosedBranchNote` widget below — same source of truth.
  static String _openingTime(String hours) {
    final m = RegExp(r'\d{1,2}:\d{2}').firstMatch(hours);
    return m?.group(0) ?? hours;
  }

  void _confirm() {
    final b = _selected;
    if (b == null || !b.isOpen) return;
    context.read<CartController>().setPickupBranch(b);
    // Spec §6: after confirming, push directly to Checkout — Cart is skipped.
    // pushReplacement drops Branches from the stack so back from Checkout
    // lands on Cart.
    Navigator.of(context).pushReplacement(
      ChRoutes.slideUpFade((_) => const CheckoutScreen()),
    );
  }

  Future<void> _openActions(Branch b) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: CH.line, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 12),
              Text(b.nameAr,
                style: GoogleFonts.changa(
                  fontSize: 16, fontWeight: FontWeight.w800, color: CH.ink)),
              const SizedBox(height: 12),
              _ActionRow(
                icon: Icons.phone_outlined,
                label: 'اتصل بالفرع',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _todoSnack('الاتصال بـ ${b.phone} قريباً');
                },
              ),
              _ActionRow(
                icon: Icons.directions_outlined,
                label: 'الاتجاهات',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _todoSnack('فتح الخرائط قريباً');
                },
              ),
            ],
          ),
        ),
      ),
    );
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
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(milliseconds: 2000),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final isArabic  = Directionality.of(context) == TextDirection.rtl;
    final sorted    = _sorted;
    final allClosed = sorted.every((b) => !b.isOpen);
    final sel       = _selected;
    final showClosedNote = sel != null && !sel.isOpen;
    final topInset  = MediaQuery.paddingOf(context).top;

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
          body: ListView(
            controller: _scroll,
            padding: EdgeInsets.only(top: topInset + 8, bottom: 40),
            children: [
              // ────── Header ──────
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 14),
                child: Row(
                  children: [
                    _IconBoxButton(
                      glyph: isArabic ? '→' : '←',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.pickerMode ? 'اختر الفرع' : 'فروعنا',
                            style: GoogleFonts.changa(
                              fontSize: 23, fontWeight: FontWeight.w800, color: CH.ink),
                          ),
                          Text(
                            widget.pickerMode
                                ? 'للاستلام من المطعم'
                                : 'اتصل بالفرع أو احصل على الاتجاهات',
                            style: GoogleFonts.cairo(
                              fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ────── Map strip (placeholder — dark block + brand mark @ 20%) ──────
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                child: _MapStrip(dim: allClosed),
              ),

              // ────── No-location cream2 card (always shown until GPS lands) ──────
              if (!_hasLocation)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                  child: _EnableLocationCard(onEnable: () =>
                      _todoSnack('طلب صلاحية الموقع قريباً')),
                ),

              // ────── All-closed strip ──────
              if (allClosed)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                  child: _AllClosedStrip(),
                ),

              // ────── Loading / error / empty ──────
              if (_loading)
                const Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(16, 24, 16, 24),
                  child: Center(child: CircularProgressIndicator(color: CH.hot)),
                )
              else if (_fetchError != null)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 0),
                  child: _FetchErrorCard(msg: _fetchError!, onRetry: _fetch),
                )
              else if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 24),
                  child: Center(
                    child: Text('لا يوجد فروع متاحة حالياً',
                      style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w700, color: CH.muted)),
                  ),
                )
              else
                // ────── Branch rows ──────
                for (final b in sorted)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
                    child: _BranchRow(
                      branch:       b,
                      selected:     widget.pickerMode && b.id == _selectedId,
                      showRadio:    widget.pickerMode,
                      showDistance: _hasLocation && b.distanceKm != null,
                      onTap:        () => _onRowTap(b),
                      onOverflow:   () => _openActions(b),
                    ),
                  ),

              // ────── Closed-branch note + Confirm CTA — picker mode only ─
              if (widget.pickerMode) ...[
                if (showClosedNote)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 0),
                    child: _ClosedBranchNote(hours: sel.hoursText),
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 16, 0),
                  child: _ConfirmCta(
                    enabled: _canConfirm,
                    onTap:   _confirm,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Extra card used above.
class _FetchErrorCard extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _FetchErrorCard({required this.msg, required this.onRetry});
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
//  Offline-only fallback list (kept for Checkout's `branch ?? kBranches.first`
//  fallback when the delivery flow ships and needs a hard default).
//  With `BranchService` now wired above, this is only consulted if Checkout
//  hits a race where cart.branch is null for pickup — which shouldn't happen
//  in practice.
// ══════════════════════════════════════════════════════════════════
const List<Branch> kBranches = [
  Branch(
    id: 'b1',
    nameAr: 'كرانشي هت — الفرقان',
    nameEn: 'Crunchy Hot — Al-Furqan',
    shortNameAr: 'الفرقان',
    addressAr: 'شارع النيل، مقابل حديقة السبيل',
    phone: '+963946193094',
    isOpen: true,
    hoursText: '12:00 — 02:00',
    distanceKm: 1.2,
    lat: 36.2021, lng: 37.1343,
  ),
  Branch(
    id: 'b2',
    nameAr: 'كرانشي هت — الشهباء',
    nameEn: 'Crunchy Hot — Al-Shahbaa',
    shortNameAr: 'الشهباء',
    addressAr: 'ساحة سعد الله الجابري، بناء 5',
    phone: '+963946193094',
    isOpen: true,
    hoursText: '12:00 — 02:00',
    distanceKm: 3.4,
    lat: 36.2003, lng: 37.1400,
  ),
  Branch(
    id: 'b3',
    nameAr: 'كرانشي هت — الحمدانية',
    nameEn: 'Crunchy Hot — Hamdaniyah',
    shortNameAr: 'الحمدانية',
    addressAr: 'الحمدانية، دوار الحمدانية',
    phone: '+963946193094',
    isOpen: false,
    hoursText: '13:00 — 02:00',
    distanceKm: 5.6,
    lat: 36.1900, lng: 37.1100,
  ),
];

// ══════════════════════════════════════════════════════════════════
//  Map strip — placeholder until google_maps_flutter is wired
// ══════════════════════════════════════════════════════════════════
class _MapStrip extends StatelessWidget {
  final bool dim;
  const _MapStrip({required this.dim});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'خريطة الفروع',
      hint: 'قريباً',
      button: false,
      child: Container(
        height: 170,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CH.char,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Opacity(
          opacity: dim ? 0.70 : 1.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Brand mark @ 20% (spec §7 offline pattern — used until real map lands)
              Center(
                child: Opacity(
                  opacity: 0.20,
                  child: Image.asset(
                    'assets/crunchy-hot-logo.jpg',
                    width: 96,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: 10, start: 12,
                child: Text('🗺️  الخريطة قريباً',
                  style: GoogleFonts.cairo(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: CH.darkHeaderMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Enable-location cream2 card
// ══════════════════════════════════════════════════════════════════
class _EnableLocationCard extends StatelessWidget {
  final VoidCallback onEnable;
  const _EnableLocationCard({required this.onEnable});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CH.cream2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('📡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'فعّل الموقع لترتيب الفروع حسب الأقرب',
              style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF6D5D51)),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onEnable,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('تفعيل',
              style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.w800, color: CH.hot)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  All-closed strip (dark)
// ══════════════════════════════════════════════════════════════════
class _AllClosedStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CH.char,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'كل الفروع مقفلة حالياً · تفتح 12:00',
        style: GoogleFonts.cairo(
          fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Closed branch cream2 note
// ══════════════════════════════════════════════════════════════════
class _ClosedBranchNote extends StatelessWidget {
  final String hours;
  const _ClosedBranchNote({required this.hours});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CH.cream2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('⏰', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'هذا الفرع مقفل — بيفتح ${_openingTime(hours)}',
              style: GoogleFonts.cairo(
                fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF6D5D51)),
            ),
          ),
        ],
      ),
    );
  }

  /// Grab the first `HH:MM` from a `"HH:MM — HH:MM"` string.
  static String _openingTime(String hours) {
    final m = RegExp(r'\d{1,2}:\d{2}').firstMatch(hours);
    return m?.group(0) ?? hours;
  }
}

// ══════════════════════════════════════════════════════════════════
//  Branch row
// ══════════════════════════════════════════════════════════════════
class _BranchRow extends StatelessWidget {
  final Branch branch;
  final bool   selected;
  /// Picker mode → show the radio dot and let `selected` colour the border.
  /// Browse mode → drop the radio, keep the overflow "..." for actions.
  final bool   showRadio;
  final bool   showDistance;
  final VoidCallback onTap;
  final VoidCallback onOverflow;

  const _BranchRow({
    required this.branch,
    required this.selected,
    required this.showRadio,
    required this.showDistance,
    required this.onTap,
    required this.onOverflow,
  });

  @override
  Widget build(BuildContext context) {
    final distText = branch.distanceKm == null
        ? ''
        : (branch.distanceKm! < 1
            ? '${(branch.distanceKm! * 1000 / 50).round() * 50} م'
            : '${branch.distanceKm!.toStringAsFixed(1)} كم');

    return Semantics(
      button: true, selected: selected, inMutuallyExclusiveGroup: true,
      label: '${branch.nameAr}, ${branch.isOpen ? "مفتوح" : "مغلق"}, ${branch.addressAr}, ${branch.hoursText}${showDistance && distText.isNotEmpty ? ", $distText" : ""}',
      child: Opacity(
        opacity: branch.isOpen ? 1.0 : 0.65,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? CH.hot : Colors.transparent,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E1D12).withValues(alpha: 0.05),
                    offset: const Offset(0, 6),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Name + status tag
                        Row(
                          children: [
                            Flexible(
                              child: Text(branch.nameAr,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.changa(
                                  fontSize: 16, fontWeight: FontWeight.w800, color: CH.ink)),
                            ),
                            const SizedBox(width: 8),
                            _StatusTag(open: branch.isOpen),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(branch.addressAr,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
                        const SizedBox(height: 3),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            _hoursDistLine(branch, distText, showDistance),
                            style: GoogleFonts.cairo(
                              fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showRadio) ...[
                        _Radio(selected: selected),
                        const SizedBox(height: 8),
                      ],
                      Semantics(
                        button: true, label: 'خيارات إضافية',
                        child: SizedBox(
                          width: 36, height: 36,
                          child: InkResponse(
                            onTap: onOverflow,
                            radius: 20,
                            child: const Icon(Icons.more_horiz_rounded,
                              size: 20, color: CH.muted),
                          ),
                        ),
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

  static String _hoursDistLine(Branch b, String dist, bool showDist) {
    final left = '🕒 ${b.hoursText}';
    return showDist && dist.isNotEmpty ? '$left  ·  🚶 $dist' : left;
  }
}

// ── Status tag ──
class _StatusTag extends StatelessWidget {
  final bool open;
  const _StatusTag({required this.open});
  @override
  Widget build(BuildContext context) {
    final bg   = open ? const Color(0x1F2FA84F) : const Color(0x1AE11D2A);
    final fg   = open ? CH.green : CH.red;
    final text = open ? 'مفتوح' : 'مغلق';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
        style: GoogleFonts.cairo(
          fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

// ── Radio (shared with saved-address rows visually) ──
class _Radio extends StatelessWidget {
  final bool selected;
  const _Radio({required this.selected});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 20, height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? CH.hot : Colors.white,
        border: Border.all(
          color: selected ? CH.hot : const Color(0xFFDCCBBA),
          width: 1.5,
        ),
      ),
      child: !selected ? null : Center(
        child: Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Top-bar icon button (matches other screens)
// ══════════════════════════════════════════════════════════════════
class _IconBoxButton extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  const _IconBoxButton({required this.glyph, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Semantics(
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
}

// ══════════════════════════════════════════════════════════════════
//  Closed-branch sheet — primary "Call" button. Kept local so this
//  screen owns its own button style without touching the widget lib.
// ══════════════════════════════════════════════════════════════════
class _SheetCallButton extends StatelessWidget {
  final String phone;
  final VoidCallback onTap;
  const _SheetCallButton({required this.phone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CH.hot,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: CH.hotDeep.withValues(alpha: 0.25),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_outlined, size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Text('اتصل بالفرع',
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Actions sheet row (call / directions)
// ══════════════════════════════════════════════════════════════════
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Row(
          children: [
            Icon(icon, size: 22, color: CH.ink),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                style: GoogleFonts.cairo(
                  fontSize: 15, fontWeight: FontWeight.w700, color: CH.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Confirm CTA (inline, per spec §2 — no fixed bar)
// ══════════════════════════════════════════════════════════════════
class _ConfirmCta extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _ConfirmCta({required this.enabled, required this.onTap});

  @override
  State<_ConfirmCta> createState() => _ConfirmCtaState();
}

class _ConfirmCtaState extends State<_ConfirmCta> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, enabled: widget.enabled,
      hint: widget.enabled ? null : 'اختر فرعاً مفتوحاً',
      child: AnimatedScale(
        scale: widget.enabled && _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: widget.enabled ? ChShadows.primaryButton : null,
          ),
          child: Material(
            color: !widget.enabled ? CH.line : (_pressed ? CH.hotDeep : CH.hot),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: widget.enabled ? widget.onTap : null,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Center(
                  child: Text('تأكيد الفرع',
                    style: GoogleFonts.changa(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: widget.enabled ? Colors.white : CH.inactive)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
