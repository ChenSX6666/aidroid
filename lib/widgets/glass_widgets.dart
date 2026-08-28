import 'dart:ui';
import 'package:flutter/material.dart';

/// Global glass mode toggle
final ValueNotifier<bool> glassModeEnabled = ValueNotifier(true);

/// Glass card with BackdropFilter, press animation, and shimmer effect
class GlassCard extends StatefulWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? tintColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.blur = 12.0,
    this.opacity = 0.15,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.tintColor,
    this.onTap,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressAnim;
  double _shimmerPhase = 0;

  @override
  void initState() {
    super.initState();
    _pressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _pressAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: glassModeEnabled,
      builder: (context, enabled, _) {
        if (!enabled) return _buildNormal(context);
        return _buildGlass(context);
      },
    );
  }

  Widget _buildNormal(BuildContext context) {
    final card = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        color: widget.tintColor ?? Theme.of(context).cardColor,
      ),
      child: widget.child,
    );
    if (widget.onTap != null) {
      return GestureDetector(onTap: widget.onTap, child: card);
    }
    return card;
  }

  Widget _buildGlass(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _shimmerPhase = 1.0);
        _pressAnim.forward(from: 0);
      },
      onTapUp: (_) {
        _pressAnim.reverse();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _shimmerPhase = 0);
        });
      },
      onTapCancel: () {
        _pressAnim.reverse();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _shimmerPhase = 0);
        });
      },
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pressAnim,
        builder: (context, child) {
          return ClipRRect(
            borderRadius: widget.borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.blur,
                sigmaY: widget.blur,
              ),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  color: (widget.tintColor ?? Colors.white)
                      .withAlpha((widget.opacity * 255).toInt()),
                  border: Border.all(
                    color: Colors.white.withAlpha(40),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(15),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                // Shimmer overlay on press
                foregroundDecoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  gradient: _shimmerPhase > 0
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white
                                .withAlpha((_pressAnim.value * 50).toInt()),
                            Colors.transparent,
                            Colors.white
                                .withAlpha((_pressAnim.value * 25).toInt()),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        )
                      : null,
                ),
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Show a glass-styled dialog
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black26,
    builder: (ctx) => ValueListenableBuilder<bool>(
      valueListenable: glassModeEnabled,
      builder: (context, enabled, _) {
        if (!enabled) return Dialog(child: builder(ctx));
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Dialog(
            backgroundColor: Colors.white.withAlpha(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withAlpha(40)),
            ),
            child: builder(ctx),
          ),
        );
      },
    ),
  );
}

/// Glass-styled bottom sheet
Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (ctx) => ValueListenableBuilder<bool>(
      valueListenable: glassModeEnabled,
      builder: (context, enabled, _) {
        if (!enabled) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: builder(ctx),
          );
        }
        return ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(15),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(color: Colors.white.withAlpha(30)),
                ),
              ),
              child: builder(ctx),
            ),
          ),
        );
      },
    ),
  );
}

/// Glass-styled container (simpler, no press animation)
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? tintColor;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 10.0,
    this.opacity = 0.12,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding,
    this.tintColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: glassModeEnabled,
      builder: (context, enabled, _) {
        if (!enabled) {
          return Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: tintColor ?? Theme.of(context).cardColor,
              border: border,
            ),
            child: child,
          );
        }
        return ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                color: (tintColor ?? Colors.white)
                    .withAlpha((opacity * 255).toInt()),
                border: border ??
                    Border.all(
                      color: Colors.white.withAlpha(30),
                      width: 0.5,
                    ),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
