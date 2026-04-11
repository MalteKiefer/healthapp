import 'package:flutter/material.dart';

/// Reusable 6-digit numeric PIN input with a 6-dot indicator and a 3x4
/// numpad. Used by both setup and lock screens.
class PinNumpad extends StatefulWidget {
  const PinNumpad({
    super.key,
    required this.onCompleted,
    this.errorText,
    this.enabled = true,
  });

  final void Function(String pin) onCompleted;
  final String? errorText;
  final bool enabled;

  @override
  State<PinNumpad> createState() => _PinNumpadState();
}

class _PinNumpadState extends State<PinNumpad> {
  final List<int> _digits = [];

  void _press(int d) {
    if (!widget.enabled) return;
    if (_digits.length >= 6) return;
    setState(() => _digits.add(d));
    if (_digits.length == 6) {
      widget.onCompleted(_digits.join());
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(_digits.clear);
      });
    }
  }

  void _backspace() {
    if (!widget.enabled) return;
    if (_digits.isEmpty) return;
    setState(_digits.removeLast);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _digits.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? cs.primary : Colors.transparent,
                border: Border.all(color: cs.primary, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        if (widget.errorText != null)
          Text(widget.errorText!, style: TextStyle(color: cs.error)),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          childAspectRatio: 1.5,
          children: [
            for (var i = 1; i <= 9; i++) _button(i.toString(), () => _press(i)),
            const SizedBox.shrink(),
            _button('0', () => _press(0)),
            _button('\u232B', _backspace),
          ],
        ),
      ],
    );
  }

  Widget _button(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FilledButton.tonal(
        onPressed: widget.enabled ? onTap : null,
        child: Text(label, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
