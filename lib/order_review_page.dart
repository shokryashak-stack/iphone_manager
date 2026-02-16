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
  }

  Map<String, Map<String, int>> _requiredCounts() {
    final req = _defaultCounts;
    for (final o in _orders) {
      final m = (o['model'] ?? '').trim();
      final c = (o['color'] ?? '').trim();
      if (req.containsKey(m) && req[m]!.containsKey(c)) {
        req[m]![c] = (req[m]![c] ?? 0) + 1;
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
      if (color.isEmpty || !widget.modelColors[model]!.contains(color)) {
        errs.add('❌ لون غير معروف للعميل: ${name.isEmpty ? '-' : name}');
        continue;
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
