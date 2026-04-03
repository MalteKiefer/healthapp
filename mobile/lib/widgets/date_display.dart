import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateDisplay extends StatelessWidget {
  final String? isoDate;
  final String format;
  final TextStyle? style;
  final String fallback;

  const DateDisplay({
    super.key,
    required this.isoDate,
    this.format = 'MMM d, yyyy',
    this.style,
    this.fallback = '—',
  });

  @override
  Widget build(BuildContext context) {
    final text = _format();
    return Text(text, style: style);
  }

  String _format() {
    if (isoDate == null || isoDate!.isEmpty) return fallback;
    try {
      final date = DateTime.parse(isoDate!).toLocal();
      return DateFormat(format).format(date);
    } catch (_) {
      return fallback;
    }
  }
}
