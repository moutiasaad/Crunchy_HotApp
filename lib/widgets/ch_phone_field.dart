import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/dial_code.dart';
import '../theme/theme.dart';

/// Phone input with a leading dial-code picker.
///
/// Layout (LTR forced so the +NNN and digits keep their natural order even
/// inside an RTL screen):
///
///   [ 🇸🇾 +963 ▾ | 946 123 456                 ✓ ]
///
/// Tapping the leading chip opens a bottom-sheet country list with a search
/// box. Selecting a country calls [onCountryChanged] and re-emits [onChanged]
/// with the new E.164 value.
///
/// The widget exposes value **and** validity via callbacks so the parent
/// screen can drive its own CTA-enabled state. E.164 output is normalised
/// (strips whitespace and any leading zero on the national number).
class ChPhoneField extends StatefulWidget {
  /// Initial phone as an E.164 string (e.g. `+963946193094`), or null for a
  /// fresh field defaulting to [DialCodes.defaultCode].
  final String? initialE164;

  /// Fires whenever either the country OR the local number changes. Value
  /// is the current E.164 (or an incomplete `+963...` prefix if the user
  /// hasn't finished typing).
  final ValueChanged<String>? onChanged;

  /// Fires when the user picks a new country from the sheet.
  final ValueChanged<DialCode>? onCountryChanged;

  /// Optional inline error text (red border + line below).
  final String? errorText;

  /// Focus node exposed so a parent form can focus/blur programmatically.
  final FocusNode? focusNode;

  /// Called when the user submits the field (return key on keyboard).
  final ValueChanged<String>? onSubmitted;

  const ChPhoneField({
    super.key,
    this.initialE164,
    this.onChanged,
    this.onCountryChanged,
    this.errorText,
    this.focusNode,
    this.onSubmitted,
  });

  @override
  State<ChPhoneField> createState() => _ChPhoneFieldState();
}

class _ChPhoneFieldState extends State<ChPhoneField> {
  late DialCode _country;
  late final TextEditingController _local = TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    final init = widget.initialE164;
    if (init != null && init.isNotEmpty) {
      _country = DialCodes.fromE164(init);
      // Trim off the country code from the E.164 to recover the local part.
      _local.text = init.startsWith(_country.code)
          ? init.substring(_country.code.length)
          : init.replaceAll(RegExp(r'^\+'), '');
    } else {
      _country = DialCodes.defaultCode;
    }
    _local.addListener(_onLocalChanged);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _local.dispose();
    // Only dispose the focus node if we created it internally.
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _onLocalChanged() {
    widget.onChanged?.call(_country.toE164(_local.text));
    setState(() {}); // rebuild for the trailing check-mark
  }

  Future<void> _openPicker() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<DialCode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _DialCodePicker(current: _country),
    );
    if (picked == null || !mounted) return;
    setState(() => _country = picked);
    widget.onCountryChanged?.call(picked);
    widget.onChanged?.call(_country.toE164(_local.text));
  }

  bool get _valid => _country.isValidLocal(_local.text);

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final focused  = _focus.hasFocus;
    final Color borderColor = hasError
        ? CH.red
        : (focused || _valid) ? CH.hot : CH.line;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: focused ? const Color(0xFFFFF7F2) : CH.cream,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Row(children: [
              _DialCodeChip(country: _country, onTap: _openPicker),
              Container(width: 1, height: 26, color: CH.line),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _local,
                  focusNode:  _focus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [
                    // Accept ASCII + Arabic-Indic digits — normalised on emit.
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩\s]')),
                    LengthLimitingTextInputFormatter(_country.maxLocalDigits + 4),
                  ],
                  onSubmitted: widget.onSubmitted,
                  cursorColor: CH.hot,
                  style: GoogleFonts.cairo(
                    fontSize: 16, fontWeight: FontWeight.w700, color: CH.ink,
                    letterSpacing: 0.5),
                  decoration: InputDecoration(
                    border:             InputBorder.none,
                    enabledBorder:      InputBorder.none,
                    focusedBorder:      InputBorder.none,
                    errorBorder:        InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    disabledBorder:     InputBorder.none,
                    filled:             false,
                    isDense:            true,
                    contentPadding:     const EdgeInsets.symmetric(vertical: 14),
                    hintText: 'رقم موبايلك',
                    hintTextDirection: TextDirection.rtl,
                    hintStyle: GoogleFonts.cairo(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: const Color(0xFFB3A396)),
                  ),
                ),
              ),
              if (_valid) ...[
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.check_circle_rounded, color: CH.green, size: 20),
                ),
              ] else
                const SizedBox(width: 8),
            ]),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.errorText!,
              style: GoogleFonts.cairo(
                fontSize: 12, fontWeight: FontWeight.w700, color: CH.red)),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Leading dial-code chip
// ══════════════════════════════════════════════════════════════════
class _DialCodeChip extends StatelessWidget {
  final DialCode country;
  final VoidCallback onTap;
  const _DialCodeChip({required this.country, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(13)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Text(country.code,
              style: GoogleFonts.cairo(
                fontSize: 15, fontWeight: FontWeight.w800, color: CH.ink,
                letterSpacing: 0.5)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded, color: CH.muted, size: 22),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Bottom-sheet picker
// ══════════════════════════════════════════════════════════════════
class _DialCodePicker extends StatefulWidget {
  final DialCode current;
  const _DialCodePicker({required this.current});

  @override
  State<_DialCodePicker> createState() => _DialCodePickerState();
}

class _DialCodePickerState extends State<_DialCodePicker> {
  String _query = '';

  List<DialCode> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return DialCodes.all;
    return DialCodes.all.where((c) {
      return c.nameAr.contains(q) ||
             c.nameEn.toLowerCase().contains(q) ||
             c.code.contains(q) ||
             c.iso.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight   = MediaQuery.sizeOf(context).height * 0.72;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44, height: 4,
              decoration: BoxDecoration(
                color: CH.line, borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
              child: Text('اختر الدولة',
                style: GoogleFonts.changa(
                  fontSize: 18, fontWeight: FontWeight.w800, color: CH.ink)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: CH.cream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: CH.line, width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  const Icon(Icons.search, size: 20, color: CH.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      autofocus: false,
                      onChanged: (v) => setState(() => _query = v),
                      style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w700, color: CH.ink),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        hintText: 'ابحث بالدولة أو الرمز',
                        hintStyle: GoogleFonts.cairo(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: const Color(0xFFB3A396)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final c = _filtered[i];
                  final selected = c.iso == widget.current.iso;
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(c),
                    child: Container(
                      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 12),
                      color: selected
                          ? CH.hot.withValues(alpha: 0.06)
                          : Colors.transparent,
                      child: Row(children: [
                        Text(c.flag, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 14),
                        Expanded(child: Text(c.nameAr,
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                            color: CH.ink))),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(c.code,
                            style: GoogleFonts.cairo(
                              fontSize: 14, fontWeight: FontWeight.w800,
                              color: selected ? CH.hot : CH.muted)),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle_rounded,
                            color: CH.hot, size: 20),
                        ],
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
