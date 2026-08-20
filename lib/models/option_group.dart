/// A configurable option on a product — one row of a spice-level radio group
/// or one entry in an add-ons checklist.
///
/// Mirrors the backend `options` table. `id` is the numeric server id — the
/// same one we send in `POST /cart/items { options: [id, ...] }`.
class OptionValue {
  final int    id;
  final String nameAr;
  final String nameEn;
  final int    priceDelta;      // SYP added to the base price
  final bool   isDefault;
  final bool   isAvailable;

  const OptionValue({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.priceDelta,
    this.isDefault   = false,
    this.isAvailable = true,
  });

  factory OptionValue.fromJson(Map<String, dynamic> j) => OptionValue(
        id:           (j['id'] as num).toInt(),
        nameAr:       (j['name_ar'] as String?) ?? '',
        nameEn:       (j['name_en'] as String?) ?? '',
        priceDelta:  ((j['price_delta'] as num?) ?? 0).toInt(),
        isDefault:    (j['is_default']   as bool?) ?? false,
        isAvailable:  (j['is_available'] as bool?) ?? true,
      );

  @override
  bool operator ==(Object other) => other is OptionValue && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A group of options attached to a product — "درجة الحرارة", "الحجم",
/// "إضافات". Rendering on the Detail screen keys off [selectionType]:
/// - `single` → radio-style row (like the spice picker in the reference).
/// - `multiple` → checkbox list (add-ons).
class OptionGroup {
  final int                id;
  final String             nameAr;
  final String             nameEn;
  final String             selectionType;   // 'single' | 'multiple'
  final bool               isRequired;
  final int                minSelect;
  final int                maxSelect;
  final List<OptionValue>  options;

  const OptionGroup({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.selectionType,
    required this.isRequired,
    required this.minSelect,
    required this.maxSelect,
    required this.options,
  });

  bool get isSingleSelect => selectionType == 'single' || (minSelect == 1 && maxSelect == 1);

  factory OptionGroup.fromJson(Map<String, dynamic> j) => OptionGroup(
        id:            (j['id'] as num).toInt(),
        nameAr:        (j['name_ar'] as String?) ?? '',
        nameEn:        (j['name_en'] as String?) ?? '',
        selectionType: (j['selection_type'] as String?) ?? 'single',
        isRequired:    (j['is_required'] as bool?) ?? false,
        minSelect:    ((j['min_select'] as num?) ?? 0).toInt(),
        maxSelect:    ((j['max_select'] as num?) ?? 1).toInt(),
        options: ((j['options'] as List?) ?? const [])
            .map((o) => OptionValue.fromJson(o as Map<String, dynamic>))
            .toList(),
      );
}
