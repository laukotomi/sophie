import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class SyncLottieIndicator extends StatefulWidget {
  final int pendingSyncs;
  final int successVersion;

  const SyncLottieIndicator({
    super.key,
    required this.pendingSyncs,
    required this.successVersion,
  });

  @override
  State<SyncLottieIndicator> createState() => _SyncLottieIndicatorState();
}

class _SyncLottieIndicatorState extends State<SyncLottieIndicator>
    with SingleTickerProviderStateMixin {
  static const String _syncLottieAsset = 'assets/loading_tick.json';
  static const int _syncTotalFrames = 60;
  static const int _syncLoadingFrames = 17;
  static const double _syncSplit = _syncLoadingFrames / _syncTotalFrames;

  late final AnimationController _controller;
  Duration? _lottieDuration;
  bool _show = false;
  int _lastPlayedSuccessVersion = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _lastPlayedSuccessVersion = widget.successVersion;

    if (widget.pendingSyncs > 0) {
      _startLoadingSegment();
    }
  }

  @override
  void didUpdateWidget(covariant SyncLottieIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.pendingSyncs > 0) {
      _startLoadingSegment();
      return;
    }

    final hasNewSuccess = widget.successVersion != _lastPlayedSuccessVersion;
    if (hasNewSuccess) {
      _lastPlayedSuccessVersion = widget.successVersion;
      unawaited(_playSuccessSegment());
      return;
    }

    _stopAndHide();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startLoadingSegment() {
    if (!_show) {
      setState(() => _show = true);
    }
    _controller
      ..stop()
      ..repeat(
        min: 0,
        max: _syncSplit,
        period: const Duration(milliseconds: 450),
      );
  }

  Future<void> _playSuccessSegment() async {
    _controller.stop();
    if (!_show) {
      setState(() => _show = true);
    }

    final duration = _lottieDuration ?? const Duration(seconds: 2);
    final successMs = (duration.inMilliseconds * (1 - _syncSplit)).round();

    try {
      _controller.value = _syncSplit;
      await _controller.animateTo(
        1,
        duration: Duration(milliseconds: successMs),
        curve: Curves.easeOut,
      );
    } finally {
      _stopAndHide();
    }
  }

  void _stopAndHide() {
    _controller.stop();
    if (_show) {
      setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();

    return SizedBox(
      width: 52,
      height: 52,
      child: Lottie.asset(
        _syncLottieAsset,
        controller: _controller,
        fit: BoxFit.contain,
        onLoaded: (composition) {
          _lottieDuration = composition.duration;
          if (widget.pendingSyncs > 0) {
            _startLoadingSegment();
          }
        },
      ),
    );
  }
}
