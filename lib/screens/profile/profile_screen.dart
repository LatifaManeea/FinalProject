import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/app_user.dart';
import '../../models/yearly_recap.dart';
import '../../services/database.dart';
import '../../widgets/recap_card.dart';
import '../../widgets/vignette_backdrop.dart';
import '../about/about_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';

/// Proposal screen 10 — the yearly recap and account menu.
///
/// Past screenings used to be listed here too, under a second,
/// separate FILMS WATCHED / CINEMAS VISITED tile row that just
/// repeated what the recap card already said. Both are gone: the
/// recap card is the one place those numbers live, and the full
/// attended-screenings list moved to its own screen behind the
/// "History" button — this page is the recap and the account menu,
/// nothing competing with either for attention.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _picker = ImagePicker();

  AppUser? _user;
  YearlyRecap? _recap;

  /// Shown the instant a photo is picked, before the upload finishes —
  /// so tapping the avatar feels immediate rather than waiting on a
  /// round trip before anything changes on screen. Cleared once
  /// [_user]'s own `avatarUrl` reflects the upload (or the upload
  /// fails and this is dropped back to whatever was there before).
  File? _pendingAvatarFile;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The recap comes from the repository (in memory today) and is
  /// shown as soon as it resolves. The signed-in profile is a separate
  /// Supabase round trip that can hang or fail — it used to be awaited
  /// first, which left the whole page on a spinner for as long as that
  /// call took. It now loads after, and its failure costs only the
  /// name, email and photo.
  Future<void> _load() async {
    final recap = await appRepository.recap(DateTime.now().year);
    if (!mounted) return;
    setState(() => _recap = recap);

    try {
      final user = await Database().getCurrentUser();
      if (!mounted) return;
      setState(() => _user = user);
    } catch (_) {
      // Not signed in, offline, or Supabase is unreachable. Everything
      // above is already on screen.
    }
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

  Future<void> _editAvatar() async {
    final user = _user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in again before changing your photo.')),
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.textPrimary),
              title: Text('Take photo', style: AppTypography.bodyLarge),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
              title: Text('Choose from library', style: AppTypography.bodyLarge),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(source: source, maxWidth: 1000, imageQuality: 85);
    } catch (e) {
      if (!mounted) return;
      final isCamera = source == ImageSource.camera;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCamera
                ? 'Couldn\'t open the camera. On the iOS Simulator there is no camera — try Library instead, or a real device.'
                : 'Couldn\'t open the photo library: $e',
          ),
        ),
      );
      return;
    }
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    setState(() {
      _pendingAvatarFile = file;
      _uploadingAvatar = true;
    });

    try {
      final avatarUrl = await Database().uploadAvatar(user.id, file);
      await Database().updateProfile(user.id, _user?.displayName ?? user.displayName, avatarUrl);
      if (!mounted) return;
      setState(() {
        _user = _user?.copyWith(avatarUrl: avatarUrl);
        _pendingAvatarFile = null;
        _uploadingAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingAvatarFile = null;
        _uploadingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t save your photo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        showVelvet: false,
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _uploadingAvatar ? null : _editAvatar,
                        child: Stack(
                          children: [
                            ClipOval(
                              child: SizedBox(
                                width: 84,
                                height: 84,
                                child: _AvatarImage(user: user, pendingFile: _pendingAvatarFile),
                              ),
                            ),
                            if (_uploadingAvatar)
                              const Positioned.fill(
                                child: ClipOval(
                                  child: ColoredBox(
                                    color: Colors.black45,
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt, size: 14, color: AppColors.onGold),
                              ),
                            ),
                          ],
                        ),
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
                RecapCard(recap: _recap),
                const SizedBox(height: 30),
                Text('MORE', style: AppTypography.overline),
                const SizedBox(height: 12),
                _ProfileMenuRow(
                  icon: Icons.history,
                  label: 'History',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
                ),
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
      ),
    );
  }
}

/// The 84×84 circle's contents: a picked-but-not-yet-uploaded local
/// file first, then the saved `avatarUrl`, then the display name's
/// initial as a last resort — the same fallback ladder either way, so
/// a slow or broken image never leaves the circle blank.
class _AvatarImage extends StatelessWidget {
  const _AvatarImage({required this.user, required this.pendingFile});

  final AppUser? user;
  final File? pendingFile;

  Widget _initial() {
    return ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Text(
          (user?.displayName.isNotEmpty ?? false) ? user!.displayName[0].toUpperCase() : '?',
          style: AppTypography.displayLarge,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingFile = this.pendingFile;
    if (pendingFile != null) {
      return Image.file(pendingFile, fit: BoxFit.cover);
    }

    final avatarUrl = user?.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return Image.network(
        avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _initial(),
        loadingBuilder: (context, child, progress) => progress == null ? child : _initial(),
      );
    }

    return _initial();
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
