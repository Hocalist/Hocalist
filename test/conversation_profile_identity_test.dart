import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/chat/conversation_profile_identity.dart';

void main() {
  test('chat B cannot display the cached seller from offer A', () {
    expect(
      sellerProfileIdentity(
        fromConversation: true,
        conversation: (profileId: 'seller-b', name: 'Seller B'),
        offer: (profileId: 'seller-a', name: 'Seller A'),
      ),
      (profileId: 'seller-b', name: 'Seller B'),
    );
  });
  test('missing chat identity never falls back to an unrelated offer', () {
    expect(
      sellerProfileIdentity(
        fromConversation: true,
        offer: (profileId: 'seller-a', name: 'Seller A'),
      ),
      (profileId: null, name: null),
    );
  });
  test('offer entry ignores another open conversation', () {
    expect(
      sellerProfileIdentity(
        fromConversation: false,
        conversation: (profileId: 'seller-b', name: 'Seller B'),
        offer: (profileId: 'seller-a', name: 'Seller A'),
      ),
      (profileId: 'seller-a', name: 'Seller A'),
    );
  });
}
