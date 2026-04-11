import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/api_error_messages.dart';
import '../../core/i18n/translations.dart';
import '../../models/lab.dart';
import '../../providers/providers.dart';

// -- Providers ----------------------------------------------------------------

final _labsProvider =
    FutureProvider.family<List<LabResult>, String>((ref, id) async {
  final d = await ref
      .read(apiClientProvider)
      .get<Map<String, dynamic>>('/api/v1/profiles/$id/labs');
  return (d['items'] as List)
      .map((e) => LabResult.fromJson(e as Map<String, dynamic>))
      .toList();
});

final _trendsProvider =
    FutureProvider.family<List<MarkerTrend>, String>((ref, id) async {
  final d = await ref
      .read(apiClientProvider)
      .get<Map<String, dynamic>>('/api/v1/profiles/$id/labs/trends');
  return (d['items'] as List)
      .map((e) => MarkerTrend.fromJson(e as Map<String, dynamic>))
      .toList();
});

// -- Marker row model for form ------------------------------------------------

class _MarkerEntry {
  final TextEditingController markerCtrl;
  final TextEditingController valueCtrl;
  final TextEditingController unitCtrl;
  _MarkerEntry({String marker = '', String value = '', String unit = ''})
      : markerCtrl = TextEditingController(text: marker),
        valueCtrl = TextEditingController(text: value),
        unitCtrl = TextEditingController(text: unit);
  void dispose() {
    markerCtrl.dispose();
    valueCtrl.dispose();
    unitCtrl.dispose();
  }
}

// -- Screen -------------------------------------------------------------------

enum _View { list, trends }

const _rangeKeys = ['3d', '7d', '30d', '90d', '1y', 'All'];

class LabsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const LabsScreen({super.key, required this.profileId});
  @override
  ConsumerState<LabsScreen> createState() => _LabsScreenState();
}

class _LabsScreenState extends ConsumerState<LabsScreen> {
  _View _view = _View.list;
  String _range = '3d';

  Future<void> _showFormSheet({LabResult? existing}) async {
    final api = ref.read(apiClientProvider);
    final isEdit = existing != null;
    final labNameCtrl =
        TextEditingController(text: existing?.labName ?? '');
    final sampleDateCtrl = TextEditingController(
        text: existing != null
            ? (existing.sampleDate.length >= 10
                ? existing.sampleDate.substring(0, 10)
                : existing.sampleDate)
            : '');
    final resultDateCtrl = TextEditingController(
        text: isEdit && existing.resultDate != null
            ? (existing.resultDate!.length >= 10
                ? existing.resultDate!.substring(0, 10)
                : existing.resultDate!)
            : '');
    final orderedByCtrl =
        TextEditingController(text: existing?.orderedBy ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    // Multi-marker rows
    final markers = <_MarkerEntry>[];
    if (isEdit && existing.values.isNotEmpty) {
      for (final v in existing.values) {
        markers.add(_MarkerEntry(
          marker: v.marker,
          value: v.value?.toString() ?? '',
          unit: v.unit ?? '',
        ));
      }
    } else {
      markers.add(_MarkerEntry());
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) {
          bool isSaving = false;
          return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: ListView(
              controller: scrollCtrl,
              children: [
                const SizedBox(height: 8),
                Text(
                  isEdit ? T.tr('labs.edit') : T.tr('labs.add'),
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: labNameCtrl,
                  decoration: InputDecoration(
                      labelText: T.tr('labs.lab_name')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sampleDateCtrl,
                  decoration: InputDecoration(
                    labelText: T.tr('labs.sample_date'),
                    hintText: 'YYYY-MM-DD',
                    suffixIcon: const Icon(Icons.calendar_today),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final initDate = sampleDateCtrl.text.isNotEmpty
                        ? (DateTime.tryParse(sampleDateCtrl.text) ??
                            DateTime.now())
                        : DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: initDate,
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      sampleDateCtrl.text =
                          DateFormat('yyyy-MM-dd').format(picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                // -- Markers section --
                Row(
                  children: [
                    Expanded(
                      child: Text(T.tr('labs.marker'),
                          style: Theme.of(ctx)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: T.tr('labs.add_marker'),
                      onPressed: () {
                        setSheetState(() => markers.add(_MarkerEntry()));
                      },
                    ),
                  ],
                ),
                ...List.generate(markers.length, (i) {
                  final m = markers[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: m.markerCtrl,
                                decoration: InputDecoration(
                                    labelText: T.tr('labs.marker_name')),
                              ),
                            ),
                            if (markers.length > 1)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    size: 20),
                                tooltip: T.tr('common.delete'),
                                onPressed: () async {
                                  await HapticFeedback.mediumImpact();
                                  setSheetState(() {
                                    markers[i].dispose();
                                    markers.removeAt(i);
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: m.valueCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText: T.tr('labs.value')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: m.unitCtrl,
                                decoration: InputDecoration(
                                    labelText: T.tr('labs.unit')),
                              ),
                            ),
                          ],
                        ),
                        if (i < markers.length - 1)
                          const Divider(height: 24),
                      ],
                    ),
                  );
                }),
                // -- Advanced section --
                ExpansionTile(
                  title: Text(T.tr('common.advanced')),
                  children: [
                    TextField(
                      controller: resultDateCtrl,
                      decoration: InputDecoration(
                        labelText: T.tr('labs.result_date'),
                        hintText: 'YYYY-MM-DD',
                        suffixIcon: const Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                      onTap: () async {
                        final initDate = resultDateCtrl.text.isNotEmpty
                            ? (DateTime.tryParse(resultDateCtrl.text) ??
                                DateTime.now())
                            : DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: initDate,
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          resultDateCtrl.text =
                              DateFormat('yyyy-MM-dd').format(picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: orderedByCtrl,
                      decoration: InputDecoration(
                          labelText: T.tr('labs.ordered_by')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                          labelText: T.tr('common.notes')),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: isSaving ? null : () async {
                    setSheetState(() => isSaving = true);
                    final dateStr = sampleDateCtrl.text.trim().isNotEmpty
                        ? '${sampleDateCtrl.text.trim()}T00:00:00.000Z'
                        : DateTime.now().toUtc().toIso8601String();
                    final markerValues = markers
                        .where((m) => m.markerCtrl.text.trim().isNotEmpty)
                        .map((m) => <String, dynamic>{
                              'marker': m.markerCtrl.text.trim(),
                              if (double.tryParse(m.valueCtrl.text.trim()) !=
                                  null)
                                'value':
                                    double.tryParse(m.valueCtrl.text.trim()),
                              if (m.unitCtrl.text.trim().isNotEmpty)
                                'unit': m.unitCtrl.text.trim(),
                            })
                        .toList();
                    final body = <String, dynamic>{
                      'sample_date': dateStr,
                      if (labNameCtrl.text.trim().isNotEmpty)
                        'lab_name': labNameCtrl.text.trim(),
                      if (resultDateCtrl.text.trim().isNotEmpty)
                        'result_date':
                            '${resultDateCtrl.text.trim()}T00:00:00.000Z',
                      if (orderedByCtrl.text.trim().isNotEmpty)
                        'ordered_by': orderedByCtrl.text.trim(),
                      if (notesCtrl.text.trim().isNotEmpty)
                        'notes': notesCtrl.text.trim(),
                      'values': markerValues,
                    };
                    try {
                      if (isEdit) {
                        await api.patch<void>(
                          '/api/v1/profiles/${widget.profileId}/labs/${existing.id}',
                          body: body,
                        );
                      } else {
                        await api.post<void>(
                          '/api/v1/profiles/${widget.profileId}/labs',
                          body: body,
                        );
                      }
                      ref.invalidate(_labsProvider(widget.profileId));
                      ref.invalidate(_trendsProvider(widget.profileId));
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        setSheetState(() => isSaving = false);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(apiErrorMessage(e)),
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    }
                  },
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(T.tr('common.save')),
                ),
              ],
            ),
          ),
        );
        },
      ),
    );
    labNameCtrl.dispose();
    sampleDateCtrl.dispose();
    resultDateCtrl.dispose();
    orderedByCtrl.dispose();
    notesCtrl.dispose();
    for (final m in markers) {
      m.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('labs.title')),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormSheet(),
        tooltip: T.tr('labs.add'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<_View>(
              segments: [
                ButtonSegment(
                    value: _View.list,
                    icon: const Icon(Icons.list, size: 18),
                    label: Text(T.tr('labs.list'))),
                ButtonSegment(
                    value: _View.trends,
                    icon: const Icon(Icons.show_chart, size: 18),
                    label: Text(T.tr('labs.trends'))),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          if (_view == _View.trends)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: _rangeKeys
                    .map((r) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(T.tr('range.${r.toLowerCase()}')),
                            selected: _range == r,
                            onSelected: (_) => setState(() => _range = r),
                          ),
                        ))
                    .toList(),
              ),
            ),
          Expanded(
            child: _view == _View.list
                ? _ListTab(
                    profileId: widget.profileId,
                    onEdit: (lab) => _showFormSheet(existing: lab),
                  )
                : _TrendsTab(profileId: widget.profileId, range: _range),
          ),
        ],
      ),
    );
  }
}

// -- List Tab -----------------------------------------------------------------

class _ListTab extends ConsumerWidget {
  final String profileId;
  final void Function(LabResult) onEdit;
  const _ListTab({required this.profileId, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ref.watch(_labsProvider(profileId)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(T.tr('labs.failed'), style: tt.bodyLarge),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(_labsProvider(profileId)),
                child: Text(T.tr('common.retry')),
              ),
            ]),
          ),
          data: (labs) {
            if (labs.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.science_outlined, size: 48, color: cs.outline),
                  const SizedBox(height: 12),
                  Text(T.tr('labs.no_data'),
                      style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(_labsProvider(profileId));
                ref.invalidate(_trendsProvider(profileId));
              },
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: labs.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LabCard(
                    result: labs[i],
                    onEdit: () => onEdit(labs[i]),
                    profileId: profileId,
                  ),
                ),
              ),
            );
          },
        );
  }
}

class _LabCard extends StatefulWidget {
  final LabResult result;
  final VoidCallback onEdit;
  final String profileId;
  const _LabCard({
    required this.result,
    required this.onEdit,
    required this.profileId,
  });
  @override
  State<_LabCard> createState() => _LabCardState();
}

class _LabCardState extends State<_LabCard> {
  bool _expanded = false;

  void _shareLabResult() {
    final r = widget.result;
    final parts = <String>[
      'Lab Result: ${r.labName ?? T.tr('labs.title')}',
      'Date: ${r.sampleDate.length >= 10 ? r.sampleDate.substring(0, 10) : r.sampleDate}',
    ];
    for (final v in r.values) {
      parts.add(
          '${v.marker}: ${v.value ?? '-'} ${v.unit ?? ''} ${v.flag != null ? '(${v.flag})' : ''}');
    }
    Share.share(parts.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final r = widget.result;
    final date =
        r.sampleDate.length >= 10 ? r.sampleDate.substring(0, 10) : r.sampleDate;
    String dateFormatted = date;
    try {
      final d = DateTime.parse(r.sampleDate);
      dateFormatted = DateFormat('MMM d, yyyy').format(d);
    } catch (_) {}

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.science, size: 18, color: cs.onTertiaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.labName ?? T.tr('labs.title'),
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          dateFormatted,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, size: 18),
                    tooltip: T.tr('common.share'),
                    onPressed: _shareLabResult,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: T.tr('common.edit'),
                    onPressed: widget.onEdit,
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${r.values.length} marker${r.values.length == 1 ? '' : 's'}',
                      style: tt.labelSmall?.copyWith(color: cs.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: cs.outline,
                  ),
                ],
              ),
              if (_expanded && r.values.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(color: cs.outlineVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                ...r.values.map((v) => _MarkerRow(value: v)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkerRow extends StatelessWidget {
  final LabValue value;
  const _MarkerRow({required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final f = value.flag?.toLowerCase() ?? '';
    final flagColor = f.startsWith('critical')
        ? cs.error
        : (f == 'high' || f == 'low')
            ? cs.tertiary
            : cs.primary;
    final flagLabel = f.isEmpty ? 'ok' : f;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(value.marker, style: tt.bodyMedium),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value.value != null
                  ? '${value.value} ${value.unit ?? ''}'
                  : '\u2013',
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              (value.referenceLow != null || value.referenceHigh != null)
                  ? '${value.referenceLow ?? ''}\u2013${value.referenceHigh ?? ''}'
                  : '',
              style: tt.bodySmall?.copyWith(color: cs.outline),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: flagColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              flagLabel,
              style: TextStyle(
                  fontSize: 10, color: flagColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Trends Tab ---------------------------------------------------------------

class _TrendsTab extends ConsumerWidget {
  final String profileId;
  final String range;
  const _TrendsTab({required this.profileId, required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ref.watch(_trendsProvider(profileId)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(_trendsProvider(profileId)),
                child: Text(T.tr('common.retry')),
              ),
            ]),
          ),
          data: (trends) {
            if (trends.isEmpty) {
              return Center(
                child: Text(T.tr('labs.no_trends'),
                    style:
                        tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(_labsProvider(profileId));
                ref.invalidate(_trendsProvider(profileId));
              },
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.0,
                ),
                itemCount: trends.length,
                itemBuilder: (_, i) =>
                    _TrendCard(trend: trends[i], range: range),
              ),
            );
          },
        );
  }
}

class _TrendCard extends StatelessWidget {
  final MarkerTrend trend;
  final String range;
  const _TrendCard({required this.trend, required this.range});

  List<TrendDataPoint> _filtered() {
    final now = DateTime.now();
    final cutoff = switch (range) {
      '3d' => now.subtract(const Duration(days: 3)),
      '7d' => now.subtract(const Duration(days: 7)),
      '30d' => now.subtract(const Duration(days: 30)),
      '90d' => now.subtract(const Duration(days: 90)),
      '1y' => now.subtract(const Duration(days: 365)),
      _ => DateTime(2000),
    };
    return trend.dataPoints
        .where((d) => DateTime.tryParse(d.date)?.isAfter(cutoff) ?? true)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pts = _filtered();
    final last = pts.isNotEmpty ? pts.last : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trend.marker,
                style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (last != null)
              Text(
                '${last.value} ${trend.unit ?? ''}',
                style: tt.titleMedium?.copyWith(
                    color: cs.primary, fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: pts.isEmpty
                  ? Center(
                      child: Text(T.tr('labs.no_trend_data'),
                          style: tt.bodySmall?.copyWith(color: cs.outline)))
                  : _buildChart(pts, cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(List<TrendDataPoint> pts, ColorScheme cs) {
    final spots = pts
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();
    final yVals = pts.map((p) => p.value);
    final dMin = yVals.reduce((a, b) => a < b ? a : b);
    final dMax = yVals.reduce((a, b) => a > b ? a : b);
    final rl = trend.referenceLow;
    final rh = trend.referenceHigh;
    final yMin =
        [dMin, if (rl != null) rl].reduce((a, b) => a < b ? a : b) - 1;
    final yMax =
        [dMax, if (rh != null) rh].reduce((a, b) => a > b ? a : b) + 1;
    const noTitles =
        AxisTitles(sideTitles: SideTitles(showTitles: false));

    return LineChart(
      LineChartData(
        minY: yMin,
        maxY: yMax,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: noTitles,
          rightTitles: noTitles,
          topTitles: noTitles,
          bottomTitles: noTitles,
        ),
        rangeAnnotations: (rl != null && rh != null)
            ? RangeAnnotations(horizontalRangeAnnotations: [
                HorizontalRangeAnnotation(
                    y1: rl, y2: rh, color: cs.primary.withValues(alpha: 0.08))
              ])
            : const RangeAnnotations(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: cs.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.primary.withValues(alpha: 0.1),
                  cs.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
