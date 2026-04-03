import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/lab.dart';
import '../../providers/providers.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _labsProvider = FutureProvider.family<List<LabResult>, String>((ref, id) async {
  final d = await ref.read(apiClientProvider).get<Map<String, dynamic>>('/api/v1/profiles/$id/labs');
  return (d['items'] as List).map((e) => LabResult.fromJson(e as Map<String, dynamic>)).toList();
});

final _trendsProvider = FutureProvider.family<List<MarkerTrend>, String>((ref, id) async {
  final d = await ref.read(apiClientProvider).get<Map<String, dynamic>>('/api/v1/profiles/$id/labs/trends');
  return (d['items'] as List).map((e) => MarkerTrend.fromJson(e as Map<String, dynamic>)).toList();
});

// ── Screen ────────────────────────────────────────────────────────────────────

enum _View { list, trends }
const _ranges = ['7d', '30d', '90d', '1y', 'All'];

class LabsScreen extends ConsumerStatefulWidget {
  final String profileId;
  const LabsScreen({super.key, required this.profileId});
  @override
  ConsumerState<LabsScreen> createState() => _LabsScreenState();
}

class _LabsScreenState extends ConsumerState<LabsScreen> {
  _View _view = _View.list;
  String _range = '90d';
  int? _expandedTrend;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Lab Results'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<_View>(
              segments: const [
                ButtonSegment(value: _View.list, label: Text('List')),
                ButtonSegment(value: _View.trends, label: Text('Trends')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)),
      body: _view == _View.list
          ? _ListTab(profileId: widget.profileId)
          : _TrendsTab(
              profileId: widget.profileId,
              range: _range,
              expandedIndex: _expandedTrend,
              onRangeChanged: (r) => setState(() => _range = r),
              onExpand: (i) => setState(() => _expandedTrend = _expandedTrend == i ? null : i),
            ),
    );
  }
}

// ── List tab ──────────────────────────────────────────────────────────────────

class _ListTab extends ConsumerWidget {
  final String profileId;
  const _ListTab({required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_labsProvider(profileId)).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (labs) => labs.isEmpty
          ? const Center(child: Text('No lab results yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: labs.length,
              itemBuilder: (_, i) => _LabCard(result: labs[i]),
            ),
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
    final r = widget.result;
    final date = r.sampleDate.length >= 10 ? r.sampleDate.substring(0, 10) : r.sampleDate;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(r.labName ?? 'Lab Result', style: Theme.of(context).textTheme.titleMedium)),
              Text(date, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 8),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20),
            ]),
            Text('${r.values.length} marker${r.values.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            if (_expanded && r.values.isNotEmpty) ...[
              const Divider(height: 20),
              _MarkerTable(values: r.values),
            ],
          ]),
        ),
      ),
    );
  }
}

class _MarkerTable extends StatelessWidget {
  final List<LabValue> values;
  const _MarkerTable({required this.values});

  Widget _cell(BuildContext ctx, String t) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(t, style: Theme.of(ctx).textTheme.bodySmall));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Table(
      columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: IntrinsicColumnWidth()},
      children: [
        TableRow(
          children: ['Marker', 'Value', 'Reference', '']
              .map((h) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(h, style: Theme.of(context).textTheme.labelSmall)))
              .toList(),
        ),
        for (final v in values)
          TableRow(children: [
            _cell(context, v.marker),
            _cell(context, v.value != null ? '${v.value} ${v.unit ?? ''}' : '–'),
            _cell(context, (v.referenceLow != null || v.referenceHigh != null) ? '${v.referenceLow ?? ''} – ${v.referenceHigh ?? ''}' : '–'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Builder(builder: (ctx) {
                final f = v.flag?.toLowerCase() ?? '';
                final color = f.startsWith('critical') ? cs.error : (f == 'high' || f == 'low') ? cs.tertiary : cs.primary;
                final label = f.isEmpty ? 'ok' : f;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                );
              }),
            ),
          ]),
      ],
    );
  }
}

// ── Trends tab ────────────────────────────────────────────────────────────────

class _TrendsTab extends ConsumerWidget {
  final String profileId;
  final String range;
  final int? expandedIndex;
  final ValueChanged<String> onRangeChanged;
  final ValueChanged<int> onExpand;
  const _TrendsTab({required this.profileId, required this.range, required this.expandedIndex, required this.onRangeChanged, required this.onExpand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_trendsProvider(profileId)).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (trends) {
        if (trends.isEmpty) return const Center(child: Text('No trends yet.'));
        return Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _ranges.map((r) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(label: Text(r), selected: range == r, onSelected: (_) => onRangeChanged(r)))).toList(),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0),
              itemCount: trends.length,
              itemBuilder: (_, i) => _TrendCard(trend: trends[i], range: range, expanded: expandedIndex == i, onTap: () => onExpand(i)),
            ),
          ),
        ]);
      },
    );
  }
}

class _TrendCard extends StatelessWidget {
  final MarkerTrend trend;
  final String range;
  final bool expanded;
  final VoidCallback onTap;
  const _TrendCard({required this.trend, required this.range, required this.expanded, required this.onTap});

  List<TrendDataPoint> _filtered() {
    final now = DateTime.now();
    final cutoff = switch (range) {
      '7d' => now.subtract(const Duration(days: 7)),
      '30d' => now.subtract(const Duration(days: 30)),
      '90d' => now.subtract(const Duration(days: 90)),
      '1y' => now.subtract(const Duration(days: 365)),
      _ => DateTime(2000),
    };
    return trend.dataPoints.where((d) => DateTime.tryParse(d.date)?.isAfter(cutoff) ?? true).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pts = _filtered();
    final last = pts.isNotEmpty ? pts.last : null;
    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trend.marker, style: Theme.of(context).textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (last != null)
              Text('${last.value} ${trend.unit ?? ''}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.primary)),
            const SizedBox(height: 6),
            Expanded(child: pts.isEmpty ? const Center(child: Text('No data')) : _buildChart(pts, cs)),
          ]),
        ),
      ),
    );
  }

  Widget _buildChart(List<TrendDataPoint> pts, ColorScheme cs) {
    final spots = pts.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList();
    final yVals = pts.map((p) => p.value);
    final dMin = yVals.reduce((a, b) => a < b ? a : b);
    final dMax = yVals.reduce((a, b) => a > b ? a : b);
    final rl = trend.referenceLow;
    final rh = trend.referenceHigh;
    final yMin = [dMin, if (rl != null) rl].reduce((a, b) => a < b ? a : b) - 1;
    final yMax = [dMax, if (rh != null) rh].reduce((a, b) => a > b ? a : b) + 1;
    final noTitles = const AxisTitles(sideTitles: SideTitles(showTitles: false));
    return LineChart(LineChartData(
      minY: yMin, maxY: yMax,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: expanded
          ? FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20,
                getTitlesWidget: (v, _) {
                  final i = v.round();
                  if (i < 0 || i >= pts.length) return const SizedBox.shrink();
                  final d = pts[i].date;
                  return Text(d.length >= 10 ? d.substring(5, 10) : d, style: const TextStyle(fontSize: 8));
                })),
              rightTitles: noTitles, topTitles: noTitles)
          : FlTitlesData(leftTitles: noTitles, rightTitles: noTitles, topTitles: noTitles, bottomTitles: noTitles),
      rangeAnnotations: (rl != null && rh != null)
          ? RangeAnnotations(horizontalRangeAnnotations: [HorizontalRangeAnnotation(y1: rl, y2: rh, color: cs.primary.withOpacity(0.1))])
          : const RangeAnnotations(),
      lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: cs.primary, barWidth: 2, dotData: FlDotData(show: expanded))],
      lineTouchData: expanded
          ? LineTouchData(touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (ss) => ss.map((s) => LineTooltipItem('${s.y} ${trend.unit ?? ''}', const TextStyle(fontSize: 11))).toList()))
          : const LineTouchData(enabled: false),
    ));
  }
}
