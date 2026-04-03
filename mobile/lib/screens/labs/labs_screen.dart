import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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

  Future<void> _showAddSheet() async {
    final labNameCtrl = TextEditingController();
    final sampleDateCtrl = TextEditingController();
    final markerCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final unitCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: ListView(
            controller: scrollCtrl,
            children: [
              const SizedBox(height: 8),
              Text(T.tr('labs.add'),
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 20),
              TextField(
                controller: labNameCtrl,
                decoration: const InputDecoration(labelText: 'Lab Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sampleDateCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sample Date',
                  hintText: 'YYYY-MM-DD',
                ),
                keyboardType: TextInputType.datetime,
              ),
              const SizedBox(height: 16),
              Text('First Marker',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleSmall
                      ?.copyWith(
                          color:
                              Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: markerCtrl,
                decoration: const InputDecoration(labelText: 'Marker Name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: valueCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(labelText: 'Value'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: unitCtrl,
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final dateStr = sampleDateCtrl.text.trim().isNotEmpty
                      ? '${sampleDateCtrl.text.trim()}T00:00:00.000Z'
                      : DateTime.now().toUtc().toIso8601String();
                  final body = <String, dynamic>{
                    'sample_date': dateStr,
                    if (labNameCtrl.text.trim().isNotEmpty)
                      'lab_name': labNameCtrl.text.trim(),
                    'values': [
                      if (markerCtrl.text.trim().isNotEmpty)
                        {
                          'marker': markerCtrl.text.trim(),
                          if (double.tryParse(valueCtrl.text.trim()) != null)
                            'value':
                                double.tryParse(valueCtrl.text.trim()),
                          if (unitCtrl.text.trim().isNotEmpty)
                            'unit': unitCtrl.text.trim(),
                        },
                    ],
                  };
                  try {
                    await ref.read(apiClientProvider).post<void>(
                          '/api/v1/profiles/${widget.profileId}/labs',
                          body: body,
                        );
                    ref.invalidate(_labsProvider(widget.profileId));
                    ref.invalidate(_trendsProvider(widget.profileId));
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: Text(T.tr('common.save')),
              ),
            ],
          ),
        ),
      ),
    );
    labNameCtrl.dispose();
    sampleDateCtrl.dispose();
    markerCtrl.dispose();
    valueCtrl.dispose();
    unitCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(T.tr('labs.title')),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
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
                ? _ListTab(profileId: widget.profileId)
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
  const _ListTab({required this.profileId});

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
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: labs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LabCard(result: labs[i]),
              ),
            );
          },
        );
  }
}

class _LabCard extends StatefulWidget {
  final LabResult result;
  const _LabCard({required this.result});
  @override
  State<_LabCard> createState() => _LabCardState();
}

class _LabCardState extends State<_LabCard> {
  bool _expanded = false;

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
            return GridView.builder(
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
