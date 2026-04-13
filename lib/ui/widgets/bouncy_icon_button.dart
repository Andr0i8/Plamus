import 'package:flutter/material.dart';

/// Tappable icon with a subtle scale “bounce” on press (premium feel).
class BouncyIconButton extends StatefulWidget {
  /// Creates a bouncy icon button.
  const BouncyIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 28,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  State<BouncyIconButton> createState() => _BouncyIconButtonState();
}

class _BouncyIconButtonState extends State<BouncyIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (widget.onPressed == null) return;
    await _c.forward();
    await _c.reverse();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final child = ScaleTransition(
      scale: Tween<double>(begin: 1, end: 0.94).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
      ),
      child: IconButton(
        tooltip: widget.tooltip,
        iconSize: widget.size,
        onPressed: widget.onPressed == null ? null : _tap,
        icon: Icon(widget.icon),
      ),
    );
    return child;
  }
}
