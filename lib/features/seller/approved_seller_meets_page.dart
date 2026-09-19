import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/control_foundation.dart';
import '../../theme/seller_ui_foundation.dart';
import 'approved_seller_reschedule_dialog.dart';

class ApprovedSellerMeetsPage extends StatefulWidget {
  const ApprovedSellerMeetsPage({
    required this.onOpenChat,
    this.dealCompleted = false,
    this.onPinVerified,
    super.key,
  });

  final VoidCallback onOpenChat;
  final bool dealCompleted;
  final VoidCallback? onPinVerified;

  @override
  State<ApprovedSellerMeetsPage> createState() =>
      _ApprovedSellerMeetsPageState();
}

class _ApprovedSellerMeetsPageState extends State<ApprovedSellerMeetsPage> {
  final Set<String> _expandedAppointments = <String>{};
  final Set<String> _verifiedAppointments = <String>{};
  _MeetFilter _selectedFilter = _MeetFilter.upcoming;

  @override
  void initState() {
    super.initState();
    if (widget.dealCompleted) {
      _verifiedAppointments.add('JM');
    }
  }

  @override
  void didUpdateWidget(covariant ApprovedSellerMeetsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.dealCompleted && widget.dealCompleted) {
      _verifiedAppointments.add('JM');
    }
  }

  void _toggleAppointment(_Appointment appointment) {
    setState(() {
      if (!_expandedAppointments.add(appointment.initials)) {
        _expandedAppointments.remove(appointment.initials);
      }
    });
  }

  void _selectFilter(_MeetFilter filter) {
    if (_selectedFilter == filter) return;
    setState(() {
      _selectedFilter = filter;
      _expandedAppointments.clear();
    });
  }

  Future<void> _openMeetFilters() async {
    var draft = _selectedFilter;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SellerModalSheet(
          icon: Icons.filter_alt_outlined,
          title: 'Filter appointments',
          subtitle: 'Choose which meeting status you want to review.',
          onClose: () => Navigator.of(sheetContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _MeetFilter.values)
                    HocalistFilterChip(
                      role: HocalistControlRole.seller,
                      label: switch (option) {
                        _MeetFilter.upcoming => 'Upcoming',
                        _MeetFilter.today => 'Today',
                        _MeetFilter.completed => 'Completed',
                        _MeetFilter.canceled => 'Canceled',
                      },
                      selected: draft == option,
                      onSelected: (_) => setSheetState(() => draft = option),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SellerPrimaryButton(
                label: 'Show appointments',
                onPressed: () {
                  _selectFilter(draft);
                  Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isCompleted(_Appointment appointment) =>
      _verifiedAppointments.contains(appointment.initials);

  bool _matchesFilter(_Appointment appointment) {
    final completed = _isCompleted(appointment);
    return switch (_selectedFilter) {
      _MeetFilter.upcoming => !completed && !appointment.canceled,
      _MeetFilter.today => appointment.isToday && !appointment.canceled,
      _MeetFilter.completed => completed,
      _MeetFilter.canceled => appointment.canceled,
    };
  }

  Future<void> _openReschedule(_Appointment appointment) async {
    final submitted = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB30B1231),
      builder: (context) => ApprovedSellerRescheduleDialog(
        customerName: appointment.name,
        currentDate: appointment.date,
        currentTime: appointment.time,
      ),
    );
    if (!mounted || submitted != true) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: Key('sellerRescheduleSubmittedNotice'),
          content: Text('Reschedule request sent. You are still in Meets.'),
        ),
      );
  }

  Future<void> _openPinEntry(_Appointment appointment) async {
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => _SellerPinSheet(appointment: appointment),
    );
    if (!mounted || verified != true) return;
    setState(() {
      _verifiedAppointments.add(appointment.initials);
      _selectedFilter = _MeetFilter.completed;
      _expandedAppointments.clear();
    });
    widget.onPinVerified?.call();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: Key('sellerPinVerifiedNotice'),
          content: Text('PIN verified. The meeting is now completed.'),
        ),
      );
  }

  Future<void> _showConnectionPreview({
    required IconData icon,
    required String title,
    required String subtitle,
    required String message,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x990B1231),
      builder: (sheetContext) => SellerModalSheet(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onClose: () => Navigator.pop(sheetContext),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SellerUiColors.lavender,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(message),
            ),
            const SizedBox(height: 12),
            SellerPrimaryButton(
              label: 'Got it',
              onPressed: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMapPreview(_Appointment appointment) {
    return _showConnectionPreview(
      icon: Icons.map_outlined,
      title: 'Meeting location',
      subtitle: '${appointment.location}, ${appointment.city}',
      message:
          'The meetup location is saved with this appointment. Turn-by-turn directions will open here when the native map provider is connected.',
    );
  }

  Future<void> _openCallPreview(_Appointment appointment) {
    return _showConnectionPreview(
      icon: Icons.call_outlined,
      title: 'Call ${appointment.name}',
      subtitle: 'Calling stays protected until contact access is connected.',
      message:
          'The call action is ready for the native phone handoff. For now, use Message to contact the buyer without leaving Hocalist.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleAppointments = _appointments.where(_matchesFilter).toList();
    final upcomingCount = _appointments
        .where(
          (appointment) => !_isCompleted(appointment) && !appointment.canceled,
        )
        .length;
    final todayCount = _appointments
        .where((appointment) => appointment.isToday && !appointment.canceled)
        .length;
    final completedCount = _appointments.where(_isCompleted).length;
    final canceledCount = _appointments
        .where((appointment) => appointment.canceled)
        .length;
    return SellerResponsivePage(
      builder: (context, metrics) {
        return CustomScrollView(
          key: const Key('sellerMeetsScroll'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                metrics.pageHorizontalPadding(14),
                metrics.spacing(12),
                metrics.pageHorizontalPadding(14),
                metrics.spacing(14),
              ),
              sliver: SliverList.list(
                children: [
                  _MeetsHeader(onFilter: _openMeetFilters),
                  SizedBox(height: metrics.spacing(12)),
                  _MeetStatusTabs(
                    selected: _selectedFilter,
                    upcomingCount: upcomingCount,
                    todayCount: todayCount,
                    completedCount: completedCount,
                    canceledCount: canceledCount,
                    onSelected: _selectFilter,
                  ),
                  SizedBox(height: metrics.spacing(14)),
                  if (visibleAppointments.isEmpty)
                    _EmptyAppointments(filter: _selectedFilter)
                  else
                    for (final appointment in visibleAppointments) ...[
                      _AppointmentCard(
                        appointment: appointment,
                        expanded: _expandedAppointments.contains(
                          appointment.initials,
                        ),
                        onToggle: () => _toggleAppointment(appointment),
                        onMessage: widget.onOpenChat,
                        onOpenMap: () => _openMapPreview(appointment),
                        onCall: () => _openCallPreview(appointment),
                        onReschedule: () => _openReschedule(appointment),
                        completed: _isCompleted(appointment),
                        onEnterPin: () => _openPinEntry(appointment),
                      ),
                      SizedBox(height: metrics.spacing(12)),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MeetsHeader extends StatelessWidget {
  const _MeetsHeader({required this.onFilter});

  final VoidCallback onFilter;
  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 34),
        Expanded(
          child: Column(
            children: [
              Text(
                'Meets',
                style: sellerText(metrics, 25, weight: FontWeight.w800),
              ),
              SizedBox(height: metrics.geometry(3)),
              Text(
                'Customers you agreed to meet',
                textAlign: TextAlign.center,
                style: sellerText(metrics, 13, color: SellerUiColors.body),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Filter appointments',
          onPressed: onFilter,
          icon: const Icon(Icons.filter_alt_outlined),
          color: SellerUiColors.primaryBright,
        ),
      ],
    );
  }
}

class _MeetStatusTabs extends StatelessWidget {
  const _MeetStatusTabs({
    required this.selected,
    required this.upcomingCount,
    required this.todayCount,
    required this.completedCount,
    required this.canceledCount,
    required this.onSelected,
  });

  final _MeetFilter selected;
  final int upcomingCount;
  final int todayCount;
  final int completedCount;
  final int canceledCount;
  final ValueChanged<_MeetFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 340;
        return Container(
          padding: EdgeInsets.all(metrics.geometry(2)),
          decoration: BoxDecoration(
            border: Border.all(color: SellerUiColors.line),
            borderRadius: BorderRadius.circular(metrics.geometry(11)),
          ),
          child: Row(
            children: [
              _StatusTab(
                key: const Key('sellerMeetFilterUpcoming'),
                label: 'Upcoming',
                count: '$upcomingCount',
                selected: selected == _MeetFilter.upcoming,
                compact: compact,
                onTap: () => onSelected(_MeetFilter.upcoming),
              ),
              _StatusTab(
                key: const Key('sellerMeetFilterToday'),
                label: 'Today',
                count: '$todayCount',
                selected: selected == _MeetFilter.today,
                compact: compact,
                onTap: () => onSelected(_MeetFilter.today),
              ),
              _StatusTab(
                key: const Key('sellerMeetFilterCompleted'),
                label: 'Completed',
                count: '$completedCount',
                selected: selected == _MeetFilter.completed,
                compact: compact,
                onTap: () => onSelected(_MeetFilter.completed),
              ),
              _StatusTab(
                key: const Key('sellerMeetFilterCanceled'),
                label: 'Canceled',
                count: '$canceledCount',
                selected: selected == _MeetFilter.canceled,
                compact: compact,
                onTap: () => onSelected(_MeetFilter.canceled),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.compact,
    required this.onTap,
    super.key,
  });
  final String label;
  final String count;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final accessibilityFlex = switch (label) {
      'Upcoming' => 12,
      'Today' => 8,
      'Completed' => 11,
      'Canceled' => 10,
      _ => 10,
    };
    return Expanded(
      // The default approved row stays evenly divided. Only the narrow
      // accessibility layout assigns space by label length, keeping all four
      // actions on the original single row without truncating their names.
      flex: compact && metrics.accessibilityReflow ? accessibilityFlex : 1,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label appointments, $count',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(metrics.geometry(9)),
          child: Container(
            constraints: BoxConstraints(
              minHeight: compact ? 44 : metrics.geometry(48),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 0 : metrics.geometry(2),
            ),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [
                        SellerUiColors.primary,
                        SellerUiColors.primaryBright,
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(metrics.geometry(9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _StatusTabLabel(
                    label: label,
                    selected: selected,
                    // Keep the approved calendar treatment at normal text
                    // sizes. On a narrow phone with accessibility reflow the
                    // label and count need the full tab width so the action
                    // name is never clipped.
                    showIcon:
                        selected && !(compact && metrics.accessibilityReflow),
                    compact: compact,
                  ),
                ),
                SizedBox(width: compact ? 1.5 : metrics.geometry(4)),
                _StatusCount(
                  count: count,
                  selected: selected,
                  compact: compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusTabLabel extends StatelessWidget {
  const _StatusTabLabel({
    required this.label,
    required this.selected,
    required this.showIcon,
    required this.compact,
  });

  final String label;
  final bool selected;
  final bool showIcon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showIcon) ...[
          Icon(
            Icons.calendar_month_outlined,
            size: metrics.artSize(compact ? 12 : 14),
            color: Colors.white,
          ),
          SizedBox(width: compact ? 1.5 : metrics.geometry(3)),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.center,
            style: sellerText(
              metrics,
              compact ? 9.5 : 9,
              weight: FontWeight.w700,
              color: selected ? Colors.white : SellerUiColors.body,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCount extends StatelessWidget {
  const _StatusCount({
    required this.count,
    required this.selected,
    required this.compact,
  });

  final String count;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return CircleAvatar(
      radius: metrics.geometry(compact ? 8 : 9),
      backgroundColor: selected ? Colors.white : SellerUiColors.lavender,
      child: Text(
        count,
        style: sellerText(
          metrics,
          compact ? 8.5 : 8,
          weight: FontWeight.w800,
          color: SellerUiColors.primaryBright,
        ),
      ),
    );
  }
}

class _EmptyAppointments extends StatelessWidget {
  const _EmptyAppointments({required this.filter});

  final _MeetFilter filter;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final (title, message) = switch (filter) {
      _MeetFilter.upcoming => (
        'No upcoming appointments',
        'Appointments you agree to will appear here.',
      ),
      _MeetFilter.today => (
        'No appointments today',
        'Your meetings scheduled for today will appear here.',
      ),
      _MeetFilter.completed => (
        'No completed appointments',
        'PIN-verified meetings will appear here.',
      ),
      _MeetFilter.canceled => (
        'No canceled appointments',
        'Canceled meetings will remain available here for reference.',
      ),
    };
    return Container(
      key: Key('sellerMeetEmpty${filter.name}'),
      padding: EdgeInsets.symmetric(
        horizontal: metrics.spacing(20),
        vertical: metrics.spacing(30),
      ),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Column(
        children: [
          Container(
            width: metrics.artSize(52),
            height: metrics.artSize(52),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: SellerUiColors.lavender,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_available_outlined,
              size: metrics.artSize(26),
              color: SellerUiColors.primaryBright,
            ),
          ),
          SizedBox(height: metrics.spacing(10)),
          Text(title, style: sellerText(metrics, 16, weight: FontWeight.w800)),
          SizedBox(height: metrics.geometry(4)),
          Text(
            message,
            textAlign: TextAlign.center,
            style: sellerText(metrics, 12, color: SellerUiColors.body),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.expanded,
    required this.completed,
    required this.onToggle,
    required this.onEnterPin,
    required this.onMessage,
    required this.onOpenMap,
    required this.onCall,
    required this.onReschedule,
  });
  final _Appointment appointment;
  final bool expanded;
  final bool completed;
  final VoidCallback onToggle;
  final VoidCallback onEnterPin;
  final VoidCallback onMessage;
  final VoidCallback onOpenMap;
  final VoidCallback onCall;
  final VoidCallback onReschedule;
  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Container(
      padding: EdgeInsets.all(metrics.spacing(11)),
      decoration: BoxDecoration(
        color: SellerUiColors.white,
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0B1231),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: metrics.artSize(26),
                    backgroundColor: appointment.avatarColor,
                    child: Text(
                      appointment.initials,
                      style: sellerText(
                        metrics,
                        20,
                        weight: FontWeight.w800,
                        color: appointment.initialColor,
                      ),
                    ),
                  ),
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
                    Text(
                      appointment.name,
                      style: sellerText(metrics, 18, weight: FontWeight.w800),
                    ),
                    Text(
                      'Buyer appointment',
                      style: sellerText(
                        metrics,
                        12,
                        weight: FontWeight.w700,
                        color: SellerUiColors.body,
                      ),
                    ),
                    Text(
                      '${appointment.city}  •  ${appointment.distance}',
                      style: sellerText(
                        metrics,
                        11,
                        color: SellerUiColors.body,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.geometry(7),
                      vertical: metrics.geometry(5),
                    ),
                    decoration: BoxDecoration(
                      color: SellerUiColors.greenSurface,
                      borderRadius: BorderRadius.circular(metrics.geometry(7)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (completed) ...[
                          Icon(
                            Icons.check_circle_outline,
                            size: metrics.artSize(13),
                            color: SellerUiColors.green,
                          ),
                          SizedBox(width: metrics.geometry(3)),
                        ],
                        Text(
                          completed ? 'Completed' : appointment.date,
                          style: sellerText(
                            metrics,
                            10,
                            weight: FontWeight.w800,
                            color: SellerUiColors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: metrics.geometry(3)),
                  Text(
                    completed ? 'PIN verified' : appointment.time,
                    style: sellerText(
                      metrics,
                      11,
                      weight: FontWeight.w800,
                      color: completed
                          ? SellerUiColors.green
                          : SellerUiColors.primaryBright,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24, color: SellerUiColors.line),
          Semantics(
            container: true,
            button: true,
            onTap: onToggle,
            label: expanded
                ? 'Hide deal and meeting details for ${appointment.name}'
                : 'View deal and meeting details for ${appointment.name}',
            excludeSemantics: true,
            child: InkWell(
              key: Key('sellerMeetProduct${appointment.initials}'),
              onTap: onToggle,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(metrics.geometry(8)),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: metrics.geometry(5)),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: metrics.artSize(18),
                      color: SellerUiColors.primaryBright,
                    ),
                    SizedBox(width: metrics.geometry(7)),
                    Expanded(
                      child: Text(
                        expanded
                            ? 'Hide deal & meeting details'
                            : 'View deal & meeting details',
                        style: sellerText(
                          metrics,
                          12,
                          weight: FontWeight.w800,
                          color: SellerUiColors.primaryBright,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 180),
                      turns: expanded ? 0.5 : 0,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: metrics.artSize(22),
                        color: SellerUiColors.primaryBright,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 24, color: SellerUiColors.line),
            Row(
              children: [
                Container(
                  width: metrics.artSize(52),
                  height: metrics.artSize(52),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SellerUiColors.lavender,
                    borderRadius: BorderRadius.circular(metrics.geometry(8)),
                  ),
                  child: Icon(
                    Icons.tablet_mac_outlined,
                    size: metrics.artSize(28),
                    color: SellerUiColors.primaryBright,
                  ),
                ),
                SizedBox(width: metrics.spacing(9)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deal details',
                        style: sellerText(
                          metrics,
                          9,
                          color: SellerUiColors.body,
                        ),
                      ),
                      Text(
                        appointment.product,
                        style: sellerText(metrics, 14, weight: FontWeight.w800),
                      ),
                      Text(
                        appointment.details,
                        style: sellerText(
                          metrics,
                          10,
                          color: SellerUiColors.body,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: metrics.geometry(8)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agreed Price',
                      style: sellerText(metrics, 9, color: SellerUiColors.body),
                    ),
                    Text(
                      appointment.price,
                      style: sellerText(
                        metrics,
                        17,
                        weight: FontWeight.w800,
                        color: SellerUiColors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24, color: SellerUiColors.line),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: SellerUiColors.primaryBright,
                ),
                SizedBox(width: metrics.geometry(7)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meeting location',
                        style: sellerText(
                          metrics,
                          9,
                          color: SellerUiColors.body,
                        ),
                      ),
                      Text(
                        appointment.location,
                        style: sellerText(metrics, 13, weight: FontWeight.w800),
                      ),
                      Text(
                        appointment.city,
                        style: sellerText(
                          metrics,
                          10,
                          color: SellerUiColors.body,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('sellerMeetMap-${appointment.initials}'),
                  tooltip: 'Open map',
                  onPressed: onOpenMap,
                  icon: const Icon(Icons.map_outlined),
                  color: SellerUiColors.primaryBright,
                ),
              ],
            ),
            SizedBox(height: metrics.spacing(8)),
            Row(
              children: [
                Expanded(
                  child: _MeetAction(
                    key: ValueKey('sellerMeetCall-${appointment.initials}'),
                    icon: completed
                        ? Icons.check_circle_outline
                        : Icons.lock_outline,
                    label: completed ? 'PIN verified' : 'Enter PIN',
                    color: completed
                        ? SellerUiColors.green
                        : SellerUiColors.primaryBright,
                    onTap: completed ? null : onEnterPin,
                  ),
                ),
                SizedBox(width: metrics.geometry(6)),
                Expanded(
                  child: _MeetAction(
                    icon: Icons.call_outlined,
                    label: 'Call',
                    color: SellerUiColors.green,
                    onTap: onCall,
                  ),
                ),
                SizedBox(width: metrics.geometry(6)),
                Expanded(
                  child: _MeetAction(
                    icon: Icons.chat_bubble_outline,
                    label: 'Message',
                    color: SellerUiColors.primaryBright,
                    onTap: onMessage,
                  ),
                ),
                SizedBox(width: metrics.geometry(6)),
                Expanded(
                  child: _MeetAction(
                    icon: Icons.history,
                    label: 'Reschedule',
                    color: SellerUiColors.amber,
                    onTap: onReschedule,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MeetAction extends StatelessWidget {
  const _MeetAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, metrics.geometry(62)),
        padding: EdgeInsets.symmetric(horizontal: metrics.geometry(2)),
        side: const BorderSide(color: SellerUiColors.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.geometry(8)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: metrics.artSize(20), color: color),
          SizedBox(height: metrics.geometry(3)),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sellerText(
              metrics,
              9,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerPinSheet extends StatefulWidget {
  const _SellerPinSheet({required this.appointment});

  final _Appointment appointment;

  @override
  State<_SellerPinSheet> createState() => _SellerPinSheetState();
}

class _SellerPinSheetState extends State<_SellerPinSheet> {
  static const _prototypePin = '15230';
  final _controller = TextEditingController();
  String? _error;
  bool _verified = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _verifyPin() {
    FocusScope.of(context).unfocus();
    if (_controller.text == _prototypePin) {
      setState(() {
        _error = null;
        _verified = true;
      });
      return;
    }
    setState(() {
      _error = 'That PIN does not match. Check the 5 digits with the buyer.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sheetWidth = media.size.width.clamp(0.0, 620.0);
    final metrics = ApprovedReplicaMetrics.resolve(
      availableWidth: sheetWidth,
      textScaler: media.textScaler,
    );
    return ApprovedReplicaScope(
      metrics: metrics,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            key: const Key('sellerPinSheet'),
            color: SellerUiColors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: media.size.height * .92,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  metrics.spacing(18),
                  metrics.spacing(10),
                  metrics.spacing(18),
                  metrics.spacing(18),
                ),
                child: _verified
                    ? _SellerPinVerifiedContent(
                        metrics: metrics,
                        appointment: widget.appointment,
                        onDone: () => Navigator.of(context).pop(true),
                      )
                    : _SellerPinEntryContent(
                        metrics: metrics,
                        appointment: widget.appointment,
                        controller: _controller,
                        error: _error,
                        onChanged: (_) {
                          if (_error != null) {
                            setState(() => _error = null);
                          } else {
                            setState(() {});
                          }
                        },
                        onVerify: _controller.text.length == 5
                            ? _verifyPin
                            : null,
                        onCancel: () => Navigator.of(context).pop(false),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SellerPinEntryContent extends StatelessWidget {
  const _SellerPinEntryContent({
    required this.metrics,
    required this.appointment,
    required this.controller,
    required this.error,
    required this.onChanged,
    required this.onVerify,
    required this.onCancel,
  });

  final ApprovedReplicaMetrics metrics;
  final _Appointment appointment;
  final TextEditingController controller;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback? onVerify;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SellerSheetHandle(),
        SizedBox(height: metrics.spacing(10)),
        Row(
          children: [
            Container(
              width: metrics.artSize(46),
              height: metrics.artSize(46),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SellerUiColors.lavender,
                borderRadius: BorderRadius.circular(metrics.geometry(13)),
              ),
              child: Icon(
                Icons.lock_outline,
                color: SellerUiColors.primaryBright,
                size: metrics.artSize(25),
              ),
            ),
            const Spacer(),
            IconButton(
              key: const Key('sellerPinClose'),
              tooltip: 'Close PIN entry',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
              color: SellerUiColors.body,
            ),
          ],
        ),
        SizedBox(height: metrics.spacing(8)),
        Text(
          'Enter buyer PIN',
          style: sellerText(metrics, 23, weight: FontWeight.w800),
        ),
        SizedBox(height: metrics.geometry(4)),
        Text(
          'Use the PIN shown on the buyer’s After the meetup screen to complete this meeting.',
          style: sellerText(
            metrics,
            12,
            color: SellerUiColors.body,
            height: 1.4,
          ),
        ),
        SizedBox(height: metrics.spacing(14)),
        _SellerPinMeetingSummary(metrics: metrics, appointment: appointment),
        SizedBox(height: metrics.spacing(14)),
        Text(
          'Buyer PIN',
          style: sellerText(metrics, 14, weight: FontWeight.w800),
        ),
        SizedBox(height: metrics.geometry(3)),
        Text(
          'Enter the 5-digit PIN the buyer shows you.',
          style: sellerText(metrics, 11, color: SellerUiColors.muted),
        ),
        SizedBox(height: metrics.spacing(8)),
        TextField(
          key: const Key('sellerBuyerPinField'),
          controller: controller,
          onChanged: onChanged,
          onSubmitted: (_) => onVerify?.call(),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          style: sellerText(
            metrics,
            22,
            weight: FontWeight.w800,
            letterSpacing: metrics.geometry(10),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          decoration: InputDecoration(
            hintText: '•••••',
            hintStyle: sellerText(
              metrics,
              22,
              color: SellerUiColors.muted,
              letterSpacing: metrics.geometry(10),
            ),
            counterText: '',
            filled: true,
            fillColor: SellerUiColors.white,
            contentPadding: EdgeInsets.symmetric(
              horizontal: metrics.spacing(14),
              vertical: metrics.spacing(14),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(metrics.geometry(13)),
              borderSide: BorderSide(
                color: error == null
                    ? SellerUiColors.lavenderBorder
                    : SellerUiColors.red,
                width: metrics.geometry(1.25),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(metrics.geometry(13)),
              borderSide: BorderSide(
                color: error == null
                    ? SellerUiColors.primaryBright
                    : SellerUiColors.red,
                width: metrics.geometry(1.6),
              ),
            ),
          ),
        ),
        if (error != null) ...[
          SizedBox(height: metrics.spacing(7)),
          Container(
            key: const Key('sellerPinError'),
            padding: EdgeInsets.all(metrics.spacing(10)),
            decoration: BoxDecoration(
              color: SellerUiColors.redSurface,
              borderRadius: BorderRadius.circular(metrics.geometry(10)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: metrics.artSize(19),
                  color: SellerUiColors.red,
                ),
                SizedBox(width: metrics.geometry(7)),
                Expanded(
                  child: Text(
                    error!,
                    style: sellerText(
                      metrics,
                      11,
                      weight: FontWeight.w700,
                      color: SellerUiColors.red,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: metrics.spacing(10)),
        Container(
          padding: EdgeInsets.all(metrics.spacing(10)),
          decoration: BoxDecoration(
            color: SellerUiColors.amberSurface,
            borderRadius: BorderRadius.circular(metrics.geometry(10)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: metrics.artSize(20),
                color: SellerUiColors.amber,
              ),
              SizedBox(width: metrics.geometry(7)),
              Expanded(
                child: Text(
                  'Only enter the PIN after the buyer has inspected the item and paid you offline.',
                  style: sellerText(
                    metrics,
                    11,
                    weight: FontWeight.w700,
                    color: SellerUiColors.body,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.spacing(14)),
        SellerPrimaryButton(
          key: const Key('sellerVerifyBuyerPin'),
          label: 'Verify PIN',
          leading: Icon(
            Icons.verified_user_outlined,
            size: metrics.artSize(18),
            color: SellerUiColors.white,
          ),
          onPressed: onVerify,
        ),
        SizedBox(height: metrics.spacing(8)),
        OutlinedButton(
          key: const Key('sellerCancelPinEntry'),
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: SellerUiColors.primaryBright,
            minimumSize: Size(0, metrics.geometry(44)),
            side: const BorderSide(color: SellerUiColors.lavenderBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(metrics.geometry(13)),
            ),
            textStyle: sellerText(metrics, 14, weight: FontWeight.w700),
          ),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _SellerPinVerifiedContent extends StatelessWidget {
  const _SellerPinVerifiedContent({
    required this.metrics,
    required this.appointment,
    required this.onDone,
  });

  final ApprovedReplicaMetrics metrics;
  final _Appointment appointment;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SellerSheetHandle(),
        SizedBox(height: metrics.spacing(18)),
        Center(
          child: Container(
            width: metrics.artSize(64),
            height: metrics.artSize(64),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: SellerUiColors.greenSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline,
              color: SellerUiColors.green,
              size: metrics.artSize(34),
            ),
          ),
        ),
        SizedBox(height: metrics.spacing(12)),
        Text(
          'PIN verified',
          textAlign: TextAlign.center,
          style: sellerText(metrics, 23, weight: FontWeight.w800),
        ),
        SizedBox(height: metrics.geometry(5)),
        Text(
          'The meeting with ${appointment.name} is complete.',
          textAlign: TextAlign.center,
          style: sellerText(metrics, 12, color: SellerUiColors.body),
        ),
        SizedBox(height: metrics.spacing(14)),
        Container(
          key: const Key('sellerPinVerifiedState'),
          padding: EdgeInsets.all(metrics.spacing(13)),
          decoration: BoxDecoration(
            color: SellerUiColors.greenSurface,
            borderRadius: BorderRadius.circular(metrics.geometry(12)),
            border: Border.all(color: const Color(0xFFCBEBD2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                color: SellerUiColors.green,
                size: metrics.artSize(24),
              ),
              SizedBox(width: metrics.geometry(9)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Buyer reward recorded',
                      style: sellerText(
                        metrics,
                        13,
                        weight: FontWeight.w800,
                        color: SellerUiColors.green,
                      ),
                    ),
                    SizedBox(height: metrics.geometry(2)),
                    Text(
                      'The buyer’s \$1.40 reward is recorded on this device. Online verification will be connected later.',
                      style: sellerText(
                        metrics,
                        11,
                        color: SellerUiColors.body,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.spacing(14)),
        SellerPrimaryButton(
          key: const Key('sellerPinDone'),
          label: 'Done',
          leading: Icon(
            Icons.check_rounded,
            size: metrics.artSize(18),
            color: SellerUiColors.white,
          ),
          onPressed: onDone,
        ),
      ],
    );
  }
}

class _SellerPinMeetingSummary extends StatelessWidget {
  const _SellerPinMeetingSummary({
    required this.metrics,
    required this.appointment,
  });

  final ApprovedReplicaMetrics metrics;
  final _Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(metrics.spacing(11)),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFF),
        border: Border.all(color: SellerUiColors.line),
        borderRadius: BorderRadius.circular(metrics.geometry(12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: metrics.artSize(22),
            backgroundColor: appointment.avatarColor,
            child: Text(
              appointment.initials,
              style: sellerText(
                metrics,
                16,
                weight: FontWeight.w800,
                color: appointment.initialColor,
              ),
            ),
          ),
          SizedBox(width: metrics.geometry(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.name,
                  style: sellerText(metrics, 14, weight: FontWeight.w800),
                ),
                Text(
                  appointment.product,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sellerText(metrics, 11, color: SellerUiColors.body),
                ),
                Text(
                  '${appointment.date}  •  ${appointment.time}',
                  style: sellerText(metrics, 10, color: SellerUiColors.muted),
                ),
              ],
            ),
          ),
          SizedBox(width: metrics.geometry(8)),
          Text(
            appointment.price,
            style: sellerText(
              metrics,
              16,
              weight: FontWeight.w800,
              color: SellerUiColors.green,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerSheetHandle extends StatelessWidget {
  const _SellerSheetHandle();

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    return Center(
      child: Container(
        width: metrics.artSize(42),
        height: metrics.geometry(4),
        decoration: BoxDecoration(
          color: SellerUiColors.lavenderBorder,
          borderRadius: BorderRadius.circular(metrics.geometry(10)),
        ),
      ),
    );
  }
}

enum _MeetFilter { upcoming, today, completed, canceled }

class _Appointment {
  const _Appointment({
    required this.name,
    required this.initials,
    required this.request,
    required this.city,
    required this.distance,
    required this.date,
    required this.time,
    required this.product,
    required this.details,
    required this.price,
    required this.location,
    required this.avatarColor,
    required this.initialColor,
    this.isToday = false,
    this.canceled = false,
  });
  final String name,
      initials,
      request,
      city,
      distance,
      date,
      time,
      product,
      details,
      price,
      location;
  final Color avatarColor, initialColor;
  final bool isToday;
  final bool canceled;
}

const _appointments = [
  _Appointment(
    name: 'James M.',
    initials: 'JM',
    request: 'Looking for iPad Air (5th gen)',
    city: 'Yonkers, NY',
    distance: '2.1 mi',
    date: 'May 19, 2025',
    time: '2:00 PM',
    product: 'iPad Air (5th gen)',
    details: '64GB  •  Space Gray  •  Good condition',
    price: r'$475',
    location: 'Cross County Mall',
    avatarColor: Color(0xFFF0EDFF),
    initialColor: SellerUiColors.primaryBright,
    isToday: true,
  ),
  _Appointment(
    name: 'Alicia C.',
    initials: 'AC',
    request: 'Need iPad Pro 11-inch',
    city: 'New Rochelle, NY',
    distance: '4.7 mi',
    date: 'May 19, 2025',
    time: '5:30 PM',
    product: 'iPad Pro 11-inch (M2)',
    details: '128GB  •  Silver  •  Like new',
    price: r'$650',
    location: 'New Rochelle Public Library',
    avatarColor: Color(0xFFFFF0DF),
    initialColor: SellerUiColors.amber,
    isToday: true,
  ),
  _Appointment(
    name: 'Robert W.',
    initials: 'RW',
    request: 'iPad 10th Gen',
    city: 'Mount Vernon, NY',
    distance: '3.3 mi',
    date: 'May 20, 2025',
    time: '11:00 AM',
    product: 'iPad 10th Gen',
    details: '64GB  •  Blue  •  Excellent condition',
    price: r'$375',
    location: 'Target - Mount Vernon',
    avatarColor: Color(0xFFE3F7E9),
    initialColor: SellerUiColors.green,
    canceled: false,
  ),
];
