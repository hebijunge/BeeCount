// 首页右下角的 AI 记账悬浮球：点一下直达对话，按住不放可以拖到任意位置，位置会记住。
//
// 位置存「距右 / 距底」两个逻辑像素，而不是左上角绝对坐标 —— 转屏或换机型时左上角
// 坐标会把球甩到屏幕中间，右下角锚定至少还落在用户原来放的那一片。
//
// 挂在 Scaffold 的 floatingActionButton 槽位 + 自定义 location 上，而不是往 body 里
// 塞一层 Stack：那样整棵首页子树都要重新缩进一次，diff 全是噪音。长按而不是随手拖，
// 是因为球落在列表上时单指拖动要先让给列表滚动。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ui_state_providers.dart';
import '../../styles/tokens.dart';
import '../ai/agent_ai_mark.dart';

const double kAiFabSize = 52;
const double kAiFabEdgeMargin = 12;

/// 「距右 / 距底」→ FAB 左上角坐标。单独抽成函数是为了能直接断言，
/// 不用去伪造 ScaffoldPrelayoutGeometry。
Offset aiFabOffsetFor({
  required Size screen,
  required Size fab,
  required Offset position,
  required double bottomInset,
}) =>
    Offset(
      screen.width - position.dx - fab.width,
      screen.height - bottomInset - position.dy - fab.height,
    );

/// 把整球夹在可用区内（底部还要躲开导航栏），否则能被拖出屏幕再也点不到。
Offset aiFabClamped(
  Offset position, {
  required Size screen,
  required Size fab,
  required double bottomInset,
}) {
  final maxRight =
      math.max(kAiFabEdgeMargin, screen.width - fab.width - kAiFabEdgeMargin);
  final maxBottom = math.max(kAiFabEdgeMargin,
      screen.height - bottomInset - fab.height - kAiFabEdgeMargin);
  return Offset(
    position.dx.clamp(kAiFabEdgeMargin, maxRight).toDouble(),
    position.dy.clamp(kAiFabEdgeMargin, maxBottom).toDouble(),
  );
}

class AiRecordFabLocation extends FloatingActionButtonLocation {
  AiRecordFabLocation({required this.position, required this.bottomInset});

  final Offset position;
  final double bottomInset;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) => aiFabOffsetFor(
        screen: geometry.scaffoldSize,
        fab: geometry.floatingActionButtonSize,
        position: position,
        bottomInset: bottomInset,
      );

  @override
  String toString() => 'AiRecordFabLocation($position)';
}

class AiRecordFab extends ConsumerStatefulWidget {
  const AiRecordFab({
    super.key,
    required this.tooltip,
    required this.onTap,
    required this.bottomInset,
  });

  final String tooltip;
  final VoidCallback onTap;

  /// 底部被导航栏占掉的高度，拖动范围要停在它上方。
  final double bottomInset;

  @override
  ConsumerState<AiRecordFab> createState() => _AiRecordFabState();
}

class _AiRecordFabState extends ConsumerState<AiRecordFab> {
  /// 非 null 表示正在长按拖动，值是长按开始那一刻的 (距右, 距底)。
  Offset? _dragOrigin;

  void _onDragUpdate(Offset origin, Offset moved) {
    // moved 是屏幕坐标（y 向下为正）：手指往右上走 → 距右变小、距底变大。
    ref.read(aiFabPositionProvider.notifier).state = aiFabClamped(
      Offset(origin.dx - moved.dx, origin.dy - moved.dy),
      screen: MediaQuery.sizeOf(context),
      fab: const Size.square(kAiFabSize),
      bottomInset: widget.bottomInset,
    );
  }

  /// transform 以左上角为原点，直接缩放会让球往左上跑，所以先补半个差量再缩放，
  /// 视觉上围绕球心放大。
  Matrix4 _scaleAroundCenter(double scale) {
    final shift = kAiFabSize * (1 - scale) / 2;
    return Matrix4.identity()
      ..translate(shift, shift)
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(aiFabPositionProvider);
    final dragging = _dragOrigin != null;

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPressStart: (_) => setState(() => _dragOrigin = position),
          onLongPressMoveUpdate: (details) {
            final origin = _dragOrigin;
            if (origin == null) return;
            _onDragUpdate(origin, details.localOffsetFromOrigin);
          },
          onLongPressEnd: (_) => setState(() => _dragOrigin = null),
          child: AnimatedContainer(
            key: const ValueKey('ai-record-fab'),
            duration: const Duration(milliseconds: 120),
            width: kAiFabSize,
            height: kAiFabSize,
            transform: _scaleAroundCenter(dragging ? 1.12 : 1.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dragging ? 0.28 : 0.16),
                  blurRadius: dragging ? 16 : 8,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: BeeTokens.surface(context).withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Center(
              child: AgentAiMark(size: 26, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
