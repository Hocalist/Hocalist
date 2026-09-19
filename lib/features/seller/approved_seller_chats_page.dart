import 'package:flutter/material.dart';

import '../../data/local_marketplace_repository.dart';
import '../../theme/seller_ui_foundation.dart';

class ApprovedSellerChatsPage extends StatefulWidget {
  const ApprovedSellerChatsPage({
    required this.onOpenConversation,
    this.latestOffer,
    this.latestMessagePreview,
    super.key,
  });

  final VoidCallback onOpenConversation;
  final LocalOfferRecord? latestOffer;
  final String? latestMessagePreview;

  @override
  State<ApprovedSellerChatsPage> createState() =>
      _ApprovedSellerChatsPageState();
}

class _ApprovedSellerChatsPageState extends State<ApprovedSellerChatsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  List<_SellerChat> get _allChats {
    final offer = widget.latestOffer;
    final firstName = offer?.buyerName ?? 'Maya R.';
    final initials = firstName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return <_SellerChat>[
      _SellerChat(
        name: firstName,
        initials: initials.isEmpty ? 'MC' : initials,
        request: offer?.requestTitle ?? 'iPad Air offer selected',
        preview:
            widget.latestMessagePreview ??
            offer?.message ??
            'The buyer selected your offer. Confirm the meetup details.',
        time: '9:30 AM',
        avatarColor: const Color(0xFFF0EDFF),
        initialColor: SellerUiColors.primaryBright,
        unread: 2,
        online: true,
      ),
      ..._sellerChats.skip(1),
    ];
  }

  List<_SellerChat> get _visibleChats {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _allChats;
    return _allChats
        .where(
          (chat) => '${chat.name} ${chat.request} ${chat.preview}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SellerResponsivePage(
      builder: (context, metrics) {
        return ListView(
          key: const Key('sellerChatsList'),
          padding: EdgeInsets.fromLTRB(
            metrics.pageHorizontalPadding(14),
            metrics.spacing(14),
            metrics.pageHorizontalPadding(14),
            metrics.spacing(16),
          ),
          children: [
            Text(
              'Chats',
              textAlign: TextAlign.center,
              style: sellerText(metrics, 25, weight: FontWeight.w800),
            ),
            SizedBox(height: metrics.geometry(3)),
            Text(
              'Keep every accepted offer and meetup conversation together',
              textAlign: TextAlign.center,
              style: sellerText(metrics, 12, color: SellerUiColors.body),
            ),
            SizedBox(height: metrics.spacing(12)),
            TextField(
              key: const Key('sellerChatsSearch'),
              controller: _searchController,
              style: sellerInputText(metrics),
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search conversations',
                hintStyle: sellerInputPlaceholder(metrics),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: SellerUiColors.lavender,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(metrics.geometry(11)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: metrics.spacing(12)),
            if (_visibleChats.isEmpty)
              _SellerChatsEmptyState(
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              )
            else
              for (final chat in _visibleChats) ...[
                _SellerChatCard(chat: chat, onTap: widget.onOpenConversation),
                SizedBox(height: metrics.spacing(9)),
              ],
          ],
        );
      },
    );
  }
}

class _SellerChatsEmptyState extends StatelessWidget {
  const _SellerChatsEmptyState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      key: const Key('sellerChatsEmptyState'),
      padding: EdgeInsets.all(metrics.spacing(20)),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: metrics.artSize(34),
            color: SellerUiColors.primaryBright,
          ),
          SizedBox(height: metrics.spacing(7)),
          Text(
            'No matching conversations',
            style: sellerText(metrics, 15, weight: FontWeight.w800),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear search')),
        ],
      ),
    );
  }
}

class _SellerChatCard extends StatelessWidget {
  const _SellerChatCard({required this.chat, required this.onTap});
  final _SellerChat chat;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Material(
      color: SellerUiColors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(11)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.geometry(11)),
        child: Padding(
          padding: EdgeInsets.all(metrics.spacing(11)),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: metrics.artSize(25),
                    backgroundColor: chat.avatarColor,
                    child: Text(
                      chat.initials,
                      style: sellerText(
                        metrics,
                        18,
                        weight: FontWeight.w800,
                        color: chat.initialColor,
                      ),
                    ),
                  ),
                  if (chat.online)
                    Positioned(
                      right: -1,
                      bottom: 0,
                      child: Container(
                        width: metrics.geometry(11),
                        height: metrics.geometry(11),
                        decoration: BoxDecoration(
                          color: SellerUiColors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(width: metrics.spacing(9)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.name,
                            style: sellerText(
                              metrics,
                              15,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          chat.time,
                          style: sellerText(
                            metrics,
                            9,
                            color: SellerUiColors.muted,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      chat.request,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sellerText(
                        metrics,
                        10,
                        weight: FontWeight.w700,
                        color: SellerUiColors.primaryBright,
                      ),
                    ),
                    SizedBox(height: metrics.geometry(2)),
                    Text(
                      chat.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sellerText(
                        metrics,
                        11,
                        color: SellerUiColors.body,
                      ),
                    ),
                  ],
                ),
              ),
              if (chat.unread > 0) ...[
                SizedBox(width: metrics.geometry(7)),
                CircleAvatar(
                  radius: metrics.geometry(10),
                  backgroundColor: SellerUiColors.primaryBright,
                  child: Text(
                    '${chat.unread}',
                    style: sellerText(
                      metrics,
                      9,
                      weight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SellerChat {
  const _SellerChat({
    required this.name,
    required this.initials,
    required this.request,
    required this.preview,
    required this.time,
    required this.avatarColor,
    required this.initialColor,
    this.unread = 0,
    this.online = false,
  });
  final String name, initials, request, preview, time;
  final Color avatarColor, initialColor;
  final int unread;
  final bool online;
}

const _sellerChats = [
  _SellerChat(
    name: 'Maya R.',
    initials: 'MR',
    request: 'iPad Air offer selected',
    preview: 'The buyer selected your offer. Confirm the meetup details.',
    time: '9:30 AM',
    avatarColor: Color(0xFFF0EDFF),
    initialColor: SellerUiColors.primaryBright,
    unread: 2,
    online: true,
  ),
  _SellerChat(
    name: 'James M.',
    initials: 'JM',
    request: 'iPad Air (5th gen)',
    preview: 'Cross County Mall works for me. See you at 2:00 PM.',
    time: 'Yesterday',
    avatarColor: Color(0xFFE3F7E9),
    initialColor: SellerUiColors.green,
    online: true,
  ),
  _SellerChat(
    name: 'Alicia C.',
    initials: 'AC',
    request: 'iPad Pro 11-inch',
    preview: 'Could we move the appointment to 5:30 PM?',
    time: 'May 18',
    avatarColor: Color(0xFFFFF0DF),
    initialColor: SellerUiColors.amber,
  ),
];
