/// A row in the user's loyalty ledger.
enum LoyaltyEntryType { earned, spent, expired, other }

extension _LoyaltyEntryTypeParse on LoyaltyEntryType {
  static LoyaltyEntryType fromApi(String? raw) {
    switch (raw) {
      case 'earned': return LoyaltyEntryType.earned;
      case 'spent':  return LoyaltyEntryType.spent;
      case 'expired':return LoyaltyEntryType.expired;
      default:       return LoyaltyEntryType.other;
    }
  }
}

class LoyaltyLedgerEntry {
  final LoyaltyEntryType type;
  final int              points;         // signed: earned positive, spent/expired positive here — sign is derived from `type`
  final int              balanceAfter;
  final String?          note;
  final DateTime?        expiresAt;
  final DateTime         createdAt;

  const LoyaltyLedgerEntry({
    required this.type,
    required this.points,
    required this.balanceAfter,
    required this.createdAt,
    this.note,
    this.expiresAt,
  });

  factory LoyaltyLedgerEntry.fromJson(Map<String, dynamic> j) => LoyaltyLedgerEntry(
        type:          _LoyaltyEntryTypeParse.fromApi(j['type'] as String?),
        points:       (j['points']        ?? 0) as int,
        balanceAfter: (j['balance_after'] ?? 0) as int,
        note:          j['note']          as String?,
        expiresAt:     j['expires_at']    == null ? null : DateTime.tryParse(j['expires_at'] as String),
        createdAt:     DateTime.tryParse((j['created_at'] ?? '') as String) ?? DateTime.now(),
      );

  /// Signed delta for display (e.g. `+45`, `-200`, `-60`).
  int get signedDelta => switch (type) {
        LoyaltyEntryType.earned  =>  points.abs(),
        LoyaltyEntryType.spent   => -points.abs(),
        LoyaltyEntryType.expired => -points.abs(),
        LoyaltyEntryType.other   =>  points,
      };
}

/// Config knobs returned by the server (`rules` block).
class LoyaltyRules {
  final int earnRatePer1000Syp;      // points earned per 1000 SYP spent
  final int redeemPointsPer1000Syp;  // conversion when redeeming at checkout
  final int expiryDays;              // points expiry window

  const LoyaltyRules({
    required this.earnRatePer1000Syp,
    required this.redeemPointsPer1000Syp,
    required this.expiryDays,
  });

  factory LoyaltyRules.fromJson(Map<String, dynamic> j) => LoyaltyRules(
        // Fallbacks match SettingsSeeder + config/business.php so a first-boot
        // preview before /loyalty resolves lines up with what the server will
        // actually apply. Do NOT invent numbers here.
        earnRatePer1000Syp:     (j['earn_rate_per_1000_syp']     ?? 10)  as int,
        redeemPointsPer1000Syp: (j['redeem_points_per_1000_syp'] ?? 100) as int,
        expiryDays:             (j['expiry_days']                ?? 180) as int,
      );

  static const empty = LoyaltyRules(
    earnRatePer1000Syp: 10, redeemPointsPer1000Syp: 100, expiryDays: 180,
  );
}

/// Full loyalty payload — balance + rules + ledger.
class LoyaltyStatus {
  final int                       balance;
  final LoyaltyRules              rules;
  final List<LoyaltyLedgerEntry>  ledger;

  const LoyaltyStatus({
    required this.balance,
    required this.rules,
    required this.ledger,
  });

  factory LoyaltyStatus.fromJson(Map<String, dynamic> j) => LoyaltyStatus(
        balance: (j['balance'] ?? 0) as int,
        rules:   LoyaltyRules.fromJson((j['rules'] as Map<String, dynamic>?) ?? const {}),
        ledger:  ((j['ledger'] as List?) ?? const [])
                  .map((e) => LoyaltyLedgerEntry.fromJson(e as Map<String, dynamic>))
                  .toList(),
      );

  static const empty = LoyaltyStatus(
    balance: 0, rules: LoyaltyRules.empty, ledger: [],
  );

  /// Ledger entries that expire in the next N days (spec §6).
  List<LoyaltyLedgerEntry> expiringWithin(Duration window) {
    final cutoff = DateTime.now().add(window);
    return ledger.where((e) =>
      e.type == LoyaltyEntryType.earned &&
      e.expiresAt != null &&
      e.expiresAt!.isBefore(cutoff),
    ).toList();
  }
}
