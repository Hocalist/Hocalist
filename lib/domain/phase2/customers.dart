class SellerCustomer {
  const SellerCustomer({required this.buyerId, required this.displayName,
    required this.purchaseCount, required this.lastPurchaseAt,
    required this.saved, required this.note});
  final String buyerId;
  final String displayName;
  final int purchaseCount;
  final DateTime lastPurchaseAt;
  final bool saved;
  final String note;
}

class CustomerHistory {
  const CustomerHistory({required this.concludedRequests, required this.confirmedPurchases,
    required this.ongoingRequests, required this.completionPercent});
  final int concludedRequests;
  final int confirmedPurchases;
  final int ongoingRequests;
  final double? completionPercent;
}

typedef SellerCustomerList = ({bool insightsAvailable, List<SellerCustomer> items});
