import 'package:flutter/material.dart';

typedef CustomerKeyFn = String Function(Map<String, String> customer);
typedef GetCustomersFn = List<Map<String, String>> Function();
typedef NormalizePhonesFn = Future<int> Function();
typedef EditCustomerFn = Future<int?> Function(Map<String, String> customer);
typedef DeleteCustomerFn = Future<int?> Function(Map<String, String> customer);
typedef DeleteSelectedCustomersFn = Future<int?> Function(Set<String> customerKeys);
typedef SetCustomerStatusOverrideFn = Future<void> Function(String customerKey, String? statusCode);

class CustomersPage extends StatefulWidget {
  const CustomersPage({
    super.key,
    required this.getCustomers,
    required this.customerKey,
    required this.normalizePhones,
    required this.editCustomer,
    required this.deleteCustomer,
    required this.deleteSelectedCustomers,
    required this.setCustomerStatusOverride,
  });

  final GetCustomersFn getCustomers;
  final CustomerKeyFn customerKey;
  final NormalizePhonesFn normalizePhones;
  final EditCustomerFn editCustomer;
  final DeleteCustomerFn deleteCustomer;
  final DeleteSelectedCustomersFn deleteSelectedCustomers;
  final SetCustomerStatusOverrideFn setCustomerStatusOverride;

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _selectionMode = false;
  final Set<String> _selectedKeys = <String>{};
  late List<Map<String, String>> _customers;

  @override
  void initState() {
    super.initState();
    _customers = widget.getCustomers();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatIso(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return "${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}";
    } catch (_) {
      return iso;
    }
  }

  String _normArabic(String s) {
    // light normalization to keep both Arabic and digits searchable
    return s
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .toLowerCase();
  }

  String _onlyDigits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Color _statusColor(String code, bool isDark) {
    switch (code) {
      case 'delivered':
        return Colors.green;
      case 'review':
        return Colors.orange;
      case 'returned':
        return Colors.redAccent;
      case 'canceled':
        return isDark ? Colors.white54 : Colors.black45;
      case 'in_transit':
      default:
        return Colors.blueAccent;
    }
  }

  Future<void> _changeStatusForCustomer(String customerKey, String currentLabel) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text("تعديل الحالة", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text("الحالة الحالية: $currentLabel", textAlign: TextAlign.right),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.auto_mode_rounded),
                title: const Text("تلقائي"),
                subtitle: const Text("يرجع لحساب الحالة تلقائيًا"),
                onTap: () => Navigator.pop(ctx, null),
              ),
              ListTile(
                leading: const Icon(Icons.local_shipping_rounded),
                title: const Text("جاري التوصيل"),
                onTap: () => Navigator.pop(ctx, 'in_transit'),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_rounded, color: Colors.green),
                title: const Text("تم التسليم"),
                onTap: () => Navigator.pop(ctx, 'delivered'),
              ),
              ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                title: const Text("راجع"),
                onTap: () => Navigator.pop(ctx, 'review'),
              ),
              ListTile(
                leading: const Icon(Icons.assignment_return_rounded, color: Colors.redAccent),
                title: const Text("مرتجع"),
                onTap: () => Navigator.pop(ctx, 'returned'),
              ),
              ListTile(
                leading: const Icon(Icons.cancel_rounded),
                title: const Text("ملغي"),
                onTap: () => Navigator.pop(ctx, 'canceled'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );

    // canceled sheet
    if (!mounted) return;
    if (picked == null) {
      await widget.setCustomerStatusOverride(customerKey, null);
    } else {
      await widget.setCustomerStatusOverride(customerKey, picked);
    }
    if (!mounted) return;
    await _refresh();
  }

  void _applyFilter() {
    final qRaw = _searchCtrl.text.trim();
    final qName = _normArabic(qRaw);
    final qDigits = _onlyDigits(qRaw);

    final all = widget.getCustomers();
    if (qRaw.isEmpty) {
      setState(() => _customers = all);
      return;
    }

    setState(() {
      _customers = all.where((c) {
        final name = _normArabic(c['name'] ?? '');
        final gov = _normArabic(c['governorate'] ?? '');
        final address = _normArabic(c['address'] ?? '');
        final phone = _onlyDigits(c['phone'] ?? '');
        final phones = _onlyDigits(c['phones'] ?? '');

        final phoneMatch = qDigits.isNotEmpty && (phone.contains(qDigits) || phones.contains(qDigits));
        final textMatch = qName.isNotEmpty && (name.contains(qName) || gov.contains(qName) || address.contains(qName));
        return phoneMatch || textMatch;
      }).toList();
    });
  }

  Future<void> _refresh() async {
    setState(() => _customers = widget.getCustomers());
  }

  Future<void> _toggleSelectionMode() async {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedKeys.clear();
    });
  }

  Future<void> _selectAll() async {
    setState(() {
      for (final c in _customers) {
        _selectedKeys.add(widget.customerKey(c));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedKeys.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("مسح المحدد", textAlign: TextAlign.right),
        content: Text(
          "ده هيمسح كل أوردرات العملاء المحددين (${_selectedKeys.length}).\nمتأكد؟",
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("مسح", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    final removed = await widget.deleteSelectedCustomers(_selectedKeys);
    if (!mounted) return;
    if (removed != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم مسح $removed أوردر")));
    }
    setState(() {
      _selectedKeys.clear();
      _selectionMode = false;
      _customers = widget.getCustomers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("داتا العملاء"),
        actions: [
          IconButton(
            tooltip: "تنظيف الأرقام",
            onPressed: () async {
              final changed = await widget.normalizePhones();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم تنظيف أرقام الهواتف (تحديث $changed أوردر)")));
              await _refresh();
            },
            icon: const Icon(Icons.cleaning_services_rounded),
          ),
          IconButton(
            tooltip: _selectionMode ? "إلغاء التحديد" : "تحديد",
            onPressed: _toggleSelectionMode,
            icon: Icon(_selectionMode ? Icons.check_box_outline_blank_rounded : Icons.checklist_rounded),
          ),
          if (_selectionMode)
            IconButton(
              tooltip: "تحديد الكل",
              onPressed: _selectAll,
              icon: const Icon(Icons.select_all_rounded),
            ),
          if (_selectionMode)
            IconButton(
              tooltip: "مسح المحدد",
              onPressed: _selectedKeys.isEmpty ? null : _deleteSelected,
              icon: Icon(Icons.delete_sweep_rounded, color: _selectedKeys.isEmpty ? null : Colors.red),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: "ابحث بالاسم أو الرقم أو العنوان",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          FocusScope.of(context).unfocus();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _customers.isEmpty
                ? const Center(child: Text("لا يوجد عملاء"))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _customers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = _customers[i];
                      final cnt = c['orders_count'] ?? '0';
                      final lastAt = c['last_order_at'] ?? '';
                      final extraPhones = (c['phones'] ?? '').trim();
                      final statusLabel = (c['status_label'] ?? '').trim();
                      final statusSummary = (c['status_summary'] ?? '').trim();
                      final statusCode = (c['status_last'] ?? '').trim();
                      final statusManual = (c['status_manual'] ?? '').trim() == 'true';
                      final key = widget.customerKey(c);
                      final selected = _selectedKeys.contains(key);

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            if (_selectionMode) {
                              setState(() {
                                if (selected) {
                                  _selectedKeys.remove(key);
                                } else {
                                  _selectedKeys.add(key);
                                }
                              });
                              return;
                            }
                            final updated = await widget.editCustomer(c);
                            if (!mounted) return;
                            if (updated != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم تحديث $updated أوردر لهذا العميل")));
                            }
                            await _refresh();
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  if (_selectionMode)
                                    Checkbox(
                                      value: selected,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selectedKeys.add(key);
                                          } else {
                                            _selectedKeys.remove(key);
                                          }
                                        });
                                      },
                                    )
                                  else
                                    IconButton(
                                      tooltip: "مسح العميل",
                                      onPressed: () async {
                                        final removed = await widget.deleteCustomer(c);
                                        if (!mounted) return;
                                        if (removed != null) {
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم مسح $removed أوردر")));
                                        }
                                        await _refresh();
                                      },
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    ),
                                  const Spacer(),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      c['name'] ?? '-',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text("الهاتف: ${c['phone'] ?? '-'}"),
                              if (extraPhones.isNotEmpty) Text("أرقام إضافية: $extraPhones"),
                              Text("المحافظة: ${c['governorate'] ?? '-'}"),
                              Text("العنوان: ${(c['address'] ?? '').isEmpty ? '-' : c['address']!}"),
                              Text("عدد الأوردرات: $cnt"),
                              if (statusLabel.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _changeStatusForCustomer(key, statusLabel),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          if (statusManual)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(99),
                                              ),
                                              child: const Text("يدوي", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                                            ),
                                          if (statusManual) const SizedBox(width: 8),
                                          const Icon(Icons.edit_rounded, size: 18),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              "الحالة: $statusLabel",
                                              textAlign: TextAlign.right,
                                              style: TextStyle(fontWeight: FontWeight.w800, color: _statusColor(statusCode, isDark)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: _statusColor(statusCode, isDark),
                                              borderRadius: BorderRadius.circular(99),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (statusSummary.isNotEmpty)
                                Text(
                                  "ملخص: $statusSummary",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w600),
                                ),
                              if (lastAt.isNotEmpty) Text("آخر أوردر: ${_formatIso(lastAt)}"),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
