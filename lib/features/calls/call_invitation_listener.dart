import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/phase2/calls/call_gateway.dart';

/// Foreground-only invitation listener.
///
/// It polls `call_command('incoming')`, which the server already limits to a
/// live ringing call, dedupes by call id and never rings the same call twice.
/// Missed calls are produced server-side (migration 153) so a device that is
/// not foreground still gets an inbox row.
///
/// Explicit limit: this is not terminated-app ringing. Reliable background or
/// terminated-app ringing needs FCM data delivery plus a native notification /
/// CallKit integration; a foreground polling loop cannot provide it. See
/// `call_notifications.dart` for the native contract and its Android/iOS
/// requirements.
class CallInvitationListener extends StatefulWidget {
  const CallInvitationListener({
    required this.child,
    required this.canOpen,
    required this.onIncoming,
    super.key,
  });
  final Widget child;
  final bool Function() canOpen;
  final Future<void> Function(String, String) onIncoming;
  @override
  State<CallInvitationListener> createState() => _CallInvitationListenerState();
}

class _CallInvitationListenerState extends State<CallInvitationListener>
    with WidgetsBindingObserver {
  Timer? timer;
  bool foreground = true, busy = false;
  String? shown;
  CallGateway? gateway;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      gateway = CallGateway(Supabase.instance.client);
      schedule();
    } catch (_) {}
  }

  void schedule([int seconds = 5]) {
    timer?.cancel();
    timer = Timer(Duration(seconds: seconds), poll);
  }

  Future<void> poll() async {
    if (!mounted) return;
    var delay = 5;
    try {
      if (!foreground || busy || !widget.canOpen()) return;
      busy = true;
      final data = await gateway!.command('incoming', {});
      if (!mounted || !foreground) return;
      final call = data['call'];
      if (call is Map && call['id'] != shown && widget.canOpen()) {
        shown = call['id'] as String;
        await widget.onIncoming(shown!, call['conversation_id'] as String);
      }
    } on CallGatewayException catch (failure) {
      // A disabled switch or a session change should not hammer the server.
      if (failure.code == 'authentication_required' ||
          failure.code == 'session_changed') {
        delay = 60;
      } else if (failure.code == 'calls_disabled') {
        delay = 30;
      } else {
        delay = 15;
      }
    } catch (_) {
      delay = 60;
    } finally {
      busy = false;
      if (mounted) schedule(delay);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed && !foreground) {
      foreground = true;
      schedule(0);
      return;
    }
    foreground = resumed;
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
