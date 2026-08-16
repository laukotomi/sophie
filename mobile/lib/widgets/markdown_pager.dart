import 'dart:math' as math;

import 'package:flutter/material.dart';

class MarkdownPager extends StatefulWidget {
  final List<String> pages;
  final double minContentHeight;
  final Widget Function(String pageText) pageBuilder;

  const MarkdownPager({
    super.key,
    required this.pages,
    required this.pageBuilder,
    this.minContentHeight = 60,
  });

  @override
  State<MarkdownPager> createState() => _MarkdownPagerState();
}

class _MarkdownPagerState extends State<MarkdownPager> {
  final _pageController = PageController();
  final Map<int, double> _pageHeights = {};

  int _currentPageIndex = 0;
  double _currentPageHeight = 180;

  @override
  void didUpdateWidget(covariant MarkdownPager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.pages != widget.pages) {
      _pageHeights.clear();
      _currentPageIndex = 0;
      _currentPageHeight = 180;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _updateMeasuredPageHeight(int index, Size size) {
    final current = _pageHeights[index];
    final next = size.height;
    if (current != null && (current - next).abs() < 0.5) return;

    _pageHeights[index] = next;
    if (index == _currentPageIndex) {
      final targetHeight = math.max(widget.minContentHeight, next);
      if ((_currentPageHeight - targetHeight).abs() >= 0.5 && mounted) {
        setState(() => _currentPageHeight = targetHeight);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: SizedBox(
            height: _currentPageHeight,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.pages.length,
              onPageChanged: (index) {
                final measured = _pageHeights[index];
                final nextHeight = measured == null
                    ? _currentPageHeight
                    : math.max(widget.minContentHeight, measured);

                if ((_currentPageHeight - nextHeight).abs() >= 0.5 ||
                    _currentPageIndex != index) {
                  setState(() {
                    _currentPageIndex = index;
                    _currentPageHeight = nextHeight;
                  });
                }
              },
              itemBuilder: (context, index) {
                return _MeasuredSize(
                  onSize: (size) => _updateMeasuredPageHeight(index, size),
                  child: widget.pageBuilder(widget.pages[index]),
                );
              },
            ),
          ),
        ),
        if (widget.pages.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: List.generate(widget.pages.length, (index) {
              final isActive = index == _currentPageIndex;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: isActive ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(110),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _MeasuredSize extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onSize;

  const _MeasuredSize({required this.child, required this.onSize});

  @override
  State<_MeasuredSize> createState() => _MeasuredSizeState();
}

class _MeasuredSizeState extends State<_MeasuredSize> {
  Size? _oldSize;
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = _contentKey.currentContext?.size;
      if (size == null || _oldSize == size) return;
      _oldSize = size;
      widget.onSize(size);
    });

    return OverflowBox(
      minHeight: 0,
      maxHeight: double.infinity,
      alignment: Alignment.topLeft,
      child: SizedBox(key: _contentKey, child: widget.child),
    );
  }
}
