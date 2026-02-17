import 'package:flutter/material.dart';

class OrderReviewPage extends StatefulWidget {
  const OrderReviewPage({
    super.key,
    required this.orders,
    required this.modelColors,
    required this.homeStock,
    this.title = 'مراجعة الأوردرات قبل الخصم',
  });

  final List<Map<String, String>> orders;
  final Map<String, List<String>> modelColors;
  final Map<String, Map<String, int>> homeStock;
  final String title;

  @override
  State<OrderReviewPage> createState() => _OrderReviewPageState();
}

class _OrderReviewPageState extends State<OrderReviewPage> {
  late List<Map<String, String>> _orders;

  Map<String, Map<String, int>> get _defaultCounts => {
        for (final model in widget.modelColors.keys)
          model: {for (final c in widget.modelColors[model]!) c: 0},
      };

  @override
  void initState() {
    super.initState();
    _orders = widget.orders.map((e) => Map<String, String>.from(e)).toList();
    _orders.sort((a, b) => _confidenceOf(a).compareTo(_confidenceOf(b)));
  }

  int _countOf(Map<String, String> o) {
    final count = int.tryParse((o['count'] ?? '1').trim()) ?? 1;
    return count <= 0 ? 1 : count;
  }

  double _confidenceOf(Map<String, String> o) {
    final s = (o['confidence'] ?? '').trim();
    final v = double.tryParse(s);
    if (v == null) return 0;
    if (v.isNaN) return 0;
    if (v < 0) return 0;
    if (v > 1) return 1;
    return v;
  }

  List<String> _missingOf(Map<String, String> o) {
    final s = (o['missing_fields'] ?? '').trim();
    if (s.isEmpty) return const <String>[];
    return s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  }

  List<String> _colorsListOf(Map<String, String> o) {
    final raw = (o['colors'] ?? '').trim();
    if (raw.isEmpty) return <String>[];
    return raw.split('|').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  }

  void _setColorsList(Map<String, String> o, List<String> colors) {
    final cleaned = colors.map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (cleaned.isEmpty) {
      o.remove('colors');
      return;
    }
    o['colors'] = cleaned.join('|');
    o['color'] = cleaned.first;
  }

  void _ensureColorsForCount(Map<String, String> o) {
    final count = _countOf(o);
    final baseColor = (o['color'] ?? '').trim();
    final colors = _colorsListOf(o);

    if (count <= 1) {
      // Keep a single color in `color`, drop `colors` to avoid confusion.
      if (baseColor.isEmpty && colors.isNotEmpty) {
        o['color'] = colors.first;
      }
      o.remove('colors');
      o['count'] = '1';
      return;
    }

    final next = <String>[];
    if (colors.isNotEmpty) {
      next.addAll(colors.take(count));
    }
    while (next.length < count) {
      if (baseColor.isNotEmpty) {
        next.add(baseColor);
      } else if (widget.modelColors.containsKey((o['model'] ?? '').trim()) && widget.modelColors[(o['model'] ?? '').trim()]!.isNotEmpty) {
        next.add(widget.modelColors[(o['model'] ?? '').trim()]!.first);
      } else {
        break;
      }
    }
    _setColorsList(o, next);
    o['count'] = count.toString();
  }

  Map<String, Map<String, int>> _requiredCounts() {
    final req = _defaultCounts;
    for (final o in _orders) {
      final m = (o['model'] ?? '').trim();
      if (!req.containsKey(m)) continue;

      final safeCount = _countOf(o);

      final baseColor = (o['color'] ?? '').trim();
      final colorsRaw = (o['colors'] ?? '').trim();
      final parts = colorsRaw.split('|').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

      final effective = <String>[];
      if (parts.isNotEmpty) {
        effective.addAll(parts.take(safeCount));
        if (effective.length < safeCount && baseColor.isNotEmpty) {
          effective.addAll(List.filled(safeCount - effective.length, baseColor));
        }
      } else if (baseColor.isNotEmpty) {
        effective.addAll(List.filled(safeCount, baseColor));
      }

      for (final c in effective) {
        if (req[m]!.containsKey(c)) {
          req[m]![c] = (req[m]![c] ?? 0) + 1;
        }
      }
    }
    return req;
  }

  List<String> _validationErrors() {
    final errs = <String>[];
    for (final o in _orders) {
      final name = (o['name'] ?? '').trim();
      final model = (o['model'] ?? '').trim();
      final color = (o['color'] ?? '').trim();
      if (model.isEmpty || !widget.modelColors.containsKey(model)) {
        errs.add('❌ موديل غير معروف للعميل: ${name.isEmpty ? '-' : name}');
        continue;
      }
      final count = _countOf(o);
      if (count > 1) {
        final colors = _colorsListOf(o);
        if (colors.length < count) {
          errs.add('❌ ألوان غير مكتملة (عدد $count) للعميل: ${name.isEmpty ? '-' : name}');
          continue;
        }
        final bad = colors.take(count).firstWhere((c) => !widget.modelColors[model]!.contains(c), orElse: () => '');
        if (bad.isNotEmpty) {
          errs.add('❌ لون غير معروف ($bad) للعميل: ${name.isEmpty ? '-' : name}');
          continue;
        }
      } else {
        if (color.isEmpty || !widget.modelColors[model]!.contains(color)) {
          errs.add('❌ لون غير معروف للعميل: ${name.isEmpty ? '-' : name}');
          continue;
        }
      }
    }

    final req = _requiredCounts();
    for (final model in req.keys) {
      for (final color in req[model]!.keys) {
        final needed = req[model]![color] ?? 0;
        if (needed <= 0) continue;
        final available = widget.homeStock[model]?[color] ?? 0;
        if (available < needed) {
          errs.add('⚠️ مخزن البيت غير كافي: $model ($color) مطلوب $needed / متاح $available');
        }
      }
    }
    return errs;
  }

  bool get _canConfirm => _orders.isNotEmpty && _validationErrors().isEmpty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    for (final o in _orders) {
      _ensureColorsForCount(o);
    }
    final errors = _validationErrors();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _canConfirm ? () => Navigator.pop(context, _orders) : null,
            child: const Text('تأكيد'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (errors.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isDark ? Colors.red.shade900 : Colors.red.shade50).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.red.shade700 : Colors.red.shade200),
              ),
              child: Text(
                errors.take(8).join('\n'),
                textAlign: TextAlign.right,
                style: TextStyle(color: isDark ? Colors.white : Colors.red.shade900, fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _orders.length,
              itemBuilder: (context, index) {
                final o = _orders[index];
                final name = (o['name'] ?? '').trim();
                final model = (o['model'] ?? '').trim();
                final colors = widget.modelColors[model] ?? const <String>[];
                final color = (o['color'] ?? '').trim();
                final price = (o['price'] ?? '').trim();
                final shipping = (o['shipping'] ?? '0').trim();
                final discount = (o['discount'] ?? '0').trim();
                final confidence = _confidenceOf(o);
                final missing = _missingOf(o);
                final safeCount = _countOf(o);
                final colorsList = _colorsListOf(o);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF111111) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: confidence >= 0.75
                                  ? Colors.green.withValues(alpha: 0.18)
                                  : (confidence >= 0.5 ? Colors.orange.withValues(alpha: 0.18) : Colors.red.withValues(alpha: 0.18)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: confidence >= 0.75
                                    ? Colors.green.withValues(alpha: 0.25)
                                    : (confidence >= 0.5 ? Colors.orange.withValues(alpha: 0.25) : Colors.red.withValues(alpha: 0.25)),
                              ),
                            ),
                            child: Text(
                              "ثقة ${(confidence * 100).round()}%",
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: confidence >= 0.75 ? Colors.green : (confidence >= 0.5 ? Colors.orange : Colors.red),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _orders.removeAt(index)),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'حذف الأوردر',
                          ),
                          const Spacer(),
                          Expanded(
                            flex: 4,
                            child: Text(
                              name.isEmpty ? '(بدون اسم)' : name,
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                      if (missing.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          "ناقص: ${missing.join('، ')}",
                          textAlign: TextAlign.right,
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w600),
                        ),
                      ],
                      if (safeCount > 1) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'نقص العدد',
                              onPressed: safeCount <= 1
                                  ? null
                                  : () {
                                      setState(() {
                                        o['count'] = (safeCount - 1).toString();
                                        _ensureColorsForCount(o);
                                      });
                                    },
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              "العدد: $safeCount",
                              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w800),
                            ),
                            IconButton(
                              tooltip: 'زود العدد',
                              onPressed: () {
                                setState(() {
                                  o['count'] = (safeCount + 1).toString();
                                  _ensureColorsForCount(o);
                                });
                              },
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            const Spacer(),
                            if (safeCount > 1)
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    final base = (o['color'] ?? '').trim();
                                    final next = List<String>.filled(safeCount, base.isEmpty ? (colors.isNotEmpty ? colors.first : '') : base);
                                    _setColorsList(o, next);
                                  });
                                },
                                icon: const Icon(Icons.palette_outlined, size: 18),
                                label: const Text('نفس اللون'),
                              ),
                          ],
                        ),
                      ],
                      if (colorsList.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          "الألوان: ${colorsList.join('، ')}",
                          textAlign: TextAlign.right,
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w700),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: widget.modelColors.containsKey(model) ? model : null,
                              items: widget.modelColors.keys
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m, textAlign: TextAlign.right)))
                                  .toList(),
                              onChanged: (v) {
                                setState(() {
                                  o['model'] = v ?? '';
                                  final firstColor = (v != null && widget.modelColors[v]!.isNotEmpty) ? widget.modelColors[v]!.first : '';
                                  o['color'] = firstColor;
                                  if (safeCount > 1) {
                                    _setColorsList(o, List<String>.filled(safeCount, firstColor));
                                  } else {
                                    o.remove('colors');
                                  }
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: 'الموديل',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: colors.contains(color) ? color : null,
                              items: colors.map((c) => DropdownMenuItem(value: c, child: Text(c, textAlign: TextAlign.right))).toList(),
                              onChanged: (v) {
                                setState(() {
                                  o['color'] = v ?? '';
                                  if (safeCount > 1) {
                                    _ensureColorsForCount(o);
                                  }
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: 'اللون',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (safeCount > 1) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            "ألوان كل جهاز:",
                            textAlign: TextAlign.right,
                            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: List.generate(safeCount, (ci) {
                            final list = _colorsListOf(o);
                            final current = (ci < list.length) ? list[ci] : (o['color'] ?? '');
                            return SizedBox(
                              width: 170,
                              child: DropdownButtonFormField<String>(
                                value: colors.contains(current) ? current : (colors.isNotEmpty ? colors.first : null),
                                items: colors.map((c) => DropdownMenuItem(value: c, child: Text(c, textAlign: TextAlign.right))).toList(),
                                onChanged: (v) {
                                  setState(() {
                                    final next = _colorsListOf(o);
                                    while (next.length < safeCount) {
                                      next.add((o['color'] ?? '').trim());
                                    }
                                    if (v != null && v.isNotEmpty) next[ci] = v;
                                    _setColorsList(o, next);
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: "جهاز ${ci + 1}",
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: price,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'السعر', border: OutlineInputBorder()),
                              onChanged: (v) => o['price'] = v.trim(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              initialValue: shipping,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'الشحن', border: OutlineInputBorder()),
                              onChanged: (v) => o['shipping'] = v.trim(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              initialValue: discount,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'الخصم', border: OutlineInputBorder()),
                              onChanged: (v) => o['discount'] = v.trim(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: (o['phone'] ?? '').trim(),
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()),
                        onChanged: (v) => o['phone'] = v.trim(),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: (o['governorate'] ?? '').trim(),
                        decoration: const InputDecoration(labelText: 'المحافظة', border: OutlineInputBorder()),
                        onChanged: (v) => o['governorate'] = v.trim(),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: (o['address'] ?? '').trim(),
                        decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder()),
                        onChanged: (v) => o['address'] = v.trim(),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: (o['notes'] ?? '').trim(),
                        decoration: const InputDecoration(labelText: 'ملاحظات', border: OutlineInputBorder()),
                        onChanged: (v) => o['notes'] = v.trim(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: FilledButton.icon(
                onPressed: _canConfirm ? () => Navigator.pop(context, _orders) : null,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_orders.isEmpty ? 'لا يوجد أوردرات' : 'تأكيد وخصم من مخزن البيت'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
