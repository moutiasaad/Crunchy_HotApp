import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/cart_controller.dart';
import '../controllers/search_controller.dart';
import '../models/models.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import '../widgets/widgets.dart';
import '../utils/ch_routes.dart';
import 'app_shell.dart';
import 'detail_screen.dart';

/// Screen 06 — Search (البحث). MVCS-wired.
///
/// Query / filter / results / recents live on [CatalogSearchController].
/// Cart add-to goes through [CartController]. This widget owns only the
/// text controller and the active bottom-nav tab.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _q = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _q.addListener(_onQueryChanged);
    _focus.addListener(() => setState(() {}));
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _q.removeListener(_onQueryChanged);
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    context.read<CatalogSearchController>().setQuery(_q.text);
    setState(() {});   // for the ✕ button + focused-border pulse
  }

  // ─────────────────── Actions ───────────────────
  Future<void> _submitAndPersist(String term) async {
    await context.read<CatalogSearchController>().commitAsRecent(term);
  }

  Future<void> _openProduct(Product p) async {
    await _submitAndPersist(_q.text);
    if (!mounted) return;
    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => DetailScreen(product: p)),
    );
  }

  void _addToCart(Product p) {
    HapticFeedback.lightImpact();
    context.read<CartController>().add(p);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('أُضيف ${p.nameAr} للسلة',
            style: GoogleFonts.cairo(
              fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(milliseconds: 2500),
        action: SnackBarAction(
          label: 'عرض السلة', textColor: CH.hot,
          onPressed: () {
            Navigator.of(context).maybePop();
            AppShell.switchTo(context, 2);
          },
        ),
      ));
  }

  void _pickRecent(String term) {
    _q.text = term;
    _q.selection = TextSelection.collapsed(offset: term.length);
    _focus.requestFocus();
  }

  // ─────────────────── Build ───────────────────
  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final search   = context.watch<CatalogSearchController>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: CH.cream,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ────── 1) Search bar row ──────
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
                child: Row(children: [
                  _IconBoxButton(
                    glyph: isArabic ? '→' : '←',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SearchField(
                      controller: _q,
                      focusNode: _focus,
                      onSubmitted: _submitAndPersist,
                      onClear: () {
                        _q.clear();
                        _focus.requestFocus();
                      },
                    ),
                  ),
                ]),
              ),

              // ────── 2) Filter chip rail ──────
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                  itemCount: SearchFilter.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final f = SearchFilter.values[i];
                    return ChChip(
                      label: f.labelAr,
                      emoji: f.emoji,
                      selected: search.filter == f,
                      onTap: () => context.read<CatalogSearchController>().setFilter(f),
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              // ────── 3) Result count line ──────
              if (search.hasQuery && !search.loading && !search.isEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_fmtResultCount(search.results.length),
                          style: GoogleFonts.cairo(
                            fontSize: 13, fontWeight: FontWeight.w700, color: CH.muted)),
                    ),
                  ),
                ),

              // ────── 4) Body ──────
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                  child: switch ((search.hasQuery, search.loading, search.results.isEmpty)) {
                    (false, _, _) => _RecentsAndPopular(
                        key: const ValueKey('recents'),
                        recents: search.recents,
                        onPick: _pickRecent,
                        onRemove: (t) => context.read<CatalogSearchController>().removeRecent(t),
                        onClearAll: () => context.read<CatalogSearchController>().clearRecents(),
                      ),
                    (true, true, _) => _LoadingSkeleton(
                        key: const ValueKey('loading'),
                        previous: search.results,
                      ),
                    (true, false, true) => _EmptyState(
                        key: const ValueKey('empty'),
                        query: _q.text,
                        onBrowse: () => Navigator.of(context).maybePop(),
                      ),
                    (true, false, false) => _ResultList(
                        key: const ValueKey('results'),
                        results: search.results,
                        query: _q.text,
                        onOpen: _openProduct,
                        onAdd:  _addToCart,
                      ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtResultCount(int n) {
    if (n == 0) return 'ما في نتائج';
    if (n == 1) return 'نتيجة واحدة';
    if (n == 2) return 'نتيجتان';
    if (n >= 3 && n <= 10) return '$n نتائج';
    return '$n نتيجة';
  }
}

// ══════════════════════════════════════════════════════════════════
//  Search field — leading 🔍, trailing ✕ when non-empty
// ══════════════════════════════════════════════════════════════════
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller, required this.focusNode,
    required this.onSubmitted, required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: focused ? CH.hot : CH.line, width: 1.5),
      ),
      child: Row(children: [
        const Icon(Icons.search, size: 15, color: CH.muted),
        const SizedBox(width: 9),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.text,
            onSubmitted: onSubmitted,
            cursorColor: CH.hot,
            style: GoogleFonts.cairo(
              fontSize: 14, fontWeight: FontWeight.w700, color: CH.ink),
            decoration: InputDecoration(
              isDense: true,
              border:            InputBorder.none,
              enabledBorder:     InputBorder.none,
              focusedBorder:     InputBorder.none,
              errorBorder:       InputBorder.none,
              focusedErrorBorder:InputBorder.none,
              disabledBorder:    InputBorder.none,
              filled:            false,
              fillColor:         Colors.transparent,
              contentPadding:    EdgeInsets.zero,
              hintText: 'دور على وجبتك المفضلة…',
              hintStyle: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: const Color(0xFFB3A396)),
            ),
          ),
        ),
        if (controller.text.isNotEmpty)
          Semantics(
            button: true, label: 'مسح البحث',
            child: SizedBox(
              width: 44, height: 44,
              child: InkResponse(
                onTap: onClear,
                radius: 22,
                child: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFC9B6A6)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _IconBoxButton extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  const _IconBoxButton({required this.glyph, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Recents + popular searches (idle state)
// ══════════════════════════════════════════════════════════════════
class _RecentsAndPopular extends StatelessWidget {
  final List<String> recents;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onRemove;
  final VoidCallback onClearAll;

  const _RecentsAndPopular({
    super.key,
    required this.recents, required this.onPick,
    required this.onRemove, required this.onClearAll,
  });

  static const _popular = ['شاورما', 'برجر', 'بروستد', 'مشروبات', 'أجنحة'];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (recents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 10),
            child: Row(children: [
              Expanded(
                child: Text('آخر ما بحثت عنه',
                  style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
              ),
              InkWell(
                onTap: onClearAll,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text('مسح الكل',
                    style: GoogleFonts.cairo(
                      fontSize: 13, fontWeight: FontWeight.w800, color: CH.hot)),
                ),
              ),
            ]),
          ),
          for (final term in recents)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
              child: _RecentRow(
                term: term,
                onTap: () => onPick(term),
                onRemove: () => onRemove(term),
              ),
            ),
          const SizedBox(height: 22),
        ],
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 10),
          child: Text('الأكثر بحثاً',
            style: GoogleFonts.cairo(
              fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              for (final term in _popular)
                ChChip(label: term, onTap: () => onPick(term)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  final String term;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _RecentRow({required this.term, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            const Text('🕘', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(term,
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w700, color: CH.ink)),
            ),
            Semantics(
              button: true, label: 'إزالة من السجل',
              child: SizedBox(
                width: 44, height: 44,
                child: InkResponse(
                  onTap: onRemove,
                  radius: 22,
                  child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFC9B6A6)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Loading + skeleton
// ══════════════════════════════════════════════════════════════════
class _LoadingSkeleton extends StatelessWidget {
  final List<Product> previous;
  const _LoadingSkeleton({super.key, required this.previous});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 26),
      children: [
        for (final p in previous) ...[
          Opacity(
            opacity: 0.40,
            child: _ProductRow(product: p, query: '', onTap: () {}, onAdd: () {}),
          ),
          const SizedBox(height: 12),
        ],
        for (int i = 0; i < 3; i++) ...[
          const _SkeletonRow(),
          if (i != 2) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ChShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76, height: 76,
            decoration: BoxDecoration(color: CH.cream2, borderRadius: BorderRadius.circular(14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 14, width: 160, color: CH.cream2),
                const SizedBox(height: 8),
                Container(height: 10, width: 120, color: CH.cream2),
                const SizedBox(height: 12),
                Container(height: 12, width: 80, color: CH.cream2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Empty + Results
// ══════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final String query;
  final VoidCallback onBrowse;
  const _EmptyState({super.key, required this.query, required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    // Wrap in a scroll view so a keyboard-eaten viewport can never overflow
    // this Column — the 56 pt emoji + two text lines + CTA is tight on
    // shorter phones once the search keyboard is up.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('ما لقينا شي بهذا الاسم',
              textAlign: TextAlign.center,
              style: GoogleFonts.changa(
                fontSize: 18, fontWeight: FontWeight.w800, color: CH.ink)),
            const SizedBox(height: 6),
            Text('"$query" — جرّب كلمة تانية أو تصفّح المنيو',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(fontSize: 14, color: CH.muted, height: 1.6)),
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

class _ResultList extends StatelessWidget {
  final List<Product> results;
  final String query;
  final ValueChanged<Product> onOpen;
  final ValueChanged<Product> onAdd;

  const _ResultList({
    super.key,
    required this.results, required this.query,
    required this.onOpen,  required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 26),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _ProductRow(
        product: results[i],
        query: query,
        onTap: () => onOpen(results[i]),
        onAdd: () => onAdd(results[i]),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final Product product;
  final String query;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const _ProductRow({
    required this.product, required this.query,
    required this.onTap, required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: ChShadows.card,
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'product-${product.id}',
                child: Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(color: CH.cream2, borderRadius: BorderRadius.circular(14)),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: (product.imageUrl == null || product.imageUrl!.isEmpty)
                      ? Text(product.emoji, style: const TextStyle(fontSize: 44))
                      : Image.network(
                          product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Text(product.emoji, style: const TextStyle(fontSize: 44)),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _HighlightedName(name: product.nameAr, query: query),
                    const SizedBox(height: 4),
                    Text(product.descriptionAr,
                      style: GoogleFonts.cairo(
                        fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(ChMoney.format(product.price),
                        style: GoogleFonts.changa(
                          fontSize: 16, fontWeight: FontWeight.w800, color: CH.hot)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'أضف ${product.nameAr} للسلة',
                child: SizedBox(
                  width: 44, height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 36, height: 36,
                      child: Material(
                        color: CH.char,
                        borderRadius: BorderRadius.circular(11),
                        child: InkWell(
                          onTap: onAdd,
                          borderRadius: BorderRadius.circular(11),
                          child: const Icon(Icons.add, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
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

class _HighlightedName extends StatelessWidget {
  final String name;
  final String query;
  const _HighlightedName({required this.name, required this.query});

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.changa(
      fontSize: 16, fontWeight: FontWeight.w800, color: CH.ink);
    final hot  = base.copyWith(color: CH.hot);

    final q = query.trim();
    if (q.length < 2) {
      return Text(name, style: base, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final low    = name.toLowerCase();
    final needle = q.toLowerCase();
    final idx    = low.indexOf(needle);
    if (idx < 0) {
      return Text(name, style: base, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    return Text.rich(
      TextSpan(children: [
        TextSpan(text: name.substring(0, idx), style: base),
        TextSpan(text: name.substring(idx, idx + needle.length), style: hot),
        TextSpan(text: name.substring(idx + needle.length), style: base),
      ]),
      maxLines: 2, overflow: TextOverflow.ellipsis,
    );
  }
}
