import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/remote_controller.dart';

/// Rebuilds only the playhead consumers. While transport is idle the subtree
/// is static; while playing it ticks at display refresh rate and interpolates
/// between the 10 Hz server events.
class PlayheadBuilder extends StatefulWidget {
  const PlayheadBuilder({
    super.key,
    required this.controller,
    required this.builder,
  });

  final RemoteController controller;
  final Widget Function(BuildContext context, double position) builder;

  @override
  State<PlayheadBuilder> createState() => _PlayheadBuilderState();
}

class _PlayheadBuilderState extends State<PlayheadBuilder>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    widget.controller.transport.addListener(_onTransport);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant PlayheadBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.transport.removeListener(_onTransport);
      widget.controller.transport.addListener(_onTransport);
      _syncTicker();
    }
  }

  void _onTransport() {
    if (!mounted) return;
    setState(() {});
    _syncTicker();
  }

  void _syncTicker() {
    final running = widget.controller.transport.value.isRunning;
    if (running && !_ticker.isActive) {
      _ticker.start();
    } else if (!running && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    widget.controller.transport.removeListener(_onTransport);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.controller.estimatedPosition);
  }
}
