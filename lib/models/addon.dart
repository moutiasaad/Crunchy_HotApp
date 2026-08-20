/// An optional extra on a menu item (extra cheese, garlic, coleslaw, upsize…).
class Addon {
  final String id;
  final String nameAr;
  final String nameEn;
  final int    price;              // SYP delta

  const Addon({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.price,
  });

  @override
  bool operator ==(Object other) => other is Addon && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
