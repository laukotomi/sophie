import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Clips [child] to [maxHeight] when [collapsed], and calls [onOverflowDetected]
/// post-frame whenever the child's natural height exceeds [maxHeight].
class CollapsibleBody extends StatefulWidget {
  const CollapsibleBody({
    super.key,
    required this.maxHeight,
    required this.collapsed,
    required this.onOverflowDetected,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.curve = Curves.easeOut,
  });

  final double maxHeight;
  final bool collapsed;
  final void Function(bool overflows) onOverflowDetected;
  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  State<CollapsibleBody> createState() => _CollapsibleBodyState();
}

class _CollapsibleBodyState extends State<CollapsibleBody>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: widget.duration,
      curve: widget.curve,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: _CollapsibleBodyRenderWidget(
        maxHeight: widget.maxHeight,
        collapsed: widget.collapsed,
        onOverflowDetected: widget.onOverflowDetected,
        child: widget.child,
      ),
    );
  }
}

class _CollapsibleBodyRenderWidget extends SingleChildRenderObjectWidget {
  const _CollapsibleBodyRenderWidget({
    required this.maxHeight,
    required this.collapsed,
    required this.onOverflowDetected,
    required super.child,
  });

  final double maxHeight;
  final bool collapsed;
  final void Function(bool overflows) onOverflowDetected;

  @override
  RenderCollapsibleBody createRenderObject(BuildContext context) =>
      RenderCollapsibleBody(
        maxHeight: maxHeight,
        collapsed: collapsed,
        onOverflowDetected: onOverflowDetected,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCollapsibleBody renderObject,
  ) {
    renderObject
      ..maxHeight = maxHeight
      ..collapsed = collapsed
      ..onOverflowDetected = onOverflowDetected;
  }
}

class RenderCollapsibleBody extends RenderProxyBox {
  RenderCollapsibleBody({
    required this._maxHeight,
    required this._collapsed,
    required this._onOverflowDetected,
  });

  double _maxHeight;
  double get maxHeight => _maxHeight;
  set maxHeight(double v) {
    if (_maxHeight == v) return;
    _maxHeight = v;
    markNeedsLayout();
  }

  bool _collapsed;
  bool get collapsed => _collapsed;
  set collapsed(bool v) {
    if (_collapsed == v) return;
    _collapsed = v;
    markNeedsLayout();
  }

  void Function(bool) _onOverflowDetected;
  // ignore: avoid_setters_without_getters
  set onOverflowDetected(void Function(bool) v) => _onOverflowDetected = v;

  @override
  void performLayout() {
    // Layout child unconstrained vertically to measure its natural height.
    child!.layout(
      constraints.copyWith(maxHeight: double.infinity),
      parentUsesSize: true,
    );
    final naturalHeight = child!.size.height;
    final overflows = naturalHeight > _maxHeight;

    // Defer notification to avoid calling setState during layout.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _onOverflowDetected(overflows);
    });

    final displayHeight = _collapsed
        ? naturalHeight.clamp(0.0, _maxHeight)
        : naturalHeight;
    size = constraints.constrain(Size(child!.size.width, displayHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_collapsed && child!.size.height > size.height) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (ctx, off) => super.paint(ctx, off),
      );
    } else {
      super.paint(context, offset);
    }
  }
}
