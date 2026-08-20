/// One row in the loyalty rewards catalogue served by
/// `GET /api/v1/loyalty/rewards`. Admin-managed via the Filament
/// RewardResource — the mobile app never fabricates rewards locally.
class Reward {
  final String id;
  final String  nameAr;
  final String? nameEn;
  final String? descriptionAr;
  final String? imageUrl;
  final String  emoji;
  final int     pointsCost;
  final int     discountAmountSyp;
  final int     couponValidDays;

  const Reward({
    required this.id,
    required this.nameAr,
    required this.pointsCost,
    required this.discountAmountSyp,
    required this.emoji,
    this.nameEn,
    this.descriptionAr,
    this.imageUrl,
    this.couponValidDays = 30,
  });

  factory Reward.fromJson(Map<String, dynamic> j) => Reward(
        id:                 j['id'].toString(),
        nameAr:             (j['name_ar'] ?? '') as String,
        nameEn:             j['name_en'] as String?,
        descriptionAr:      j['description_ar'] as String?,
        imageUrl:           j['image'] as String?,
        emoji:              (j['emoji'] as String?) ?? '🎁',
        pointsCost:         (j['points_cost'] as num).toInt(),
        discountAmountSyp: (j['discount_amount_syp'] as num).toInt(),
        couponValidDays:   ((j['coupon_valid_days'] as num?) ?? 30).toInt(),
      );
}

/// Server response from `POST /loyalty/redeem` — the personal coupon the
/// customer just earned + their new points balance.
class RewardRedemption {
  final int      redemptionId;
  final String   couponCode;
  final int      discountSyp;
  final DateTime expiresAt;
  final int      newBalance;

  const RewardRedemption({
    required this.redemptionId,
    required this.couponCode,
    required this.discountSyp,
    required this.expiresAt,
    required this.newBalance,
  });

  factory RewardRedemption.fromJson(Map<String, dynamic> j) {
    final coupon = (j['coupon'] as Map<String, dynamic>);
    return RewardRedemption(
      redemptionId: (j['redemption_id'] as num).toInt(),
      couponCode:   coupon['code'] as String,
      discountSyp: (coupon['discount_syp'] as num).toInt(),
      expiresAt:    DateTime.parse(coupon['expires_at'] as String),
      newBalance:  (j['balance'] as num).toInt(),
    );
  }
}

/// One row in the customer's personal coupon wallet — served by
/// `GET /loyalty/coupons`. Includes past + present redemptions; UI filters
/// to `active` for the "apply on checkout" list and shows the rest as history.
enum MyCouponStatus { active, used, expired }

class MyCoupon {
  final int             redemptionId;
  final String?         code;              // null if backing PromoCode was deleted
  final String          rewardName;
  final String          rewardEmoji;
  final String?         rewardImageUrl;
  final int             discountSyp;
  final DateTime?       expiresAt;
  final DateTime?       usedAt;
  final DateTime        redeemedAt;
  final MyCouponStatus  status;

  const MyCoupon({
    required this.redemptionId,
    required this.code,
    required this.rewardName,
    required this.rewardEmoji,
    required this.discountSyp,
    required this.redeemedAt,
    required this.status,
    this.rewardImageUrl,
    this.expiresAt,
    this.usedAt,
  });

  bool get isActive => status == MyCouponStatus.active && (code?.isNotEmpty ?? false);

  factory MyCoupon.fromJson(Map<String, dynamic> j) => MyCoupon(
        redemptionId:    (j['redemption_id'] as num).toInt(),
        code:             j['code'] as String?,
        rewardName:      (j['reward_name'] ?? '—') as String,
        rewardEmoji:     (j['reward_emoji'] ?? '🎁') as String,
        rewardImageUrl:   j['reward_image'] as String?,
        discountSyp:     (j['discount_amount_syp'] as num).toInt(),
        expiresAt:        j['expires_at'] == null ? null : DateTime.parse(j['expires_at'] as String),
        usedAt:           j['used_at']   == null ? null : DateTime.parse(j['used_at']   as String),
        redeemedAt:       DateTime.parse(j['redeemed_at'] as String),
        status:           switch (j['status']) {
          'used'    => MyCouponStatus.used,
          'expired' => MyCouponStatus.expired,
          _         => MyCouponStatus.active,
        },
      );
}
