import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../widgets/widgets.dart';

/// Design-system showcase — renders every component from §5 of the spec.
/// This is the first screen you see when the app boots. Replace once real
/// screens (Home / Menu / Cart / …) exist in `lib/screens/`.
class ShowcaseScreen extends StatefulWidget {
  const ShowcaseScreen({super.key});
  @override
  State<ShowcaseScreen> createState() => _ShowcaseScreenState();
}

class _ShowcaseScreenState extends State<ShowcaseScreen> {
  int _tab = 0;
  int _cartCount = 3;
  int _qty = 1;
  bool _fav = false;
  bool _extraCheese = false;
  bool _extraSauce = true;
  bool _points = false;
  int _rating = 4;
  String _mode = 'delivery';
  String _selectedAddress = 'home';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CH.cream,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // --- Dark header showcase ---
          ChDarkHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: ChLocationSelector(
                        label: 'التوصيل إلى',
                        value: 'حلب — الفرقان',
                      ),
                    ),
                    const ChPointsPill(points: 340),
                    const SizedBox(width: 10),
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: CH.hot,
                        borderRadius: ChRadii.rMd,
                        boxShadow: ChShadows.darkHeaderLogo,
                      ),
                      alignment: Alignment.center,
                      child: Text('🔥', style: ChText.h3.copyWith(color: CH.paper)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const ChDarkSearchField(),
              ],
            ),
          ),

          // --- Section: chips ---
          _section('الفئات — Chips', [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ChChip(label: 'الكل', emoji: '🍽️', selected: true, onTap: () {}),
                  const SizedBox(width: 8),
                  ChChip(label: 'بروستد', emoji: '🍗', onTap: () {}),
                  const SizedBox(width: 8),
                  ChChip(label: 'شاورما', emoji: '🌯', onTap: () {}),
                  const SizedBox(width: 8),
                  ChChip(label: 'برجر', emoji: '🍔', onTap: () {}),
                  const SizedBox(width: 8),
                  ChChip(label: 'مشروبات', emoji: '🥤', onTap: () {}),
                ],
              ),
            ),
          ]),

          // --- Section: segmented toggle ---
          _section('توصيل / استلام — Segmented', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ChSegmented<String>(
                selected: _mode,
                onChanged: (v) => setState(() => _mode = v),
                items: const [
                  ChSegmentedItem(value: 'delivery', label: 'توصيل', emoji: '🛵'),
                  ChSegmentedItem(value: 'pickup',   label: 'استلام', emoji: '🏬'),
                ],
              ),
            ),
          ]),

          // --- Section: offer banner ---
          _section('عرض هذا الأسبوع — Offer Banner', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ChOfferBanner(
                title: 'وجبة العائلة الكبيرة',
                subtitle: 'دجاج بروستد كامل + 4 ساندويشات + بطاطا كبيرة + 4 مشروبات',
                newPrice: 55000,
                oldPrice: 72000,
                onCta: () {},
              ),
            ),
          ]),

          // --- Section: featured cards ---
          _section('نجوم المنيو — Featured Card', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ChFeaturedCard(
                name: 'بروستد كرانشي — 8 قطع',
                price: 45000,
                badge: const ChBadge.spicy(),
                onTap: () {},
                onAdd: () => setState(() => _cartCount++),
              ),
            ),
          ]),

          // --- Section: product row cards ---
          _section('المنيو — Product Row', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ChProductCard(
                    name: 'شاورما دجاج عربي',
                    description: 'دجاج متبل، ثوم، مخلل وبطاطا داخل خبز صاج',
                    price: 22000,
                    kcal: '520 kcal',
                    badge: const ChBadge.light(),
                    favourite: _fav,
                    onFavouriteChanged: (v) => setState(() => _fav = v),
                    onTap: () {},
                    onAdd: () => setState(() => _cartCount++),
                  ),
                  const SizedBox(height: 12),
                  ChProductCard(
                    name: 'دبل تشيز برجر',
                    description: 'قطعتين لحم مشوي + جبنة شيدر مضاعفة + صوص خاص',
                    price: 38000,
                    badge: const ChBadge.popular(),
                    onTap: () {},
                    onAdd: () => setState(() => _cartCount++),
                  ),
                  const SizedBox(height: 12),
                  ChProductCard(
                    name: 'بيبسي 330 مل',
                    description: 'مبردة',
                    price: 3000,
                    onTap: () {},
                    onAdd: () => setState(() => _cartCount++),
                    disabled: true,
                  ),
                ],
              ),
            ),
          ]),

          // --- Section: badges ---
          _section('الشارات — Badges', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: const [
                  ChBadge.spicy(),
                  ChBadge.popular(),
                  ChBadge.light(),
                  ChBadge.isNew(),
                  ChStatusBadge.open(),
                  ChStatusBadge.closed(),
                  ChStatusBadge.delivered(),
                  ChStatusBadge.cancelled(),
                ],
              ),
            ),
          ]),

          // --- Section: buttons ---
          _section('الأزرار — Buttons', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ChPrimaryButton(label: 'تأكيد الطلب', trailingValue: '91,000 ل.س', onPressed: () {}),
                  const SizedBox(height: 10),
                  const ChPrimaryButton(label: 'زر معطّل', onPressed: null),
                  const SizedBox(height: 10),
                  ChDarkButton(label: 'أضف العرض للسلة', onPressed: () {}),
                  const SizedBox(height: 10),
                  Row(children: [
                    ChGhostButton(label: 'تسجيل الدخول بحساب واتساب', icon: Icons.chat, onPressed: () {}, expanded: true),
                  ]),
                ],
              ),
            ),
          ]),

          // --- Section: quantity stepper ---
          _section('عداد الكمية — Quantity Stepper', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChQuantityStepper(value: _qty, onChanged: (v) => setState(() => _qty = v)),
                  const SizedBox(width: 20),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('90,000 ل.س', style: ChText.priceLg),
                  ),
                ],
              ),
            ),
          ]),

          // --- Section: add-ons (checkbox rows) ---
          _section('إضافات — Add-on Checkboxes', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ChCheckboxRow(
                    label: 'جبنة إضافية',
                    priceDelta: 4000,
                    checked: _extraCheese,
                    onChanged: (v) => setState(() => _extraCheese = v),
                  ),
                  const SizedBox(height: 8),
                  ChCheckboxRow(
                    label: 'صوص إضافي',
                    priceDelta: 1000,
                    checked: _extraSauce,
                    onChanged: (v) => setState(() => _extraSauce = v),
                  ),
                ],
              ),
            ),
          ]),

          // --- Section: selection rows ---
          _section('العناوين / الدفع — Selection Rows', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ChSelectionRow(
                    title: 'البيت',
                    subtitle: 'حلب — الفرقان، شارع القدس، بناء 12',
                    emoji: '🏠',
                    selected: _selectedAddress == 'home',
                    onTap: () => setState(() => _selectedAddress = 'home'),
                  ),
                  const SizedBox(height: 10),
                  ChSelectionRow(
                    title: 'العمل',
                    subtitle: 'حلب — العزيزية، برج التجارة، طابق 5',
                    emoji: '💼',
                    selected: _selectedAddress == 'work',
                    onTap: () => setState(() => _selectedAddress = 'work'),
                  ),
                ],
              ),
            ),
          ]),

          // --- Section: switch (use points) ---
          _section('استخدم النقاط — Switch', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(color: CH.paper, borderRadius: ChRadii.rCard, boxShadow: ChShadows.card),
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('استخدم 340 نقطة', style: ChText.bodyStrong),
                        const SizedBox(height: 2),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text('= 6,800 ل.س خصم', style: ChText.caption),
                        ),
                      ],
                    ),
                  ),
                  ChSwitch(value: _points, onChanged: (v) => setState(() => _points = v)),
                ]),
              ),
            ),
          ]),

          // --- Section: timeline ---
          _section('تتبّع الطلب — Timeline', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(color: CH.paper, borderRadius: ChRadii.rCard, boxShadow: ChShadows.card),
                padding: const EdgeInsets.all(16),
                child: const ChTimeline(
                  currentIndex: 2,
                  steps: [
                    ChTimelineStep(title: 'تم استلام الطلب', emoji: '📥'),
                    ChTimelineStep(title: 'قيد التحضير', emoji: '🍳'),
                    ChTimelineStep(title: 'في الطريق إليك', emoji: '🛵', subtitle: 'ETA 15 دقيقة'),
                    ChTimelineStep(title: 'تم التوصيل', emoji: '🎉'),
                  ],
                ),
              ),
            ),
          ]),

          // --- Section: rating ---
          _section('التقييم — Rating', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChRating(value: _rating, onChanged: (v) => setState(() => _rating = v)),
                ],
              ),
            ),
          ]),

          // --- Section: coupon ---
          _section('كوبون — Coupon Row', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ChCouponRow(
                percent: 20,
                code: 'FRIDAY20',
                title: 'خصم 20% على كل الطلبات',
                subtitle: 'صالح حتى الجمعة القادمة · حد أدنى 25,000 ل.س',
              ),
            ),
          ]),

          // --- Section: empty state ---
          _section('حالة فارغة — Empty State', [
            SizedBox(
              height: 260,
              child: ChEmptyState(
                emoji: '🛒',
                title: 'سلتك فارغة',
                subtitle: 'أضف أصنافك المفضلة من المنيو',
                ctaLabel: 'تصفّح المنيو',
                onCta: () {},
              ),
            ),
          ]),

          // Padding to clear the bottom bars
          const SizedBox(height: 140),
        ],
      ),

      // --- Bottom action bar (sticky primary CTA) ---
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChBottomActionBar(
            child: ChPrimaryButton(
              label: 'تأكيد الطلب',
              trailingValue: '91,000 ل.س',
              onPressed: () {},
            ),
          ),
          ChBottomNav(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            cartCount: _cartCount,
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
            child: Row(children: [
              Container(width: 4, height: 18, color: CH.hot),
              const SizedBox(width: 10),
              Text(title, style: ChText.h3.copyWith(fontSize: 18)),
            ]),
          ),
          ...children,
        ],
      ),
    );
  }
}
