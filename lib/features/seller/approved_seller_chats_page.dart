import 'package:hocalist/theme/adaptive_palette.dart';
import '../../components/hocalist_motion.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/chat/chat_safety_coordinator.dart';
import '../../domain/phase2/common.dart';
import '../../domain/phase2/conversations.dart';
import '../../features/approved/offers_chat_pages.dart' show ChatThreadView;
import '../../theme/seller_ui_foundation.dart';

class ApprovedSellerChatsPage extends StatefulWidget {
  const ApprovedSellerChatsPage({
    required this.onOpenConversation,
    this.latestOffer,
    this.latestMessagePreview,
    this.realThreads,
    this.threadsLoading = false,
    this.threadsError,
    this.onRefreshThreads,
    this.onOpenThread,
    this.onSearchConversations,
    super.key,
  });

  final VoidCallback onOpenConversation;
  final LocalOfferRecord? latestOffer;
  final String? latestMessagePreview;

  /// Real participant inbox rows. Null keeps the approved prototype list.
  final List<ChatThreadView>? realThreads;
  final bool threadsLoading;
  final String? threadsError;
  final VoidCallback? onRefreshThreads;
  final ValueChanged<ChatThreadView>? onOpenThread;

  /// Server-side paged conversation search. Null keeps the loaded-list filter.
  final Future<PageSlice<ConversationSummary>> Function(String query)?
  onSearchConversations;

  bool get usesRealThreads => realThreads != null;

  @override
  State<ApprovedSellerChatsPage> createState() =>
      _ApprovedSellerChatsPageState();
}

class _ApprovedSellerChatsPageState extends State<ApprovedSellerChatsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;
  bool _serverSearching = false;
  String? _serverError;
  List<ConversationSummary> _serverResults = const [];
  String _serverQuery = '';

  bool get _usesServerSearch => widget.onSearchConversations != null;

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final search = widget.onSearchConversations;
    if (search == null) return;
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _serverSearching = false;
        _serverError = null;
        _serverResults = const [];
        _serverQuery = '';
      });
      return;
    }
    setState(() {
      _serverSearching = true;
      _serverError = null;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_runServerSearch(query));
    });
  }

  Future<void> _runServerSearch(String query) async {
    final search = widget.onSearchConversations;
    if (search == null || !mounted) return;
    try {
      final page = await search(query);
      if (!mounted || _query.trim() != query) return;
      setState(() {
        _serverResults = page.items;
        _serverQuery = query;
        _serverSearching = false;
      });
    } catch (error) {
      if (!mounted || _query.trim() != query) return;
      setState(() {
        _serverSearching = false;
        _serverError = error is ChatSafetyException
            ? error.message
            : 'Search is unavailable right now. Try again.';
      });
    }
  }

  List<_SellerChat> get _allChats {
    final realThreads = widget.realThreads;
    if (realThreads != null) {
      return [
        for (final thread in realThreads)
          _SellerChat(
            name: thread.counterpartName,
            initials: thread.initials,
            request: '',
            preview: thread.preview,
            time: thread.timeLabel,
            avatarColor: const Color(0xFFF0EDFF),
            initialColor: SellerUiColors.primaryBright,
            unread: thread.unreadCount,
            online: thread.unreadCount > 0,
          ),
      ];
    }
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
    if (_usesServerSearch && query.length >= 2 && _serverQuery == query) {
      return [
        for (final summary in _serverResults)
          _SellerChat(
            name: summary.counterpartDisplayName,
            initials: summary.counterpartDisplayName
                .split(RegExp(r'\s+'))
                .where((part) => part.isNotEmpty)
                .take(2)
                .map((part) => part[0].toUpperCase())
                .join(),
            request: '',
            preview: summary.latestMessage?.text ?? '',
            time: '',
            avatarColor: const Color(0xFFF0EDFF),
            initialColor: SellerUiColors.primaryBright,
            unread: summary.unreadCount,
          ),
      ];
    }
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
    _searchDebounce?.cancel();
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
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search conversations',
                hintStyle: sellerInputPlaceholder(metrics),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: HocalistPalette.surface(
                  context,
                  SellerUiColors.lavender,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(metrics.geometry(11)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: metrics.spacing(12)),
            if (widget.usesRealThreads) ...[
              if (widget.threadsLoading)
                _SellerChatsNotice(
                  key: const Key('sellerChatsLoading'),
                  message: 'Loading conversations…',
                )
              else if (widget.threadsError != null)
                _SellerChatsNotice(
                  key: const Key('sellerChatsError'),
                  message: widget.threadsError!,
                  onRetry: widget.onRefreshThreads,
                ),
            ],
            if (_usesServerSearch && _query.trim().length >= 2) ...[
              if (_serverSearching)
                _SellerChatsNotice(
                  key: const Key('sellerChatsSearchLoading'),
                  message: 'Searching conversations…',
                )
              else if (_serverError != null)
                _SellerChatsNotice(
                  key: const Key('sellerChatsSearchError'),
                  message: _serverError!,
                  onRetry: () => unawaited(_runServerSearch(_query.trim())),
                ),
            ],
            if (_visibleChats.isEmpty)
              widget.usesRealThreads || _usesServerSearch
                  ? (widget.threadsLoading ||
                            widget.threadsError != null ||
                            _serverSearching ||
                            _serverError != null
                        ? const SizedBox.shrink()
                        : _SellerChatsEmptyCard(
                            key: const Key('sellerChatsEmpty'),
                            filtered: _query.trim().isNotEmpty,
                            onClear: _query.trim().isEmpty
                                ? null
                                : () {
                                    _searchController.clear();
                                    _onQueryChanged('');
                                  },
                          ))
                  : _SellerChatsEmptyState(
                      onClear: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
            else
              for (var index = 0; index < _visibleChats.length; index++) ...[
                _SellerChatCard(
                  chat: _visibleChats[index],
                  onTap: () {
                    final open = widget.onOpenThread;
                    final threads = widget.realThreads;
                    if (open != null && threads != null) {
                      open(threads[index]);
                    } else {
                      widget.onOpenConversation();
                    }
                  },
                ),
                SizedBox(height: metrics.spacing(9)),
              ],
          ],
        );
      },
    );
  }
}

/// Designed zero-conversation card for the Seller inbox. `filtered` keeps the
/// no-match state honest inside an existing inbox.
class _SellerChatsEmptyCard extends StatelessWidget {
  const _SellerChatsEmptyCard({this.filtered = false, this.onClear, super.key});

  final bool filtered;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      padding: EdgeInsets.all(metrics.spacing(16)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.white),
        border: Border.all(
          color: HocalistPalette.border(context, SellerUiColors.line),
        ),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Column(
        children: [
          Container(
            width: metrics.artSize(48),
            height: metrics.artSize(48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, SellerUiColors.lavender),
              shape: BoxShape.circle,
            ),
            child: Icon(
              filtered ? Icons.search_off_rounded : Icons.forum_outlined,
              size: metrics.artSize(24),
              color: HocalistPalette.text(
                context,
                SellerUiColors.primaryBright,
              ),
            ),
          ),
          SizedBox(height: metrics.spacing(10)),
          Text(
            filtered ? 'No matching conversations' : 'No conversations yet',
            textAlign: TextAlign.center,
            style: sellerText(metrics, 13.5, weight: FontWeight.w800),
          ),
          SizedBox(height: metrics.spacing(4)),
          Text(
            filtered
                ? 'Try another name or clear the search. Chats appear after a buyer selects your offer.'
                : 'Buyer chats appear here after a buyer selects your offer.',
            textAlign: TextAlign.center,
            style: sellerText(
              metrics,
              11,
              color: SellerUiColors.body,
              height: 1.35,
            ),
          ),
          if (onClear != null)
            TextButton(
              key: const Key('sellerChatsClearSearch'),
              onPressed: onClear,
              child: const Text('Clear search'),
            ),
        ],
      ),
    );
  }
}

class _SellerChatsNotice extends StatelessWidget {
  const _SellerChatsNotice({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      padding: EdgeInsets.all(metrics.spacing(12)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(11)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: sellerText(
              metrics,
              11.5,
              weight: FontWeight.w700,
              color: SellerUiColors.body,
            ),
          ),
          if (onRetry != null) ...[
            SizedBox(height: metrics.spacing(4)),
            TextButton(
              key: const Key('sellerChatsRetry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: Size(0, metrics.geometry(34)),
                padding: EdgeInsets.zero,
                foregroundColor: HocalistPalette.text(
                  context,
                  SellerUiColors.primaryBright,
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
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
        color: HocalistPalette.surface(context, SellerUiColors.white),
        border: Border.all(
          color: HocalistPalette.border(context, SellerUiColors.line),
        ),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: metrics.artSize(34),
            color: HocalistPalette.text(context, SellerUiColors.primaryBright),
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
    return HocalistEntrance(
      child: HocalistPressFeedback(
        child: Material(
          color: HocalistPalette.surface(context, SellerUiColors.white),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: HocalistPalette.border(context, SellerUiColors.line),
            ),
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
                        backgroundColor: HocalistPalette.surface(
                          context,
                          chat.avatarColor,
                        ),
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
                              color: HocalistPalette.surface(
                                context,
                                SellerUiColors.green,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: HocalistPalette.border(
                                  context,
                                  Colors.white,
                                ),
                                width: 2,
                              ),
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
                      backgroundColor: HocalistPalette.surface(
                        context,
                        SellerUiColors.primaryBright,
                      ),
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
