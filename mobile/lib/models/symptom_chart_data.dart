/// Time-series data for symptom occurrences and severity.
///
/// Shape matches the backend endpoint
/// `GET /api/v1/profiles/{profileId}/symptoms/chart`, which returns a flat
/// list of points:
///
/// ```json
/// {
///   "points": [
///     { "date": "2026-04-01", "symptom_type": "headache", "intensity": 6 },
///     { "date": "2026-04-02", "symptom_type": "headache", "intensity": 4 }
///   ]
/// }
/// ```
///
/// On the client side we group points by `symptom_type` to produce one
/// [SymptomSeries] per distinct symptom, each carrying a sorted list of
/// [SymptomChartPoint]s.
class SymptomChartPoint {
  final DateTime date;
  final double severity;

  const SymptomChartPoint({required this.date, required this.severity});

  factory SymptomChartPoint.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'];
    DateTime parsed;
    if (rawDate is String) {
      parsed = DateTime.tryParse(rawDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      parsed = DateTime.fromMillisecondsSinceEpoch(0);
    }
    final rawSeverity = json['intensity'] ?? json['severity'];
    final severity = (rawSeverity is num) ? rawSeverity.toDouble() : 0.0;
    return SymptomChartPoint(date: parsed, severity: severity);
  }
}

class SymptomSeries {
  final String symptomName;
  final List<SymptomChartPoint> dataPoints;

  const SymptomSeries({
    required this.symptomName,
    required this.dataPoints,
  });
}

class SymptomChartData {
  /// One entry per distinct symptom type in the response.
  final List<SymptomSeries> series;

  const SymptomChartData({required this.series});

  bool get isEmpty => series.isEmpty;

  /// Parses the raw `{ points: [...] }` response body and groups points by
  /// symptom type.
  factory SymptomChartData.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List?) ?? const [];
    final grouped = <String, List<SymptomChartPoint>>{};

    for (final raw in rawPoints) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      final name = (map['symptom_type'] as String?) ??
          (map['symptom_name'] as String?) ??
          '';
      if (name.isEmpty) continue;
      final point = SymptomChartPoint.fromJson(map);
      grouped.putIfAbsent(name, () => []).add(point);
    }

    final series = grouped.entries.map((e) {
      final pts = [...e.value]..sort((a, b) => a.date.compareTo(b.date));
      return SymptomSeries(symptomName: e.key, dataPoints: pts);
    }).toList()
      ..sort((a, b) => a.symptomName.compareTo(b.symptomName));

    return SymptomChartData(series: series);
  }
}
