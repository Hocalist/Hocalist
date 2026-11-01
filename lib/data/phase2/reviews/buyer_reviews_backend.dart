import 'package:supabase_flutter/supabase_flutter.dart';

class BuyerReviewEntry {
  BuyerReviewEntry({
    required this.id,
    required this.rating,
    required this.body,
    required this.seller,
    required this.createdAt,
  });
  final String id, body, seller;
  final int rating;
  final DateTime createdAt;
}

class BuyerReviewPurchase {
  BuyerReviewPurchase({
    required this.id,
    required this.title,
    required this.date,
  });
  final String id, title;
  final DateTime date;
}

class BuyerReviewsPageData {
  BuyerReviewsPageData({
    required this.available,
    required this.count,
    required this.sum,
    required this.items,
    required this.purchases,
    required this.hasMore,
  });
  final bool available, hasMore;
  final int count, sum;
  final List<BuyerReviewEntry> items;
  final List<BuyerReviewPurchase> purchases;
}

abstract interface class BuyerReviewsRepository {
  Future<BuyerReviewsPageData> load({int offset = 0});
  Future<void> submit(String key, String outcomeId, int rating, String body);
  Future<void> report(String reviewId, String reason);
}

class BuyerReviewsBackend implements BuyerReviewsRepository {
  BuyerReviewsBackend(this.client, this.profileId)
    : owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String profileId;
  final String? owner;
  Future<Map<String, dynamic>> call(
    String fn,
    Map<String, Object?> params,
  ) async {
    if (owner == null || client.auth.currentUser?.id != owner)
      throw StateError('Account changed');
    final result = await client.schema('hocalist').rpc(fn, params: params);
    if (client.auth.currentUser?.id != owner)
      throw StateError('Account changed');
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<BuyerReviewsPageData> load({int offset = 0}) async {
    final d = await call('buyer_reviews_read', {
      'p_profile': profileId,
      'p_offset': offset,
    });
    return BuyerReviewsPageData(
      available: d['available'] as bool,
      count: d['rating_count'] as int,
      sum: d['rating_sum'] as int,
      hasMore: d['has_more'] as bool,
      items: (d['items'] as List)
          .map(
            (v) => BuyerReviewEntry(
              id: v['id'] as String,
              rating: v['rating'] as int,
              body: v['body'] as String,
              seller: v['reviewer_label'] as String,
              createdAt: DateTime.parse(v['created_at'] as String),
            ),
          )
          .toList(),
      purchases: (d['eligible'] as List)
          .map(
            (v) => BuyerReviewPurchase(
              id: v['outcome_id'] as String,
              title: v['title'] as String,
              date: DateTime.parse(v['confirmed_at'] as String),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> submit(
    String key,
    String outcomeId,
    int rating,
    String body,
  ) async {
    await call('buyer_review_submit', {
      'p_key': key,
      'p_input': {'outcome_id': outcomeId, 'rating': rating, 'body': body},
    });
  }

  @override
  Future<void> report(String reviewId, String reason) async {
    await call('buyer_review_report', {
      'p_review': reviewId,
      'p_reason': reason,
    });
  }
}
