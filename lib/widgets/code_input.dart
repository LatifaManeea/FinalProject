import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// A row of single-digit boxes for a one-time code.
///
/// Underneath is one real, invisible [TextField] — so the number pad,
/// paste, and iOS's "From Messages/Mail" code suggestion all work as
/// usual — and the boxes just draw its text. The box waiting for the next
/// digit is outlined in [AppColors.gold].
///
/// [onCompleted] fires the moment the last digit is entered. Bump
/// [shakeCount] to shake the row (e.g. after a wrong code).
class CodeInput extends StatefulWidget {
  const CodeInput({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.length = 6,
    this.hasError = false,
    this.enabled = true,
    this.shakeCount = 0,
  });

  final TextEditingController controller;
  final ValueChanged<String> onCompleted;
  final int length;
  final bool hasError;
  final bool enabled;
  final int shakeCount;

  @override
  State<CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<CodeInput> with SingleTickerProviderStateMixin {
  final _focusNode = FocusNode();
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChange);
    _focusNode.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(CodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleChange);
      widget.controller.addListener(_handleChange);
    }
    if (widget.shakeCount != oldWidget.shakeCount) {
      _shake.forward(from: 0);
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    _focusNode.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _handleChange() {
    setState(() {});
    final code = widget.controller.text;
    if (code.length == widget.length) widget.onCompleted(code);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // A few decaying side-to-side wobbles.
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 5) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: GestureDetector(
        onTap: widget.enabled ? _focusNode.requestFocus : null,
        child: Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < widget.length; i++) ...[
                  // Tighter gaps once there are too many boxes to fit comfortably.
                  if (i > 0) SizedBox(width: widget.length > 6 ? 6 : 10),
                  Expanded(child: _box(i, code)),
                ],
              ],
            ),
            // The real input: invisible, but covering the boxes so a
            // long-press still offers Paste.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: widget.length,
                  showCursor: false,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(int index, String code) {
    final filled = index < code.length;
    final isNext = _focusNode.hasFocus && index == code.length;

    final borderColor = widget.hasError
        ? AppColors.error
        : isNext
            ? AppColors.gold
            : filled
                ? AppColors.goldDim
                : AppColors.divider;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isNext ? 2 : 1),
        boxShadow: isNext
            ? [BoxShadow(color: AppColors.gold.withValues(alpha: 0.18), blurRadius: 12, spreadRadius: -2)]
            : null,
      ),
      child: Text(
        filled ? code[index] : '',
        style: AppTypography.timerMedium.copyWith(fontSize: widget.length > 6 ? 20 : 24),
      ),
    );
  }
}
