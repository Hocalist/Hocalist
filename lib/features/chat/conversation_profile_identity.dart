typedef PublicSellerIdentity = ({String? profileId, String? name});

/// Profile entry points keep their own identity. A cached offer cannot replace
/// a chat participant, and an unrelated open chat cannot replace an offer.
PublicSellerIdentity sellerProfileIdentity({
  required bool fromConversation,
  PublicSellerIdentity? conversation,
  PublicSellerIdentity? offer,
}) =>
    (fromConversation ? conversation : offer) ?? (profileId: null, name: null);
