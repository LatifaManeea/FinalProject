import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../data/ticket_ocr_service.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/vignette_backdrop.dart';
import '../schedule/schedule_card_screen.dart';

/// Proposal screen 6 — a ticket photo chosen from the library or taken
/// on the spot, with an OCR pass over the detected text. Working from
/// a still photo rather than a live camera feed removes focus, motion
/// blur and frame-selection failure entirely (Challenge 1) — you just
/// get another photo if the first one's bad.
class UploadTicketScreen extends StatefulWidget {
  const UploadTicketScreen({super.key});

  @override
  State<UploadTicketScreen> createState() => _UploadTicketScreenState();
}

class _UploadTicketScreenState extends State<UploadTicketScreen> {
  final _picker = ImagePicker();
  File? _photo;
  bool _isParsing = false;

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, maxWidth: 2000, imageQuality: 90);
      if (picked == null) return;
      setState(() => _photo = File(picked.path));
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
    }
  }

  Future<void> _useThisPhoto() async {
    final photo = _photo;
    if (photo == null) return;

    setState(() => _isParsing = true);
    try {
      final parsed = await appTicketOcrService.parseTicketPhoto(photo.path);
      // Null when the title read off the ticket matches nothing in
      // `films` — the Schedule Card opens on the film picker instead of
      // being handed a film that isn't the one on the ticket.
      final film = await appRepository.matchFilmByTitle(parsed.filmTitleGuess ?? '');
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScheduleCardScreen(
            preselectedFilm: film,
            preselectedCinemaName: parsed.cinemaNameGuess,
            initialTicketTime: parsed.ticketTimeGuess,
            ocrConfidence: parsed.confidence,
          ),
        ),
      );
    } on TicketOcrUnavailable catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          action: SnackBarAction(
            label: 'Enter manually',
            textColor: AppColors.gold,
            onPressed: _enterManually,
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  void _enterManually() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ScheduleCardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        showVelvet: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                    Text('Upload ticket', style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 4 / 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: _photo == null
                              ? const _EmptyPhotoState()
                              : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: Image.file(_photo!, fit: BoxFit.cover),
                                    ),
                                    if (_isParsing) const _ParsingOverlay(),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: TickedSecondaryButton(
                              label: 'Library',
                              icon: Icons.photo_library_outlined,
                              onPressed: _isParsing ? null : () => _pick(ImageSource.gallery),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TickedSecondaryButton(
                              label: 'Camera',
                              icon: Icons.camera_alt_outlined,
                              onPressed: _isParsing ? null : () => _pick(ImageSource.camera),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TickedPrimaryButton(
                        label: 'Use this photo',
                        isLoading: _isParsing,
                        onPressed: _photo == null ? null : _useThisPhoto,
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: TextButton(
                          onPressed: _isParsing ? null : _enterManually,
                          child: Text(
                            'Enter details manually instead',
                            style: AppTypography.label.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPhotoState extends StatelessWidget {
  const _EmptyPhotoState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.confirmation_number_outlined, color: AppColors.textTertiary, size: 40),
        const SizedBox(height: 12),
        Text('No photo yet', style: AppTypography.bodyMedium),
      ],
    );
  }
}

class _ParsingOverlay extends StatelessWidget {
  const _ParsingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg.withOpacity(0.72),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2.6),
          const SizedBox(height: 14),
          Text('Reading your ticket…', style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
