/// A country's phone dial code — flag + Arabic name + `+NNN` prefix, plus
/// the expected national digit length so the input can validate/mask locally
/// without a full libphonenumber dependency.
///
/// Backing the leading dial-code picker on [ChPhoneField]. New countries can
/// be added to [DialCodes.all] with no other code changes.
class DialCode {
  final String iso;      // ISO alpha-2, e.g. 'SY' — used as a stable identity key
  final String flag;     // 🇸🇾 — emoji flag renders on both Android and iOS
  final String nameAr;
  final String nameEn;
  final String code;     // '+963' etc. — includes the leading '+'
  final int    minLocalDigits;
  final int    maxLocalDigits;

  const DialCode({
    required this.iso,
    required this.flag,
    required this.nameAr,
    required this.nameEn,
    required this.code,
    required this.minLocalDigits,
    required this.maxLocalDigits,
  });

  /// Compose the E.164 form for a given local (no-leading-zero) national
  /// number. Strips any leading zero the user typed — Syrians often type
  /// `0946193094` when they mean `+963946193094`.
  String toE164(String local) {
    var digits = local.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '$code$digits';
  }

  /// Is `local` a plausible national number for this country?
  bool isValidLocal(String local) {
    final digits = local.replaceAll(RegExp(r'\D'), '');
    final stripped = digits.startsWith('0') ? digits.substring(1) : digits;
    return stripped.length >= minLocalDigits &&
           stripped.length <= maxLocalDigits;
  }
}

/// Curated country list — MENA-first, plus a few globals for diaspora users.
/// Ordered by regional relevance to a Syrian audience; the picker keeps this
/// order so Syria stays at the top without a "recently used" list.
class DialCodes {
  DialCodes._();

  static const DialCode syria = DialCode(
    iso: 'SY', flag: '🇸🇾', nameAr: 'سوريا', nameEn: 'Syria',
    code: '+963', minLocalDigits: 9, maxLocalDigits: 9,
  );

  /// The default country when no user selection is stored yet.
  static const DialCode defaultCode = syria;

  static const List<DialCode> all = [
    // ── MENA ──────────────────────────────────────────────
    syria,
    DialCode(iso: 'LB', flag: '🇱🇧', nameAr: 'لبنان',     nameEn: 'Lebanon',
             code: '+961', minLocalDigits: 7, maxLocalDigits: 8),
    DialCode(iso: 'JO', flag: '🇯🇴', nameAr: 'الأردن',    nameEn: 'Jordan',
             code: '+962', minLocalDigits: 9, maxLocalDigits: 9),
    DialCode(iso: 'TR', flag: '🇹🇷', nameAr: 'تركيا',     nameEn: 'Türkiye',
             code: '+90',  minLocalDigits: 10, maxLocalDigits: 10),
    DialCode(iso: 'IQ', flag: '🇮🇶', nameAr: 'العراق',    nameEn: 'Iraq',
             code: '+964', minLocalDigits: 10, maxLocalDigits: 10),
    DialCode(iso: 'SA', flag: '🇸🇦', nameAr: 'السعودية',   nameEn: 'Saudi Arabia',
             code: '+966', minLocalDigits: 9, maxLocalDigits: 9),
    DialCode(iso: 'AE', flag: '🇦🇪', nameAr: 'الإمارات',   nameEn: 'UAE',
             code: '+971', minLocalDigits: 9, maxLocalDigits: 9),
    DialCode(iso: 'EG', flag: '🇪🇬', nameAr: 'مصر',       nameEn: 'Egypt',
             code: '+20',  minLocalDigits: 10, maxLocalDigits: 10),
    DialCode(iso: 'PS', flag: '🇵🇸', nameAr: 'فلسطين',    nameEn: 'Palestine',
             code: '+970', minLocalDigits: 9, maxLocalDigits: 9),
    DialCode(iso: 'KW', flag: '🇰🇼', nameAr: 'الكويت',    nameEn: 'Kuwait',
             code: '+965', minLocalDigits: 8, maxLocalDigits: 8),
    DialCode(iso: 'QA', flag: '🇶🇦', nameAr: 'قطر',       nameEn: 'Qatar',
             code: '+974', minLocalDigits: 8, maxLocalDigits: 8),
    DialCode(iso: 'BH', flag: '🇧🇭', nameAr: 'البحرين',   nameEn: 'Bahrain',
             code: '+973', minLocalDigits: 8, maxLocalDigits: 8),
    DialCode(iso: 'OM', flag: '🇴🇲', nameAr: 'عُمان',      nameEn: 'Oman',
             code: '+968', minLocalDigits: 8, maxLocalDigits: 8),
    DialCode(iso: 'YE', flag: '🇾🇪', nameAr: 'اليمن',     nameEn: 'Yemen',
             code: '+967', minLocalDigits: 9, maxLocalDigits: 9),
    DialCode(iso: 'DZ', flag: '🇩🇿', nameAr: 'الجزائر',   nameEn: 'Algeria',
             code: '+213', minLocalDigits: 9, maxLocalDigits: 9),
    DialCode(iso: 'MA', flag: '🇲🇦', nameAr: 'المغرب',    nameEn: 'Morocco',
             code: '+212', minLocalDigits: 9, maxLocalDigits: 9),
    DialCode(iso: 'TN', flag: '🇹🇳', nameAr: 'تونس',      nameEn: 'Tunisia',
             code: '+216', minLocalDigits: 8, maxLocalDigits: 8),
    DialCode(iso: 'LY', flag: '🇱🇾', nameAr: 'ليبيا',     nameEn: 'Libya',
             code: '+218', minLocalDigits: 9, maxLocalDigits: 10),
    DialCode(iso: 'SD', flag: '🇸🇩', nameAr: 'السودان',   nameEn: 'Sudan',
             code: '+249', minLocalDigits: 9, maxLocalDigits: 9),

    // ── Diaspora hubs ────────────────────────────────────
    DialCode(iso: 'DE', flag: '🇩🇪', nameAr: 'ألمانيا',    nameEn: 'Germany',
             code: '+49',  minLocalDigits: 10, maxLocalDigits: 11),
    DialCode(iso: 'FR', flag: '🇫🇷', nameAr: 'فرنسا',      nameEn: 'France',
             code: '+33',  minLocalDigits: 9, maxLocalDigits: 9),
    DialCode(iso: 'GB', flag: '🇬🇧', nameAr: 'المملكة المتحدة', nameEn: 'United Kingdom',
             code: '+44',  minLocalDigits: 10, maxLocalDigits: 10),
    DialCode(iso: 'SE', flag: '🇸🇪', nameAr: 'السويد',     nameEn: 'Sweden',
             code: '+46',  minLocalDigits: 7, maxLocalDigits: 10),
    DialCode(iso: 'US', flag: '🇺🇸', nameAr: 'الولايات المتحدة', nameEn: 'United States',
             code: '+1',   minLocalDigits: 10, maxLocalDigits: 10),
    DialCode(iso: 'CA', flag: '🇨🇦', nameAr: 'كندا',       nameEn: 'Canada',
             code: '+1',   minLocalDigits: 10, maxLocalDigits: 10),
  ];

  /// Look a country up by ISO. Falls back to [defaultCode] on unknown values
  /// so a stale saved preference never crashes the field.
  static DialCode byIso(String iso) {
    for (final c in all) {
      if (c.iso == iso) return c;
    }
    return defaultCode;
  }

  /// Best-effort match on an already-formatted E.164 number so the picker
  /// opens on the right country when loading an existing user's phone.
  /// Falls back to [defaultCode] when nothing matches.
  static DialCode fromE164(String e164) {
    if (!e164.startsWith('+')) return defaultCode;
    // Longest prefix wins — '+1' would otherwise eat '+964'.
    DialCode? best;
    for (final c in all) {
      if (e164.startsWith(c.code) &&
          (best == null || c.code.length > best.code.length)) {
        best = c;
      }
    }
    return best ?? defaultCode;
  }
}
