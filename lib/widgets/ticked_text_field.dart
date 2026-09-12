import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// The form field style for the app: label printed above like a ticket
/// stub field, underline-only (never a filled pill), the line
/// brightening from [AppColors.divider] to solid [AppColors.gold] on
/// focus, [AppColors.error] when invalid.
class TickedTextField extends StatefulWidget {
  const TickedTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  State<TickedTextField> createState() => _TickedTextFieldState();
}

class _TickedTextFieldState extends State<TickedTextField> {
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  bool _obscured = true;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final lineColor = hasError
        ? AppColors.error
        : _focused
            ? AppColors.gold
            : AppColors.divider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label.toUpperCase(), style: AppTypography.overline),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: lineColor, width: _focused ? 2 : 1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  obscureText: widget.obscureText && _obscured,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  autofillHints: widget.autofillHints,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                  cursorColor: AppColors.gold,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.only(bottom: 10),
                    border: InputBorder.none,
                    hintText: widget.hintText,
                    hintStyle: AppTypography.bodyLarge.copyWith(color: AppColors.textDisabled),
                  ),
                ),
              ),
              if (widget.obscureText)
                IconButton(
                  onPressed: () => setState(() => _obscured = !_obscured),
                  icon: Icon(
                    _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 19,
                    color: AppColors.textTertiary,
                  ),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          child: hasError
              ? Padding(
                  key: ValueKey(widget.errorText),
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    widget.errorText!,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                  ),
                )
              : const SizedBox(height: 0, key: ValueKey('no-error')),
        ),
      ],
    );
  }
}
