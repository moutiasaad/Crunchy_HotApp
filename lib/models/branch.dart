/// A physical restaurant location — pickup destination for screen 12.
///
/// Mirrors the shape of `App\Http\Resources\BranchResource` on the API side;
/// [distanceKm] is client-computed once location permission is granted.
class Branch {
  final String  id;
  final String  nameAr;         // e.g. "كرانشي هت — الفرقان"
  final String  nameEn;
  final String  shortNameAr;    // e.g. "الفرقان" — for the Cart pickup toggle (truncated at 14)
  final String  addressAr;
  final String  phone;
  final bool    isOpen;
  final String  hoursText;      // "12:00 — 02:00"
  final double? distanceKm;     // null when location permission is denied
  final double  lat;
  final double  lng;

  const Branch({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.shortNameAr,
    required this.addressAr,
    required this.phone,
    required this.isOpen,
    required this.hoursText,
    required this.lat,
    required this.lng,
    this.distanceKm,
  });

  /// Parse one element of `data[]` from `GET /api/v1/branches`.
  ///
  /// The API returns a single Aleppo branch today; `name` is a single field
  /// (no ar/en split). We synthesise `shortNameAr` by stripping the brand
  /// prefix (`كرانشي هت — `) if present, so the Cart pickup toggle stays
  /// tight. Hours come from the `hours[]` array — we pick today's opening
  /// window and format it for the header line.
  factory Branch.fromJson(Map<String, dynamic> j) {
    final name  = (j['name']    ?? '') as String;
    final short = name.startsWith('كرانشي هت —')
        ? name.substring('كرانشي هت —'.length).trim()
        : name;

    // Weekday: Dart's DateTime.weekday is 1..7 Mon..Sun; server uses 0..6
    // Sun..Sat (Laravel convention). Convert.
    final today = DateTime.now().weekday % 7;
    String hoursText = '';
    final hours = (j['hours'] as List?) ?? const [];
    for (final h in hours) {
      final row = h as Map<String, dynamic>;
      if ((row['weekday'] as int?) == today) {
        final open  = _trimHms(row['opens_at']  as String?);
        final close = _trimHms(row['closes_at'] as String?);
        hoursText = '$open — $close';
        break;
      }
    }

    return Branch(
      id:            j['id'].toString(),
      nameAr:        name,
      nameEn:        name,   // API is single-locale for now
      shortNameAr:   short,
      addressAr:    (j['address'] ?? '') as String,
      phone:        (j['phone']   ?? '') as String,
      isOpen:       (j['is_open_now'] ?? false) as bool,
      hoursText:     hoursText,
      lat:          ((j['lat'] ?? 0) as num).toDouble(),
      lng:          ((j['lng'] ?? 0) as num).toDouble(),
      distanceKm:    null,
    );
  }

  static String _trimHms(String? s) {
    if (s == null || s.isEmpty) return '';
    // "12:00:00" → "12:00"
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  // ──────────────── Local persistence ────────────────
  // Separate from the server shape (fromJson above) — this round-trips a
  // Branch snapshot inside the persisted cart so the pickup selection
  // survives an app restart. `isOpen` and `hoursText` are point-in-time
  // and will be refreshed the next time BranchService.list() runs.

  Map<String, dynamic> toJsonLocal() => {
        'id':          id,
        'nameAr':      nameAr,
        'nameEn':      nameEn,
        'shortNameAr': shortNameAr,
        'addressAr':   addressAr,
        'phone':       phone,
        'isOpen':      isOpen,
        'hoursText':   hoursText,
        'lat':         lat,
        'lng':         lng,
        if (distanceKm != null) 'distanceKm': distanceKm,
      };

  factory Branch.fromJsonLocal(Map<String, dynamic> j) => Branch(
        id:          j['id']          as String,
        nameAr:      j['nameAr']      as String? ?? '',
        nameEn:      j['nameEn']      as String? ?? '',
        shortNameAr: j['shortNameAr'] as String? ?? '',
        addressAr:   j['addressAr']   as String? ?? '',
        phone:       j['phone']       as String? ?? '',
        isOpen:      j['isOpen']      as bool?   ?? false,
        hoursText:   j['hoursText']   as String? ?? '',
        lat:        (j['lat']         as num?)?.toDouble() ?? 0,
        lng:        (j['lng']         as num?)?.toDouble() ?? 0,
        distanceKm: (j['distanceKm']  as num?)?.toDouble(),
      );
}
