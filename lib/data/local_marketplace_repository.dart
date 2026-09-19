import 'dart:convert';

import 'package:flutter/foundation.dart';

enum LocalOfferStatus { sent, selected, meetingConfirmed, completed }

@immutable
class LocalRequestRecord {
  const LocalRequestRecord({
    required this.id,
    required this.buyerName,
    required this.title,
    required this.budget,
  });

  final String id;
  final String buyerName;
  final String title;
  final String budget;
}

@immutable
class LocalOfferRecord {
  const LocalOfferRecord({
    required this.id,
    required this.requestId,
    required this.buyerName,
    required this.sellerName,
    required this.requestTitle,
    required this.price,
    required this.location,
    required this.meetingDate,
    required this.meetingTime,
    required this.message,
    required this.imageNames,
    required this.status,
  });

  factory LocalOfferRecord.fromJson(Map<String, Object?> json) {
    return LocalOfferRecord(
      id: json['id']! as String,
      requestId: json['requestId']! as String,
      buyerName: json['buyerName']! as String,
      sellerName: json['sellerName']! as String,
      requestTitle: json['requestTitle']! as String,
      price: json['price']! as String,
      location: json['location']! as String,
      meetingDate: json['meetingDate']! as String,
      meetingTime: json['meetingTime']! as String,
      message: json['message']! as String,
      imageNames: (json['imageNames']! as List<Object?>).cast<String>(),
      status: LocalOfferStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => LocalOfferStatus.sent,
      ),
    );
  }

  final String id;
  final String requestId;
  final String buyerName;
  final String sellerName;
  final String requestTitle;
  final String price;
  final String location;
  final String meetingDate;
  final String meetingTime;
  final String message;
  final List<String> imageNames;
  final LocalOfferStatus status;

  LocalOfferRecord copyWith({LocalOfferStatus? status}) {
    return LocalOfferRecord(
      id: id,
      requestId: requestId,
      buyerName: buyerName,
      sellerName: sellerName,
      requestTitle: requestTitle,
      price: price,
      location: location,
      meetingDate: meetingDate,
      meetingTime: meetingTime,
      message: message,
      imageNames: imageNames,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'requestId': requestId,
    'buyerName': buyerName,
    'sellerName': sellerName,
    'requestTitle': requestTitle,
    'price': price,
    'location': location,
    'meetingDate': meetingDate,
    'meetingTime': meetingTime,
    'message': message,
    'imageNames': imageNames,
    'status': status.name,
  };
}

@immutable
class LocalChatEntry {
  const LocalChatEntry({
    required this.id,
    required this.senderIsSeller,
    required this.sentAtLabel,
    this.text = '',
    this.attachmentLabel,
    this.attachmentIsImage = false,
  });

  factory LocalChatEntry.fromJson(Map<String, Object?> json) {
    return LocalChatEntry(
      id: json['id']! as String,
      senderIsSeller: json['senderIsSeller']! as bool,
      sentAtLabel: json['sentAtLabel']! as String,
      text: (json['text'] as String?) ?? '',
      attachmentLabel: json['attachmentLabel'] as String?,
      attachmentIsImage: (json['attachmentIsImage'] as bool?) ?? false,
    );
  }

  final String id;
  final bool senderIsSeller;
  final String sentAtLabel;
  final String text;
  final String? attachmentLabel;
  final bool attachmentIsImage;

  Map<String, Object?> toJson() => {
    'id': id,
    'senderIsSeller': senderIsSeller,
    'sentAtLabel': sentAtLabel,
    'text': text,
    'attachmentLabel': attachmentLabel,
    'attachmentIsImage': attachmentIsImage,
  };
}

/// Replaceable local data seam for the frontend-only prototype.
///
/// Upgraded Buyer and Seller routes read the same records from here so a local
/// action remains consistent until the real Supabase repositories are wired.
class LocalMarketplaceRepository extends ChangeNotifier {
  LocalMarketplaceRepository({
    this.request = const LocalRequestRecord(
      id: 'request-ipad-air',
      buyerName: 'Maya Chen',
      title: 'iPad Air, 5th gen or newer',
      budget: r'$350 - $480',
    ),
  });

  final LocalRequestRecord request;
  LocalOfferRecord? _latestOffer;
  final List<LocalChatEntry> _conversationEntries = <LocalChatEntry>[];
  int _sequence = 0;

  LocalOfferRecord? get latestOffer => _latestOffer;
  List<LocalChatEntry> get conversationEntries =>
      List<LocalChatEntry>.unmodifiable(_conversationEntries);

  void submitOffer(LocalOfferRecord offer) {
    _latestOffer = offer;
    notifyListeners();
  }

  void updateOfferStatus(LocalOfferStatus status) {
    final offer = _latestOffer;
    if (offer == null) return;
    _latestOffer = offer.copyWith(status: status);
    notifyListeners();
  }

  LocalChatEntry addConversationEntry({
    required bool senderIsSeller,
    String text = '',
    String? attachmentLabel,
    bool attachmentIsImage = false,
  }) {
    _sequence += 1;
    final entry = LocalChatEntry(
      id: 'local-message-$_sequence',
      senderIsSeller: senderIsSeller,
      sentAtLabel: 'Now',
      text: text,
      attachmentLabel: attachmentLabel,
      attachmentIsImage: attachmentIsImage,
    );
    _conversationEntries.add(entry);
    notifyListeners();
    return entry;
  }

  String encodeSnapshot() {
    return jsonEncode({
      'latestOffer': _latestOffer?.toJson(),
      'conversationEntries': _conversationEntries
          .map((entry) => entry.toJson())
          .toList(),
      'sequence': _sequence,
    });
  }

  void restoreSnapshot(String? encoded) {
    if (encoded == null || encoded.isEmpty) return;
    try {
      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      final offer = decoded['latestOffer'];
      _latestOffer = offer is Map<String, Object?>
          ? LocalOfferRecord.fromJson(offer)
          : null;
      _conversationEntries
        ..clear()
        ..addAll(
          ((decoded['conversationEntries'] as List<Object?>?) ?? const [])
              .whereType<Map<String, Object?>>()
              .map(LocalChatEntry.fromJson),
        );
      _sequence =
          (decoded['sequence'] as num?)?.toInt() ?? _conversationEntries.length;
    } on FormatException {
      // Ignore stale prototype snapshots and retain the safe defaults.
    } on TypeError {
      // Ignore snapshots created by an older incompatible local schema.
    }
  }
}
