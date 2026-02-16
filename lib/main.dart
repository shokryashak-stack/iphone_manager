import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'ai_assistant_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDark = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A84FF),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF050505),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A84FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF111111),
        ),
      ),
      home: const IphoneProfitCalculator(),
    );
  }
}

class IphoneProfitCalculator extends StatefulWidget {
  const IphoneProfitCalculator({super.key});

  @override
  State<IphoneProfitCalculator> createState() => _IphoneProfitCalculatorState();
}

class _IphoneProfitCalculatorState extends State<IphoneProfitCalculator> {
  final TextEditingController collectionController = TextEditingController();
  final TextEditingController expensesController = TextEditingController();
  final TextEditingController count15Controller = TextEditingController();
  final TextEditingController count16Controller = TextEditingController();
  final TextEditingController count17Controller = TextEditingController();

  double price15ProMax = 45000.0;
  double price16ProMax = 55000.0;
  double price17ProMax = 65000.0;
  int stock15 = 0;
  int stock16 = 0;
  int stock17 = 0;
  List<String> inventoryLog = [];
  final List<Map<String, String>> orders = [
    {'name': 'عميل تجريبي', 'governorate': 'القاهرة'},
  ];
  static const Map<String, List<String>> _stockModels = {
    '15 Pro Max': ['سلفر', 'اسود', 'ازرق'],
    '16 Pro Max': ['سلفر', 'دهبي', 'اسود'],
    '17 Pro Max': ['برتقالي', 'سلفر', 'اسود', 'دهبي', 'تيتانيوم', 'كحلي'],
  };
  Map<String, Map<String, int>> colorStock = {};

  double netProfit = 0.0;
  double myShare = 0.0;
  double partnerShare = 0.0;
  double myAccountBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      price15ProMax = prefs.getDouble('p15') ?? 45000.0;
      price16ProMax = prefs.getDouble('p16') ?? 55000.0;
      price17ProMax = prefs.getDouble('p17') ?? 65000.0;
      stock15 = prefs.getInt('s15') ?? 0;
      stock16 = prefs.getInt('s16') ?? 0;
      stock17 = prefs.getInt('s17') ?? 0;
      inventoryLog = prefs.getStringList('inv_log') ?? [];
      myAccountBalance = prefs.getDouble('my_account_balance') ?? 0.0;
      colorStock = _createDefaultColorStock();

      final savedColorStock = prefs.getString('color_stock_v1');
      if (savedColorStock != null && savedColorStock.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedColorStock) as Map<String, dynamic>;
          decoded.forEach((model, colors) {
            if (!_stockModels.containsKey(model) || colors is! Map<String, dynamic>) return;
            final target = colorStock[model]!;
            for (final color in target.keys) {
              target[color] = (colors[color] as num?)?.toInt() ?? 0;
            }
          });
        } catch (_) {
          // Keep default map if stored JSON is corrupted.
        }
      } else {
        colorStock['15 Pro Max']!['سلفر'] = stock15;
        colorStock['16 Pro Max']!['سلفر'] = stock16;
        colorStock['17 Pro Max']!['سلفر'] = stock17;
      }

      _syncTotalsFromColorStock();
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('p15', price15ProMax);
    await prefs.setDouble('p16', price16ProMax);
    await prefs.setDouble('p17', price17ProMax);
    await prefs.setInt('s15', stock15);
    await prefs.setInt('s16', stock16);
    await prefs.setInt('s17', stock17);
    await prefs.setStringList('inv_log', inventoryLog);
    await prefs.setDouble('my_account_balance', myAccountBalance);
    await prefs.setString('color_stock_v1', jsonEncode(colorStock));
  }

  Map<String, Map<String, int>> _createDefaultColorStock() {
    return {
      for (final model in _stockModels.keys)
        model: {
          for (final color in _stockModels[model]!) color: 0,
        },
    };
  }

  void _syncTotalsFromColorStock() {
    stock15 = colorStock['15 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    stock16 = colorStock['16 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    stock17 = colorStock['17 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? 0;
  }

  Map<String, Map<String, int>> _cloneColorStock(Map<String, Map<String, int>> source) {
    return {
      for (final entry in source.entries) entry.key: Map<String, int>.from(entry.value),
    };
  }

  void _deductFromColorStock(String model, int quantity) {
    if (quantity <= 0) return;
    final modelMap = colorStock[model];
    if (modelMap == null) return;

    int remaining = quantity;
    for (final color in _stockModels[model]!) {
      if (remaining <= 0) break;
      final available = modelMap[color] ?? 0;
      if (available <= 0) continue;
      final take = available >= remaining ? remaining : available;
      modelMap[color] = available - take;
      remaining -= take;
    }
  }

  String _normalizeModelFromAi(String model) {
    final m = model.trim().toLowerCase();
    if (m == '15' || m.contains('15')) return '15 Pro Max';
    if (m == '16' || m.contains('16')) return '16 Pro Max';
    if (m == '17' || m.contains('17')) return '17 Pro Max';
    return '';
  }

  Future<String> _deleteOrderAction(String name, String? governorate) async {
    final before = orders.length;
    orders.removeWhere((o) {
      final sameName = (o['name'] ?? '').trim() == name.trim();
      if (!sameName) return false;
      if (governorate == null || governorate.trim().isEmpty) return true;
      return (o['governorate'] ?? '').trim() == governorate.trim();
    });
    final removed = before - orders.length;
    await _addLogEntry("حذف أوردر", "الاسم: $name\nالعدد المحذوف: $removed");
    return removed > 0
        ? "✅ حاضر يا هندسة، مسحت أوردر العميل ($name)"
        : "⚠️ ملقتش أوردر بالاسم ده: $name";
  }

  Future<String> _cancelOrderAction(String name, String? governorate) async {
    final before = orders.length;
    orders.removeWhere((o) {
      final sameName = (o['name'] ?? '').trim() == name.trim();
      if (!sameName) return false;
      if (governorate == null || governorate.trim().isEmpty) return true;
      return (o['governorate'] ?? '').trim() == governorate.trim();
    });
    final removed = before - orders.length;
    await _addLogEntry("إلغاء أوردر", "الاسم: $name\nالعدد الملغي: $removed");
    return removed > 0
        ? "✅ تم إلغاء أوردر العميل ($name)"
        : "⚠️ ملقتش أوردر لإلغاءه بالاسم ده: $name";
  }

  Future<String> _addStockAction(String model, String color, int count) async {
    final modelKey = _normalizeModelFromAi(model);
    if (modelKey.isEmpty || !_stockModels.containsKey(modelKey)) {
      return "❌ موديل غير معروف: $model";
    }
    if (count <= 0) {
      return "❌ العدد لازم يكون أكبر من صفر";
    }

    String resolvedColor = color.trim();
    final knownColors = _stockModels[modelKey]!;
    final exact = knownColors.where((c) => c == resolvedColor).toList();
    if (exact.isEmpty) {
      final fallback = knownColors.firstWhere(
        (c) => c.toLowerCase() == resolvedColor.toLowerCase(),
        orElse: () => '',
      );
      if (fallback.isEmpty) {
        return "❌ اللون غير موجود للموديل $modelKey: $color";
      }
      resolvedColor = fallback;
    }

    setState(() {
      colorStock[modelKey]![resolvedColor] = (colorStock[modelKey]![resolvedColor] ?? 0) + count;
      _syncTotalsFromColorStock();
    });
    await _addLogEntry("توريد AI", "الموديل: $modelKey\nاللون: $resolvedColor\nالعدد: +$count");
    return "📦 تمام، زودت المخزن بـ $count أجهزة $modelKey - $resolvedColor";
  }

  Future<String> _checkStockAction() async {
    _syncTotalsFromColorStock();
    return "📊 إجمالي المخزن الآن:\n15 Pro Max: $stock15\n16 Pro Max: $stock16\n17 Pro Max: $stock17";
  }

  void _openAiAssistant() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIAssistantScreen(
          onDeleteOrder: _deleteOrderAction,
          onCancelOrder: _cancelOrderAction,
          onAddStock: _addStockAction,
          onCheckStock: _checkStockAction,
        ),
      ),
    );
  }

  // دالة مسح المخزون فقط مع التأكيد
  void _confirmClearStock() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _dialogBorder(context)),
        ),
        title: const Text("مسح المخزون", textAlign: TextAlign.right),
        content: const Text("هل أنت متأكد من مسح كل كميات المخزون؟ سيتم تصفير مخزون الأجهزة فقط.", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() {
                colorStock = _createDefaultColorStock();
                _syncTotalsFromColorStock();
                count15Controller.clear();
                count16Controller.clear();
                count17Controller.clear();
              });
              await _addLogEntry("مسح مخزون", "تم تصفير كل كميات الأجهزة من القائمة الجانبية");
              await _saveData();
              if (!mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              messenger.showSnackBar(const SnackBar(content: Text("تم مسح المخزون بنجاح")));
            }, 
            child: const Text("نعم، امسح المخزون", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  void _clearInputs() {
    collectionController.clear(); expensesController.clear();
    count15Controller.clear(); count16Controller.clear(); count17Controller.clear();
  }

  Future<void> _addLogEntry(String actionType, String details) async {
    DateTime now = DateTime.now();
    String formattedDate = "${now.year}/${now.month}/${now.day} - ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    String newEntry = "[$formattedDate] $actionType:\n$details";
    setState(() { inventoryLog.insert(0, newEntry); });
    await _saveData();
  }

  Future<void> _importJAndTSheet() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );

    if (!mounted || result == null) return;

    try {
      List<List<dynamic>> rows = [];
      String ext = (result.files.single.extension ?? '').toLowerCase();
      final filePath = result.files.single.path;
      if (filePath == null || filePath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تعذر قراءة مسار الملف")));
        return;
      }

      if (ext == 'xlsx' || ext == 'xls') {
        var bytes = File(filePath).readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);
        String? selectedTable;
        int bestScore = -1;

        for (final table in excel.tables.keys) {
          final sheetRows = excel.tables[table]!.rows;
          if (sheetRows.isEmpty) continue;
          final headerRow = sheetRows.first.map((c) => (c?.value ?? '').toString().toLowerCase()).toList();
          final tableName = table.toLowerCase();

          var score = 0;
          if (tableName.contains('monthly bill details')) score += 10;
          if (headerRow.any((h) => h.contains('cod amount'))) score += 6;
          if (headerRow.any((h) => h.contains('cod service fee'))) score += 6;
          if (headerRow.any((h) => h.contains('total freight') || h.contains('shipping'))) score += 5;
          if (headerRow.any((h) => h.contains('signing status'))) score += 3;
          score += sheetRows.length ~/ 20;

          if (score > bestScore) {
            bestScore = score;
            selectedTable = table;
          }
        }

        if (selectedTable == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لم يتم العثور على شيت صالح للتحليل")));
          return;
        }

        for (var row in excel.tables[selectedTable]!.rows) {
          rows.add(row.map((cell) => cell?.value).toList());
        }
      } else {
        final input = File(filePath).readAsStringSync();
        rows = const CsvToListConverter().convert(input);
      }

      if (rows.isEmpty) return;
      final headers = rows.first.map((h) => h.toString().toLowerCase().trim()).toList();

      int findHeaderIndex(List<String> keys) {
        for (int i = 0; i < headers.length; i++) {
          final h = headers[i];
          for (final k in keys) {
            if (h.contains(k)) return i;
          }
        }
        return -1;
      }

      int findHeaderByAll(List<String> keys) {
        for (int i = 0; i < headers.length; i++) {
          final h = headers[i];
          if (keys.every((k) => h.contains(k))) return i;
        }
        return -1;
      }

      int amountIndex = findHeaderIndex(['cod amount', 'amount cod', 'cod amt', 'تحصيل']);
      if (amountIndex == -1) amountIndex = findHeaderByAll(['cod', 'amount']);

      int feeIndex = findHeaderIndex(['cod service fee', 'service fee', 'cod fee', 'رسوم']);
      if (feeIndex == -1) feeIndex = findHeaderByAll(['cod', 'fee']);

      int shippingIndex = findHeaderIndex(['total freight', 'shipping cost', 'shipping fee', 'shipping', 'freight', 'شحن']);

      if (amountIndex == -1 || feeIndex == -1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("مش لاقي أعمدة COD Amount / COD Service Fee")));
        return;
      }

      double totalCodAmount = 0.0;
      double totalServiceFee = 0.0;
      double totalShipping = 0.0;
      double totalNet = 0.0;
      double totalDeductions = 0.0;
      int count = 0;

      // متغيرات لتحديد الأجهزة تلقائياً بناءً على السعر
      int auto15 = 0;
      int auto16 = 0;
      int auto17 = 0;
      int cashDeliveredCount = 0;
      const manualTransferCodMax = 1.5;

      for (int i = 1; i < rows.length; i++) {
        var row = rows[i];
        if (row.isNotEmpty) {
          dynamic cellAt(int idx) => (idx >= 0 && idx < row.length) ? row[idx] : null;

          double amount = _toDoubleSafe(cellAt(amountIndex));
          double fee = _toDoubleSafe(cellAt(feeIndex));
          double shipping = shippingIndex != -1 ? _toDoubleSafe(cellAt(shippingIndex)) : 0.0;

          if (shipping > 0) {
            totalShipping += shipping;
          }

          final isExternalTransfer = amount > 0 && amount <= manualTransferCodMax;

          // الشحنة تُعتبر "متسلّمة" فقط لو في COD Service Fee
          final isDelivered = fee > 0;

          if (isDelivered && isExternalTransfer) {
            cashDeliveredCount++;
          }

          if (isDelivered && amount > 0 && !isExternalTransfer) {
            totalCodAmount += amount;
            totalServiceFee += fee;
            count++;

            // منطق التحديد التلقائي بناءً على رينج البيع
            if (amount >= 5000 && amount <= 5500) {
              auto15++;
            } else if (amount >= 5600 && amount <= 6000) {
              auto16++;
            } else if (amount >= 6100 && amount <= 6500) {
              auto17++;
            }
          }
        }
      }

      totalDeductions = totalServiceFee + totalShipping;
      totalNet = totalCodAmount - totalDeductions;

      int cash15 = 0;
      int cash16 = 0;
      int cash17 = 0;

      if (cashDeliveredCount > 0) {
        final cashModels = await _showCashDeliveredDeviceDialog(cashDeliveredCount);
        if (!mounted) return;
        if (cashModels != null) {
          cash15 = cashModels['15'] ?? 0;
          cash16 = cashModels['16'] ?? 0;
          cash17 = cashModels['17'] ?? 0;
        }
      }

      setState(() { 
        collectionController.text = totalNet.toStringAsFixed(2);
        count15Controller.text = (auto15 + cash15).toString();
        count16Controller.text = (auto16 + cash16).toString();
        count17Controller.text = (auto17 + cash17).toString();
      });
      _showResultDialog(
        count + cashDeliveredCount,
        totalDeductions,
        totalNet,
        auto15 + cash15,
        auto16 + cash16,
        auto17 + cash17,
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("? خطأ: $e")));
    }
  }

  void _showResultDialog(int count, double ded, double net, int a15, int a16, int a17) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _dialogBorder(context)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "تم تحليل الشيت بنجاح",
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _analysisMetricRow("الأوردرات المستلمة", count.toString()),
                    const SizedBox(height: 8),
                    _analysisMetricRow("إجمالي الخصومات", "${ded.toStringAsFixed(2)} ج.م"),
                    const SizedBox(height: 8),
                    _analysisMetricRow(
                      "الصافي المحول",
                      "${net.toStringAsFixed(2)} ج.م",
                      highlight: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "الأجهزة المتعرف عليها",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _analysisDeviceRow("15 Pro Max", a15, count, const Color(0xFF5AC8FA)),
                    const SizedBox(height: 8),
                    _analysisDeviceRow("16 Pro Max", a16, count, const Color(0xFFFF9F0A)),
                    const SizedBox(height: 8),
                    _analysisDeviceRow("17 Pro Max", a17, count, const Color(0xFF30D158)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("إغلاق"),
            ),
          ),
        ],
      ),
    );
  }

  // دالة مسح سجل الحركات فقط مع التأكيد
  void _confirmClearLog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _dialogBorder(context)),
        ),
        title: const Text("مسح سجل الحركات", textAlign: TextAlign.right),
        content: const Text("هل أنت متأكد من مسح كل عناصر سجل الحركات؟", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() {
                inventoryLog.clear();
              });
              await _saveData();
              if (!mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              messenger.showSnackBar(const SnackBar(content: Text("تم مسح سجل الحركات")));
            },
            child: const Text("نعم، امسح السجل", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<Map<String, int>?> _showCashDeliveredDeviceDialog(int cashDeliveredCount) {
    final c15 = TextEditingController();
    final c16 = TextEditingController();
    final c17 = TextEditingController();

    return showDialog<Map<String, int>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _dialogBorder(context)),
        ),
        title: const Text(
          "شحنات متسلّمة كاش",
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "تم العثور على $cashDeliveredCount شحنة متسلّمة بقيمة 1 جنيه.\nحدد موديل الأجهزة:",
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              _stockField(c15, "15 Pro Max"),
              const SizedBox(height: 8),
              _stockField(c16, "16 Pro Max"),
              const SizedBox(height: 8),
              _stockField(c17, "17 Pro Max"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, {'15': 0, '16': 0, '17': 0}),
            child: const Text("تخطي", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () {
              final v15 = int.tryParse(c15.text) ?? 0;
              final v16 = int.tryParse(c16.text) ?? 0;
              final v17 = int.tryParse(c17.text) ?? 0;
              final total = v15 + v16 + v17;

              if (total != cashDeliveredCount) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("مجموع الأجهزة لازم يساوي $cashDeliveredCount")),
                );
                return;
              }

              Navigator.pop(ctx, {'15': v15, '16': v16, '17': v17});
            },
            child: const Text("تأكيد", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _analysisMetricRow(String label, String value, {bool highlight = false}) => Row(
    children: [
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: highlight ? Colors.green : null,
          fontSize: 20,
        ),
      ),
      const Spacer(),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
    ],
  );

  Widget _analysisDeviceRow(String model, int modelCount, int totalCount, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Text(
          totalCount > 0 ? "${((modelCount / totalCount) * 100).toStringAsFixed(0)}%" : "0%",
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(width: 8),
        Container(
          width: 44,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            modelCount.toString(),
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 26),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            model,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ],
    ),
  );

  void calculateProfit() {
    double totalColl = double.tryParse(collectionController.text) ?? 0.0;
    double totalExp = double.tryParse(expensesController.text) ?? 0.0;
    double cost = ( (double.tryParse(count15Controller.text) ?? 0) * price15ProMax) + 
                  ( (double.tryParse(count16Controller.text) ?? 0) * price16ProMax) + 
                  ( (double.tryParse(count17Controller.text) ?? 0) * price17ProMax);
    setState(() {
      netProfit = totalColl - cost - totalExp;
      myShare = netProfit / 2; partnerShare = netProfit / 2;
    });
  }

  void confirmAndDeduct() {
    int s15 = int.tryParse(count15Controller.text) ?? 0;
    int s16 = int.tryParse(count16Controller.text) ?? 0;
    int s17 = int.tryParse(count17Controller.text) ?? 0;
    if (s15 > stock15 || s16 > stock16 || s17 > stock17) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("المخزن لا يكفي!"), backgroundColor: Colors.red));
      return;
    }
    calculateProfit();
    setState(() {
      _deductFromColorStock('15 Pro Max', s15);
      _deductFromColorStock('16 Pro Max', s16);
      _deductFromColorStock('17 Pro Max', s17);
      _syncTotalsFromColorStock();
      myAccountBalance += myShare;
    });
    _addLogEntry("مبيعات", "بيع: (15:$s15, 16:$s16, 17:$s17)\nالمتبقي: (15:$stock15, 16:$stock16)");
    _clearInputs();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF050505) : const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'حاسبة البيزنس الاحترافية',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2, fontSize: 20),
        ),
        centerTitle: true, 
        backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: _buildDrawer(isDark),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0A0A0A), Color(0xFF050505)],
                )
              : null,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle("بيانات التحصيل"),
              _buildSectionCard(
                isDark: isDark,
                child: Column(
                  children: [
                    _buildImportBtn(),
                    const SizedBox(height: 12),
                    _buildInput(collectionController, 'صافي التحصيل من J&T', Icons.payments, isDark),
                    const SizedBox(height: 12),
                    _buildInput(expensesController, 'مصاريف إضافية', Icons.money_off, isDark),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle("الأجهزة المباعة الآن"),
              _buildSectionCard(
                isDark: isDark,
                child: Column(
                  children: [
                    _buildDeviceRow("15 Pro Max", stock15, count15Controller),
                    const SizedBox(height: 10),
                    _buildDeviceRow("16 Pro Max", stock16, count16Controller),
                    const SizedBox(height: 10),
                    _buildDeviceRow("17 Pro Max", stock17, count17Controller),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildResultCard(isDark),
              const SizedBox(height: 24),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 17,
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
      ),
    ),
  );

  Widget _buildSectionCard({required bool isDark, required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF121212) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      boxShadow: isDark
          ? const []
          : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: child,
  );

  Widget _buildResultCard(bool isDark) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF191919), Color(0xFF0B0B0B)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1F2937), Color(0xFF111827)],
              ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(children: [
        const Text("صافي الربح", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 18)),
        Text("${netProfit.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 48, fontWeight: FontWeight.w900)),
        const Divider(color: Colors.white24, height: 30),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _shareInfo("نصيبك", myShare), _shareInfo("الشريك", partnerShare),
        ]),
      ]),
    );
  }

  Widget _shareInfo(String label, double val) => Column(children: [
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 16)),
    Text(val.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
  ]);

  Widget _buildImportBtn() => SizedBox(width: double.infinity, child: ElevatedButton.icon(
    onPressed: _importJAndTSheet, icon: const Icon(Icons.file_present), label: const Text("سحب شيت (Excel/CSV)"),
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF0A84FF),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.all(15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ));

  Widget _buildInput(TextEditingController ctrl, String label, IconData icon, bool isDark) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    decoration: InputDecoration(
      prefixIcon: Icon(icon, size: 24),
      labelText: label,
      labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
  );

  Widget _buildDeviceRow(String label, int stock, TextEditingController ctrl) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 2),
              Text(
                "المخزون: $stock",
                style: TextStyle(
                  fontSize: 15,
                  color: stock > 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 88,
          child: TextField(
            controller: ctrl,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: "0",
              hintStyle: const TextStyle(fontSize: 20),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.zero,
            ),
          )
        ),
      ],
    ),
  );

  Widget _buildActionButtons() => Row(children: [
    Expanded(
      flex: 2,
      child: ElevatedButton(
        onPressed: confirmAndDeduct,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0A84FF),
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Text("تأكيد وخصم مخزن", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: OutlinedButton(
        onPressed: calculateProfit,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 60),
          side: const BorderSide(color: Color(0xFF3A3A3C)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Text("احسب الربح", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
    ),
  ]);

  Drawer _buildDrawer(bool isDark) => Drawer(
    backgroundColor: isDark ? const Color(0xFF101114) : Colors.white,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text(
            "القائمة",
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.pop(context);
              _showMyAccountDialog();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF181A1F) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? const Color(0xFF2F3440) : const Color(0xFFD1D5DB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF64D2FF), size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "${myAccountBalance.toStringAsFixed(2)} ج.م",
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF64D2FF)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "حسابي",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _drawerTile(
            icon: Icons.inventory_2_rounded,
            title: "المخزن",
            onTap: () { Navigator.pop(context); _openWarehousePage(); },
          ),
          _drawerTile(
            icon: Icons.history_edu_rounded,
            title: "سجل الحركات",
            onTap: () { Navigator.pop(context); _showLog(); },
          ),
          _drawerTile(
            icon: Icons.smart_toy_rounded,
            title: "مساعد AI",
            onTap: () { Navigator.pop(context); _openAiAssistant(); },
          ),
          _drawerTile(
            icon: Icons.delete_sweep_rounded,
            title: "مسح كل المخزون",
            danger: true,
            onTap: () { Navigator.pop(context); _confirmClearStock(); },
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: isDark ? Colors.white12 : Colors.black12),
          const SizedBox(height: 8),
          _drawerTile(
            icon: Icons.settings_rounded,
            title: "أسعار الشراء",
            onTap: () { Navigator.pop(context); _showPriceDialog(); },
          ),
        ],
      ),
    ),
  );

  Widget _drawerTile({
    required IconData icon,
    required String title,
    bool danger = false,
    required VoidCallback onTap,
  }) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFF2B1616) : const Color(0xFF161A20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: danger ? const Color(0xFFFF453A).withValues(alpha: 0.4) : const Color(0xFF2D3340),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: danger ? const Color(0xFFFF453A).withValues(alpha: 0.18) : const Color(0xFF64D2FF).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: danger ? const Color(0xFFFF453A) : const Color(0xFF64D2FF), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: danger ? const Color(0xFFFF6B62) : const Color(0xFFF3F4F6),
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: danger ? const Color(0xFFFF6B62) : const Color(0xFF8E8E93),
          ),
        ],
      ),
    ),
  );
  Future<void> _openWarehousePage() async {
    final updatedStock = await Navigator.push<Map<String, Map<String, int>>>(
      context,
      MaterialPageRoute(
        builder: (_) => WarehousePage(initialStock: _cloneColorStock(colorStock)),
      ),
    );

    if (!mounted || updatedStock == null) return;
    setState(() {
      colorStock = updatedStock;
      _syncTotalsFromColorStock();
    });
    await _saveData();
    await _addLogEntry(
      "تعديل مخزن",
      "تحديث كميات المخزن من صفحة المخزن\nالإجمالي: (15:$stock15, 16:$stock16, 17:$stock17)",
    );
  }
  void _showLog() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _dialogBorder(context)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: const Text("سجل الحركات", textAlign: TextAlign.right),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: inventoryLog.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 44, color: isDark ? Colors.white54 : Colors.black45),
                      const SizedBox(height: 8),
                      const Text("لا توجد حركات مسجلة بعد"),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: inventoryLog.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (c, i) => _buildLogItem(inventoryLog [i], isDark),
                ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: inventoryLog.isEmpty ? null : _confirmClearLog,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  label: const Text("مسح السجل"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("إغلاق"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stockField(TextEditingController ctrl, String label) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      hintText: "0",
      hintStyle: const TextStyle(fontSize: 18),
      filled: true,
      fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );

  Widget _buildLogItem(String entry, bool isDark) {
    final lines = entry.split('\n');
    final header = lines.isNotEmpty ? lines.first : entry;
    final details = lines.length > 1 ? lines.skip(1).join('\n') : '';
    final isSale = entry.contains('مبيعات');
    final isSupply = entry.contains('توريد');
    final color = isSale
        ? Colors.red
        : isSupply
            ? Colors.green
            : Colors.orange;
    final icon = isSale
        ? Icons.trending_down_rounded
        : isSupply
            ? Icons.add_box_rounded
            : Icons.inventory_2_rounded;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(header, textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ..._buildLogDetailsWidgets(details, color, isDark),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLogDetailsWidgets(String details, Color accent, bool isDark) {
    final result = <Widget>[];
    final lines = details
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final tripleRegExp = RegExp(r'15:([+\-]?\d+),\s*16:([+\-]?\d+),\s*17:([+\-]?\d+)');

    for (final line in lines) {
      final match = tripleRegExp.firstMatch(line);
      if (match != null) {
        result.add(
          _tripleValuesRow(
            _normalizeLogLineTitle(line),
            match.group(1)!,
            match.group(2)!,
            match.group(3)!,
            accent,
            isDark,
          ),
        );
      } else {
        result.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              line,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        );
      }
    }

    return result;
  }

  Widget _tripleValuesRow(
    String title,
    String v15,
    String v16,
    String v17,
    Color accent,
    bool isDark,
  ) => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: isDark ? 0.18 : 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: accent.withValues(alpha: 0.25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(
          children: [
            _deviceValuePill("17", v17, accent),
            const SizedBox(width: 6),
            _deviceValuePill("16", v16, accent),
            const SizedBox(width: 6),
            _deviceValuePill("15", v15, accent),
          ],
        ),
      ],
    ),
  );

  Widget _deviceValuePill(String model, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$model Pro Max",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            "$value جهاز",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );

  String _normalizeLogLineTitle(String line) {
    if (line.contains("إضافة")) return "الإضافة";
    if (line.contains("الرصيد بعد")) return "الرصيد بعد العملية";
    if (line.contains("قبل الجرد")) return "قبل الجرد";
    if (line.contains("بعد الجرد")) return "بعد الجرد";
    if (line.contains("بيع")) return "المبيعات";
    if (line.contains("المتبقي")) return "المتبقي";
    return "تفاصيل";
  }

  double _toDoubleSafe(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();

    String s = value.toString().trim();
    if (s.isEmpty || s == '-' || s == 'null') return 0.0;

    const arabicNums = {
      '\u0660': '0',
      '\u0661': '1',
      '\u0662': '2',
      '\u0663': '3',
      '\u0664': '4',
      '\u0665': '5',
      '\u0666': '6',
      '\u0667': '7',
      '\u0668': '8',
      '\u0669': '9',
      '\u06f0': '0',
      '\u06f1': '1',
      '\u06f2': '2',
      '\u06f3': '3',
      '\u06f4': '4',
      '\u06f5': '5',
      '\u06f6': '6',
      '\u06f7': '7',
      '\u06f8': '8',
      '\u06f9': '9',
    };
    arabicNums.forEach((k, v) => s = s.replaceAll(k, v));

    s = s.replaceAll('\u066b', '.').replaceAll('\u060c', ',').replaceAll(' ', '');

    final commaCount = ','.allMatches(s).length;
    if (commaCount > 0) {
      if (!s.contains('.') && commaCount == 1) {
        final part = s.split(',');
        final decimals = part.length == 2 ? part[1].length : 0;
        if (decimals <= 2) {
          s = s.replaceAll(',', '.');
        } else {
          s = s.replaceAll(',', '');
        }
      } else {
        s = s.replaceAll(',', '');
      }
    }

    s = s.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (s.isEmpty || s == '-' || s == '.') return 0.0;
    return double.tryParse(s) ?? 0.0;
  }

  void _showPriceDialog() {
    TextEditingController p15 = TextEditingController(text: price15ProMax.toString());
    TextEditingController p16 = TextEditingController(text: price16ProMax.toString());
    TextEditingController p17 = TextEditingController(text: price17ProMax.toString());
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _dialogBg(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _dialogBorder(context)),
      ),
      title: const Text("أسعار الشراء"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _priceField(p15, "سعر الـ 15"),
        const SizedBox(height: 8),
        _priceField(p16, "سعر الـ 16"),
        const SizedBox(height: 8),
        _priceField(p17, "سعر الـ 17"),
      ]),
      actions: [TextButton(onPressed: () {
        setState(() { price15ProMax = double.tryParse(p15.text) ?? price15ProMax; price16ProMax = double.tryParse(p16.text) ?? price16ProMax; price17ProMax = double.tryParse(p17.text) ?? price17ProMax; });
        _saveData(); Navigator.pop(ctx);
      }, child: const Text("تحديث"))],
    ));
  }

  void _showMyAccountDialog() {
    final ctrl = TextEditingController(text: myAccountBalance.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _dialogBorder(context)),
        ),
        title: const Text("حسابي"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                labelText: "رصيد حسابي",
                suffixText: "ج.م",
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () {
              final newValue = _toDoubleSafe(ctrl.text);
              setState(() {
                myAccountBalance = newValue;
              });
              _saveData();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحديث حسابي")));
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }

  Widget _priceField(TextEditingController ctrl, String label) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );

  Color _dialogBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF111111) : Colors.white;

  Color _dialogBorder(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12;
}













class WarehousePage extends StatefulWidget {
  const WarehousePage({super.key, required this.initialStock});

  final Map<String, Map<String, int>> initialStock;

  @override
  State<WarehousePage> createState() => _WarehousePageState();
}

class _WarehousePageState extends State<WarehousePage> {
  static const Map<String, List<String>> _modelColors = {
    '15 Pro Max': ['سلفر', 'اسود', 'ازرق'],
    '16 Pro Max': ['سلفر', 'دهبي', 'اسود'],
    '17 Pro Max': ['برتقالي', 'سلفر', 'اسود', 'دهبي', 'تيتانيوم', 'كحلي'],
  };

  late Map<String, Map<String, int>> stock;

  @override
  void initState() {
    super.initState();
    stock = {
      for (final model in _modelColors.keys)
        model: {
          for (final color in _modelColors[model]!)
            color: widget.initialStock[model]?[color] ?? 0,
        },
    };
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  int _modelTotal(String model) => stock[model]!.values.fold(0, (a, b) => a + b);

  int get _grandTotal => stock.values.fold(0, (sum, m) => sum + m.values.fold(0, (a, b) => a + b));

  void _changeQty(String model, String color, int delta) {
    final current = stock[model]![color] ?? 0;
    final next = current + delta;
    if (next < 0) return;
    setState(() {
      stock[model]![color] = next;
    });
  }

  Future<void> _editQty(String model, String color) async {
    final ctrl = TextEditingController(text: (stock[model]![color] ?? 0).toString());
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF111111) : Colors.white,
        title: Text('تعديل $model - $color', textAlign: TextAlign.right),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(hintText: '0'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text) ?? 0),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (value == null || value < 0) return;
    setState(() {
      stock[model]![color] = value;
    });
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF111111) : Colors.white,
        title: const Text('مسح المخزن', textAlign: TextAlign.right),
        content: const Text('تأكيد تصفير كل كميات المخزن؟', textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تصفير')),
        ],
      ),
    );

    if (ok != true) return;
    setState(() {
      for (final model in stock.keys) {
        for (final color in stock[model]!.keys) {
          stock[model]![color] = 0;
        }
      }
    });
  }

  void _saveAndBack() {
    Navigator.pop(context, {
      for (final entry in stock.entries) entry.key: Map<String, int>.from(entry.value),
    });
  }

  @override
  Widget build(BuildContext context) {
    final models = _modelColors.keys.toList();
    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF050505) : const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: _isDark ? const Color(0xFF0A0A0A) : Colors.black87,
        foregroundColor: Colors.white,
        title: const Text('المخزن', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'تصفير الكل',
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isDark ? const Color(0xFF121212) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _isDark ? Colors.white12 : Colors.black12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, color: Color(0xFF64D2FF)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('إجمالي الأجهزة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Text(
                    _grandTotal.toString(),
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF64D2FF)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    Expanded(child: _buildCompactModelCard(models[0])),
                    const SizedBox(height: 10),
                    Expanded(child: _buildCompactModelCard(models[1])),
                    const SizedBox(height: 10),
                    Expanded(child: _buildCompactModelCard(models[2])),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveAndBack,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('حفظ المخزن', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactModelCard(String model) {
    final colors = _modelColors[model]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF121212) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _isDark ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF64D2FF).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _modelTotal(model).toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Color(0xFF64D2FF),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  model,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: colors.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final color = colors[i];
                final qty = stock[model]![color] ?? 0;
                return Container(
                  width: 102,
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  decoration: BoxDecoration(
                    color: _isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _isDark ? Colors.white12 : const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      Text(color, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: () => _editQty(model, color),
                        child: Text(
                          qty.toString(),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _changeQty(model, color, -1),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(Icons.remove_rounded, size: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: InkWell(
                              onTap: () => _changeQty(model, color, 1),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A84FF).withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(Icons.add_rounded, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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







