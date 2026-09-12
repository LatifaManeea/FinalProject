import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// Primary CTA — solid flat gold fill, 14px rounding (not a pill),
/// [AppColors.onGold] text. No gradient, no glass: this is a marquee
/// ticket, not a startup landing page. Darkens to [AppColors.goldPressed]
/// while held, exactly the state that colour was defined for.
class TickedPrimaryButton extends StatefulWidget {
  const TickedPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<TickedPrimaryButton> createState() => _TickedPrimaryButtonState();
}

class _TickedPrimaryButtonState extends State<TickedPrimaryButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: _enabled ? widget.onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !_enabled
              ? AppColors.gold.withOpacity(0.35)
              : (_pressed ? AppColors.goldPressed : AppColors.gold),
          borderRadius: BorderRadius.circular(14),
        ),
        child: widget.isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.onGold),
                ),
              )
            : Text(
                widget.label,
                style: AppTypography.label.copyWith(color: AppColors.onGold),
              ),
      ),
    );
  }
}

/// Secondary CTA — outlined, low-emphasis actions like "Continue with
/// Apple".
class TickedSecondaryButton extends StatelessWidget {
  const TickedSecondaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
            ],
            Text(label, style: AppTypography.label.copyWith(color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
