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
    for (final o in _orders) {
      _ensureColorsForCount(o);
      _normalizeOrderColorsForModels(o);
    }
  }

  int _countOf(Map<String, String> o) {
    final count = int.tryParse((o['count'] ?? '1').trim()) ?? 1;
    return count <= 0 ? 1 : count;
  }

  List<String> _modelsListOf(Map<String, String> o) {
    final raw = (o['models'] ?? '').trim();
    if (raw.isEmpty) return <String>[];
    return raw.split('|').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
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

  String _normalizeArabic(String input) {
    var s = input.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    return s;
  }

  String _normalizeColorNameAny(String colorRaw) {
    final c = _normalizeArabic(colorRaw);
    if (c.isEmpty) return '';
    if (c.contains('سلفر') || c.contains('سيلفر') || c.contains('فضي') || c.contains('فضه') || c.contains('ابيض') || c.contains('أبيض') || c.contains('silver') || c.contains('white')) return 'سلفر';
    if (c.contains('اسود') || c.contains('أسود') || c.contains('بلاك') || c.contains('black')) return 'اسود';
    if (c.contains('ازرق') || c.contains('أزرق') || c.contains('blue')) return 'ازرق';
    if (c.contains('دهبي') || c.contains('ذهبي') || c.contains('جولد') || c.contains('gold')) return 'دهبي';
    if (c.contains('برتقالي') || c.contains('اورنج') || c.contains('اورانج') || c.contains('أورنج') || c.contains('orange')) return 'برتقالي';
    if (c.contains('كحلي') || c.contains('كحلى') || c.contains('navy')) return 'كحلي';
    if (c.contains('تيتانيوم') || c.contains('طبيعي') || c.contains('ناتشورال') || c.contains('natural')) return 'تيتانيوم';
    return colorRaw.trim();
  }

  String _normalizeColorForModel(String modelKey, String colorRaw) {
    final normalized = _normalizeColorNameAny(colorRaw).trim();
    if (normalized.isEmpty) return '';

    final allowed = widget.modelColors[modelKey] ?? const <String>[];
    if (allowed.contains(normalized)) return normalized;

    if (normalized == 'ازرق' && allowed.contains('كحلي')) return 'كحلي';
    if (normalized == 'كحلي' && allowed.contains('ازرق')) return 'ازرق';

    return normalized;
  }

  void _normalizeOrderColorsForModels(Map<String, String> o) {
    final count = _countOf(o);
    final baseModel = (o['model'] ?? '').trim();
    final baseColor = (o['color'] ?? '').trim();

    if (count <= 1) {
      final mapped = baseModel.isNotEmpty ? _normalizeColorForModel(baseModel, baseColor) : _normalizeColorNameAny(baseColor);
      if (mapped.isNotEmpty) o['color'] = mapped;
      return;
    }

    final models = _modelsListOf(o);
    final colors = _colorsListOf(o);

    final nextModels = <String>[]..addAll(models);
    while (nextModels.length < count) {
      nextModels.add(baseModel);
    }

    final nextColors = <String>[]..addAll(colors);
    while (nextColors.length < count) {
      nextColors.add(baseColor);
    }

    for (int i = 0; i < count; i++) {
      final m = (i < nextModels.length && nextModels[i].isNotEmpty) ? nextModels[i] : baseModel;
      final c = (i < nextColors.length && nextColors[i].isNotEmpty) ? nextColors[i] : baseColor;
      if (m.isEmpty) continue;
      final mapped = _normalizeColorForModel(m, c);
      if (mapped.isNotEmpty) nextColors[i] = mapped;
    }

    _setColorsList(o, nextColors);
  }

  void _setModelsList(Map<String, String> o, List<String> models) {
    final cleaned = models.map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (cleaned.isEmpty) {
      o.remove('models');
      return;
    }
    o['models'] = cleaned.join('|');
    o['model'] = cleaned.first;
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
    final baseModel = (o['model'] ?? '').trim();
    final models = _modelsListOf(o);

    if (count <= 1) {
      // Keep a single color in `color`, drop `colors` to avoid confusion.
      if (baseColor.isEmpty && colors.isNotEmpty) {
        o['color'] = colors.first;
      }
      o.remove('colors');
      o.remove('models');
      o['count'] = '1';
      return;
    }

    // Ensure models list
    final nextModels = <String>[];
    if (models.isNotEmpty) {
      nextModels.addAll(models.take(count));
    }
    while (nextModels.length < count) {
      if (baseModel.isNotEmpty) {
        nextModels.add(baseModel);
      } else if (widget.modelColors.keys.isNotEmpty) {
        nextModels.add(widget.modelColors.keys.first);
      } else {
        break;
      }
    }
    _setModelsList(o, nextModels);

    // Ensure colors list (based on each device model)
    final next = <String>[];
    if (colors.isNotEmpty) {
      next.addAll(colors.take(count));
    }
    while (next.length < count) {
      if (baseColor.isNotEmpty) {
        next.add(baseColor);
      } else {
        final m = (nextModels.length > next.length) ? nextModels[next.length] : baseModel;
        final palette = widget.modelColors[m] ?? const <String>[];
        final fallback = palette.isNotEmpty ? palette.first : '';
        if (fallback.isEmpty) break;
        next.add(fallback);
      }
    }
    _setColorsList(o, next);
    o['count'] = count.toString();
  }

  Map<String, Map<String, int>> _requiredCounts() {
    final req = _defaultCounts;
    for (final o in _orders) {
      final m = (o['model'] ?? '').trim();
      if (m.isEmpty) continue;

      final safeCount = _countOf(o);

      final baseColor = (o['color'] ?? '').trim();
      final parts = _colorsListOf(o);
      final baseModel = (o['model'] ?? '').trim();
      final modelParts = _modelsListOf(o);

      for (int di = 0; di < safeCount; di++) {
        final model = (di < modelParts.length && modelParts[di].isNotEmpty) ? modelParts[di] : baseModel;
        if (!req.containsKey(model)) continue;
        final rawColor = (di < parts.length && parts[di].isNotEmpty) ? parts[di] : baseColor;
        final color = _normalizeColorForModel(model, rawColor);
        if (color.isEmpty) continue;
        if (req[model]!.containsKey(color)) {
          req[model]![color] = (req[model]![color] ?? 0) + 1;
        }
      }
    }
    return req;
  }

  List<String> _validationErrors() {
    final errs = <String>[];
    for (final o in _orders) {
      final name = (o['name'] ?? '').trim();
      final baseModel = (o['model'] ?? '').trim();
      final baseColor = (o['color'] ?? '').trim();
      final count = _countOf(o);
      final models = _modelsListOf(o);
      final colors = _colorsListOf(o);

      for (int di = 0; di < count; di++) {
        final model = (di < models.length && models[di].isNotEmpty) ? models[di] : baseModel;
        if (model.isEmpty || !widget.modelColors.containsKey(model)) {
          errs.add('❌ موديل غير معروف (جهاز ${di + 1}) للعميل: ${name.isEmpty ? '-' : name}');
          break;
        }
        final rawColor = (di < colors.length && colors[di].isNotEmpty) ? colors[di] : baseColor;
        final color = _normalizeColorForModel(model, rawColor);
        if (color.isEmpty || !widget.modelColors[model]!.contains(color)) {
          errs.add('❌ لون غير معروف (جهاز ${di + 1}) للعميل: ${name.isEmpty ? '-' : name}');
          break;
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
      _normalizeOrderColorsForModels(o);
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
                final modelsList = _modelsListOf(o);

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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      final mList = _modelsListOf(o);
                                      final base = mList.isNotEmpty ? mList.first : (o['model'] ?? '').trim();
                                      final fallbackModel = widget.modelColors.containsKey(base)
                                          ? base
                                          : (widget.modelColors.keys.isNotEmpty ? widget.modelColors.keys.first : '');
                                      _setModelsList(o, List<String>.filled(safeCount, fallbackModel));

                                      final nextColors = <String>[];
                                      for (int i = 0; i < safeCount; i++) {
                                        final palette = widget.modelColors[fallbackModel] ?? const <String>[];
                                        nextColors.add(palette.isNotEmpty ? palette.first : '');
                                      }
                                      _setColorsList(o, nextColors);
                                    });
                                  },
                                  icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                                  label: const Text('نفس الموديل', maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      final base = (o['color'] ?? '').trim();
                                      final next = List<String>.filled(safeCount, base.isEmpty ? (colors.isNotEmpty ? colors.first : '') : base);
                                      _setColorsList(o, next);
                                      _normalizeOrderColorsForModels(o);
                                    });
                                  },
                                  icon: const Icon(Icons.palette_outlined, size: 18),
                                  label: const Text('نفس اللون', maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              ],
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
                      if (safeCount == 1)
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
                                    final nextModel = (v ?? '').trim();
                                    final palette = widget.modelColors[nextModel] ?? const <String>[];
                                    final currentColor = (o['color'] ?? '').trim();
                                    final mapped = nextModel.isNotEmpty ? _normalizeColorForModel(nextModel, currentColor) : currentColor;
                                    final nextColor = palette.contains(mapped) ? mapped : (palette.isNotEmpty ? palette.first : '');

                                    o['model'] = nextModel;
                                    o['color'] = nextColor;
                                    o.remove('colors');
                                    o.remove('models');
                                    o['count'] = '1';
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
                                onChanged: (v) => setState(() => o['color'] = v ?? ''),
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
                            "تفاصيل كل جهاز:",
                            textAlign: TextAlign.right,
                            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: List.generate(safeCount, (ci) {
                            final mList = _modelsListOf(o);
                            final currentModel = (ci < mList.length) ? mList[ci] : (o['model'] ?? '');
                            final palette = widget.modelColors[currentModel] ?? const <String>[];

                            final list = _colorsListOf(o);
                            final currentColor = (ci < list.length) ? list[ci] : (o['color'] ?? '');
                            return SizedBox(
                              width: 170,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DropdownButtonFormField<String>(
                                    value: widget.modelColors.containsKey(currentModel) ? currentModel : (widget.modelColors.keys.isNotEmpty ? widget.modelColors.keys.first : null),
                                    items: widget.modelColors.keys
                                        .map((m) => DropdownMenuItem(value: m, child: Text(m, textAlign: TextAlign.right)))
                                        .toList(),
                                    onChanged: (v) {
                                      setState(() {
                                        final nextModels = _modelsListOf(o);
                                        while (nextModels.length < safeCount) {
                                          nextModels.add((o['model'] ?? '').trim());
                                        }
                                        final nextModel = (v ?? '').trim();
                                        nextModels[ci] = nextModel;
                                        _setModelsList(o, nextModels);

                                        final palette2 = widget.modelColors[nextModel] ?? const <String>[];
                                        final nextColors = _colorsListOf(o);
                                        while (nextColors.length < safeCount) {
                                          nextColors.add((o['color'] ?? '').trim());
                                        }
                                        final candidate = nextModel.isNotEmpty ? _normalizeColorForModel(nextModel, nextColors[ci]) : nextColors[ci];
                                        if (candidate.isNotEmpty && palette2.contains(candidate)) {
                                          nextColors[ci] = candidate;
                                        } else {
                                          final fallback = palette2.isNotEmpty ? palette2.first : '';
                                          if (fallback.isNotEmpty && !palette2.contains(nextColors[ci])) {
                                            nextColors[ci] = fallback;
                                          }
                                        }
                                        _setColorsList(o, nextColors);
                                        _normalizeOrderColorsForModels(o);
                                      });
                                    },
                                    decoration: InputDecoration(
                                      labelText: "موديل ${ci + 1}",
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: palette.contains(currentColor) ? currentColor : (palette.isNotEmpty ? palette.first : null),
                                    items: palette.map((c) => DropdownMenuItem(value: c, child: Text(c, textAlign: TextAlign.right))).toList(),
                                    onChanged: (v) {
                                      setState(() {
                                        final next = _colorsListOf(o);
                                        while (next.length < safeCount) {
                                          next.add((o['color'] ?? '').trim());
                                        }
                                        if (v != null && v.isNotEmpty) next[ci] = v;
                                        _setColorsList(o, next);
                                        _normalizeOrderColorsForModels(o);
                                      });
                                    },
                                    decoration: InputDecoration(
                                      labelText: "لون ${ci + 1}",
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ],
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
