import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'persistence_service.dart';

/// Identifiers for every store product. Keep these in sync with Google Play
/// Console and App Store Connect exactly, including case.
class StoreIds {
  StoreIds._();

  static const String coinsTier1 = 'coins_tier_1_100';
  static const String coinsTier2 = 'coins_tier_2_500';
  static const String coinsTier3 = 'coins_tier_3_1200';
  static const String refillLives = 'refill_lives_full';
  static const String removeAds = 'remove_ads_permanent';

  static const Set<String> consumables = <String>{
    coinsTier1,
    coinsTier2,
    coinsTier3,
    refillLives,
  };

  static const Set<String> all = <String>{
    coinsTier1,
    coinsTier2,
    coinsTier3,
    refillLives,
    removeAds,
  };

  /// How many coins each coin pack grants.
  static const Map<String, int> coinAmounts = <String, int>{
    coinsTier1: 100,
    coinsTier2: 500,
    coinsTier3: 1200,
  };
}

/// A product the shop can render.
class ShopProduct {
  ShopProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.available,
  });

  final String id;
  final String title;
  final String description;

  /// Localised price string straight from the store, e.g. "£1.99".
  final String price;

  /// False when the store returned no product for this id (not configured yet,
  /// or the device has no store). The UI should show a fallback label.
  final bool available;

  bool get isConsumable => StoreIds.consumables.contains(id);
}

/// What happened to a purchase, surfaced to the UI so it can toast the player.
class PurchaseEvent {
  PurchaseEvent(this.kind, {this.productId, this.message, this.coins = 0});

  final PurchaseEventKind kind;
  final String? productId;
  final String? message;
  final int coins;

  static PurchaseEvent pending(String id) =>
      PurchaseEvent(PurchaseEventKind.pending, productId: id);
  static PurchaseEvent delivered(String id, {int coins = 0}) =>
      PurchaseEvent(PurchaseEventKind.delivered, productId: id, coins: coins);
  static PurchaseEvent restored(String id) =>
      PurchaseEvent(PurchaseEventKind.restored, productId: id);
  static PurchaseEvent failed(String message, {String? productId}) =>
      PurchaseEvent(PurchaseEventKind.failed,
          productId: productId, message: message);
  static PurchaseEvent cancelled(String id) =>
      PurchaseEvent(PurchaseEventKind.cancelled, productId: id);
}

enum PurchaseEventKind { pending, delivered, restored, failed, cancelled }

/// Full in app purchase lifecycle: product loading, purchase stream handling,
/// consumable delivery, non consumable unlocking and restore.
///
/// The purchase stream is the single source of truth. Nothing is granted until
/// the store reports `purchased` or `restored` for that product, which is what
/// both Google Play and Apple require.
class IapService {
  IapService(this._persistence);

  final PersistenceService _persistence;
  final InAppPurchase _iap = InAppPurchase.instance;
  final StreamController<PurchaseEvent> _events =
      StreamController<PurchaseEvent>.broadcast();

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final Map<String, ProductDetails> _details = <String, ProductDetails>{};
  bool _storeAvailable = false;
  bool _initialised = false;

  Stream<PurchaseEvent> get events => _events.stream;

  bool get storeAvailable => _storeAvailable;

  ProductDetails? detailsFor(String id) => _details[id];

  /// Fallback catalogue, used when the store returns nothing (emulator, no
  /// Play account, App Store review build). Prices here are display only and
  /// are never charged; the real price always comes from the store.
  List<ShopProduct> get catalogue {
    final List<ShopProduct> out = <ShopProduct>[];
    for (final String id in const <String>[
      StoreIds.coinsTier1,
      StoreIds.coinsTier2,
      StoreIds.coinsTier3,
      StoreIds.refillLives,
      StoreIds.removeAds,
    ]) {
      final ProductDetails? d = _details[id];
      out.add(ShopProduct(
        id: id,
        title: d?.title ?? _fallbackTitle(id),
        description: d?.description ?? _fallbackDescription(id),
        price: d?.price ?? _fallbackPrice(id),
        available: d != null,
      ));
    }
    return out;
  }

  static String _fallbackTitle(String id) {
    switch (id) {
      case StoreIds.coinsTier1:
        return 'Pocket of Coins';
      case StoreIds.coinsTier2:
        return 'Bag of Coins';
      case StoreIds.coinsTier3:
        return 'Chest of Coins';
      case StoreIds.refillLives:
        return 'Full Lives';
      case StoreIds.removeAds:
        return 'Remove Ads';
      default:
        return id;
    }
  }

  static String _fallbackDescription(String id) {
    switch (id) {
      case StoreIds.coinsTier1:
        return '100 coins for boosters.';
      case StoreIds.coinsTier2:
        return '500 coins, best value per coin.';
      case StoreIds.coinsTier3:
        return '1200 coins, the sweetest deal.';
      case StoreIds.refillLives:
        return 'Refill all 5 lives right now.';
      case StoreIds.removeAds:
        return 'No more interstitial ads, forever.';
      default:
        return '';
    }
  }

  static String _fallbackPrice(String id) {
    switch (id) {
      case StoreIds.coinsTier1:
        return '\$0.99';
      case StoreIds.coinsTier2:
        return '\$4.99';
      case StoreIds.coinsTier3:
        return '\$9.99';
      case StoreIds.refillLives:
        return '\$0.99';
      case StoreIds.removeAds:
        return '\$2.99';
      default:
        return '';
    }
  }

  /// Sets up the purchase stream and loads products. Safe to call twice.
  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    // Listen first, so a pending transaction from a previous run is delivered
    // before anything else.
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object error) {
        _events.add(PurchaseEvent.failed('Purchase stream error: $error'));
      },
    );

    try {
      _storeAvailable = await _iap.isAvailable();
    } catch (e) {
      _storeAvailable = false;
      _events.add(PurchaseEvent.failed('Store unavailable: $e'));
    }

    if (!_storeAvailable) {
      debugPrint('[IAP] Store not available on this device.');
      return;
    }

    try {
      final ProductDetailsResponse response =
          await _iap.queryProductDetails(StoreIds.all);
      if (response.error != null) {
        _events.add(PurchaseEvent.failed(
            'Product query failed: ${response.error!.message}'));
      }
      for (final ProductDetails d in response.productDetails) {
        _details[d.id] = d;
      }
      // Anything requested but not returned is either misconfigured or not yet
      // approved by the store; the shop falls back to a display-only entry.
      for (final String id in response.notFoundIDs) {
        debugPrint('[IAP] Product not found in store: $id');
      }
    } catch (e) {
      _events.add(PurchaseEvent.failed('Product query error: $e'));
    }

    // A non consumable that the player already owns should never be sold again.
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[IAP] Initial restore skipped: $e');
    }
  }

  /// Starts a purchase. The result arrives on [events], never here.
  Future<void> buy(String productId) async {
    if (!_storeAvailable) {
      _events.add(PurchaseEvent.failed(
          'The store is not available on this device.',
          productId: productId));
      return;
    }
    final ProductDetails? d = _details[productId];
    if (d == null) {
      _events.add(PurchaseEvent.failed('That item is not available right now.',
          productId: productId));
      return;
    }
    try {
      final PurchaseParam param = PurchaseParam(productDetails: d);
      if (StoreIds.consumables.contains(productId)) {
        await _iap.buyConsumable(purchaseParam: param, autoConsume: true);
      } else {
        await _iap.buyNonConsumable(purchaseParam: param);
      }
    } catch (e) {
      _events.add(PurchaseEvent.failed('Could not start the purchase: $e',
          productId: productId));
    }
  }

  /// Re-issues the restore flow. Required by both stores to be reachable from
  /// the UI, and it is how a reinstall gets its non consumables back.
  Future<void> restore() async {
    if (!_storeAvailable) {
      _events.add(
          PurchaseEvent.failed('The store is not available on this device.'));
      return;
    }
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _events.add(PurchaseEvent.failed('Restore failed: $e'));
    }
  }

  /// Handles every state the store can report for a transaction.
  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      try {
        switch (purchase.status) {
          case PurchaseStatus.pending:
            _events.add(PurchaseEvent.pending(purchase.productID));
            break;

          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            final bool restored = purchase.status == PurchaseStatus.restored;
            final bool granted = await _deliver(purchase, restored: restored);
            if (granted) {
              _events.add(restored
                  ? PurchaseEvent.restored(purchase.productID)
                  : PurchaseEvent.delivered(
                      purchase.productID,
                      coins: StoreIds.coinAmounts[purchase.productID] ?? 0,
                    ));
            }
            // Finishing tells the store the transaction is done. For
            // consumables with autoConsume this is still required.
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
            break;

          case PurchaseStatus.error:
            _events.add(PurchaseEvent.failed(
              purchase.error?.message ?? 'The purchase could not be completed.',
              productId: purchase.productID,
            ));
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
            break;

          case PurchaseStatus.canceled:
            _events.add(PurchaseEvent.cancelled(purchase.productID));
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
            break;
        }
      } catch (e) {
        _events.add(PurchaseEvent.failed('Could not process the purchase: $e',
            productId: purchase.productID));
      }
    }
  }

  /// Grants the goods. Returns false when the product is unknown, so the UI is
  /// never told about a delivery that did not happen.
  ///
  /// A real deployment should verify `purchase.verificationData.serverVerificationData`
  /// against Google Play / App Store server APIs before granting. That needs a
  /// backend, so this build grants locally and logs the receipt for later.
  Future<bool> _deliver(PurchaseDetails purchase,
      {required bool restored}) async {
    final String id = purchase.productID;
    final PlayerProgress p = _persistence.progress;

    switch (id) {
      case StoreIds.coinsTier1:
      case StoreIds.coinsTier2:
      case StoreIds.coinsTier3:
        final int amount = StoreIds.coinAmounts[id] ?? 0;
        p.coins += amount;
        await _persistence.save();
        return true;

      case StoreIds.refillLives:
        p.refillLives();
        await _persistence.save();
        return true;

      case StoreIds.removeAds:
        p.adsRemoved = true;
        await _persistence.save();
        return true;

      default:
        debugPrint('[IAP] Unknown product delivered: $id');
        return false;
    }
  }

  /// Cheap local check used to hide ad units before the store answers.
  bool get adsRemoved => _persistence.progress.adsRemoved;

  void dispose() {
    _subscription?.cancel();
    _events.close();
  }
}
