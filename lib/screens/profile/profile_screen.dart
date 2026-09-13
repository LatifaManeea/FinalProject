import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/app_user.dart';
import '../../models/attendance.dart';
import '../../services/database.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/vignette_backdrop.dart';
import '../about/about_screen.dart';
import '../settings/settings_screen.dart';

/// Proposal screen 10 — films watched, cinemas visited, editable
/// display name and avatar. `TickedRepository` doesn't expose a
/// profile-update call yet (the frozen contract only covers auth,
/// reference data, scheduling and history) — the display name edit
/// below is local/cosmetic until a `updateProfile` method is added
/// alongside the real backend; it's a backward-compatible addition,
/// not a break of what's already frozen.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppUser? _user;
  List<Attendance> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await Database().getCurrentUser();
    final history = await appRepository.history();
    if (!mounted) return;
    setState(() {
      _user = user;
      _history = history;
    });
  }

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _user?.displayName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Display name', style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTypography.bodyLarge,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && _user != null) {
      setState(() => _user = _user!.copyWith(displayName: result));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final filmsWatched = _history.length;
    final cinemasVisited = _history.map((a) => a.cinemaName).toSet().length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        showVelvet: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 42,
                          backgroundColor: AppColors.surface2,
                          child: Text(
                            (user?.displayName.isNotEmpty ?? false) ? user!.displayName[0].toUpperCase() : '?',
                            style: AppTypography.displayLarge,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                            child: const Icon(Icons.edit, size: 14, color: AppColors.onGold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _editDisplayName,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(user?.displayName ?? '—', style: AppTypography.displayMedium),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit_outlined, size: 16, color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(user?.email ?? '', style: AppTypography.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  StatTile(value: '$filmsWatched', label: 'FILMS WATCHED'),
                  const SizedBox(width: 12),
                  StatTile(value: '$cinemasVisited', label: 'CINEMAS VISITED'),
                ],
              ),
              const SizedBox(height: 28),
              _ProfileMenuRow(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
              _ProfileMenuRow(
                icon: Icons.info_outline,
                label: 'About Us',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
            child: Row(
              children: [
                Icon(icon, color: AppColors.textSecondary, size: 20),
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600))),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
