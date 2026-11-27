import 'package:flutter/material.dart';

import '../../data/local_marketplace_repository.dart';

class ChatPriceEditor extends StatefulWidget {
  const ChatPriceEditor({
    super.key,
    required this.seller,
    required this.title,
    required this.currentPrice,
    required this.currentMinor,
    required this.submit,
  });

  final bool seller;
  final String title;
  final String currentPrice;
  final int currentMinor;
  final Future<String?> Function(int minor, String key) submit;

  @override
  State<ChatPriceEditor> createState() => _ChatPriceEditorState();
}

class _ChatPriceEditorState extends State<ChatPriceEditor> {
  bool _saving = false;
  String _amount = '';
  String? _error;
  String? _operationKey;
  int? _lastSubmitted;

  Future<void> _send() async {
    if (_saving) return;
    final amount = _amount.trim();
    final parsed = RegExp(
      r'^([0-9]{1,9})(?:\.([0-9]{1,2}))?$',
    ).firstMatch(amount);
    final minor = parsed == null
        ? 0
        : int.parse(parsed[1]!) * 100 +
              int.parse((parsed[2] ?? '').padRight(2, '0'));
    if (minor <= 0 || minor == widget.currentMinor) {
      setState(
        () => _error = minor <= 0
            ? 'Enter a positive price with up to two decimal places.'
            : 'Enter a different price.',
      );
      return;
    }
    if (_lastSubmitted != minor) {
      _lastSubmitted = minor;
      _operationKey = LocalMarketplaceRepository.newStoreOperationKey(
        'chat-price',
      );
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.submit(minor, _operationKey!);
    } catch (_) {
      error = 'Could not confirm the request. Retry to check safely.';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(widget.seller ? 'Update price' : 'Request a price change'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text('Current price: ${widget.currentPrice}'),
            const SizedBox(height: 10),
            const Text(
              'The current price stays in place until the other person accepts.',
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('chat-proposed-price'),
              readOnly: _saving,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Proposed price',
                errorText: _error,
              ),
              onChanged: (value) => _amount = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _send,
            child: Text(_saving ? 'Sending…' : 'Send proposal'),
          ),
        ],
      ),
    );
  }
}
