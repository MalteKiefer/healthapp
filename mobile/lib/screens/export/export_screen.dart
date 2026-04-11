import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/spacing.dart';
import '../../models/export_schedule.dart';
import '../../providers/export_provider.dart';
import '../../providers/providers.dart';
import 'export_schedules_screen.dart';

/// `T.tr` returns the key itself when no entry is found, so we use that
/// to fall back to a hard-coded English string when a translation is missing.
String _trOr(String key, String fallback) {
  final v = T.tr(key);
  return v == key ? fallback : v;
}

/// Top-level Export screen — three large action cards (FHIR / PDF / ICS)
/// plus an "Import FHIR bundle" entry point. Each download action streams
/// the response as bytes, writes a temp file, and shares it via the system
/// share sheet (see [ExportController]).
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final state = ref.watch(exportControllerProvider);
    final controller = ref.read(exportControllerProvider.notifier);
    final profile = ref.watch(selectedProfileProvider);
    final profileId = profile?.id ?? '';
    final hasProfile = profileId.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_trOr('export.title', 'Export')),
        actions: [
          IconButton(
            tooltip: _trOr('export.schedules', 'Schedules'),
            icon: const Icon(Icons.schedule),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ExportSchedulesScreen(),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (!hasProfile)
            _InfoBanner(
              icon: Icons.person_outline,
              color: colors.tertiaryContainer,
              foreground: colors.onTertiaryContainer,
              message: 'Select a profile first to enable exports.',
            ),
          if (state.error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _InfoBanner(
              icon: Icons.error_outline,
              color: colors.errorContainer,
              foreground: colors.onErrorContainer,
              message: state.error!,
              onClose: () => controller.reset(),
            ),
          ],
          if (state.lastFilename != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _InfoBanner(
              icon: Icons.check_circle_outline,
              color: colors.secondaryContainer,
              foreground: colors.onSecondaryContainer,
              message: 'Exported ${state.lastFilename}',
              onClose: () => controller.reset(),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _ExportActionCard(
            icon: Icons.local_hospital_outlined,
            title: _trOr('export.fhir', 'Export FHIR'),
            description:
                'Download an HL7 FHIR R4 bundle of every record for this profile.',
            busy: state.busy && state.activeFormat == ExportFormats.fhir,
            disabled: !hasProfile || state.busy,
            onPressed: () => controller.exportFhir(profileId),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          _ExportActionCard(
            icon: Icons.picture_as_pdf_outlined,
            title: _trOr('export.pdf', 'Export PDF'),
            description:
                'Generate a printable PDF report summarizing the profile.',
            busy: state.busy && state.activeFormat == ExportFormats.pdf,
            disabled: !hasProfile || state.busy,
            onPressed: () => controller.exportPdf(profileId),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          _ExportActionCard(
            icon: Icons.event_outlined,
            title: _trOr('export.ics', 'Export ICS'),
            description:
                'Download upcoming appointments as an ICS calendar file.',
            busy: state.busy && state.activeFormat == ExportFormats.ics,
            disabled: !hasProfile || state.busy,
            onPressed: () => controller.exportIcs(profileId),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Import',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ExportActionCard(
            icon: Icons.upload_file_outlined,
            title: _trOr('export.import_fhir', 'Import FHIR bundle'),
            description:
                'Upload a FHIR JSON bundle and merge its records into this profile.',
            busy: state.busy && state.activeFormat == 'import-fhir',
            disabled: !hasProfile || state.busy,
            onPressed: () => _pickAndImport(context, ref, profileId),
            primary: false,
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndImport(
    BuildContext context,
    WidgetRef ref,
    String profileId,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to read file contents.')),
      );
      return;
    }
    final ok = await ref
        .read(exportControllerProvider.notifier)
        .importFhir(profileId, bytes);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'FHIR bundle imported successfully.' : 'Import failed.',
        ),
      ),
    );
  }
}

class _ExportActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool busy;
  final bool disabled;
  final bool primary;
  final VoidCallback onPressed;

  const _ExportActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.busy,
    required this.disabled,
    required this.onPressed,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final bg = primary ? colors.primaryContainer : colors.surfaceContainerHigh;
    final fg = primary ? colors.onPrimaryContainer : colors.onSurface;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: disabled ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg - AppSpacing.xs),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: fg, size: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      style: text.bodySmall?.copyWith(
                        color: fg.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 28,
                height: 28,
                child: busy
                    ? CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(fg),
                      )
                    : Icon(Icons.chevron_right, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color foreground;
  final String message;
  final VoidCallback? onClose;

  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.foreground,
    required this.message,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm + AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: foreground),
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: foreground),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
