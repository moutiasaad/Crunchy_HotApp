import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/orders_controller.dart';
import '../models/models.dart';
import '../theme/theme.dart';

/// Screen 15 — Rating (التقييم).
///
/// One-tap quality signal after delivery. Always skippable via `لاحقاً`;
/// never blocks the app. Reached with `pushReplacement` from Tracking's
/// delivered state, so back = same as `لاحقاً` (routes Home).
class RatingScreen extends StatefulWidget {
  final String    orderId;
  final OrderMode mode;
  final bool      paymentIsCash;
  final String    heroEmoji;

  const RatingScreen({
    super.key,
    required this.orderId,
    required this.mode,
    this.paymentIsCash = true,
    this.heroEmoji     = '🍗',
  });

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int _stars = 0;
  final Set<String> _tags = {};
  final TextEditingController _note = TextEditingController();
  int? _tip;             // 2000 / 5000 / 10000 — SYP; null = none
  bool _busy = false;
  int  _lastTappedStar = 0;
  Timer? _popTimer;

  // ─── Tag sets (spec §3) ────────────────────────────────────
  static const _positiveTags = [
    'وصل سخن', 'توصيل سريع', 'طعم ممتاز', 'تغليف نظيف',
  ];
  static const _negativeTags = [
    'وصل بارد', 'تأخر التوصيل', 'الطلب ناقص', 'الطعم مو منيح', 'تغليف سيء',
  ];

  bool get _isPickup   => widget.mode == OrderMode.pickup;
  bool get _isPositive => _stars >= 4;
  List<String> get _currentTagSet => _isPositive ? _positiveTags : _negativeTags;
  bool get _showTipCard => _stars >= 4 && !_isPickup;
  bool get _canSubmit   => _stars > 0 && !_busy;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    _popTimer?.cancel();
    super.dispose();
  }

  // ─── Actions ───────────────────────────────────────────────

  void _setStars(int v, {bool haptic = true}) {
    if (v == _stars) return;
    if (haptic) HapticFeedback.selectionClick();
    setState(() {
      _stars           = v;
      _lastTappedStar  = v;
      // Reset tag selection since the tag set may swap.
      _tags.clear();
      // Hide the tip if user drops below the positive threshold.
      if (!_isPositive) _tip = null;
    });
    _popTimer?.cancel();
    _popTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _lastTappedStar = 0);
    });
  }

  void _goHome() {
    // Sync history before we leave — covers Later, Submit, and error paths.
    // Without this the just-completed order stays in whatever status the local
    // Order snapshot held when Checkout ran; the Orders tab is kept alive in
    // the shell's IndexedStack, so `initState` won't re-fire on tab visit.
    unawaited(context.read<OrdersController>().refresh());
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    try {
      // TODO: OrderService.review() when it's wired. For now, fake it +
      // spec §4: on failure queue locally — don't ever show retry dialog.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      if (_stars <= 3) {
        await _showLowScoreSheet();
        if (!mounted) return;
      }

      _goHome();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('شكراً لتقييمك 🙏',
            style: GoogleFonts.cairo(
              fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          backgroundColor: CH.char,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          duration: const Duration(seconds: 3),
        ));
    } catch (_) {
      // Rating failures are queued silently (spec §4). Fall back to Home.
      if (!mounted) return;
      _goHome();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('رح ينرسل تقييمك لما يرجع الاتصال',
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _showLowScoreSheet() async {
    final wantsRefund = _tags.contains('الطلب ناقص');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 12,
          bottom: 20 + MediaQuery.paddingOf(sheetCtx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: CH.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('آسفين على هالتجربة',
              textAlign: TextAlign.center,
              style: GoogleFonts.changa(
                fontSize: 20, fontWeight: FontWeight.w800, color: CH.ink)),
            const SizedBox(height: 8),
            Text('فريقنا رح يتواصل معك خلال ساعة.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 14, height: 1.6, color: CH.muted)),
            const SizedBox(height: 20),
            _SheetPrimary(
              label: 'تواصل معنا هلق',
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _todoSnack('فتح واتساب قريباً');
              },
            ),
            if (wantsRefund) ...[
              const SizedBox(height: 10),
              _SheetGhost(
                label: 'اطلب استرجاع',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _todoSnack('تقديم طلب الاسترجاع قريباً');
                },
              ),
            ],
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(sheetCtx).pop(),
              child: Text('تمام',
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800, color: CH.muted)),
            ),
          ],
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
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        duration: const Duration(milliseconds: 2000),
      ));
  }

  // ─── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.4,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _goHome();
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            body: IgnorePointer(
              ignoring: _busy,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(24, topInset + 20, 24, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _ItemThumb(emoji: widget.heroEmoji),
                          const SizedBox(height: 18),
                          Text('كيف كانت وجبتك؟',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.changa(
                              fontSize: 24, fontWeight: FontWeight.w800, color: CH.ink)),
                          const SizedBox(height: 6),
                          Text('تقييمك يساعدنا نضل مقرمشين 🐓',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(
                              fontSize: 14, height: 1.7, color: CH.muted)),
                          const SizedBox(height: 22),

                          _StarRow(
                            value:       _stars,
                            lastTapped:  _lastTappedStar,
                            onChanged:   (v) => _setStars(v),
                            onCross:     (v) => _setStars(v, haptic: v != _stars),
                          ),
                          const SizedBox(height: 8),

                          _RatingWord(stars: _stars),
                          const SizedBox(height: 22),

                          // Tags fade in only once the user has picked a rating.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                            child: _stars == 0
                                ? const SizedBox.shrink(key: ValueKey('no-tags'))
                                : _TagCloud(
                                    key: ValueKey(_isPositive ? 'pos' : 'neg'),
                                    tags: _currentTagSet,
                                    selected: _tags,
                                    onToggle: (t) => setState(() {
                                      if (!_tags.add(t)) _tags.remove(t);
                                    }),
                                  ),
                          ),
                          const SizedBox(height: 20),

                          _NoteBox(controller: _note),

                          if (_showTipCard) ...[
                            const SizedBox(height: 16),
                            _TipCard(
                              value:     _tip,
                              cash:      widget.paymentIsCash,
                              onPick:    (v) => setState(() => _tip = _tip == v ? null : v),
                            ),
                          ],
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  _ActionBar(
                    canSubmit: _canSubmit,
                    busy:      _busy,
                    onLater:   _goHome,
                    onSubmit:  _submit,
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

// ══════════════════════════════════════════════════════════════════
//  Item thumb — 88 sq cream + inner cream2 with hero glyph
// ══════════════════════════════════════════════════════════════════
class _ItemThumb extends StatelessWidget {
  final String emoji;
  const _ItemThumb({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: 88, height: 88,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: CH.cream,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: CH.cream2,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 36)),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Star row — 5 stars, tap or drag; always LTR (spec §9)
// ══════════════════════════════════════════════════════════════════
class _StarRow extends StatelessWidget {
  final int value;
  final int lastTapped;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onCross;
  const _StarRow({
    required this.value, required this.lastTapped,
    required this.onChanged, required this.onCross,
  });

  static const _starSize = 44.0;   // hit box
  static const _gap      = 10.0;

  int _starFromDx(double dx, double totalWidth) {
    // Divide the row into 5 equal slices; clamp to [1, 5].
    final slice = totalWidth / 5;
    final idx   = (dx / slice).floor() + 1;
    return idx.clamp(1, 5);
  }

  @override
  Widget build(BuildContext context) {
    // Fixed intrinsic width so the drag calculation is stable.
    const rowW = _starSize * 5 + _gap * 4;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Semantics(
        slider: true,
        value: '$value من 5',
        increasedValue: '${(value + 1).clamp(1, 5)} من 5',
        decreasedValue: '${(value - 1).clamp(1, 5)} من 5',
        onIncrease: () => onChanged((value + 1).clamp(1, 5)),
        onDecrease: () => onChanged((value - 1).clamp(1, 5)),
        child: SizedBox(
          width: rowW,
          height: _starSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onChanged(_starFromDx(d.localPosition.dx, rowW)),
            onHorizontalDragUpdate: (d) =>
                onCross(_starFromDx(d.localPosition.dx, rowW)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 1; i <= 5; i++) ...[
                  _Star(filled: i <= value, popping: i == lastTapped),
                  if (i != 5) const SizedBox(width: _gap),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Star extends StatelessWidget {
  final bool filled;
  final bool popping;
  const _Star({required this.filled, required this.popping});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: 44, height: 44,
      child: Center(
        child: AnimatedScale(
          scale: (popping && !reduceMotion) ? 1.25 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 160),
            style: TextStyle(
              fontSize: 32,
              color: filled ? CH.yellow : const Color(0xFFE6D6C6),
              height: 1,
              fontFamilyFallback: const ['Cairo'],
            ),
            child: const Text('★'),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Rating word (cross-fades on change)
// ══════════════════════════════════════════════════════════════════
class _RatingWord extends StatelessWidget {
  final int stars;
  const _RatingWord({required this.stars});

  static const _words = <int, String>{
    1: 'سيئ', 2: 'مقبول', 3: 'جيد', 4: 'جيد جداً', 5: 'ممتاز 🔥',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Semantics(
        liveRegion: true,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: stars == 0
              ? const SizedBox.shrink(key: ValueKey('empty'))
              : Text(
                  _words[stars]!,
                  key: ValueKey(stars),
                  style: GoogleFonts.cairo(
                    fontSize: 15, fontWeight: FontWeight.w800, color: CH.hot),
                ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Tag cloud — wrapping chips (multi-select)
// ══════════════════════════════════════════════════════════════════
class _TagCloud extends StatelessWidget {
  final List<String> tags;
  final Set<String>  selected;
  final ValueChanged<String> onToggle;
  const _TagCloud({
    super.key,
    required this.tags, required this.selected, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final t in tags)
          _TagChip(
            label: t,
            selected: selected.contains(t),
            onTap: () => onToggle(t),
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TagChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: selected,
      button: true,
      label: label,
      child: Material(
        color: selected ? CH.char : Colors.white,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              shape: StadiumBorder(
                side: BorderSide(color: selected ? CH.char : CH.line, width: 1.5)),
            ),
            child: Text(label,
              style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: selected ? Colors.white : CH.ink)),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Comment box — cream field with counter past 240 chars
// ══════════════════════════════════════════════════════════════════
class _NoteBox extends StatelessWidget {
  final TextEditingController controller;
  const _NoteBox({required this.controller});

  static const int _softLimit = 240;
  static const int _hardLimit = 300;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 22),
          decoration: BoxDecoration(
            color: CH.cream,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CH.line, width: 1.5),
          ),
          child: TextField(
            controller:      controller,
            minLines:        3,
            maxLines:        6,
            maxLength:       _hardLimit,
            textInputAction: TextInputAction.newline,
            cursorColor:     CH.hot,
            style: GoogleFonts.cairo(
              fontSize: 14, fontWeight: FontWeight.w600, color: CH.ink, height: 1.6),
            decoration: InputDecoration(
              counterText:        '',
              isDense:            true,
              border:             InputBorder.none,
              enabledBorder:      InputBorder.none,
              focusedBorder:      InputBorder.none,
              errorBorder:        InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder:     InputBorder.none,
              filled:             false,
              fillColor:          Colors.transparent,
              contentPadding:     EdgeInsets.zero,
              hintText: 'اكتب ملاحظتك (اختياري)…',
              hintStyle: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: const Color(0xFFB3A396)),
            ),
          ),
        ),
        if (controller.text.length > _softLimit)
          PositionedDirectional(
            end: 12, bottom: 8,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text('${controller.text.length}/$_hardLimit',
                style: GoogleFonts.cairo(
                  fontSize: 11, fontWeight: FontWeight.w600, color: CH.muted)),
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Tip card — cream card + amount chips (2k / 5k / 10k)
// ══════════════════════════════════════════════════════════════════
class _TipCard extends StatelessWidget {
  final int? value;
  final bool cash;
  final ValueChanged<int> onPick;
  const _TipCard({required this.value, required this.cash, required this.onPick});

  static const _options = <(int, String)>[
    (2000,  '2k'),
    (5000,  '5k'),
    (10000, '10k'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CH.cream,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('🛵', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('إكرامية للسائق',
                      style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
                    const SizedBox(height: 2),
                    Text('كامل المبلغ يوصل للسائق',
                      style: GoogleFonts.cairo(
                        fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final (v, label) in _options)
                      _TipChip(
                        label: label,
                        selected: value == v,
                        onTap: () => onPick(v),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (cash && value != null) ...[
            const SizedBox(height: 8),
            Text('بتنعطى للسائق نقداً',
              style: GoogleFonts.cairo(
                fontSize: 11, fontWeight: FontWeight.w600, color: CH.muted)),
          ],
        ],
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TipChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, selected: selected, inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? CH.char : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? CH.char : CH.line, width: 1.5),
            ),
            child: Text(label,
              style: GoogleFonts.cairo(
                fontSize: 12, fontWeight: FontWeight.w800,
                color: selected ? Colors.white : CH.ink)),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Action bar (fixed): [لاحقاً] [إرسال التقييم]
// ══════════════════════════════════════════════════════════════════
class _ActionBar extends StatelessWidget {
  final bool canSubmit;
  final bool busy;
  final VoidCallback onLater;
  final VoidCallback onSubmit;
  const _ActionBar({
    required this.canSubmit, required this.busy,
    required this.onLater,   required this.onSubmit,
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
      child: Row(
        children: [
          // `لاحقاً` leads in both directions (spec §9). It's placed first in
          // the row for the accessibility tab order requirement.
          _LaterBtn(onTap: busy ? () {} : onLater, disabled: busy),
          const SizedBox(width: 10),
          Expanded(child: _SubmitBtn(
            enabled: canSubmit,
            busy:    busy,
            onTap:   onSubmit,
          )),
        ],
      ),
    );
  }
}

class _LaterBtn extends StatelessWidget {
  final VoidCallback onTap;
  final bool disabled;
  const _LaterBtn({required this.onTap, required this.disabled});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, label: 'لاحقاً', enabled: !disabled,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CH.line, width: 1.5),
            ),
            child: Text('لاحقاً',
              style: GoogleFonts.cairo(
                fontSize: 15, fontWeight: FontWeight.w800, color: CH.muted)),
          ),
        ),
      ),
    );
  }
}

class _SubmitBtn extends StatefulWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  const _SubmitBtn({required this.enabled, required this.busy, required this.onTap});

  @override
  State<_SubmitBtn> createState() => _SubmitBtnState();
}

class _SubmitBtnState extends State<_SubmitBtn> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && !widget.busy;
    return Semantics(
      button: true, enabled: active, label: 'إرسال التقييم',
      child: AnimatedScale(
        scale: active && _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: active ? ChShadows.primaryButton : null,
          ),
          child: Material(
            color: !active ? CH.line : (_pressed ? CH.hotDeep : CH.hot),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: active ? widget.onTap : null,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Center(
                  child: widget.busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text('إرسال التقييم',
                          style: GoogleFonts.changa(
                            fontSize: 16, fontWeight: FontWeight.w800,
                            color: active ? Colors.white : CH.inactive)),
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
//  Low-score sheet buttons
// ══════════════════════════════════════════════════════════════════
class _SheetPrimary extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SheetPrimary({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
}

class _SheetGhost extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SheetGhost({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CH.line, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(label,
            style: GoogleFonts.cairo(
              fontSize: 15, fontWeight: FontWeight.w800, color: CH.ink)),
        ),
      ),
    );
  }
}
