class LabValue {
  final String marker;
  final double? value;
  final String? unit;
  final double? referenceLow;
  final double? referenceHigh;
  final String? flag;

  LabValue({
    required this.marker,
    this.value,
    this.unit,
    this.referenceLow,
    this.referenceHigh,
    this.flag,
  });

  factory LabValue.fromJson(Map<String, dynamic> json) => LabValue(
        marker: json['marker'],
        value: (json['value'] as num?)?.toDouble(),
        unit: json['unit'],
        referenceLow: (json['reference_low'] as num?)?.toDouble(),
        referenceHigh: (json['reference_high'] as num?)?.toDouble(),
        flag: json['flag'],
      );
}

class LabResult {
  final String id;
  final String? labName;
  final String? orderedBy;
  final String sampleDate;
  final List<LabValue> values;
  final String? createdAt;

  LabResult({
    required this.id,
    this.labName,
    this.orderedBy,
    required this.sampleDate,
    this.values = const [],
    this.createdAt,
  });

  factory LabResult.fromJson(Map<String, dynamic> json) => LabResult(
        id: json['id'],
        labName: json['lab_name'],
        orderedBy: json['ordered_by'],
        sampleDate: json['sample_date'],
        values: (json['values'] as List?)
                ?.map((v) => LabValue.fromJson(v as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: json['created_at'],
      );
}

class MarkerTrend {
  final String marker;
  final String? unit;
  final double? referenceLow;
  final double? referenceHigh;
  final List<TrendDataPoint> dataPoints;

  MarkerTrend({
    required this.marker,
    this.unit,
    this.referenceLow,
    this.referenceHigh,
    required this.dataPoints,
  });

  factory MarkerTrend.fromJson(Map<String, dynamic> json) => MarkerTrend(
        marker: json['marker'],
        unit: json['unit'],
        referenceLow: (json['reference_low'] as num?)?.toDouble(),
        referenceHigh: (json['reference_high'] as num?)?.toDouble(),
        dataPoints: (json['data_points'] as List)
            .map((d) => TrendDataPoint.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}

class TrendDataPoint {
  final String date;
  final double value;
  final String? flag;

  TrendDataPoint({required this.date, required this.value, this.flag});

  factory TrendDataPoint.fromJson(Map<String, dynamic> json) => TrendDataPoint(
        date: json['date'],
        value: (json['value'] as num).toDouble(),
        flag: json['flag'],
      );
}
