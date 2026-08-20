/// Shared domain enums.
library;

enum Spice { mild, hot, extraHot }

enum PayMethod { cash, shamCash, card, payAtCounter }

extension PayMethodMeta on PayMethod {
  String get labelAr => switch (this) {
        PayMethod.cash         => 'نقداً عند التسليم',
        PayMethod.shamCash     => 'شام كاش',
        PayMethod.card         => 'بطاقة مصرفية',
        PayMethod.payAtCounter => 'الدفع عند الاستلام',
      };

  String get detailAr => switch (this) {
        PayMethod.cash         => 'جهّز المبلغ للسائق',
        PayMethod.shamCash     => 'محفظة إلكترونية · فوري',
        PayMethod.card         => 'أضف بطاقة',
        PayMethod.payAtCounter => 'ادفع كاش أو بطاقة على الكاشير',
      };

  String get emoji => switch (this) {
        PayMethod.cash         => '💵',
        PayMethod.shamCash     => '📲',
        PayMethod.card         => '💳',
        PayMethod.payAtCounter => '🏬',
      };

  /// Wire values for `POST /orders` — mirrors the Laravel enum.
  String get apiValue => switch (this) {
        PayMethod.cash         => 'cash_on_delivery',
        PayMethod.payAtCounter => 'cash_on_pickup',
        PayMethod.shamCash     => 'sham_cash',
        PayMethod.card         => 'card',
      };
}

enum OrderMode { delivery, pickup }

enum OrderStatus { received, preparing, onTheWay, delivered, cancelled }

/// Filter chips on the Search screen (§4 of SEARCH_SCREEN.md).
enum SearchFilter { popular, cheapest, spicy, quick, under30k }

extension SearchFilterLabels on SearchFilter {
  String get labelAr => switch (this) {
        SearchFilter.popular  => 'الأكثر طلباً',
        SearchFilter.cheapest => 'الأرخص',
        SearchFilter.spicy    => '🔥 حار',
        SearchFilter.quick    => '⚡ تحضير سريع',
        SearchFilter.under30k => 'أقل من 30 ألف',
      };

  String? get emoji => switch (this) {
        SearchFilter.popular  => '⭐',
        SearchFilter.cheapest => '💸',
        _                     => null,   // emoji baked into label
      };
}
