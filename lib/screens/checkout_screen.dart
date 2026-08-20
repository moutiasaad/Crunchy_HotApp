import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../controllers/auth_controller.dart';
import '../controllers/cart_controller.dart';
import '../controllers/loyalty_controller.dart';
import '../controllers/orders_controller.dart';
import '../models/models.dart';
import '../services/address_service.dart';
import '../services/api_client.dart' show ApiException;
import '../services/cart_service.dart';
import '../services/order_service.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import '../utils/ch_routes.dart';
import '../widgets/ch_button.dart';
import 'branches_screen.dart';
import 'offers_screen.dart';
import 'tracking_screen.dart';

void _cLog(String msg) {
  if (kDebugMode) debugPrint('[Checkout] $msg');
}

/// Screen 13 — Checkout (إتمام الطلب).
///
/// Confirm *where*, *how you pay*, *what discounts*, *what it costs* — one
/// screen, no wizard. Contents are read-only here; quantities live on Cart.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  // ─── Constants ───────────────────────────────────────────────
  static const int _minOrderSyp    = 25000;   // matches Cart's minimum
  static const int _pointValueSyp  = 20;      // 1 point = 20 SYP
  static const int _pointsFloor    = 200;     // hidden below this balance
  static const int _etaMinutes     = 35;

  // ─── UI state ────────────────────────────────────────────────
  PayMethod _pay        = PayMethod.cash;
  int       _cashChange = 0;                  // 0 = بدون; else 50000 / 100000
  _Coupon?  _coupon;
  String?   _couponError;
  bool      _couponBusy = false;              // POST /cart/promo in flight
  bool      _usePoints  = false;
  bool      _placing    = false;

  // Address is typed inline here — no separate screen, no saved list.
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _couponCtrl  = TextEditingController();

  @override
  void initState() {
    super.initState();
    _addressCtrl.addListener(() => setState(() {}));
    _couponCtrl.addListener(() => setState(() {}));
    // Prime the customer's coupon wallet so it's ready to display right
    // under the code input — no waiting for a spinner.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final loyalty = context.read<LoyaltyController>();
      if (context.read<AuthController>().isSignedIn) {
        loyalty.loadCoupons();
      }
    });
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _couponCtrl.dispose();
    super.dispose();
  }

  String get _addressText => _addressCtrl.text.trim();
  bool   get _hasValidAddress => _addressText.length >= 5;

  // ─── Data ────────────────────────────────────────────────────
  int get _pointsBalance =>
      context.read<AuthController>().user?.loyaltyPoints ?? 0;

  bool get _showPointsRow =>
      context.read<AuthController>().isSignedIn && _pointsBalance >= _pointsFloor;

  int get _pointsDiscountRaw =>
      _usePoints ? _pointsBalance * _pointValueSyp : 0;

  /// Cap points discount at the remaining bill after fee + coupon.
  int _pointsDiscount(int subtotal, int fee) {
    if (!_usePoints) return 0;
    final head = (subtotal + fee - (_coupon?.saving ?? 0)).clamp(0, 1 << 62);
    return _pointsDiscountRaw.clamp(0, head);
  }

  int _totalOf(int subtotal, int fee) {
    final discount = (_coupon?.saving ?? 0) + _pointsDiscount(subtotal, fee);
    return (subtotal + fee - discount).clamp(0, 1 << 62);
  }

  // ─── Payment methods list (pickup adds a 4th row) ────────────
  List<PayMethod> _methodsFor(OrderMode mode) => mode == OrderMode.pickup
      ? const [PayMethod.cash, PayMethod.shamCash, PayMethod.card, PayMethod.payAtCounter]
      : const [PayMethod.cash, PayMethod.shamCash, PayMethod.card];

  // ─── Actions ─────────────────────────────────────────────────

  /// Apply the promo code the user typed. Server is authoritative: it
  /// validates the code and attaches it to the cart; on success we compute
  /// a display-only saving locally from the returned coupon details so the
  /// total updates immediately. Final discount is recomputed by
  /// PricingEngine when the order is placed.
  Future<void> _applyCouponCode() async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty || _couponBusy) return;

    setState(() {
      _couponBusy  = true;
      _couponError = null;
    });

    final cart        = context.read<CartController>();
    final cartService = context.read<CartService>();
    final subtotal    = cart.totals.subtotal;
    final deliveryFee = cart.totals.deliveryFee;

    try {
      final resp = await cartService.applyPromo(code);
      final promo = (resp['applied_promo'] as Map<String, dynamic>?);
      if (promo == null) throw StateError('missing applied_promo');

      final type  = promo['type'] as String;
      final value = (promo['value'] as num).toInt();
      final maxDiscount = promo['max_discount'] == null
          ? null
          : (promo['max_discount'] as num).toInt();
      final minOrder = ((promo['min_order'] as num?) ?? 0).toInt();

      if (subtotal < minOrder) {
        // Server accepted the code but our cart doesn't meet its minimum.
        // Roll it back so the customer isn't misled at place-order time.
        await cartService.clearPromo();
        if (!mounted) return;
        setState(() {
          _coupon = null;
          _couponError = 'الكود يحتاج طلباً لا يقل عن ${ChMoney.format(minOrder)}';
        });
        return;
      }

      final saving = switch (type) {
        'percent' => (maxDiscount == null)
            ? (subtotal * value) ~/ 100
            : ((subtotal * value) ~/ 100).clamp(0, maxDiscount),
        'fixed'         => value,
        'free_delivery' => deliveryFee,
        _               => 0,
      };

      if (!mounted) return;
      setState(() {
        _coupon = _Coupon(code: promo['code'] as String, saving: saving);
        _couponError = null;
        _couponCtrl.clear();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _coupon = null;
        _couponError = e.message.isNotEmpty
            ? e.message
            : 'الكود غير صالح أو منتهي الصلاحية';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _coupon = null;
        _couponError = 'ما قدرنا نطبّق الكود — جرّب مرة تانية';
      });
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }

  Future<void> _removeCoupon() async {
    // Fire-and-forget: even if the server call fails, drop it from the UI.
    final cartService = context.read<CartService>();
    setState(() {
      _coupon = null;
      _couponError = null;
    });
    try {
      await cartService.clearPromo();
    } catch (_) {
      // Silent — the local state is what the user sees; a stale server
      // promo_code_id will be overridden by the next apply or ignored when
      // PricingEngine sees the promo failed its own checks.
    }
  }

  /// Secondary — opens the offers/coupons picker (browse mode). Selected
  /// code is dropped into the input field for a normal apply.
  Future<void> _browseCoupons() async {
    final picked = await Navigator.of(context).push<Coupon>(
      ChRoutes.slideUpFade((_) => const OffersScreen(pickMode: true)),
    );
    if (picked == null || !mounted) return;
    _couponCtrl.text = picked.code;
    await _applyCouponCode();
  }

  /// One-tap: apply a coupon straight from the customer's wallet.
  Future<void> _applyFromWallet(MyCoupon c) async {
    if (c.code == null || c.code!.isEmpty) return;
    HapticFeedback.selectionClick();
    _couponCtrl.text = c.code!;
    await _applyCouponCode();
  }

  Future<void> _changePickupBranch() async {
    await Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => const BranchesScreen()),
    );
    if (mounted) setState(() {}); // rebuild with the new branch selection
  }

  Future<void> _placeOrder() async {
    if (_placing) return;
    setState(() => _placing = true);
    HapticFeedback.selectionClick();

    // Snapshot the values Tracking needs BEFORE we clear the cart.
    final cart           = context.read<CartController>();
    final cartService    = context.read<CartService>();
    final orderService   = context.read<OrderService>();
    final addressService = context.read<AddressService>();
    final ordersCtrl     = context.read<OrdersController>();
    final authCtrl       = context.read<AuthController>();
    final mode           = cart.mode;
    final branch         = cart.branch ?? kBranches.first;
    final addressLine    = _addressText;
    final fallbackId     = _generateOrderId();

    _cLog('placeOrder → mode=${mode.name}  lines=${cart.lines.length}  pay=${_pay.name}');

    try {
      String orderNumber = fallbackId;

      // ── Sync the local cart to the server, one line at a time ──
      // Products come from the API (int IDs); seed fallback products use
      // "p1"..."p12" which won't validate against `exists:products,id` — we
      // surface a clean error in that case rather than silently faking.
      for (final line in cart.lines) {
        final pid = int.tryParse(line.product.id);
        if (pid == null) {
          throw StateError(
            'المنتج "${line.product.nameAr}" غير مسجّل في الخادم — '
            'أعد تحميل المنيو من الرئيسية ثم جرّب مجدداً.',
          );
        }
        await cartService.addItem(
          productId: pid,
          quantity:  line.quantity,
          note:      line.note,
          offerId:   line.offerId == null ? null : int.tryParse(line.offerId!),
          // TODO: map spice + addons to server option IDs when the catalogue
          // API surfaces them (`GET /products/{slug}` optionGroups.options).
        );
      }

      // ── Resolve address_id / branch_id per mode ──
      int? addressIdInt;
      int? branchIdInt;
      String paymentMethod;

      if (mode == OrderMode.delivery) {
        if (!_hasValidAddress) {
          throw StateError('اكتب عنوان التوصيل أوّلاً');
        }
        addressIdInt = await addressService.create(text: addressLine);
        paymentMethod = 'cash_on_delivery';
      } else {
        // Pickup: use the real /branches id.
        branchIdInt = int.tryParse(cart.branch?.id ?? branch.id) ?? 1;
        paymentMethod = 'cash_on_pickup';
      }

      // ── Place the order ──
      final resp = await orderService.place(
        mode:          mode,
        addressId:     addressIdInt,
        branchId:      branchIdInt,
        paymentMethod: paymentMethod,
      );
      final data = (resp['data'] as Map<String, dynamic>?) ?? resp;
      orderNumber = (data['order_number'] as String?) ?? fallbackId;
      _cLog('placeOrder ✓ server order_number=$orderNumber');

      if (!mounted) return;

      HapticFeedback.mediumImpact();
      cart.clear();
      // Nudge the orders list to refetch so history reflects the new order
      // the moment the user opens the tab.
      unawaited(ordersCtrl.refresh());
      // Re-fetch /me so the header's loyalty points reflect the ones
      // just earned by this order.
      unawaited(authCtrl.refreshUser());

      // Spec §1: pushReplacement so back from Tracking goes Home, never Checkout.
      Navigator.of(context).pushReplacement(
        ChRoutes.slideUpFade((_) => TrackingScreen(
          orderId: orderNumber,
          mode:    mode,
          branch:  branch,
          deliveryAddress: mode == OrderMode.delivery ? addressLine : null,
        )),
      );
    } catch (e) {
      _cLog('placeOrder ✗ $e');
      if (!mounted) return;
      setState(() => _placing = false);

      // Extract a clean human message from ApiException; server puts a
      // localized reason in `.message` ("الفرع مغلق حالياً.", "المطعم
      // مقفل حالياً.", etc.). Fall back to a generic line otherwise.
      final raw = e is ApiException
          ? e.message
          : (e is StateError ? e.message : 'ما قدرنا نأكد الطلب — جرّب مرة تانية');

      // Business-hours failures should NOT show a red retry-me snackbar —
      // spamming Retry can't reopen the branch. Route to an explanatory
      // sheet with actions that actually help.
      final isClosed = raw.contains('مغلق') || raw.contains('مقفل');
      if (isClosed) {
        await _showBranchClosedSheet(raw);
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(raw,
            style: GoogleFonts.cairo(
              fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          backgroundColor: CH.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 108),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'إعادة المحاولة', textColor: Colors.white, onPressed: _placeOrder,
          ),
        ));
    }
  }

  /// Explains that the pickup branch (or the whole restaurant) is closed and
  /// gives the user something to actually do — pickup gets a "switch branch"
  /// CTA, delivery just gets a clear "come back later" message.
  Future<void> _showBranchClosedSheet(String serverMsg) async {
    final cart = context.read<CartController>();
    final isPickup = cart.mode == OrderMode.pickup;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          top: 22, left: 20, right: 20,
          bottom: 24 + MediaQuery.paddingOf(sheetCtx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44, height: 4,
                decoration: BoxDecoration(
                  color: CH.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Center(child: Text('🕒', style: TextStyle(fontSize: 44))),
            const SizedBox(height: 10),
            Text('المطعم مغلق حالياً',
              textAlign: TextAlign.center,
              style: GoogleFonts.changa(
                fontSize: 20, fontWeight: FontWeight.w800, color: CH.ink)),
            const SizedBox(height: 6),
            Text(
              serverMsg.replaceAll(RegExp(r'\.+$'), ''),
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w600, color: CH.muted,
                height: 1.6),
            ),
            const SizedBox(height: 6),
            Text(
              isPickup
                  ? 'جرّب فرع تاني ضمن ساعات العمل، أو انتظر افتتاح هذا الفرع.'
                  : 'الطلب محفوظ في السلة — رجّع بعد فتح المطعم لتأكيده.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted,
                height: 1.6),
            ),
            const SizedBox(height: 22),
            if (isPickup)
              ChPrimaryButton(
                label: 'اختر فرع تاني',
                onPressed: () async {
                  Navigator.of(sheetCtx).pop();
                  if (!mounted) return;
                  await Navigator.of(context).push(
                    ChRoutes.slideUpFade((_) => const BranchesScreen()),
                  );
                  if (mounted) setState(() {});
                },
              )
            else
              ChPrimaryButton(
                label: 'حسناً',
                onPressed: () => Navigator.of(sheetCtx).pop(),
              ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: Text('إغلاق',
                  style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final cart     = context.watch<CartController>();
    final totals   = cart.totals;
    final methods  = _methodsFor(cart.mode);
    final points   = _pointsDiscount(totals.subtotal, totals.deliveryFee);
    final total    = _totalOf(totals.subtotal, totals.deliveryFee);

    final belowMin        = !cart.isEmpty && totals.subtotal < _minOrderSyp;
    final missingAddress  = cart.mode == OrderMode.delivery && !_hasValidAddress;
    final missingBranch   = cart.mode == OrderMode.pickup   && cart.branch == null;
    final canPlace = !cart.isEmpty && !belowMin && !missingAddress && !missingBranch;

    final topInset = MediaQuery.paddingOf(context).top;

    // Make sure Cash is picked when pickup switches off the payment we can't use.
    if (cart.mode == OrderMode.delivery && _pay == PayMethod.payAtCounter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pay = PayMethod.cash);
      });
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Scaffold(
          backgroundColor: CH.cream,
          body: IgnorePointer(
            ignoring: _placing,
            child: Stack(
              children: [
                ListView(
                  padding: EdgeInsets.only(top: topInset + 8, bottom: 130),
                  children: [
                    _Header(
                      glyph: isArabic ? '→' : '←',
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(height: 16),

                    // Fulfilment card (address input / branch)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
                      child: _FulfilmentCard(
                        mode:              cart.mode,
                        addressController: _addressCtrl,
                        branch:            cart.branch,
                        etaMinutes:        _etaMinutes,
                        onChangeBranch:    _changePickupBranch,
                      ),
                    ),

                    // Payment title
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('طريقة الدفع',
                          style: GoogleFonts.changa(
                            fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink)),
                      ),
                    ),

                    // Payment rows
                    for (final m in methods)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
                        child: _PaymentRow(
                          method: m,
                          selected: m == _pay,
                          onTap: () => setState(() => _pay = m),
                        ),
                      ),

                    // Cash change chips (delivery + cash only)
                    if (_pay == PayMethod.cash && cart.mode == OrderMode.delivery)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 14),
                        child: _CashChangeChips(
                          value: _cashChange,
                          onChanged: (v) => setState(() => _cashChange = v),
                        ),
                      )
                    else
                      const SizedBox(height: 4),

                    // Coupon row — server-validated code input + the
                    // customer's personal wallet of redeemed rewards.
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
                      child: _CouponRow(
                        controller: _couponCtrl,
                        coupon:  _coupon,
                        error:   _couponError,
                        busy:    _couponBusy,
                        wallet:  context.watch<LoyaltyController>().activeCoupons,
                        onApply:  _applyCouponCode,
                        onRemove: _removeCoupon,
                        onBrowse: _browseCoupons,
                        onWalletTap: _applyFromWallet,
                      ),
                    ),

                    // Points row (only if signed-in + ≥ floor)
                    if (_showPointsRow)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
                        child: _PointsRow(
                          on:        _usePoints,
                          balance:   _pointsBalance,
                          valueSyp:  _pointValueSyp,
                          capped:    _usePoints && points < _pointsDiscountRaw,
                          onChanged: (v) => setState(() => _usePoints = v),
                        ),
                      ),

                    // Totals card
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                      child: _TotalsCard(
                        subtotal:        totals.subtotal,
                        deliveryFee:     totals.deliveryFee,
                        couponDiscount:  _coupon?.saving ?? 0,
                        pointsDiscount:  points,
                        total:           total,
                        mode:            cart.mode,
                      ),
                    ),

                    if (belowMin) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
                        child: Text(
                          'الحد الأدنى للطلب ${ChMoney.format(_minOrderSyp)}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            fontSize: 12, fontWeight: FontWeight.w700, color: CH.red),
                        ),
                      ),
                    ],
                  ],
                ),

                // Fixed CTA bar
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _CtaBar(
                    total:   total,
                    busy:    _placing,
                    enabled: canPlace,
                    hint:    _disabledReason(cart, missingAddress, missingBranch, belowMin),
                    onTap:   _placeOrder,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// e.g. `CH-2481` — 4 digits derived from the current epoch.
  static String _generateOrderId() {
    final s = DateTime.now().millisecondsSinceEpoch.toString();
    return 'CH-${s.substring(s.length - 4)}';
  }

  String? _disabledReason(CartController cart, bool noAddr, bool noBranch, bool below) {
    if (cart.isEmpty) return 'السلة فارغة';
    if (noAddr)       return 'اكتب عنوان التوصيل أوّلاً';
    if (noBranch)     return 'اختر فرع الاستلام أوّلاً';
    if (below)        return 'المبلغ أقل من الحد الأدنى';
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════
//  Coupon value object (local to this screen)
// ═════════════════════════════════════════════════════════════════
class _Coupon {
  final String code;
  final int    saving;   // SYP
  const _Coupon({required this.code, required this.saving});
}

// ═════════════════════════════════════════════════════════════════
//  Header — back button + title
// ═════════════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  final String glyph;
  final VoidCallback onBack;
  const _Header({required this.glyph, required this.onBack});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
        child: Row(
          children: [
            _IconBoxButton(glyph: glyph, onTap: onBack),
            const SizedBox(width: 12),
            Text('إتمام الطلب',
              style: GoogleFonts.changa(
                fontSize: 25, fontWeight: FontWeight.w800, color: CH.ink)),
          ],
        ),
      );
}

class _IconBoxButton extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  const _IconBoxButton({required this.glyph, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'رجوع',
        child: SizedBox(
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
        ),
      );
}

// ═════════════════════════════════════════════════════════════════
//  Fulfilment card — inline address textarea for delivery,
//  branch selector for pickup.
// ═════════════════════════════════════════════════════════════════
class _FulfilmentCard extends StatelessWidget {
  final OrderMode              mode;
  final TextEditingController  addressController;
  final Branch?                branch;
  final int                    etaMinutes;
  final VoidCallback           onChangeBranch;

  const _FulfilmentCard({
    required this.mode,
    required this.addressController,
    required this.branch,
    required this.etaMinutes,
    required this.onChangeBranch,
  });

  @override
  Widget build(BuildContext context) {
    return mode == OrderMode.delivery
        ? _DeliveryAddressCard(
            controller: addressController,
            etaMinutes: etaMinutes,
          )
        : _PickupBranchCard(
            branch:   branch,
            onChange: onChangeBranch,
          );
  }
}

// ─── Delivery: inline address input ─────────────────────────────
class _DeliveryAddressCard extends StatelessWidget {
  final TextEditingController controller;
  final int                   etaMinutes;
  const _DeliveryAddressCard({
    required this.controller,
    required this.etaMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: CH.cream, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: const Text('📍', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Text('عنوان التوصيل',
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: CH.cream,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CH.line, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller:      controller,
              maxLines:        4,
              minLines:        3,
              maxLength:       500,
              textInputAction: TextInputAction.newline,
              cursorColor:     CH.hot,
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w700, color: CH.ink, height: 1.6),
              decoration: InputDecoration(
                counterText:        '',
                border:             InputBorder.none,
                enabledBorder:      InputBorder.none,
                focusedBorder:      InputBorder.none,
                errorBorder:        InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder:     InputBorder.none,
                filled:             false,
                fillColor:          Colors.transparent,
                isDense:            true,
                contentPadding:     const EdgeInsets.symmetric(vertical: 12),
                hintText: 'اكتب عنوانك بالتفصيل — المنطقة، الشارع، البناء، الطابق، أي معلم قريب…',
                hintStyle: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: const Color(0xFFB3A396), height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text('الوصول خلال ~$etaMinutes دقيقة',
            style: GoogleFonts.cairo(
              fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
        ],
      ),
    );
  }
}

// ─── Pickup: branch card (unchanged) ────────────────────────────
class _PickupBranchCard extends StatelessWidget {
  final Branch?      branch;
  final VoidCallback onChange;
  const _PickupBranchCard({required this.branch, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final detail = branch == null
        ? 'لم يتم اختيار فرع — اضغط "تغيير"'
        : '${branch!.nameAr} — ${branch!.addressAr}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: CH.cream, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: const Text('🏬', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('الاستلام من',
                  style: GoogleFonts.cairo(
                    fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
                const SizedBox(height: 3),
                Text(detail,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true, label: 'تغيير',
            child: SizedBox(
              height: 44,
              child: TextButton(
                onPressed: onChange,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('تغيير',
                  style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w800, color: CH.hot)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Payment row — selection row shape
// ═════════════════════════════════════════════════════════════════
class _PaymentRow extends StatelessWidget {
  final PayMethod method;
  final bool selected;
  final VoidCallback onTap;
  const _PaymentRow({required this.method, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, selected: selected, inMutuallyExclusiveGroup: true,
      label: '${method.labelAr}, ${method.detailAr}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? CH.hot : Colors.transparent, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: CH.cream, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(method.emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(method.labelAr,
                        style: GoogleFonts.cairo(
                          fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
                      const SizedBox(height: 3),
                      Text(method.detailAr,
                        style: GoogleFonts.cairo(
                          fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Radio(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool selected;
  const _Radio({required this.selected});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? CH.hot : Colors.white,
          border: Border.all(
            color: selected ? CH.hot : const Color(0xFFDCCBBA), width: 1.5),
        ),
        child: !selected ? null : Center(
          child: Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          ),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════
//  Cash change chips
// ═════════════════════════════════════════════════════════════════
class _CashChangeChips extends StatelessWidget {
  final int value;                    // 0 = none; else denomination in SYP
  final ValueChanged<int> onChanged;
  const _CashChangeChips({required this.value, required this.onChanged});

  static const _options = <(int, String)>[
    (0,      'بدون'),
    (50000,  '50,000'),
    (100000, '100,000'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('معك فراطة؟',
          style: GoogleFonts.cairo(
            fontSize: 12, fontWeight: FontWeight.w800, color: CH.muted)),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 8, runSpacing: 6,
            children: [
              for (final (v, label) in _options)
                _Chip(
                  label: label,
                  selected: v == value,
                  onTap: () => onChanged(v),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, selected: selected, inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? CH.hot : Colors.white,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              shape: StadiumBorder(side: BorderSide(
                color: selected ? CH.hot : CH.line, width: 1.5)),
            ),
            child: Text(label,
              style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: selected ? Colors.white : CH.ink)),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Coupon row
// ═════════════════════════════════════════════════════════════════
class _CouponRow extends StatelessWidget {
  final TextEditingController controller;
  final _Coupon?      coupon;
  final String?       error;
  final bool          busy;
  final List<MyCoupon> wallet;
  final VoidCallback  onApply;
  final VoidCallback  onRemove;
  final VoidCallback  onBrowse;
  final Future<void> Function(MyCoupon) onWalletTap;

  const _CouponRow({
    required this.controller,
    required this.coupon,
    required this.error,
    required this.busy,
    required this.wallet,
    required this.onApply,
    required this.onRemove,
    required this.onBrowse,
    required this.onWalletTap,
  });

  @override
  Widget build(BuildContext context) {
    // Applied → show a compact "applied" card. Not applied → show a proper
    // text field where the customer types the code, plus a small "browse"
    // link below for those who don't know their code by heart.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: error != null ? CH.red : CH.line, width: 1.2),
          ),
          child: coupon != null
              ? _AppliedRow(coupon: coupon!, onRemove: onRemove)
              : _InputRow(
                  controller: controller,
                  busy:       busy,
                  onApply:    onApply,
                ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 4, 0),
            child: Text(error!,
              style: GoogleFonts.cairo(
                fontSize: 12, fontWeight: FontWeight.w700, color: CH.red)),
          ),
        if (coupon == null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 4, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onBrowse,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('استعرض الكوبونات المتاحة',
                  style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w800, color: CH.hot)),
              ),
            ),
          ),

        // ── Personal wallet: coupons the customer already redeemed with
        //    points. Tap to apply — no need to remember/copy the code.
        if (coupon == null && wallet.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text('كوبوناتك',
                style: GoogleFonts.cairo(
                  fontSize: 12, fontWeight: FontWeight.w800, color: CH.muted)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CH.hot.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${wallet.length}',
                  style: GoogleFonts.cairo(
                    fontSize: 11, fontWeight: FontWeight.w800, color: CH.hot)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final c in wallet)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _WalletCouponTile(coupon: c, onTap: () => onWalletTap(c)),
            ),
        ],
      ],
    );
  }
}

/// One row in the "كوبوناتك" list — visually distinct from the input card
/// so it's obvious this is a saved coupon (from redeeming points), not
/// something the user typed.
class _WalletCouponTile extends StatelessWidget {
  final MyCoupon coupon;
  final VoidCallback onTap;
  const _WalletCouponTile({required this.coupon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final expiresIn = coupon.expiresAt?.difference(DateTime.now()).inDays;
    final expiryLabel = expiresIn == null
        ? null
        : expiresIn <= 0
            ? 'ينتهي اليوم'
            : (expiresIn == 1 ? 'ينتهي غداً' : 'باقي $expiresIn يوم');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CH.hot.withValues(alpha: 0.3), width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Reward avatar
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox(
                  width: 40, height: 40,
                  child: (coupon.rewardImageUrl == null || coupon.rewardImageUrl!.isEmpty)
                      ? Container(
                          color: CH.cream,
                          alignment: Alignment.center,
                          child: Text(coupon.rewardEmoji, style: const TextStyle(fontSize: 20)),
                        )
                      : Image.network(coupon.rewardImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: CH.cream,
                            alignment: Alignment.center,
                            child: Text(coupon.rewardEmoji, style: const TextStyle(fontSize: 20)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              // Reward name + code + savings
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(coupon.rewardName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w800, color: CH.ink)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(coupon.code ?? '',
                          style: GoogleFonts.cairo(
                            fontSize: 11, fontWeight: FontWeight.w800,
                            color: CH.hot, letterSpacing: 0.5)),
                      ),
                      const SizedBox(width: 6),
                      Text('· يخصم ${ChMoney.format(coupon.discountSyp)}',
                        style: GoogleFonts.cairo(
                          fontSize: 11, fontWeight: FontWeight.w700, color: CH.muted)),
                    ]),
                    if (expiryLabel != null) ...[
                      const SizedBox(height: 2),
                      Text('⏳ $expiryLabel',
                        style: GoogleFonts.cairo(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: (expiresIn != null && expiresIn <= 2) ? CH.red : CH.muted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // One-tap apply pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: CH.hot,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('تطبيق',
                  style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onApply;
  const _InputRow({
    required this.controller,
    required this.busy,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final canApply = controller.text.trim().isNotEmpty && !busy;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsetsDirectional.only(start: 4, end: 8),
          child: Text('🎟️', style: TextStyle(fontSize: 18)),
        ),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: controller,
              enabled: !busy,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-_]')),
                LengthLimitingTextInputFormatter(40),
              ],
              onSubmitted: (_) => canApply ? onApply() : null,
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w800,
                color: CH.ink, letterSpacing: 0.5),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
                hintText: 'كود الخصم',
                hintStyle: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w700, color: CH.muted),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: canApply ? CH.char : CH.line,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            onTap: canApply ? onApply : null,
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: busy
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text('تطبيق',
                      style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: canApply ? Colors.white : CH.muted)),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppliedRow extends StatelessWidget {
  final _Coupon coupon;
  final VoidCallback onRemove;
  const _AppliedRow({required this.coupon, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsetsDirectional.only(start: 4, end: 12),
          child: Text('🎟️', style: TextStyle(fontSize: 18)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(coupon.code,
                  style: GoogleFonts.cairo(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: CH.ink, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 3),
              Text('وفّرت ${ChMoney.format(coupon.saving)}',
                style: GoogleFonts.cairo(
                  fontSize: 12, fontWeight: FontWeight.w700, color: CH.green)),
            ],
          ),
        ),
        Semantics(
          button: true, label: 'إزالة الكود',
          child: SizedBox(
            width: 44, height: 44,
            child: InkResponse(
              onTap: onRemove,
              radius: 22,
              child: const Icon(Icons.close_rounded, size: 20, color: CH.muted),
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Points row — switch (yellow tile)
// ═════════════════════════════════════════════════════════════════
class _PointsRow extends StatelessWidget {
  final bool   on;
  final int    balance;
  final int    valueSyp;
  final bool   capped;
  final ValueChanged<bool> onChanged;

  const _PointsRow({
    required this.on, required this.balance, required this.valueSyp,
    required this.capped, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final worth = balance * valueSyp;
    final detail = capped
        ? 'تم استخدام النقاط اللازمة فقط'
        : '$balance نقطة = خصم ${ChMoney.format(worth)}';

    return Semantics(
      toggled: on,
      button: true, label: 'استخدم نقاطي',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => onChanged(!on),
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: on ? CH.hot : Colors.transparent, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4D6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Text('⭐', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('استخدم نقاطي',
                        style: GoogleFonts.cairo(
                          fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink)),
                      const SizedBox(height: 3),
                      Text(detail,
                        style: GoogleFonts.cairo(
                          fontSize: 12, fontWeight: FontWeight.w600, color: CH.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _MiniSwitch(on: on, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniSwitch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const _MiniSwitch({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 46, height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: on ? CH.green : const Color(0xFFE2D3C3),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          // Directional: knob sits at the END edge when on. In RTL the end
          // edge is the LEFT of the track, which matches the universal
          // switch convention of "on = away from label".
          alignment: on ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
          child: Container(
            width: 20, height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.white,
              boxShadow: [BoxShadow(
                color: Color(0x33000000), offset: Offset(0, 1), blurRadius: 2)],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Totals card
// ═════════════════════════════════════════════════════════════════
class _TotalsCard extends StatelessWidget {
  final int subtotal;
  final int deliveryFee;
  final int couponDiscount;
  final int pointsDiscount;
  final int total;
  final OrderMode mode;

  const _TotalsCard({
    required this.subtotal, required this.deliveryFee,
    required this.couponDiscount, required this.pointsDiscount,
    required this.total, required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final feeLabel = mode == OrderMode.delivery ? 'رسوم التوصيل' : 'الاستلام من الفرع';
    final feeValue = deliveryFee == 0 ? 'مجاناً' : ChMoney.format(deliveryFee);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(label: 'المجموع الفرعي', value: ChMoney.format(subtotal)),
          const SizedBox(height: 8),
          _Line(label: feeLabel, value: feeValue, positiveGreen: deliveryFee == 0),
          if (couponDiscount > 0) ...[
            const SizedBox(height: 8),
            _Line(label: 'خصم الكوبون',
              value: '− ${ChMoney.format(couponDiscount)}',
              positiveGreen: true, boldGreen: true),
          ],
          if (pointsDiscount > 0) ...[
            const SizedBox(height: 8),
            _Line(label: 'خصم النقاط',
              value: '− ${ChMoney.format(pointsDiscount)}',
              positiveGreen: true, boldGreen: true),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 12),
            child: _DashedHLine(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي',
                style: GoogleFonts.changa(
                  fontSize: 19, fontWeight: FontWeight.w800, color: CH.ink)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  key: ValueKey(total),
                  child: Text(ChMoney.format(total),
                    style: GoogleFonts.changa(
                      fontSize: 19, fontWeight: FontWeight.w800, color: CH.hot)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool positiveGreen;   // fee = free
  final bool boldGreen;       // discount lines
  const _Line({
    required this.label, required this.value,
    this.positiveGreen = false, this.boldGreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = GoogleFonts.cairo(
      fontSize: 14,
      fontWeight: boldGreen ? FontWeight.w700 : FontWeight.w700,
      color: (positiveGreen || boldGreen) ? CH.green : const Color(0xFF6D5D51),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
          style: GoogleFonts.cairo(
            fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF6D5D51))),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: Directionality(
            textDirection: TextDirection.ltr,
            key: ValueKey('$label-$value'),
            child: Text(value, style: valueStyle),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Dashed 1-px horizontal line (shared pattern)
// ═════════════════════════════════════════════════════════════════
class _DashedHLine extends StatelessWidget {
  const _DashedHLine();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1,
        child: CustomPaint(
          painter: _DashedHLinePainter(
            color: const Color(0xFFE6D6C6),
            dashLength: 5, gapLength: 4, strokeWidth: 1,
          ),
          child: const SizedBox.expand(),
        ),
      );
}

class _DashedHLinePainter extends CustomPainter {
  final Color color;
  final double dashLength;
  final double gapLength;
  final double strokeWidth;
  _DashedHLinePainter({
    required this.color, required this.dashLength,
    required this.gapLength, required this.strokeWidth,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = strokeWidth;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dashLength).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += dashLength + gapLength;
    }
  }
  @override
  bool shouldRepaint(_DashedHLinePainter o) =>
      o.color != color || o.dashLength != dashLength ||
      o.gapLength != gapLength || o.strokeWidth != strokeWidth;
}

// ═════════════════════════════════════════════════════════════════
//  CTA bar (fixed, bottom)
// ═════════════════════════════════════════════════════════════════
class _CtaBar extends StatelessWidget {
  final int total;
  final bool busy;
  final bool enabled;
  final String? hint;
  final VoidCallback onTap;

  const _CtaBar({
    required this.total, required this.busy, required this.enabled,
    required this.hint, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: 14, left: 20, right: 20,
        bottom: 20 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: CH.navTopBorder, width: 1)),
      ),
      child: _PrimaryCta(
        total: total, busy: busy, enabled: enabled, hint: hint, onTap: onTap,
      ),
    );
  }
}

class _PrimaryCta extends StatefulWidget {
  final int total;
  final bool busy;
  final bool enabled;
  final String? hint;
  final VoidCallback onTap;
  const _PrimaryCta({
    required this.total, required this.busy, required this.enabled,
    required this.hint, required this.onTap,
  });

  @override
  State<_PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<_PrimaryCta> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && !widget.busy;
    return Semantics(
      button: true, enabled: active,
      hint: widget.busy ? 'جاري تأكيد الطلب' : widget.hint,
      child: AnimatedScale(
        scale: active && _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: active ? ChShadows.primaryButton : null,
          ),
          child: Material(
            color: !active ? CH.line : (_pressed ? CH.hotDeep : CH.hot),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: active ? widget.onTap : null,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.busy) ...[
                      const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ] else ...[
                      Text('تأكيد الطلب',
                        style: GoogleFonts.changa(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          color: active ? Colors.white : CH.inactive)),
                      Text('  ·  ',
                        style: GoogleFonts.changa(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          color: active ? Colors.white : CH.inactive)),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                          child: Text(
                            ChMoney.format(widget.total),
                            key: ValueKey(widget.total),
                            style: GoogleFonts.changa(
                              fontSize: 16, fontWeight: FontWeight.w800,
                              color: active ? Colors.white : CH.inactive),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
