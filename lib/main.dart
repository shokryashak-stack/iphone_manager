import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:http/http.dart' as http;
import 'config.dart';
import 'ai_assistant_screen.dart';
import 'order_review_page.dart';
import 'customers_page.dart';

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
  final List<Map<String, String>> orders = [];
  final List<Map<String, String>> customers = [];
  
  static const Map<String, List<String>> _stockModels = {
    '15 Pro Max': ['ط³ظ„ظپط±', 'ط§ط³ظˆط¯', 'ط§ط²ط±ظ‚'],
    '16 Pro Max': ['ط³ظ„ظپط±', 'ط¯ظ‡ط¨ظٹ', 'ط§ط³ظˆط¯'],
    '17 Pro Max': ['ط¨ط±طھظ‚ط§ظ„ظٹ', 'ط³ظ„ظپط±', 'ط§ط³ظˆط¯', 'ط¯ظ‡ط¨ظٹ', 'طھظٹطھط§ظ†ظٹظˆظ…', 'ظƒط­ظ„ظٹ'],
  };

  static const int _reviewAfterDays = 5;
  static const String _customerStatusOverridePrefsKey = 'customer_status_override_v1';
  final Map<String, String> _customerStatusOverrides = {};
  
  Map<String, Map<String, int>> colorStock = {};
  Map<String, Map<String, int>> homeColorStock = {};
  int homeStock15 = 0;
  int homeStock16 = 0;
  int homeStock17 = 0;

  double netProfit = 0.0;
  double myShare = 0.0;
  double partnerShare = 0.0;
  double myAccountBalance = 0.0;
  List<Map<String, String>> _lastSheetMatchedRows = <Map<String, String>>[];
  List<Map<String, String>> _lastSheetUnmatchedRows = <Map<String, String>>[];
  String _lastSheetAnalysisAt = '';

  final List<_UndoSnapshot> _undoStack = [];
  static const int _maxUndoDepth = 50;
  static const String _undoPrefsKey = 'undo_stack_v2';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    collectionController.dispose();
    expensesController.dispose();
    count15Controller.dispose();
    count16Controller.dispose();
    count17Controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final undoEncoded = prefs.getString(_undoPrefsKey);
    List<_UndoSnapshot> loadedUndo = [];
    if (undoEncoded != null && undoEncoded.isNotEmpty) {
      try {
        final decoded = jsonDecode(undoEncoded);
        if (decoded is List) {
          loadedUndo = decoded
              .whereType<String>()
              .map((s) => _UndoSnapshot.fromEncoded(s))
              .whereType<_UndoSnapshot>()
              .toList();
        }
      } catch (_) {}
    }
    setState(() {
      price15ProMax = prefs.getDouble('p15') ?? 45000.0;
      price16ProMax = prefs.getDouble('p16') ?? 55000.0;
      price17ProMax = prefs.getDouble('p17') ?? 65000.0;
      stock15 = prefs.getInt('s15') ?? 0;
      stock16 = prefs.getInt('s16') ?? 0;
      stock17 = prefs.getInt('s17') ?? 0;
      inventoryLog = prefs.getStringList('inv_log') ?? [];
      myAccountBalance = prefs.getDouble('my_account_balance') ?? 0.0;
      
      final savedOrders = prefs.getString('orders_v1');
      if (savedOrders != null && savedOrders.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedOrders) as List<dynamic>;
          orders
            ..clear()
            ..addAll(
              decoded.whereType<Map>().map(
                (e) => Map<String, String>.fromEntries(
                  e.entries.map(
                    (entry) => MapEntry(
                      entry.key.toString(),
                      (entry.value ?? '').toString(),
                    ),
                  ),
                ),
              ),
            );
        } catch (_) {}
      }
      
      final savedCustomers = prefs.getString('customers_v1');
      if (savedCustomers != null && savedCustomers.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedCustomers) as List<dynamic>;
          customers
            ..clear()
            ..addAll(
              decoded.whereType<Map>().map(
                    (e) => Map<String, String>.fromEntries(
                      e.entries.map(
                        (entry) => MapEntry(
                          entry.key.toString(),
                          (entry.value ?? '').toString(),
                        ),
                      ),
                    ),
                  ),
            );
        } catch (_) {}
      }

      final savedOverrides = prefs.getString(_customerStatusOverridePrefsKey);
      if (savedOverrides != null && savedOverrides.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedOverrides);
          if (decoded is Map) {
            final mapped = decoded.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
            mapped.removeWhere((k, v) => v.trim().isEmpty);
            _customerStatusOverrides
              ..clear()
              ..addAll(mapped);
          }
        } catch (_) {}
      }
       
      colorStock = _createDefaultColorStock();
      homeColorStock = _createDefaultColorStock();

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
        } catch (_) {}
      } else {
        colorStock['15 Pro Max']!['ط³ظ„ظپط±'] = stock15;
        colorStock['16 Pro Max']!['ط³ظ„ظپط±'] = stock16;
        colorStock['17 Pro Max']!['ط³ظ„ظپط±'] = stock17;
      }

      final savedHomeColorStock = prefs.getString('home_color_stock_v1');
      if (savedHomeColorStock != null && savedHomeColorStock.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedHomeColorStock) as Map<String, dynamic>;
          decoded.forEach((model, colors) {
            if (!_stockModels.containsKey(model) || colors is! Map<String, dynamic>) return;
            final target = homeColorStock[model]!;
            for (final color in target.keys) {
              target[color] = (colors[color] as num?)?.toInt() ?? 0;
            }
          });
        } catch (_) {}
      }

      _syncTotalsFromColorStock();
      _syncHomeTotalsFromColorStock();
      
      if (customers.isEmpty && orders.isNotEmpty) {
        _rebuildCustomersFromOrders();
      }

      _undoStack
        ..clear()
        ..addAll(loadedUndo.take(_maxUndoDepth));
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
    await prefs.setString('home_color_stock_v1', jsonEncode(homeColorStock));
    await prefs.setString('orders_v1', jsonEncode(orders));
    await prefs.setString('customers_v1', jsonEncode(customers));
    await prefs.setString(_customerStatusOverridePrefsKey, jsonEncode(_customerStatusOverrides));
  }

  void _pushUndo(String label) {
    final snapshot = _UndoSnapshot(
      label: label,
      at: DateTime.now().toIso8601String(),
      price15ProMax: price15ProMax,
      price16ProMax: price16ProMax,
      price17ProMax: price17ProMax,
      stock15: stock15,
      stock16: stock16,
      stock17: stock17,
      homeStock15: homeStock15,
      homeStock16: homeStock16,
      homeStock17: homeStock17,
      colorStock: _cloneColorStock(colorStock),
      homeColorStock: _cloneColorStock(homeColorStock),
      orders: orders.map((e) => Map<String, String>.from(e)).toList(),
      customers: customers.map((e) => Map<String, String>.from(e)).toList(),
      inventoryLog: List<String>.from(inventoryLog),
      netProfit: netProfit,
      myShare: myShare,
      partnerShare: partnerShare,
      myAccountBalance: myAccountBalance,
      collectionText: collectionController.text,
      expensesText: expensesController.text,
      count15Text: count15Controller.text,
      count16Text: count16Controller.text,
      count17Text: count17Controller.text,
      customerStatusOverrides: Map<String, String>.from(_customerStatusOverrides),
    );

    _undoStack.add(snapshot);
    if (_undoStack.length > _maxUndoDepth) {
      _undoStack.removeAt(0);
    }
    unawaited(_saveUndoStack());
  }

  Future<bool> _undoLast() async {
    if (_undoStack.isEmpty) return false;
    final s = _undoStack.removeLast();

    setState(() {
      price15ProMax = s.price15ProMax;
      price16ProMax = s.price16ProMax;
      price17ProMax = s.price17ProMax;

      stock15 = s.stock15;
      stock16 = s.stock16;
      stock17 = s.stock17;

      homeStock15 = s.homeStock15;
      homeStock16 = s.homeStock16;
      homeStock17 = s.homeStock17;

      colorStock = _cloneColorStock(s.colorStock);
      homeColorStock = _cloneColorStock(s.homeColorStock);

      orders
        ..clear()
        ..addAll(s.orders.map((e) => Map<String, String>.from(e)));
      customers
        ..clear()
        ..addAll(s.customers.map((e) => Map<String, String>.from(e)));
      inventoryLog = List<String>.from(s.inventoryLog);

      netProfit = s.netProfit;
      myShare = s.myShare;
      partnerShare = s.partnerShare;
      myAccountBalance = s.myAccountBalance;

      collectionController.text = s.collectionText;
      expensesController.text = s.expensesText;
      count15Controller.text = s.count15Text;
      count16Controller.text = s.count16Text;
      count17Controller.text = s.count17Text;

      _customerStatusOverrides
        ..clear()
        ..addAll(s.customerStatusOverrides);
    });

    await _saveData();
    await _saveUndoStack();
    return true;
  }

  Future<bool> _undoToIndex(int index) async {
    if (index < 0 || index >= _undoStack.length) return false;

    final s = _undoStack.removeAt(index);
    if (index < _undoStack.length) {
      _undoStack.removeRange(index, _undoStack.length);
    }

    setState(() {
      price15ProMax = s.price15ProMax;
      price16ProMax = s.price16ProMax;
      price17ProMax = s.price17ProMax;

      stock15 = s.stock15;
      stock16 = s.stock16;
      stock17 = s.stock17;

      homeStock15 = s.homeStock15;
      homeStock16 = s.homeStock16;
      homeStock17 = s.homeStock17;

      colorStock = _cloneColorStock(s.colorStock);
      homeColorStock = _cloneColorStock(s.homeColorStock);

      orders
        ..clear()
        ..addAll(s.orders.map((e) => Map<String, String>.from(e)));
      customers
        ..clear()
        ..addAll(s.customers.map((e) => Map<String, String>.from(e)));
      inventoryLog = List<String>.from(s.inventoryLog);

      netProfit = s.netProfit;
      myShare = s.myShare;
      partnerShare = s.partnerShare;
      myAccountBalance = s.myAccountBalance;

      collectionController.text = s.collectionText;
      expensesController.text = s.expensesText;
      count15Controller.text = s.count15Text;
      count16Controller.text = s.count16Text;
      count17Controller.text = s.count17Text;

      _customerStatusOverrides
        ..clear()
        ..addAll(s.customerStatusOverrides);
    });

    await _saveData();
    await _saveUndoStack();
    return true;
  }

  String _formatUndoIso(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y/$m/$d $hh:$mm';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _saveUndoStack() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _undoStack.map((e) => e.toEncoded()).toList();
      await prefs.setString(_undoPrefsKey, jsonEncode(encoded));
    } catch (_) {}
  }

  String _normalizeArabicName(String input) {
    var s = input.trim().toLowerCase();
    s = s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '');
    s = s.replaceAll(RegExp(r'[^a-z\u0600-\u06FF\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  String _normalizeColorNameAny(String colorRaw) {
    final c = _normalizeArabicName(colorRaw);
    if (c.isEmpty) return '';
    if (c.contains('ط³ظ„ظپط±') || c.contains('ط³ظٹظ„ظپط±') || c.contains('ظپط¶ظٹ') || c.contains('ظپط¶ظ‡') || c.contains('ط§ط¨ظٹط¶') || c.contains('ط£ط¨ظٹط¶') || c.contains('silver') || c.contains('white')) return 'ط³ظ„ظپط±';
    if (c.contains('ط§ط³ظˆط¯') || c.contains('ط£ط³ظˆط¯') || c.contains('ط¨ظ„ط§ظƒ') || c.contains('black')) return 'ط§ط³ظˆط¯';
    if (c.contains('ط§ط²ط±ظ‚') || c.contains('ط£ط²ط±ظ‚') || c.contains('blue')) return 'ط§ط²ط±ظ‚';
    if (c.contains('ط¯ظ‡ط¨ظٹ') || c.contains('ط°ظ‡ط¨ظٹ') || c.contains('ط¬ظˆظ„ط¯') || c.contains('gold')) return 'ط¯ظ‡ط¨ظٹ';
    if (c.contains('ط¨ط±طھظ‚ط§ظ„ظٹ') || c.contains('ط§ظˆط±ظ†ط¬') || c.contains('ط§ظˆط±ط§ظ†ط¬') || c.contains('ط£ظˆط±ظ†ط¬') || c.contains('orange')) return 'ط¨ط±طھظ‚ط§ظ„ظٹ';
    if (c.contains('ظƒط­ظ„ظٹ') || c.contains('ظƒط­ظ„ظ‰') || c.contains('navy')) return 'ظƒط­ظ„ظٹ';
    if (c.contains('طھظٹطھط§ظ†ظٹظˆظ…') || c.contains('ط·ط¨ظٹط¹ظٹ') || c.contains('ظ†ط§طھط´ظˆط±ط§ظ„') || c.contains('natural')) return 'طھظٹطھط§ظ†ظٹظˆظ…';
    return colorRaw.trim();
  }

  String _normalizeColorForModel(String modelKey, String colorRaw) {
    final normalized = _normalizeColorNameAny(colorRaw).trim();
    if (normalized.isEmpty) return '';

    final allowed = _stockModels[modelKey] ?? const <String>[];
    if (allowed.contains(normalized)) return normalized;

    // Smart mapping: treat "ط§ط²ط±ظ‚" and "ظƒط­ظ„ظٹ" as the same family depending on model.
    if (normalized == 'ط§ط²ط±ظ‚' && allowed.contains('ظƒط­ظ„ظٹ')) return 'ظƒط­ظ„ظٹ';
    if (normalized == 'ظƒط­ظ„ظٹ' && allowed.contains('ط§ط²ط±ظ‚')) return 'ط§ط²ط±ظ‚';

    return normalized;
  }

  String _toWesternDigits(String value) {
    var s = value;
    const arabicNums = {
      '\u0660': '0', '\u0661': '1', '\u0662': '2', '\u0663': '3', '\u0664': '4',
      '\u0665': '5', '\u0666': '6', '\u0667': '7', '\u0668': '8', '\u0669': '9',
      '\u06f0': '0', '\u06f1': '1', '\u06f2': '2', '\u06f3': '3', '\u06f4': '4',
      '\u06f5': '5', '\u06f6': '6', '\u06f7': '7', '\u06f8': '8', '\u06f9': '9',
    };
    arabicNums.forEach((k, v) => s = s.replaceAll(k, v));
    return s;
  }

  String _normalizePhone(String input) {
    final raw = _toWesternDigits(input);

    final match = RegExp(r'(?:\\+?20)?\\s*0?1[0-2,5]\\d{8}').firstMatch(raw);
    if (match != null) {
      var s = match.group(0) ?? '';
      s = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (s.startsWith('20') && s.length >= 12) s = '0${s.substring(2)}';
      if (!s.startsWith('0') && s.length == 11) s = '0$s';
      return s;
    }

    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('20') && digits.length >= 12) {
      digits = '0${digits.substring(2)}';
    }

    final m2 = RegExp(r'01[0-2,5]\\d{8}').firstMatch(digits);
    if (m2 != null) {
      return m2.group(0) ?? digits;
    }
    return digits;
  }

  List<String> _orderPhones(Map<String, String> order) {
    final list = <String>[];
    final p = _normalizePhone(order['phone'] ?? '');
    if (p.isNotEmpty) list.add(p);

    final extra = (order['phones'] ?? '').trim();
    if (extra.isNotEmpty) {
      for (final raw in extra.split(',')) {
        final n = _normalizePhone(raw);
        if (n.isNotEmpty) list.add(n);
      }
    }
    return list.toSet().toList();
  }

  String _customerKeyFromCustomer(Map<String, String> c) {
    final phone = _normalizePhone(c['phone'] ?? '');
    if (phone.isNotEmpty) return 'p:$phone';
    final name = _normalizeArabicName(c['name'] ?? '');
    final gov = _normalizeArabicName(c['governorate'] ?? '');
    if (name.isNotEmpty && gov.isNotEmpty) return 'n:$name|g:$gov';
    final addr = _normalizeArabicName(c['address'] ?? '');
    if (addr.isNotEmpty) return 'a:$addr';
    return 'n:$name|g:$gov';
  }

  bool _orderMatchesCustomer(Map<String, String> order, Map<String, String> customer) {
    final cPhone = _normalizePhone(customer['phone'] ?? '');
    final cPhones = (customer['phones'] ?? '').split(',').map(_normalizePhone).where((x) => x.isNotEmpty).toSet();
    if (cPhone.isNotEmpty || cPhones.isNotEmpty) {
      final op = _normalizePhone(order['phone'] ?? '');
      final oPhones = (order['phones'] ?? '').split(',').map(_normalizePhone).where((x) => x.isNotEmpty).toSet();
      if (cPhone.isNotEmpty && (op == cPhone || oPhones.contains(cPhone))) return true;
      for (final p in cPhones) {
        if (p.isNotEmpty && (op == p || oPhones.contains(p))) return true;
      }
    }

    final cAddr = _normalizeArabicName(customer['address'] ?? '');
    if (cAddr.isNotEmpty) {
      final oa = _normalizeArabicName(order['address'] ?? '');
      final cGov = _normalizeArabicName(customer['governorate'] ?? '');
      final og = _normalizeArabicName(order['governorate'] ?? '');
      final govOk = cGov.isEmpty || og.isEmpty || og.contains(cGov) || cGov.contains(og);
      final longEnough = cAddr.length >= 12 && oa.length >= 12;
      if (govOk && longEnough && (oa.contains(cAddr) || cAddr.contains(oa))) return true;
    }

    final cName = _normalizeArabicName(customer['name'] ?? '');
    if (cName.isNotEmpty) {
      final on = _normalizeArabicName(order['name'] ?? '');
      if (on.isNotEmpty && (on == cName || on.contains(cName) || cName.contains(on))) {
        final cGov = _normalizeArabicName(customer['governorate'] ?? '');
        if (cGov.isEmpty) return true;
        final og = _normalizeArabicName(order['governorate'] ?? '');
        return og.isNotEmpty && (og.contains(cGov) || cGov.contains(og));
      }
    }

    return false;
  }

  List<Map<String, String>> _customersSnapshot() {
    _rebuildCustomersFromOrders();
    return customers.map((e) => Map<String, String>.from(e)).toList();
  }

  ({String code, String label}) _derivedOrderStatus(Map<String, String> order, DateTime now) {
    final raw = _normalizeArabicName(order['status'] ?? '');

    DateTime? createdAt;
    try {
      final iso = (order['created_at'] ?? '').trim();
      if (iso.isNotEmpty) createdAt = DateTime.parse(iso).toLocal();
    } catch (_) {}

    if (raw.contains('delivered') || raw.contains('طھظ… ط§ظ„طھط³ظ„ظٹظ…') || raw.contains('طھط³ظ„ظٹظ…')) {
      return (code: 'delivered', label: 'طھظ… ط§ظ„طھط³ظ„ظٹظ…');
    }
    if (raw.contains('returned') || raw.contains('ظ…ط±طھط¬ط¹') || raw.contains('ط±ط¬ط¹')) {
      return (code: 'returned', label: 'ظ…ط±طھط¬ط¹');
    }
    if (raw.contains('canceled') || raw.contains('ظ…ظ„ط؛ظٹ') || raw.contains('ط§ظ„ط؛ط§ط،')) {
      return (code: 'canceled', label: 'ظ…ظ„ط؛ظٹ');
    }
    if (raw.contains('review') || raw.contains('ط±ط§ط¬ط¹')) {
      return (code: 'review', label: 'ط±ط§ط¬ط¹');
    }

    // shipped / unknown => infer by age
    if (createdAt != null) {
      final days = now.difference(createdAt).inDays;
      if (days >= _reviewAfterDays) return (code: 'review', label: 'ط±ط§ط¬ط¹');
    }
    return (code: 'in_transit', label: 'ط¬ط§ط±ظٹ ط§ظ„طھظˆطµظٹظ„');
  }

  ({String code, String label}) _statusFromCode(String code) {
    switch (code) {
      case 'delivered':
        return (code: 'delivered', label: 'طھظ… ط§ظ„طھط³ظ„ظٹظ…');
      case 'review':
        return (code: 'review', label: 'ط±ط§ط¬ط¹');
      case 'returned':
        return (code: 'returned', label: 'ظ…ط±طھط¬ط¹');
      case 'canceled':
        return (code: 'canceled', label: 'ظ…ظ„ط؛ظٹ');
      case 'in_transit':
      default:
        return (code: 'in_transit', label: 'ط¬ط§ط±ظٹ ط§ظ„طھظˆطµظٹظ„');
    }
  }

  Future<void> _setCustomerStatusOverride(String customerKey, String? statusCode) async {
    _pushUndo("طھط¹ط¯ظٹظ„ ط­ط§ظ„ط© ط¹ظ…ظٹظ„");
    setState(() {
      final next = (statusCode ?? '').trim();
      if (next.isEmpty) {
        _customerStatusOverrides.remove(customerKey);
      } else {
        _customerStatusOverrides[customerKey] = next;
      }
      _rebuildCustomersFromOrders();
    });
    await _saveData();
  }

  Future<int> _normalizeOrderPhonesAndRebuildCustomers() async {
    _pushUndo("طھظ†ط¸ظٹظپ ط£ط±ظ‚ط§ظ… ط§ظ„ط¹ظ…ظ„ط§ط،");
    int changed = 0;
    for (final o in orders) {
      final beforePhone = o['phone'] ?? '';
      final beforePhones = o['phones'] ?? '';

      final list = <String>[];
      final p = _normalizePhone(beforePhone);
      if (p.isNotEmpty) list.add(p);
      if (beforePhones.trim().isNotEmpty) {
        for (final raw in beforePhones.split(',')) {
          final n = _normalizePhone(raw);
          if (n.isNotEmpty) list.add(n);
        }
      }
      final unique = list.toSet().toList();
      final nextPhone = unique.isNotEmpty ? unique.first : '';
      final nextPhones = unique.length > 1 ? unique.join(',') : '';

      if (nextPhone != _normalizePhone(beforePhone) || nextPhones != beforePhones.trim()) {
        o['phone'] = nextPhone;
        if (nextPhones.isEmpty) {
          o.remove('phones');
        } else {
          o['phones'] = nextPhones;
        }
        changed++;
      }
    }

    _rebuildCustomersFromOrders();
    await _saveData();
    return changed;
  }

  Future<int?> _editCustomerDialogAndApply(Map<String, String> customer) async {
    _pushUndo("طھط¹ط¯ظٹظ„ ط¹ظ…ظٹظ„");
    final nameCtrl = TextEditingController(text: customer['name'] ?? '');
    final phoneCtrl = TextEditingController(text: customer['phone'] ?? '');
    final govCtrl = TextEditingController(text: customer['governorate'] ?? '');
    final addrCtrl = TextEditingController(text: customer['address'] ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        title: const Text("طھط¹ط¯ظٹظ„ ط¨ظٹط§ظ†ط§طھ ط¹ظ…ظٹظ„", textAlign: TextAlign.right),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "ط§ظ„ط§ط³ظ…")),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "ط§ظ„ظ‡ط§طھظپ")),
              const SizedBox(height: 8),
              TextField(controller: govCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "ط§ظ„ظ…ط­ط§ظپط¸ط©")),
              const SizedBox(height: 8),
              TextField(controller: addrCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "ط§ظ„ط¹ظ†ظˆط§ظ†")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("ط¥ظ„ط؛ط§ط،")),
          ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("ط­ظپط¸")),
        ],
      ),
    );

    if (saved != true) return null;

    final newName = nameCtrl.text.trim();
    final newPhone = _normalizePhone(phoneCtrl.text);
    final newGov = govCtrl.text.trim();
    final newAddr = addrCtrl.text.trim();

    int updated = 0;
    for (final o in orders) {
      if (!_orderMatchesCustomer(o, customer)) continue;

      if (newName.isNotEmpty) o['name'] = newName;
      if (newGov.isNotEmpty) o['governorate'] = newGov;
      if (newAddr.isNotEmpty) o['address'] = newAddr;

      if (newPhone.isNotEmpty) {
        final extras = <String>{};
        final op = _normalizePhone(o['phone'] ?? '');
        if (op.isNotEmpty) extras.add(op);
        final beforeExtras = (o['phones'] ?? '').split(',').map(_normalizePhone).where((x) => x.isNotEmpty);
        extras.addAll(beforeExtras);
        extras.add(newPhone);

        o['phone'] = newPhone;
        final list = extras.toList();
        list.removeWhere((x) => x == newPhone);
        if (list.isEmpty) {
          o.remove('phones');
        } else {
          o['phones'] = list.join(',');
        }
      }

      updated++;
    }

    _rebuildCustomersFromOrders();
    await _saveData();
    return updated;
  }

  Future<int?> _deleteCustomerWithConfirm(Map<String, String> customer) async {
    _pushUndo("ظ…ط³ط­ ط¹ظ…ظٹظ„");
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        title: const Text("ظ…ط³ط­ ط¹ظ…ظٹظ„", textAlign: TextAlign.right),
        content: Text(
          "ط¯ظ‡ ظ‡ظٹظ…ط³ط­ ظƒظ„ ط£ظˆط±ط¯ط±ط§طھ ط§ظ„ط¹ظ…ظٹظ„ ط¯ظ‡ ظ…ظ† ط§ظ„طھط·ط¨ظٹظ‚.\n\nط§ظ„ط¹ظ…ظٹظ„: ${customer['name'] ?? '-'}\nط§ظ„ظ‡ط§طھظپ: ${customer['phone'] ?? '-'}\n\nظ…طھط£ظƒط¯طں",
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("ط¥ظ„ط؛ط§ط،")),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("ظ…ط³ط­", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return null;

    final before = orders.length;
    orders.removeWhere((o) => _orderMatchesCustomer(o, customer));
    final removed = before - orders.length;

    _rebuildCustomersFromOrders();
    await _saveData();
    return removed;
  }

  Future<int?> _deleteSelectedCustomersByKeys(Set<String> keys) async {
    if (keys.isEmpty) return 0;
    _pushUndo("ظ…ط³ط­ ط¹ظ…ظ„ط§ط،");
    int removedOrders = 0;
    final keysNow = keys.toList();
    for (final k in keysNow) {
      final customer = customers.firstWhere(
        (c) => _customerKeyFromCustomer(c) == k,
        orElse: () => <String, String>{},
      );
      if (customer.isEmpty) continue;
      final before = orders.length;
      orders.removeWhere((o) => _orderMatchesCustomer(o, customer));
      removedOrders += before - orders.length;
    }

    _rebuildCustomersFromOrders();
    await _saveData();
    return removedOrders;
  }

  void _openCustomersPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomersPage(
          getCustomers: _customersSnapshot,
          customerKey: _customerKeyFromCustomer,
          normalizePhones: _normalizeOrderPhonesAndRebuildCustomers,
          editCustomer: _editCustomerDialogAndApply,
          deleteCustomer: _deleteCustomerWithConfirm,
          deleteSelectedCustomers: _deleteSelectedCustomersByKeys,
          setCustomerStatusOverride: _setCustomerStatusOverride,
        ),
      ),
    );
  }

  String _customerKeyForOrder(Map<String, String> order) {
    final phones = _orderPhones(order);
    if (phones.isNotEmpty) return 'p:${phones.first}';
    final name = _normalizeArabicName(order['name'] ?? '');
    final gov = _normalizeArabicName(order['governorate'] ?? '');
    if (name.isNotEmpty && gov.isNotEmpty) return 'n:$name|g:$gov';
    final address = _normalizeArabicName(order['address'] ?? '');
    if (address.isNotEmpty) return 'a:$address';
    return 'n:$name|g:$gov';
  }

  void _rebuildCustomersFromOrders() {
    final Map<String, Map<String, String>> grouped = {};
    final Map<String, Set<String>> phonesByKey = {};
    final Map<String, List<Map<String, String>>> ordersByKey = {};
    final now = DateTime.now();
    for (final order in orders) {
      final key = _customerKeyForOrder(order);
      ordersByKey.putIfAbsent(key, () => <Map<String, String>>[]).add(order);
      final existing = grouped[key];
      final phones = _orderPhones(order);
      phonesByKey.putIfAbsent(key, () => <String>{}).addAll(phones);
      if (existing == null) {
        grouped[key] = {
          'name': order['name'] ?? '',
          'phone': phones.isNotEmpty ? phones.first : _normalizePhone(order['phone'] ?? ''),
          'governorate': order['governorate'] ?? '',
          'address': order['address'] ?? '',
          'orders_count': '1',
          'last_order_at': order['created_at'] ?? DateTime.now().toIso8601String(),
        };
      } else {
        final c = int.tryParse(existing['orders_count'] ?? '0') ?? 0;
        existing['orders_count'] = (c + 1).toString();
        final incomingDate = order['created_at'] ?? '';
        if (incomingDate.isNotEmpty) {
          existing['last_order_at'] = incomingDate;
        }
        if ((existing['phone'] ?? '').isEmpty && phones.isNotEmpty) {
          existing['phone'] = phones.first;
        }
        if ((existing['address'] ?? '').isEmpty && (order['address'] ?? '').isNotEmpty) {
          existing['address'] = order['address'] ?? '';
        }
      }
    }

    for (final e in grouped.entries) {
      final key = e.key;
      final c = e.value;
      final list = ordersByKey[key] ?? const <Map<String, String>>[];
      if (list.isEmpty) continue;

      Map<String, String> last = list.first;
      DateTime lastAt = DateTime.fromMillisecondsSinceEpoch(0);
      for (final o in list) {
        try {
          final iso = (o['created_at'] ?? '').trim();
          if (iso.isEmpty) continue;
          final dt = DateTime.parse(iso).toLocal();
          if (dt.isAfter(lastAt)) {
            lastAt = dt;
            last = o;
          }
        } catch (_) {}
      }

      final override = (_customerStatusOverrides[key] ?? '').trim();
      if (override.isNotEmpty) {
        final s = _statusFromCode(override);
        c['status_last'] = s.code;
        c['status_label'] = s.label;
        c['status_manual'] = 'true';
      } else {
        final lastStatus = _derivedOrderStatus(last, now);
        c['status_last'] = lastStatus.code;
        c['status_label'] = lastStatus.label;
        c['status_manual'] = 'false';
      }

      final counts = <String, int>{};
      final modelsCount = <String, int>{};
      final colorsCount = <String, int>{};
      for (final o in list) {
        final s = _derivedOrderStatus(o, now);
        counts[s.code] = (counts[s.code] ?? 0) + 1;

        final baseModel = _normalizeModelFromAi(o['model'] ?? '');
        final baseColor = _normalizeColorNameAny(o['color'] ?? '');
        final count = _parseIntSafe(o['count'] ?? '1');
        final safeCount = count <= 0 ? 1 : count;
        final modelParts = (o['models'] ?? '')
            .split('|')
            .map((x) => _normalizeModelFromAi(x))
            .where((x) => x.isNotEmpty)
            .toList();
        final colorParts = (o['colors'] ?? '')
            .split('|')
            .map((x) => _normalizeColorNameAny(x))
            .where((x) => x.isNotEmpty)
            .toList();

        for (int i = 0; i < safeCount; i++) {
          final model = (i < modelParts.length && modelParts[i].isNotEmpty) ? modelParts[i] : baseModel;
          final color = (i < colorParts.length && colorParts[i].isNotEmpty) ? colorParts[i] : baseColor;
          if (model.isNotEmpty) {
            modelsCount[model] = (modelsCount[model] ?? 0) + 1;
          }
          if (color.isNotEmpty) {
            colorsCount[color] = (colorsCount[color] ?? 0) + 1;
          }
        }
      }

      final parts = <String>[];
      void addPart(String code, String label) {
        final n = counts[code] ?? 0;
        if (n > 0) parts.add('$label: $n');
      }

      addPart('in_transit', 'ط¬ط§ط±ظٹ');
      addPart('review', 'ط±ط§ط¬ط¹');
      addPart('delivered', 'طھظ…');
      addPart('returned', 'ظ…ط±طھط¬ط¹');
      addPart('canceled', 'ظ…ظ„ط؛ظٹ');

      c['status_summary'] = parts.join('طŒ ');
      c['last_model'] = _normalizeModelFromAi(last['model'] ?? '');
      c['last_color'] = _normalizeColorNameAny(last['color'] ?? '');

      String buildSummary(Map<String, int> map) {
        if (map.isEmpty) return '';
        final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return entries.map((e) => "${e.key}أ—${e.value}").join('طŒ ');
      }

      c['models_summary'] = buildSummary(modelsCount);
      c['colors_summary'] = buildSummary(colorsCount);
    }

    customers
      ..clear()
      ..addAll(
        grouped.entries.map((e) {
          final c = e.value;
          final pset = phonesByKey[e.key] ?? <String>{};
          final phone = _normalizePhone(c['phone'] ?? '');
          final all = <String>{...pset};
          if (phone.isNotEmpty) all.add(phone);
          if (all.length > 1) c['phones'] = all.join(',');
          c['phone'] = phone;
          return c;
        }),
      );
    customers.sort((a, b) => (b['last_order_at'] ?? '').compareTo(a['last_order_at'] ?? ''));
  }

  Map<String, String>? _findExistingCustomer(Map<String, String> order) {
    final targetPhone = _normalizePhone(order['phone'] ?? '');
    final targetName = _normalizeArabicName(order['name'] ?? '');
    final targetGov = _normalizeArabicName(order['governorate'] ?? '');
    final targetAddress = _normalizeArabicName(order['address'] ?? '');

    for (final c in customers) {
      final cPhone = _normalizePhone(c['phone'] ?? '');
      if (targetPhone.isNotEmpty && cPhone.isNotEmpty && targetPhone == cPhone) {
        return c;
      }
    }
    if (targetName.isNotEmpty) {
      for (final c in customers) {
        final cName = _normalizeArabicName(c['name'] ?? '');
        if (cName.isEmpty) continue;
        final sameName = cName == targetName || cName.contains(targetName) || targetName.contains(cName);
        if (!sameName) continue;
        final cGov = _normalizeArabicName(c['governorate'] ?? '');
        if (targetGov.isNotEmpty && cGov.isNotEmpty) {
          if (targetGov.contains(cGov) || cGov.contains(targetGov)) return c;
        } else {
          return c;
        }
      }
    }
    if (targetAddress.isNotEmpty) {
      for (final c in customers) {
        final cAddress = _normalizeArabicName(c['address'] ?? '');
        if (cAddress.isEmpty) continue;
        final cGov = _normalizeArabicName(c['governorate'] ?? '');
        final govOk = targetGov.isEmpty || cGov.isEmpty || targetGov.contains(cGov) || cGov.contains(targetGov);
        final longEnough = cAddress.length >= 12 && targetAddress.length >= 12;
        if (govOk && longEnough && (cAddress.contains(targetAddress) || targetAddress.contains(cAddress))) {
          return c;
        }
      }
    }
    return null;
  }

  // --- طھط­ظ„ظٹظ„ ط£ظˆط±ط¯ط±ط§طھ ط§ظ„ظˆط§طھط³ط§ط¨ ط¹ط¨ط± ط§ظ„ط³ظٹط±ظپط± (Render) ---
  Future<List<Map<String, String>>?> _parseOrdersWithServerAi(String rawText) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/ai/parse_orders');

    String s(dynamic v) => (v ?? '').toString().trim();

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': rawText}),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        print('AI parse_orders HTTP ${response.statusCode}: ${response.body}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return null;

      return decoded.whereType<Map>().map((e) {
        final phones = (e['phones'] is List)
            ? (e['phones'] as List).map((x) => s(x)).where((x) => x.isNotEmpty).toList()
            : <String>[];

        final createdAt = s(e['created_at']).isNotEmpty ? s(e['created_at']) : DateTime.now().toIso8601String();
        final status = s(e['status']).isNotEmpty ? s(e['status']) : 'shipped';

        final phone = s(e['phone']).isNotEmpty ? s(e['phone']) : (phones.isNotEmpty ? phones.first : '');

        return <String, String>{
          'name': s(e['name']),
          'governorate': s(e['governorate']),
          'phone': phone,
          if (phones.length > 1) 'phones': phones.join(','),
          'address': s(e['address']),
          'model': s(e['model']),
          'color': s(e['color']),
          'price': s(e['price']),
          'shipping': s(e['shipping']).isNotEmpty ? s(e['shipping']) : '0',
          'discount': s(e['discount']).isNotEmpty ? s(e['discount']) : '0',
          'cod_total': s(e['cod_total']),
          'notes': s(e['notes']),
          'status': status,
          'created_at': createdAt,
        };
      }).toList();
    } catch (e) {
      print('Server AI parse_orders error: $e');
      return null;
    }
  }

  Future<({int orderIndex, double confidence})?> _resolveDeliveryMatchWithAi({
    required String sheetName,
    required String sheetGov,
    required double amount,
    required double fee,
    required double shipping,
    required List<int> candidateIndices,
  }) async {
    if (candidateIndices.isEmpty) return null;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/ai/match_delivery');

    try {
      final candidates = candidateIndices.map((oi) {
        final order = orders[oi];
        final phones = _orderPhones(order);
        return <String, dynamic>{
          'candidate_id': oi,
          'name': order['name'] ?? '',
          'governorate': order['governorate'] ?? '',
          'phone': order['phone'] ?? '',
          'phones': phones,
          'address': order['address'] ?? '',
          'cod_total': order['cod_total'] ?? '',
          'price': order['price'] ?? '',
          'shipping': order['shipping'] ?? '',
          'discount': order['discount'] ?? '',
          'count': order['count'] ?? '1',
          'created_at': order['created_at'] ?? '',
          'status': order['status'] ?? '',
        };
      }).toList();

      final body = <String, dynamic>{
        'row': {
          'receiver_name': sheetName,
          'destination': sheetGov,
          'cod_amount': amount,
          'cod_service_fee': fee,
          'shipping_fee': shipping,
        },
        'candidates': candidates,
      };

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;
      print('AI /resolve_unmatched_row raw response: ${response.body}');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final idx = int.tryParse((decoded['match_candidate_id'] ?? '').toString()) ?? -1;
      final confidence = double.tryParse((decoded['confidence'] ?? '').toString()) ?? 0.0;
      if (idx < 0 || !candidateIndices.contains(idx)) return null;
      return (orderIndex: idx, confidence: confidence);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>?> _resolveUnmatchedRowWithGemini({
    required String sheetName,
    required String sheetGov,
    required double amount,
    required List<Map<String, String>> candidateCustomers,
  }) async {
    if (candidateCustomers.isEmpty) return null;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/ai/resolve_unmatched_row');

    try {
      final body = <String, dynamic>{
        'row': {
          'receiver_name': sheetName,
          'destination': sheetGov,
          'cod_amount': amount,
        },
        'candidates': candidateCustomers.map((c) {
          return <String, dynamic>{
            'name': c['name'] ?? '',
            'governorate': c['governorate'] ?? '',
            'phone': c['phone'] ?? '',
            'address': c['address'] ?? '',
            'last_model': c['last_model'] ?? '',
            'last_color': c['last_color'] ?? '',
            'models_summary': c['models_summary'] ?? '',
            'colors_summary': c['colors_summary'] ?? '',
            'score': c['score'] ?? '',
          };
        }).toList(),
      };

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;

      String s(dynamic v) => (v ?? '').toString().trim();
      return <String, String>{
        'status': s(decoded['status']),
        'model': s(decoded['model']),
        'color': s(decoded['color']),
        'confidence': s(decoded['confidence']),
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _dynamicOrderToStringMap(Map<String, dynamic> e) {
    String s(dynamic v) => (v ?? '').toString().trim();

    final phones = (e['phones'] is List)
        ? (e['phones'] as List).map((x) => s(x)).where((x) => x.isNotEmpty).toList()
        : <String>[];

    final colors = (e['colors'] is List)
        ? (e['colors'] as List).map((x) => s(x)).where((x) => x.isNotEmpty).toList()
        : <String>[];
    final models = (e['models'] is List)
        ? (e['models'] as List).map((x) => s(x)).where((x) => x.isNotEmpty).toList()
        : <String>[];

    final phone = s(e['phone']).isNotEmpty ? s(e['phone']) : (phones.isNotEmpty ? phones.first : '');

    return <String, String>{
      'name': s(e['name']),
      'governorate': s(e['governorate']),
      'phone': phone,
      if (phones.length > 1) 'phones': phones.join(','),
      'address': s(e['address']),
      'model': s(e['model']),
      if (models.isNotEmpty) 'models': models.join('|'),
      'color': s(e['color']),
      if (colors.isNotEmpty) 'colors': colors.join('|'),
      'count': s(e['count']).isNotEmpty ? s(e['count']) : '1',
      'price': s(e['price']),
      'shipping': s(e['shipping']).isNotEmpty ? s(e['shipping']) : '0',
      'discount': s(e['discount']).isNotEmpty ? s(e['discount']) : '0',
      'cod_total': s(e['cod_total']),
      'notes': s(e['notes']),
      'confidence': s(e['confidence']),
      'missing_fields': (e['missing_fields'] is List)
          ? (e['missing_fields'] as List).map((x) => s(x)).where((x) => x.isNotEmpty).join(',')
          : s(e['missing_fields']),
      'status': s(e['status']).isNotEmpty ? s(e['status']) : 'shipped',
      'created_at': s(e['created_at']).isNotEmpty ? s(e['created_at']) : DateTime.now().toIso8601String(),
    };
  }

  Future<String> _applyIncomingOrdersToHomeStock(List<Map<String, String>> incoming, {String logSource = 'ط§ط³طھظٹط±ط§ط¯ ظˆط§طھط³ط§ط¨ AI'}) async {
    if (incoming.isEmpty) return 'ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط£ظˆط±ط¯ط±ط§طھ ظپظٹ ط§ظ„ظ†طµ.';
    _pushUndo(logSource);

    List<Map<String, String>> orderDevices(Map<String, String> o) {
      final count = _parseIntSafe(o['count'] ?? '1');
      final safeCount = count <= 0 ? 1 : count;

      final baseModel = _normalizeModelFromAi((o['model'] ?? '').trim());
      final baseColor = baseModel.isEmpty ? _normalizeColorNameAny((o['color'] ?? '').trim()) : _normalizeColorForModel(baseModel, (o['color'] ?? '').trim());

      final modelsRaw = (o['models'] ?? '').trim();
      final models = modelsRaw
          .split('|')
          .map((x) => _normalizeModelFromAi(x))
          .where((x) => x.isNotEmpty)
          .toList();

      final colorsRaw = (o['colors'] ?? '').trim();
      final colors = colorsRaw
          .split('|')
          .map((x) => _normalizeColorNameAny(x))
          .where((x) => x.isNotEmpty)
          .toList();

      final devices = <Map<String, String>>[];
      for (int i = 0; i < safeCount; i++) {
        final m = (i < models.length && models[i].isNotEmpty) ? models[i] : baseModel;
        final rawColor = (i < colors.length && colors[i].isNotEmpty) ? colors[i] : baseColor;
        final c = m.isEmpty ? rawColor : _normalizeColorForModel(m, rawColor);
        devices.add({'model': m, 'color': c});
      }
      return devices;
    }

    final tempHome = _cloneColorStock(homeColorStock);
    final stockErrors = <String>[];
    final repeatHints = <String>[];
    final deductedSummary = _createDefaultColorStock();

    for (final o in incoming) {
      // validation happens per-device below (supports mixed models)

      final devices = orderDevices(o);
      if (devices.isEmpty) {
        stockErrors.add("â‌Œ ط§ظ„ظ€ AI ظ„ظ… ظٹط³طھط·ط¹ ط§ط³طھظ†طھط§ط¬ ط¨ظٹط§ظ†ط§طھ ط§ظ„ط£ط¬ظ‡ط²ط© ظ„ظ„ط¹ظ…ظٹظ„: ${o['name'] ?? '-'}");
        continue;
      }

      bool valid = true;
      final needed = <String, Map<String, int>>{};
      for (final d in devices) {
        final m = (d['model'] ?? '').trim();
        final c = (d['color'] ?? '').trim();
        if (m.isEmpty || !_stockModels.containsKey(m)) {
          stockErrors.add("â‌Œ ظ…ظˆط¯ظٹظ„ ط؛ظٹط± ظ…ط¹ط±ظˆظپ ظ„ظ„ط¹ظ…ظٹظ„: ${o['name'] ?? '-'}");
          valid = false;
          break;
        }
        if (c.isEmpty || !_stockModels[m]!.contains(c)) {
          stockErrors.add("â‌Œ ظ„ظˆظ† ط؛ظٹط± طµط§ظ„ط­ ظ„ظ„ظ…ظˆط¯ظٹظ„ ($m) ظ„ظ„ط¹ظ…ظٹظ„: ${o['name'] ?? '-'}");
          valid = false;
          break;
        }
        needed.putIfAbsent(m, () => <String, int>{});
        needed[m]![c] = (needed[m]![c] ?? 0) + 1;
      }
      if (!valid) continue;

      for (final m in needed.keys) {
        for (final entry in needed[m]!.entries) {
          final c = entry.key;
          final need = entry.value;
          final available = tempHome[m]?[c] ?? 0;
          if (available < need) {
            stockErrors.add("âڑ ï¸ڈ ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ ط؛ظٹط± ظƒط§ظپظٹ: $m ($c) ظ„ظ„ط¹ظ…ظٹظ„ ${o['name']} (ظ…ط·ظ„ظˆط¨ $need / ظ…طھط§ط­ $available)");
            valid = false;
            break;
          }
        }
        if (!valid) break;
      }
      if (!valid) continue;

      for (final m in needed.keys) {
        for (final entry in needed[m]!.entries) {
          final c = entry.key;
          final need = entry.value;
          final available = tempHome[m]?[c] ?? 0;
          tempHome[m]![c] = available - need;
          deductedSummary[m]![c] = (deductedSummary[m]![c] ?? 0) + need;
        }
      }

      final existingCustomer = _findExistingCustomer(o);
      if (existingCustomer != null) {
        repeatHints.add("ًں”„ ${o['name'] ?? ''} (ط¹ظ…ظٹظ„ ظ…طھظƒط±ط±)");
      }
    }

    if (stockErrors.isNotEmpty) {
      return stockErrors.take(6).join('\n');
    }

    String logDetails = "طھظ… ط³ط­ط¨ ${incoming.length} ط£ظˆط±ط¯ط± (ط¨ط§ظ„ط°ظƒط§ط، ط§ظ„ط§طµط·ظ†ط§ط¹ظٹ)طŒ ظˆط®طµظ… ط§ظ„ط¢طھظٹ:\n";
    for (var model in deductedSummary.keys) {
      List<String> colorParts = [];
      deductedSummary[model]!.forEach((color, qty) {
        if (qty > 0) colorParts.add("$qty $color");
      });
      if (colorParts.isNotEmpty) {
        logDetails += "- $model: (${colorParts.join('طŒ ')})\n";
      }
    }

    setState(() {
      orders.addAll(incoming);
      homeColorStock = tempHome;
      _syncHomeTotalsFromColorStock();
      _rebuildCustomersFromOrders();
    });

    await _saveData();
    await _addLogEntry(logSource, logDetails.trim());

    final repeats = repeatHints.isNotEmpty ? "\n\n${repeatHints.take(8).join('\n')}" : "";
    return "âœ… طھظ… ط§ظ„ط§ط³طھظٹط±ط§ط¯ ط¨ظ†ط¬ط§ط­.\n\n${logDetails.trim()}$repeats";
  }

  // --- ظ†ط§ظپط°ط© ط§ظ„ط§ط³طھظٹط±ط§ط¯ ط§ظ„ط°ظƒظٹ ظ„ظ„ظˆط§طھط³ط§ط¨ ---
  Future<void> _showWhatsAppBulkImportDialog() async {
    final textCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _dialogBorder(context)),
        ),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('ط§ط³طھظٹط±ط§ط¯ ط°ظƒظٹ (AI)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            SizedBox(width: 8),
            Icon(Icons.auto_awesome, color: Colors.amber),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: textCtrl,
            maxLines: 14,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'ط§ظ„طµظ‚ ط£ظˆط±ط¯ط±ط§طھ ط§ظ„ظˆط§طھط³ط§ط¨ ط¨ط£ظٹ ط´ظƒظ„ ظ‡ظ†ط§طŒ ظˆط§ظ„ظ€ AI ظ‡ظٹظپظ‡ظ…ظ‡ط§ ظˆظٹط®طµظ…ظ‡ط§ ظ…ظ† ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ...',
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A1A1A)
                  : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ط¥ظ„ط؛ط§ط،'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (textCtrl.text.trim().isEmpty) return;

              // ط¥ط¸ظ‡ط§ط± Loading 
              showDialog(
                context: ctx,
                barrierDismissible: false,
                builder: (_) => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0A84FF)),
                ),
              );

              // ط¥ط±ط³ط§ظ„ ظ„ظ€ Gemini
              final incoming = await _parseOrdersWithServerAi(textCtrl.text);
              
              if (!mounted) return;
              Navigator.pop(context); // ظ‚ظپظ„ ط§ظ„ظ€ Loading

              if (incoming == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('â‌Œ ط­ط¯ط« ط®ط·ط£ ظپظٹ طھط­ظ„ظٹظ„ ط§ظ„ط°ظƒط§ط، ط§ظ„ط§طµط·ظ†ط§ط¹ظٹ! طھط£ظƒط¯ ظ…ظ† ط§ظ„ط¥ظ†طھط±ظ†طھ.'), backgroundColor: Colors.red),
                );
                return;
              }

              if (incoming.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط£ظˆط±ط¯ط±ط§طھ ظپظٹ ط§ظ„ظ†طµ.')),
                );
                return;
              }

              // ط§ظ„ط®طµظ… ط§ظ„ظپط¹ظ„ظٹ ظ…ظ† ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ
              final tempHome = _cloneColorStock(homeColorStock);
              final stockErrors = <String>[];
              final repeatHints = <String>[];
              Map<String, Map<String, int>> deductedSummary = _createDefaultColorStock();

              for (final o in incoming) {
                final modelKey = o['model'] ?? '';
                final colorKey = o['color'] ?? ''; 
                final qty = int.tryParse((o['count'] ?? o['qty'] ?? '1').toString()) ?? 1;
                final safeQty = qty <= 0 ? 1 : qty;
                
                if (modelKey.isEmpty || colorKey.isEmpty || !_stockModels.containsKey(modelKey)) {
                  stockErrors.add("â‌Œ ط§ظ„ظ€ AI ظ„ظ… ظٹط³طھط·ط¹ ط§ط³طھظ†طھط§ط¬ ط§ظ„ظ…ظˆط¯ظٹظ„/ط§ظ„ظ„ظˆظ† ظ„ظ„ط¹ظ…ظٹظ„: ${o['name'] ?? '-'}");
                  continue;
                }
                
                final available = tempHome[modelKey]?[colorKey] ?? 0;
                if (available < safeQty) {
                  stockErrors.add("âڑ ï¸ڈ ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ ط؛ظٹط± ظƒط§ظپظٹ: $modelKey ($colorKey) ظ„ظ„ط¹ظ…ظٹظ„ ${o['name']} (ظ…ط·ظ„ظˆط¨ $safeQty / ظ…طھط§ط­ $available)");
                  continue;
                }
                
                tempHome[modelKey]![colorKey] = available - safeQty;
                deductedSummary[modelKey]![colorKey] = (deductedSummary[modelKey]![colorKey] ?? 0) + safeQty;
                
                final existingCustomer = _findExistingCustomer(o);
                if (existingCustomer != null) {
                  repeatHints.add("ًں”„ ${o['name'] ?? ''} (ط¹ظ…ظٹظ„ ظ…طھظƒط±ط±)");
                }
              }

              if (stockErrors.isNotEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(stockErrors.take(4).join('\n')),
                    duration: const Duration(seconds: 5),
                    backgroundColor: Colors.red.shade800,
                  ),
                );
                return; 
              }

              String logDetails = "طھظ… ط³ط­ط¨ ${incoming.length} ط£ظˆط±ط¯ط± (ط¨ط§ظ„ط°ظƒط§ط، ط§ظ„ط§طµط·ظ†ط§ط¹ظٹ)طŒ ظˆط®طµظ… ط§ظ„ط¢طھظٹ:\n";
              for (var model in deductedSummary.keys) {
                List<String> colorParts = [];
                deductedSummary[model]!.forEach((color, qty) {
                  if (qty > 0) colorParts.add("$qty $color");
                });
                if (colorParts.isNotEmpty) {
                  logDetails += "- $model: (${colorParts.join('طŒ ')})\n";
                }
              }

              setState(() {
                orders.addAll(incoming);
                homeColorStock = tempHome;
                _syncHomeTotalsFromColorStock();
                _rebuildCustomersFromOrders(); 
              });
              
              await _saveData();
              await _addLogEntry('ط§ط³طھظٹط±ط§ط¯ ط°ظƒظٹ AI', logDetails.trim());

              if (!mounted) return;
              Navigator.pop(ctx); // ظ‚ظپظ„ ط§ظ„ط´ط§ط´ط©
              
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: _dialogBg(context),
                  title: const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                       Text('طھظ… ط§ظ„ط³ط­ط¨ ط¨ظ†ط¬ط§ط­', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                       SizedBox(width: 8),
                       Icon(Icons.check_circle, color: Colors.green),
                    ],
                  ),
                  content: Text(logDetails, textAlign: TextAlign.right, style: const TextStyle(fontSize: 16)),
                  actions: [
                    if (repeatHints.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(repeatHints.join(' | '))));
                        },
                        child: const Text('ط¹ط±ط¶ ط§ظ„ظ…طھظƒط±ط±ظٹظ†', style: TextStyle(color: Colors.orange)),
                      ),
                    ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('طھظ…ط§ظ…')),
                  ],
                ),
              );
            },
            child: const Text('طھط­ظ„ظٹظ„ ظˆط®طµظ… ظ…ظ† ط§ظ„ط¨ظٹطھ', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Map<String, Map<String, int>> _createDefaultColorStock() {
    return {
      for (final model in _stockModels.keys)
        model: {for (final color in _stockModels[model]!) color: 0},
    };
  }

  void _syncTotalsFromColorStock() {
    stock15 = colorStock['15 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    stock16 = colorStock['16 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    stock17 = colorStock['17 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? 0;
  }

  void _syncHomeTotalsFromColorStock() {
    homeStock15 = homeColorStock['15 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    homeStock16 = homeColorStock['16 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    homeStock17 = homeColorStock['17 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? 0;
  }

  Map<String, Map<String, int>> _cloneColorStock(Map<String, Map<String, int>> source) {
    return {
      for (final entry in source.entries)
        entry.key: Map<String, int>.from(entry.value),
    };
  }

  void _smartDeduct(String model, int totalQty, Map<String, int> exactColors) {
    if (totalQty <= 0) return;
    final modelMap = colorStock[model];
    if (modelMap == null) return;

    int remaining = totalQty;

    for (final color in exactColors.keys) {
      if (remaining <= 0) break;
      int exactQty = exactColors[color] ?? 0;
      if (exactQty > 0) {
        final available = modelMap[color] ?? 0;
        if (available <= 0) continue;

        int take = available >= exactQty ? exactQty : available;
        if (take > remaining) take = remaining;

        modelMap[color] = available - take;
        remaining -= take;
      }
    }

    if (remaining > 0) {
      for (final color in _stockModels[model]!) {
        if (remaining <= 0) break;
        final available = modelMap[color] ?? 0;
        if (available <= 0) continue;

        final take = available >= remaining ? remaining : available;
        modelMap[color] = available - take;
        remaining -= take;
      }
    }
  }

  String _normalizeModelFromAi(String model) {
    final m = model.trim().toLowerCase();
    if (m == '15' || m.contains('15')) return '15 Pro Max';
    if (m == '16' || m.contains('16')) return '16 Pro Max';
    if (m == '17' || m.contains('17')) return '17 Pro Max';
    return '';
  }

  String _orderModelDigit(Map<String, String> order) {
    final m = _normalizeModelFromAi(order['model'] ?? '');
    if (m.startsWith('15')) return '15';
    if (m.startsWith('16')) return '16';
    if (m.startsWith('17')) return '17';
    return '';
  }

  String _normalizePersonNameForMatch(String s) {
    final n = _normalizeArabicName(s)
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const stop = <String>{
      'ط§ط³ظ…',
      'ط§ظ„ط§ط³ظ…',
      'ط¹ظ…ظٹظ„',
      'ط§ظ„ط¹ظ…ظٹظ„',
      'ظ…ط³طھظ„ظ…',
      'ط§ظ„ظ…ط³طھظ„ظ…',
      'ط§ظ„ط§ظ†ط³ظ‡',
      'ط§ظ„ط³ظٹط¯',
      'ط§ظ„ط³ظٹط¯ظ‡',
    };
    final tokens = n
        .split(' ')
        .where((e) => e.trim().isNotEmpty)
        .where((e) => !stop.contains(e.trim()))
        .toList();
    return tokens.join(' ');
  }

  double _nameMatchScore(String a, String b) {
    final n1 = _normalizePersonNameForMatch(a);
    final n2 = _normalizePersonNameForMatch(b);
    if (n1.isEmpty || n2.isEmpty) return 0;
    if (n1 == n2) return 1;
    if (n1.contains(n2) || n2.contains(n1)) return 0.85;
    final t1 = n1.split(' ').where((e) => e.isNotEmpty && e.length > 1).toSet();
    final t2 = n2.split(' ').where((e) => e.isNotEmpty && e.length > 1).toSet();
    if (t1.isEmpty || t2.isEmpty) return 0;
    final inter = t1.intersection(t2).length;
    final union = t1.union(t2).length;
    if (union == 0) return 0;
    return inter / union;
  }

  List<String> _nameTokensForFuzzy(String input) {
    final normalized = _normalizeArabicName(input)
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return const <String>[];

    const stop = <String>{
      'ط§ظ„ط³ظٹط¯',
      'ط³ظٹط¯',
      'ط¯ظƒطھظˆط±',
      'ط§ظ„ط¯ظƒطھظˆط±',
      'ط§ط³طھط§ط°',
      'ط§ظ„ط£ط³طھط§ط°',
      'ط§ظ„ط§ط³طھط§ط°',
      'ط§ظ„ط§ط³طھط§ط°ظ‡',
      'ط§ط³طھط§ط°ظ‡',
      'ظ…ظ‡ظ†ط¯ط³',
      'ط§ظ„ط§ط³ظ…',
      'ط§ط³ظ…',
      'ط§ظ„ط¹ظ…ظٹظ„',
      'ط¹ظ…ظٹظ„',
      'ط§ظ„ظ…ط³طھظ„ظ…',
      'ظ…ط³طھظ„ظ…',
    };

    return normalized
        .split(' ')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty && x.length > 1 && !stop.contains(x))
        .toList();
  }

  bool _tokenMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    return a.contains(b) || b.contains(a);
  }

  double _tokenScore(List<String> sheetTokens, List<String> customerTokens) {
    if (sheetTokens.isEmpty || customerTokens.isEmpty) return 0.0;
    var exact = 0.0;
    var partial = 0.0;
    for (final st in sheetTokens) {
      var best = 0.0;
      for (final ct in customerTokens) {
        if (st == ct) {
          best = 1.0;
          break;
        }
        if (_tokenMatch(st, ct) && best < 0.6) {
          best = 0.6;
        }
      }
      if (best == 1.0) exact += 1.0;
      if (best == 0.6) partial += 1.0;
    }
    return ((exact + (partial * 0.6)) / sheetTokens.length).clamp(0.0, 1.0);
  }

  String _normalizeGovernorateForMatch(String input) {
    var s = _normalizeArabicName(input);
    s = s
        .replaceAll('محافظه', '')
        .replaceAll('محافظة', '')
        .replaceAll('مدينه', '')
        .replaceAll('مدينة', '')
        .trim();
    s = s.replaceAll(' ', '');
    if (s == 'بورسعيد') return 'بورسعيد';
    if (s == 'كفرشيخ') return 'كفرالشيخ';
    if (s == 'كفرالشيخ') return 'كفرالشيخ';
    if (s == 'دقهليه') return 'الدقهلية';
    if (s == 'الدقهليه') return 'الدقهلية';
    if (s == 'اسماعيليه') return 'الاسماعيلية';
    if (s == 'الاسماعيليه') return 'الاسماعيلية';
    return s;
  }

  double _governorateMatchScore(String sheetGov, String orderGov) {
    final a = _normalizeGovernorateForMatch(sheetGov);
    final b = _normalizeGovernorateForMatch(orderGov);
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;
    if (a.contains(b) || b.contains(a)) return 0.85;
    return 0.0;
  }

  Map<String, String>? _findBestCustomerForSheetRow({
    required String sheetName,
    required String sheetGov,
    required String sheetPhone,
  }) {
    if (customers.isEmpty) return null;

    Map<String, String>? best;
    double bestScore = 0.0;
    for (final c in customers) {
      final nameScore = _nameMatchScore(sheetName, c['name'] ?? '');
      final govScore = _governorateMatchScore(sheetGov, c['governorate'] ?? '');
      final cPhone = _normalizePhone(c['phone'] ?? '');
      final cPhones = (c['phones'] ?? '').split(',').map(_normalizePhone).where((x) => x.isNotEmpty).toSet();
      final phoneScore = (sheetPhone.isNotEmpty && (cPhone == sheetPhone || cPhones.contains(sheetPhone))) ? 1.0 : 0.0;

      var score = (nameScore * 0.65) + (govScore * 0.25) + (phoneScore * 0.10);
      if (phoneScore >= 1.0 && nameScore >= 0.45) {
        score = score < 0.95 ? 0.95 : score;
      } else if (nameScore >= 0.82 && govScore >= 0.85) {
        score = score < 0.90 ? 0.90 : score;
      }

      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (best == null) return null;
    if (bestScore >= 0.70) return best;
    return null;
  }

  Map<String, int> _extractModelCountsFromOrder(Map<String, String> order) {
    final out = <String, int>{'15': 0, '16': 0, '17': 0};
    final baseModel = _normalizeModelFromAi(order['model'] ?? '');
    final modelsRaw = (order['models'] ?? '').trim();
    final modelParts = modelsRaw
        .split('|')
        .map((x) => _normalizeModelFromAi(x))
        .where((x) => x.isNotEmpty)
        .toList();

    final count = _parseIntSafe(order['count'] ?? '1');
    final safeCount = count <= 0 ? 1 : count;

    for (int i = 0; i < safeCount; i++) {
      final m = (i < modelParts.length && modelParts[i].isNotEmpty) ? modelParts[i] : baseModel;
      if (m.startsWith('15')) out['15'] = (out['15'] ?? 0) + 1;
      if (m.startsWith('16')) out['16'] = (out['16'] ?? 0) + 1;
      if (m.startsWith('17')) out['17'] = (out['17'] ?? 0) + 1;
    }

    if ((out['15'] ?? 0) + (out['16'] ?? 0) + (out['17'] ?? 0) == 0) {
      if (baseModel.startsWith('15')) out['15'] = safeCount;
      if (baseModel.startsWith('16')) out['16'] = safeCount;
      if (baseModel.startsWith('17')) out['17'] = safeCount;
    }
    return out;
  }

  int _parseIntSafe(String v) => int.tryParse(_toWesternDigits(v).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  Future<String> _deleteOrderAction(String name, String? governorate) async {
    _pushUndo("ط­ط°ظپ ط£ظˆط±ط¯ط±");
    final requested = _normalizeArabicName(name);
    final requestedGov = governorate == null ? '' : _normalizeArabicName(governorate);
    final before = orders.length;
    orders.removeWhere((o) {
      final orderName = _normalizeArabicName(o['name'] ?? '');
      final sameName = orderName == requested || orderName.contains(requested) || requested.contains(orderName);
      if (!sameName) return false;
      if (requestedGov.isEmpty) return true;
      final orderGov = _normalizeArabicName(o['governorate'] ?? '');
      return orderGov == requestedGov;
    });
    final removed = before - orders.length;
    await _saveData();
    await _addLogEntry("ط­ط°ظپ ط£ظˆط±ط¯ط±", "ط§ظ„ط§ط³ظ…: $name\nط§ظ„ط¹ط¯ط¯ ط§ظ„ظ…ط­ط°ظˆظپ: $removed");
    return removed > 0
        ? "âœ… ط­ط§ط¶ط± ظٹط§ ظ‡ظ†ط¯ط³ط©طŒ ظ…ط³ط­طھ ط£ظˆط±ط¯ط± ط§ظ„ط¹ظ…ظٹظ„ ($name)"
        : "âڑ ï¸ڈ ظ…ظ„ظ‚طھط´ ط£ظˆط±ط¯ط± ط¨ط§ظ„ط§ط³ظ… ط¯ظ‡: $name";
  }

  Future<String> _cancelOrderAction(String name, String? governorate) async {
    _pushUndo("ط¥ظ„ط؛ط§ط، ط£ظˆط±ط¯ط±");
    final requested = _normalizeArabicName(name);
    final requestedGov = governorate == null ? '' : _normalizeArabicName(governorate);
    var canceled = 0;
    for (final o in orders) {
      final orderName = _normalizeArabicName(o['name'] ?? '');
      final sameName = orderName == requested || orderName.contains(requested) || requested.contains(orderName);
      if (!sameName) continue;
      final orderGov = _normalizeArabicName(o['governorate'] ?? '');
      if (requestedGov.isNotEmpty && orderGov != requestedGov) continue;
      o['status'] = 'cancelled';
      o['cancelled_at'] = DateTime.now().toIso8601String();
      canceled++;
    }
    await _saveData();
    await _addLogEntry("ط¥ظ„ط؛ط§ط، ط£ظˆط±ط¯ط±", "ط§ظ„ط§ط³ظ…: $name\nط§ظ„ط¹ط¯ط¯ ط§ظ„ظ…ظ„ط؛ظٹ: $canceled");
    return canceled > 0
        ? "âœ… طھظ… ط¥ظ„ط؛ط§ط، ط£ظˆط±ط¯ط± ط§ظ„ط¹ظ…ظٹظ„ ($name)"
        : "âڑ ï¸ڈ ظ…ظ„ظ‚طھط´ ط£ظˆط±ط¯ط± ظ„ط¥ظ„ط؛ط§ط،ظ‡ ط¨ط§ظ„ط§ط³ظ… ط¯ظ‡: $name";
  }

  Future<String> _addStockAction(String model, String color, int count) async {
    final modelKey = _normalizeModelFromAi(model);
    if (modelKey.isEmpty || !_stockModels.containsKey(modelKey)) {
      return "â‌Œ ظ…ظˆط¯ظٹظ„ ط؛ظٹط± ظ…ط¹ط±ظˆظپ: $model";
    }
    if (count <= 0) return "â‌Œ ط§ظ„ط¹ط¯ط¯ ظ„ط§ط²ظ… ظٹظƒظˆظ† ط£ظƒط¨ط± ظ…ظ† طµظپط±";

    String resolvedColor = color.trim();
    final knownColors = _stockModels[modelKey]!;
    final exact = knownColors.where((c) => c == resolvedColor).toList();
    if (exact.isEmpty) {
      final fallback = knownColors.firstWhere((c) => c.toLowerCase() == resolvedColor.toLowerCase(), orElse: () => '');
      if (fallback.isEmpty) return "â‌Œ ط§ظ„ظ„ظˆظ† ط؛ظٹط± ظ…ظˆط¬ظˆط¯ ظ„ظ„ظ…ظˆط¯ظٹظ„ $modelKey: $color";
      resolvedColor = fallback;
    }

    _pushUndo("طھظˆط±ظٹط¯ AI");
    setState(() {
      colorStock[modelKey]![resolvedColor] = (colorStock[modelKey]![resolvedColor] ?? 0) + count;
      _syncTotalsFromColorStock();
    });
    await _addLogEntry("طھظˆط±ظٹط¯ AI", "ط§ظ„ظ…ظˆط¯ظٹظ„: $modelKey\nط§ظ„ظ„ظˆظ†: $resolvedColor\nط§ظ„ط¹ط¯ط¯: +$count");
    return "ًں“¦ طھظ…ط§ظ…طŒ ط²ظˆط¯طھ ط§ظ„ظ…ط®ط²ظ† ط¨ظ€ $count ط£ط¬ظ‡ط²ط© $modelKey - $resolvedColor";
  }

  Future<String> _checkStockAction() async {
    _syncTotalsFromColorStock();
    _syncHomeTotalsFromColorStock();
    return "ًں“ٹ ط§ظ„ظ…ط®ط²ظ† ط§ظ„ط±ط¦ظٹط³ظٹ:\n15 Pro Max: $stock15\n16 Pro Max: $stock16\n17 Pro Max: $stock17\n\nًںڈ  ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ:\n15 Pro Max: $homeStock15\n16 Pro Max: $homeStock16\n17 Pro Max: $homeStock17";
  }

  Future<String> _bulkImportOrdersAction(List<Map<String, dynamic>> ordersRaw) async {
    final incoming = ordersRaw.map(_dynamicOrderToStringMap).toList();
    if (!mounted) return 'طھظ… ط§ظ„ط¥ظ„ط؛ط§ط،.';

    final reviewed = await Navigator.of(context).push<List<Map<String, String>>>(
      MaterialPageRoute(
        builder: (_) => OrderReviewPage(
          orders: incoming,
          modelColors: _stockModels,
          homeStock: homeColorStock,
        ),
      ),
    );

    if (reviewed == null) return 'طھظ… ط§ظ„ط¥ظ„ط؛ط§ط،.';

    for (final o in reviewed) {
      final price = _parseIntSafe(o['price'] ?? '');
      final shipping = _parseIntSafe(o['shipping'] ?? '0');
      final discount = _parseIntSafe(o['discount'] ?? '0');
      final codTotal = price > 0 ? (price - discount + shipping) : 0;
      if (codTotal > 0) o['cod_total'] = codTotal.toString();
    }
    return _applyIncomingOrdersToHomeStock(reviewed, logSource: 'ط§ط³طھظٹط±ط§ط¯ ظˆط§طھط³ط§ط¨ (ظ…ط±ط§ط¬ط¹ط©)');
  }

  void _openAiAssistant({int initialTabIndex = 0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIAssistantScreen(
          onDeleteOrder: _deleteOrderAction,
          onCancelOrder: _cancelOrderAction,
          onAddStock: _addStockAction,
          onCheckStock: _checkStockAction,
          onBulkImport: _bulkImportOrdersAction,
          initialTabIndex: initialTabIndex,
        ),
      ),
    );
  }

  void _confirmClearStock() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        title: const Text("ظ…ط³ط­ ط§ظ„ظ…ط®ط²ظˆظ†", textAlign: TextAlign.right),
        content: const Text("ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒط¯ ظ…ظ† ظ…ط³ط­ ظƒظ„ ظƒظ…ظٹط§طھ ط§ظ„ظ…ط®ط²ظˆظ†طں ط³ظٹطھظ… طھطµظپظٹط± ظ…ط®ط²ظˆظ† ط§ظ„ط£ط¬ظ‡ط²ط© ظپظ‚ط·.", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ط¥ظ„ط؛ط§ط،")),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              _pushUndo("ظ…ط³ط­ ظ…ط®ط²ظˆظ†");
              setState(() {
                colorStock = _createDefaultColorStock();
                _syncTotalsFromColorStock();
                count15Controller.clear();
                count16Controller.clear();
                count17Controller.clear();
              });
              await _addLogEntry("ظ…ط³ط­ ظ…ط®ط²ظˆظ†", "طھظ… طھطµظپظٹط± ظƒظ„ ظƒظ…ظٹط§طھ ط§ظ„ط£ط¬ظ‡ط²ط© ظ…ظ† ط§ظ„ظ‚ط§ط¦ظ…ط© ط§ظ„ط¬ط§ظ†ط¨ظٹط©");
              await _saveData();
              if (!mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              messenger.showSnackBar(const SnackBar(content: Text("طھظ… ظ…ط³ط­ ط§ظ„ظ…ط®ط²ظˆظ† ط¨ظ†ط¬ط§ط­")));
            },
            child: const Text("ظ†ط¹ظ…طŒ ط§ظ…ط³ط­ ط§ظ„ظ…ط®ط²ظˆظ†", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _clearInputs() {
    collectionController.clear();
    expensesController.clear();
    count15Controller.clear();
    count16Controller.clear();
    count17Controller.clear();
  }

  Future<void> _addLogEntry(String actionType, String details) async {
    DateTime now = DateTime.now();
    String formattedDate = "${now.year}/${now.month}/${now.day} - ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    String newEntry = "[$formattedDate] $actionType:\n$details";
    setState(() {
      inventoryLog.insert(0, newEntry);
    });
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("طھط¹ط°ط± ظ‚ط±ط§ط،ط© ظ…ط³ط§ط± ط§ظ„ظ…ظ„ظپ")));
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
          score += sheetRows.length ~/ 20;

          if (score > bestScore) {
            bestScore = score;
            selectedTable = table;
          }
        }

        if (selectedTable == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط´ظٹطھ طµط§ظ„ط­ ظ„ظ„طھط­ظ„ظٹظ„")));
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

      int findHeaderExactPriority(List<String> exactOrPreferred, List<String> fallbackContains) {
        for (final key in exactOrPreferred) {
          for (int i = 0; i < headers.length; i++) {
            final h = headers[i];
            if (h.trim() == key || h.contains(key)) return i;
          }
        }
        for (int i = 0; i < headers.length; i++) {
          final h = headers[i];
          for (final key in fallbackContains) {
            if (h.contains(key)) return i;
          }
        }
        return -1;
      }

      int amountIndex = findHeaderIndex(['cod amount', 'amount cod', 'cod amt', 'طھط­طµظٹظ„']);
      if (amountIndex == -1) amountIndex = findHeaderByAll(['cod', 'amount']);

      int feeIndex = findHeaderIndex(['cod service fee', 'service fee', 'cod fee', 'ط±ط³ظˆظ…']);
      if (feeIndex == -1) feeIndex = findHeaderByAll(['cod', 'fee']);

      int shippingIndex = findHeaderIndex(['total freight', 'shipping cost', 'shipping fee', 'shipping', 'freight', 'ط´ط­ظ†']);
      int receiverNameIndex = findHeaderExactPriority(
        ['receiver name', 'consignee name', 'receiver', 'consignee', 'ط§ط³ظ… ط§ظ„ظ…ط³طھظ„ظ…'],
        ['receiver', 'consignee', 'ط§ط³ظ… ط§ظ„ظ…ط³طھظ„ظ…', 'receiver name'],
      );
      int destinationIndex = findHeaderExactPriority(
        ['destination', 'governorate', 'city', 'ط§ظ„ظ…ط­ط§ظپط¸ط©', 'ط§ظ„ظ…ط­ط§ظپط¸ظ‡'],
        ['destination', 'governorate', 'city', 'ظ…ط­ط§ظپط¸ط©', 'ط§ظ„ظ…ط­ط§ظپط¸ظ‡'],
      );
      int receiverPhoneIndex = findHeaderExactPriority(
        ['receiver mobile', 'receiver phone', 'consignee mobile', 'consignee phone', 'mobile', 'phone', 'ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ', 'طھظ„ظٹظپظˆظ†'],
        ['receiver', 'consignee', 'mobile', 'phone', 'ظ‡ط§طھظپ', 'طھظ„ظٹظپظˆظ†'],
      );

      if (feeIndex == -1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ظ…ط´ ظ„ط§ظ‚ظٹ ط¹ظ…ظˆط¯ COD Service Fee")));
        return;
      }

      double totalCodAmount = 0.0;
      double totalServiceFee = 0.0;
      double totalShipping = 0.0;
      double totalNet = 0.0;
      double totalDeductions = 0.0;
      int count = 0;

      int auto15 = 0;
      int auto16 = 0;
      int auto17 = 0;
      final usedOrderIndices = <int>{};
      int matchedDelivered = 0;
      int unmatchedDelivered = 0;
      final matchedRows = <Map<String, String>>[];
      final unmatchedRows = <Map<String, String>>[];

      int findBestOrderIndex(String sheetName, String sheetGov) {
        final targetName = _normalizeArabicName(sheetName);
        final targetGov = _normalizeGovernorateForMatch(sheetGov);
        if (targetName.isEmpty) return -1;

        bool hasTwoConsecutiveWords(String sheet, String db) {
          final words = sheet.split(' ').where((w) => w.trim().isNotEmpty).toList();
          if (words.length < 2) return false;
          for (int wi = 0; wi < words.length - 1; wi++) {
            final pair = '${words[wi]} ${words[wi + 1]}';
            if (db.contains(pair)) return true;
          }
          return false;
        }

        int bestIdx = -1;
        double bestScore = -1;
        for (int oi = 0; oi < orders.length; oi++) {
          if (usedOrderIndices.contains(oi)) continue;
          final order = orders[oi];
          final status = _normalizeArabicName(order['status'] ?? '');
          if (status == 'delivered' || status == 'cancelled' || status == 'canceled') continue;

          final dbGov = _normalizeGovernorateForMatch(order['governorate'] ?? '');
          final govMatches = targetGov.isEmpty || dbGov.isEmpty || targetGov.contains(dbGov) || dbGov.contains(targetGov);
          if (!govMatches) continue;

          final dbName = _normalizeArabicName(order['name'] ?? '');
          if (dbName.isEmpty) continue;

          final exactOrContains = targetName == dbName || targetName.contains(dbName) || dbName.contains(targetName);
          final twoWords = hasTwoConsecutiveWords(targetName, dbName);
          if (!exactOrContains && !twoWords) continue;

          final score = exactOrContains
              ? (targetName == dbName ? 3.0 : 2.0)
              : 1.0;
          if (score > bestScore) {
            bestScore = score;
            bestIdx = oi;
          }
        }
        return bestIdx;
      }

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;

        dynamic cellAt(int idx) => (idx >= 0 && idx < row.length) ? row[idx] : null;

        final amount = amountIndex != -1 ? _toDoubleSafe(cellAt(amountIndex)) : 0.0;
        final fee = _toDoubleSafe(cellAt(feeIndex));
        final shipping = shippingIndex != -1 ? _toDoubleSafe(cellAt(shippingIndex)) : 0.0;

        if (shipping > 0) totalShipping += shipping;

        final isDelivered = fee > 0;
        if (!isDelivered) continue;

        totalCodAmount += amount;
        totalServiceFee += fee;
        count++;

        final sheetName = (cellAt(receiverNameIndex)?.toString() ?? '').trim();
        final sheetGov = (cellAt(destinationIndex)?.toString() ?? '').trim();
        final sheetPhone = _normalizePhone((cellAt(receiverPhoneIndex)?.toString() ?? '').trim());

        final matchedIndex = findBestOrderIndex(sheetName, sheetGov);
        if (matchedIndex != -1) {
          usedOrderIndices.add(matchedIndex);
          final matchedOrder = orders[matchedIndex];
          matchedOrder['sheet_matched_pending'] = 'true';
          matchedOrder['sheet_matched_at'] = DateTime.now().toIso8601String();

          matchedDelivered++;
          matchedRows.add({
            'sheet_name': sheetName,
            'sheet_governorate': sheetGov,
            'sheet_phone': sheetPhone,
            'sheet_amount': amount.toStringAsFixed(0),
            'order_name': matchedOrder['name'] ?? '',
            'order_governorate': matchedOrder['governorate'] ?? '',
            'order_model': matchedOrder['model'] ?? '',
            'order_color': matchedOrder['color'] ?? '',
            'score': 'name_gov_match',
          });

          final countsByModel = _extractModelCountsFromOrder(matchedOrder);
          auto15 += countsByModel['15'] ?? 0;
          auto16 += countsByModel['16'] ?? 0;
          auto17 += countsByModel['17'] ?? 0;
        } else {
          unmatchedDelivered++;
          unmatchedRows.add({
            'sheet_name': sheetName,
            'sheet_governorate': sheetGov,
            'sheet_phone': sheetPhone,
            'sheet_amount': amount.toStringAsFixed(0),
            'reason': 'manual_select_needed (name_governorate_only)',
          });
        }
      }

      totalDeductions = totalServiceFee + totalShipping;
      totalNet = totalCodAmount - totalDeductions;

      setState(() {
        collectionController.text = totalNet.toStringAsFixed(2);
        count15Controller.text = auto15.toString();
        count16Controller.text = auto16.toString();
        count17Controller.text = auto17.toString();
        _rebuildCustomersFromOrders();
        _lastSheetMatchedRows = matchedRows;
        _lastSheetUnmatchedRows = unmatchedRows;
        _lastSheetAnalysisAt = DateTime.now().toIso8601String();
      });
      await _saveData();
      await _addLogEntry("ظ…ط·ط§ط¨ظ‚ط© طھط³ظ„ظٹظ… ط§ظ„ط´ظٹطھ", "ظ…ط·ط§ط¨ظ‚ط§طھ ط¨ط§ظ†طھط¸ط§ط± ط§ظ„طھط£ظƒظٹط¯: $matchedDelivered\nط­ط§ظ„ط§طھ ط؛ظٹط± ظ…ط¤ظƒط¯ط©: $unmatchedDelivered");
      _showResultDialog(count, totalDeductions, totalNet, auto15, auto16, auto17);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("? ط®ط·ط£: $e")));
    }
  }
void _showResultDialog(int count, double ded, double net, int a15, int a16, int a17) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text("طھظ… طھط­ظ„ظٹظ„ ط§ظ„ط´ظٹطھ ط¨ظ†ط¬ط§ط­", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20))),
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
                decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    _analysisMetricRow("ط§ظ„ط£ظˆط±ط¯ط±ط§طھ ط§ظ„ظ…ط³طھظ„ظ…ط©", count.toString()),
                    const SizedBox(height: 8),
                    _analysisMetricRow("ط¥ط¬ظ…ط§ظ„ظٹ ط§ظ„ط®طµظˆظ…ط§طھ", "${ded.toStringAsFixed(2)} ط¬.ظ…"),
                    const SizedBox(height: 8),
                    _analysisMetricRow("ط§ظ„طµط§ظپظٹ ط§ظ„ظ…ط­ظˆظ„", "${net.toStringAsFixed(2)} ط¬.ظ…", highlight: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text("ط§ظ„ط£ط¬ظ‡ط²ط© ط§ظ„ظ…طھط¹ط±ظپ ط¹ظ„ظٹظ‡ط§", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showLastSheetAnalysisDetails,
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                  label: const Text("طھظپط§طµظٹظ„ ط§ظ„طھط­ظ„ظٹظ„"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text("ط¥ط؛ظ„ط§ظ‚"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLastSheetAnalysisDetails() {
    final matched = _lastSheetMatchedRows;
    final unmatched = _lastSheetUnmatchedRows;
    if (matched.isEmpty && unmatched.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ظ„ط§ طھظˆط¬ط¯ طھظپط§طµظٹظ„ طھط­ظ„ظٹظ„ ط­ط§ظ„ظٹط§ظ‹")));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: _dialogBg(context),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
            titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("طھظپط§طµظٹظ„ طھط­ظ„ظٹظ„ ط§ظ„ط´ظٹطھ", textAlign: TextAlign.right),
                if (_lastSheetAnalysisAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _lastSheetAnalysisAt,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 8),
                TabBar(
                  tabs: [
                    Tab(text: 'ط§طھط·ط§ط¨ظ‚ (${matched.length})'),
                    Tab(text: 'ظ…ط§ ط§طھط·ط§ط¨ظ‚ط´ (${unmatched.length})'),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: TabBarView(
                children: [
                  _buildSheetAnalysisList(
                    rows: matched,
                    emptyText: "ظ„ط§ طھظˆط¬ط¯ ط´ط­ظ†ط§طھ ظ…طھط·ط§ط¨ظ‚ط©",
                    matchedMode: true,
                  ),
                  _buildSheetAnalysisList(
                    rows: unmatched,
                    emptyText: "ظ„ط§ طھظˆط¬ط¯ ط´ط­ظ†ط§طھ ط؛ظٹط± ظ…طھط·ط§ط¨ظ‚ط©",
                    matchedMode: false,
                  ),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text("ط¥ط؛ظ„ط§ظ‚"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetAnalysisList({
    required List<Map<String, String>> rows,
    required String emptyText,
    required bool matchedMode,
  }) {
    if (rows.isEmpty) {
      return Center(child: Text(emptyText, textAlign: TextAlign.center));
    }

    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = rows[i];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("ط§ظ„ط§ط³ظ… (ط§ظ„ط´ظٹطھ): ${r['sheet_name'] ?? '-'}", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text("ط§ظ„ظ…ط­ط§ظپط¸ط© (ط§ظ„ط´ظٹطھ): ${r['sheet_governorate'] ?? '-'}", textAlign: TextAlign.right),
              if ((r['sheet_phone'] ?? '').trim().isNotEmpty) Text("ط§ظ„ظ‡ط§طھظپ (ط§ظ„ط´ظٹطھ): ${r['sheet_phone']}", textAlign: TextAlign.right),
              Text("ط§ظ„ظ…ط¨ظ„ط؛: ${r['sheet_amount'] ?? '-'}", textAlign: TextAlign.right),
              if (matchedMode) ...[
                const SizedBox(height: 4),
                Text("طھظ…طھ ظ…ط·ط§ط¨ظ‚طھظ‡ ظ…ط¹: ${r['order_name'] ?? '-'}", textAlign: TextAlign.right),
                Text("ظ…ط­ط§ظپط¸ط© ط§ظ„ط£ظˆط±ط¯ط±: ${r['order_governorate'] ?? '-'}", textAlign: TextAlign.right),
                Text("ط§ظ„ظ…ظˆط¯ظٹظ„/ط§ظ„ظ„ظˆظ†: ${(r['order_model'] ?? '-')} / ${(r['order_color'] ?? '-')}", textAlign: TextAlign.right),
                Text("ط¯ط±ط¬ط© ط§ظ„طھط·ط§ط¨ظ‚: ${r['score'] ?? '-'}", textAlign: TextAlign.right),
              ] else ...[
                const SizedBox(height: 4),
                Text("ط§ظ„ط³ط¨ط¨: ${r['reason'] ?? 'ط؛ظٹط± ظ…ط­ط¯ط¯'}", textAlign: TextAlign.right),
                if (((r['inferred_15'] ?? '0') != '0') || ((r['inferred_16'] ?? '0') != '0') || ((r['inferred_17'] ?? '0') != '0'))
                  Text("طھظ‚ط¯ظٹط± ط§ظ„ط£ط¬ظ‡ط²ط©: 15=${r['inferred_15'] ?? '0'}طŒ 16=${r['inferred_16'] ?? '0'}طŒ 17=${r['inferred_17'] ?? '0'}", textAlign: TextAlign.right),
              ],
            ],
          ),
        );
      },
    );
  }

  void _confirmClearLog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        title: const Text("ظ…ط³ط­ ط³ط¬ظ„ ط§ظ„ط­ط±ظƒط§طھ", textAlign: TextAlign.right),
        content: const Text("ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒط¯ ظ…ظ† ظ…ط³ط­ ظƒظ„ ط¹ظ†ط§طµط± ط³ط¬ظ„ ط§ظ„ط­ط±ظƒط§طھطں", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ط¥ظ„ط؛ط§ط،")),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() => inventoryLog.clear());
              await _saveData();
              if (!mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              messenger.showSnackBar(const SnackBar(content: Text("طھظ… ظ…ط³ط­ ط³ط¬ظ„ ط§ظ„ط­ط±ظƒط§طھ")));
            },
            child: const Text("ظ†ط¹ظ…طŒ ط§ظ…ط³ط­ ط§ظ„ط³ط¬ظ„", style: TextStyle(color: Colors.red)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        title: const Text("ط´ط­ظ†ط§طھ ظ…طھط³ظ„ظ‘ظ…ط© ظƒط§ط´", textAlign: TextAlign.right, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("طھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ $cashDeliveredCount ط´ط­ظ†ط© ظ…طھط³ظ„ظ‘ظ…ط© ط¨ظ‚ظٹظ…ط© 1 ط¬ظ†ظٹظ‡.\nط­ط¯ط¯ ظ…ظˆط¯ظٹظ„ ط§ظ„ط£ط¬ظ‡ط²ط©:", textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
          TextButton(onPressed: () => Navigator.pop(ctx, {'15': 0, '16': 0, '17': 0}), child: const Text("طھط®ط·ظٹ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ElevatedButton(
            onPressed: () {
              final v15 = int.tryParse(c15.text) ?? 0;
              final v16 = int.tryParse(c16.text) ?? 0;
              final v17 = int.tryParse(c17.text) ?? 0;
              final total = v15 + v16 + v17;

              if (total != cashDeliveredCount) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("ظ…ط¬ظ…ظˆط¹ ط§ظ„ط£ط¬ظ‡ط²ط© ظ„ط§ط²ظ… ظٹط³ط§ظˆظٹ $cashDeliveredCount")));
                return;
              }
              Navigator.pop(ctx, {'15': v15, '16': v16, '17': v17});
            },
            child: const Text("طھط£ظƒظٹط¯", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _analysisMetricRow(String label, String value, {bool highlight = false}) => Row(
    children: [
      Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: highlight ? Colors.green : null, fontSize: 20)),
      const Spacer(),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
    ],
  );

  Widget _analysisDeviceRow(String model, int modelCount, int totalCount, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.35))),
    child: Row(
      children: [
        Text(totalCount > 0 ? "${((modelCount / totalCount) * 100).toStringAsFixed(0)}%" : "0%", style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(width: 8),
        Container(
          width: 44, height: 34, alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
          child: Text(modelCount.toString(), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 26)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(model, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
      ],
    ),
  );

  void calculateProfit() {
    double totalColl = double.tryParse(collectionController.text) ?? 0.0;
    double totalExp = double.tryParse(expensesController.text) ?? 0.0;
    double cost = ((double.tryParse(count15Controller.text) ?? 0) * price15ProMax) +
                  ((double.tryParse(count16Controller.text) ?? 0) * price16ProMax) +
                  ((double.tryParse(count17Controller.text) ?? 0) * price17ProMax);
    setState(() {
      netProfit = totalColl - cost - totalExp;
      myShare = netProfit / 2;
      partnerShare = netProfit / 2;
    });
  }

  void confirmAndDeduct() {
    int s15 = int.tryParse(count15Controller.text) ?? 0;
    int s16 = int.tryParse(count16Controller.text) ?? 0;
    int s17 = int.tryParse(count17Controller.text) ?? 0;
    
    if (s15 > stock15 || s16 > stock16 || s17 > stock17) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ط§ظ„ظ…ط®ط²ظ† ظ„ط§ ظٹظƒظپظٹ!"), backgroundColor: Colors.red));
      return;
    }
    
    calculateProfit();
    _pushUndo("ظ…ط¨ظٹط¹ط§طھ");

    Map<String, Map<String, int>> exactToDeduct = _createDefaultColorStock();
    List<Map<String, String>> ordersToMark = [];

    for (var o in orders) {
      final isDelivered = _normalizeArabicName(o['status'] ?? '') == 'delivered';
      final isPendingFromSheet = (o['sheet_matched_pending'] ?? '') == 'true';
      if ((isDelivered || isPendingFromSheet) && o['deducted_main'] != 'true') {
        final baseModel = _normalizeModelFromAi(o['model'] ?? '');
        final modelsRaw = (o['models'] ?? '').trim();
        final modelParts = modelsRaw
            .split('|')
            .map((x) => _normalizeModelFromAi(x))
            .where((x) => x.isNotEmpty)
            .toList();

        final colorsRaw = (o['colors'] ?? '').trim();
        final count = _parseIntSafe(o['count'] ?? '1');
        final safeCount = count <= 0 ? 1 : count;
        final baseColor = _normalizeArabicName(o['color'] ?? '');

        List<String> parts = colorsRaw
            .split('|')
            .map((x) => _normalizeArabicName(x))
            .where((x) => x.isNotEmpty)
            .toList();
        if (parts.isEmpty && baseColor.isNotEmpty) {
          parts = List.filled(safeCount, baseColor);
        } else if (parts.length < safeCount && baseColor.isNotEmpty) {
          parts.addAll(List.filled(safeCount - parts.length, baseColor));
        }

        var any = false;
        for (int di = 0; di < safeCount; di++) {
          final m = (di < modelParts.length && modelParts[di].isNotEmpty) ? modelParts[di] : baseModel;
          if (!exactToDeduct.containsKey(m)) continue;

          final cNorm = (di < parts.length && parts[di].isNotEmpty) ? parts[di] : baseColor;
          if (cNorm.isEmpty) continue;

          final known = _normalizeColorForModel(m, cNorm);
          if (known.isEmpty || !_stockModels[m]!.contains(known)) continue;
          exactToDeduct[m]![known] = (exactToDeduct[m]![known] ?? 0) + 1;
          any = true;
        }
        if (any) ordersToMark.add(o);
      }
    }

    setState(() {
      _smartDeduct('15 Pro Max', s15, exactToDeduct['15 Pro Max']!);
      _smartDeduct('16 Pro Max', s16, exactToDeduct['16 Pro Max']!);
      _smartDeduct('17 Pro Max', s17, exactToDeduct['17 Pro Max']!);

      for (var o in ordersToMark) {
        if ((o['sheet_matched_pending'] ?? '') == 'true') {
          o['status'] = 'delivered';
          o['delivered_at'] = DateTime.now().toIso8601String();
          o['sheet_matched_pending'] = 'false';
        }
        o['deducted_main'] = 'true';
      }

      _syncTotalsFromColorStock();
      myAccountBalance += myShare;
    });

    _saveData();
    _addLogEntry("ظ…ط¨ظٹط¹ط§طھ", "ط¨ظٹط¹: (15:$s15, 16:$s16, 17:$s17)\nط§ظ„ظ…طھط¨ظ‚ظٹ: (15:$stock15, 16:$stock16, 17:$stock17)");
    _clearInputs();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF050505) : const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('ط­ط§ط³ط¨ط© ط§ظ„ط¨ظٹط²ظ†ط³ ط§ظ„ط§ط­طھط±ط§ظپظٹط©', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2, fontSize: 20)),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: _buildDrawer(isDark),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A0A0A), Color(0xFF050505)]) : null,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle("ط¨ظٹط§ظ†ط§طھ ط§ظ„طھط­طµظٹظ„"),
              _buildSectionCard(
                isDark: isDark,
                child: Column(
                  children: [
                    _buildImportBtn(),
                    const SizedBox(height: 12),
                    _buildInput(collectionController, 'طµط§ظپظٹ ط§ظ„طھط­طµظٹظ„ ظ…ظ† J&T', Icons.payments, isDark),
                    const SizedBox(height: 12),
                    _buildInput(expensesController, 'ظ…طµط§ط±ظٹظپ ط¥ط¶ط§ظپظٹط©', Icons.money_off, isDark),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle("ط§ظ„ط£ط¬ظ‡ط²ط© ط§ظ„ظ…ط¨ط§ط¹ط© ط§ظ„ط¢ظ†"),
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
    child: Text(text, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
  );

  Widget _buildSectionCard({required bool isDark, required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF121212) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      boxShadow: isDark ? const [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: child,
  );

  Widget _buildResultCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: isDark ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF191919), Color(0xFF0B0B0B)]) : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1F2937), Color(0xFF111827)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Text("طµط§ظپظٹ ط§ظ„ط±ط¨ط­", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 18)),
          Text("${netProfit.toStringAsFixed(2)} ط¬.ظ…", style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 48, fontWeight: FontWeight.w900)),
          const Divider(color: Colors.white24, height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _shareInfo("ظ†طµظٹط¨ظƒ", myShare),
              _shareInfo("ط§ظ„ط´ط±ظٹظƒ", partnerShare),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shareInfo(String label, double val) => Column(
    children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 16)),
      Text(val.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28)),
    ],
  );

  Widget _buildImportBtn() => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: _importJAndTSheet,
      icon: const Icon(Icons.file_present),
      label: const Text("ط³ط­ط¨ ط´ظٹطھ (Excel/CSV)"),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0A84FF),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );

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
              Text("ط§ظ„ظ…ط®ط²ظˆظ†: $stock", style: TextStyle(fontSize: 15, color: stock > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.w600)),
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
          ),
        ),
      ],
    ),
  );

  Widget _buildActionButtons() => Row(
    children: [
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
          child: const Text("طھط£ظƒظٹط¯ ظˆط®طµظ… ظ…ط®ط²ظ†", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
          child: const Text("ط§ط­ط³ط¨ ط§ظ„ط±ط¨ط­", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
      ),
    ],
  );

  Drawer _buildDrawer(bool isDark) => Drawer(
    backgroundColor: isDark ? const Color(0xFF101114) : Colors.white,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text("ط§ظ„ظ‚ط§ط¦ظ…ط©", textAlign: TextAlign.right, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)),
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
                      "${myAccountBalance.toStringAsFixed(2)} ط¬.ظ…",
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF64D2FF)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text("ط­ط³ط§ط¨ظٹ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _drawerTile(icon: Icons.inventory_2_rounded, title: "ط§ظ„ظ…ط®ط²ظ†", onTap: () { Navigator.pop(context); _openWarehousePage(); }),
          _drawerTile(icon: Icons.home_work_rounded, title: "ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ", onTap: () { Navigator.pop(context); _openHomeWarehousePage(); }),
          _drawerTile(icon: Icons.history_edu_rounded, title: "ط³ط¬ظ„ ط§ظ„ط­ط±ظƒط§طھ", onTap: () { Navigator.pop(context); _showLog(); }),
          _drawerTile(icon: Icons.playlist_add_check_rounded, title: "ط§ط³طھظٹط±ط§ط¯ ط£ظˆط±ط¯ط±ط§طھ ظˆط§طھط³ط§ط¨", onTap: () { Navigator.pop(context); _openAiAssistant(initialTabIndex: 1); }),
          _drawerTile(icon: Icons.people_alt_rounded, title: "ط¯ط§طھط§ ط§ظ„ط¹ظ…ظ„ط§ط،", onTap: () { Navigator.pop(context); _openCustomersPage(); }),
          _drawerTile(icon: Icons.smart_toy_rounded, title: "ظ…ط³ط§ط¹ط¯ AI", onTap: () { Navigator.pop(context); _openAiAssistant(); }),
          _drawerTile(icon: Icons.delete_sweep_rounded, title: "ظ…ط³ط­ ظƒظ„ ط§ظ„ظ…ط®ط²ظˆظ†", danger: true, onTap: () { Navigator.pop(context); _confirmClearStock(); }),
          const SizedBox(height: 8),
          Container(height: 1, color: isDark ? Colors.white12 : Colors.black12),
          const SizedBox(height: 8),
          _drawerTile(icon: Icons.settings_rounded, title: "ط£ط³ط¹ط§ط± ط§ظ„ط´ط±ط§ط،", onTap: () { Navigator.pop(context); _showPriceDialog(); }),
        ],
      ),
    ),
  );

  Widget _drawerTile({required IconData icon, required String title, bool danger = false, required VoidCallback onTap}) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFF2B1616) : const Color(0xFF161A20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: danger ? const Color(0xFFFF453A).withValues(alpha: 0.4) : const Color(0xFF2D3340)),
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: danger ? const Color(0xFFFF453A).withValues(alpha: 0.18) : const Color(0xFF64D2FF).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: danger ? const Color(0xFFFF453A) : const Color(0xFF64D2FF), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, textAlign: TextAlign.right, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: danger ? const Color(0xFFFF6B62) : const Color(0xFFF3F4F6)))),
          Icon(Icons.chevron_right_rounded, size: 22, color: danger ? const Color(0xFFFF6B62) : const Color(0xFF8E8E93)),
        ],
      ),
    ),
  );

  Future<void> _openWarehousePage() async {
    final updatedStock = await Navigator.push<Map<String, Map<String, int>>>(
      context,
      MaterialPageRoute(
        builder: (_) => WarehousePage(
          initialStock: _cloneColorStock(colorStock),
          title: 'ط§ظ„ظ…ط®ط²ظ† ط§ظ„ط±ط¦ظٹط³ظٹ',
          saveLabel: 'ط­ظپط¸ ط§ظ„ظ…ط®ط²ظ† ط§ظ„ط±ط¦ظٹط³ظٹ',
        ),
      ),
    );

    if (!mounted || updatedStock == null) return;
    _pushUndo("طھط¹ط¯ظٹظ„ ظ…ط®ط²ظ†");
    setState(() {
      colorStock = updatedStock;
      _syncTotalsFromColorStock();
    });
    await _saveData();
    await _addLogEntry("طھط¹ط¯ظٹظ„ ظ…ط®ط²ظ†", "طھط­ط¯ظٹط« ظƒظ…ظٹط§طھ ط§ظ„ظ…ط®ط²ظ† ظ…ظ† طµظپط­ط© ط§ظ„ظ…ط®ط²ظ†\nط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ: (15:$stock15, 16:$stock16, 17:$stock17)");
  }

  Future<void> _openHomeWarehousePage() async {
    final updatedStock = await Navigator.push<Map<String, Map<String, int>>>(
      context,
      MaterialPageRoute(
        builder: (_) => WarehousePage(
          initialStock: _cloneColorStock(homeColorStock),
          title: 'ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ',
          saveLabel: 'ط­ظپط¸ ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ',
        ),
      ),
    );

    if (!mounted || updatedStock == null) return;
    _pushUndo("طھط¹ط¯ظٹظ„ ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ");
    setState(() {
      homeColorStock = updatedStock;
      _syncHomeTotalsFromColorStock();
    });
    await _saveData();
    await _addLogEntry("طھط¹ط¯ظٹظ„ ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ", "طھط­ط¯ظٹط« ظƒظ…ظٹط§طھ ظ…ط®ط²ظ† ط§ظ„ط¨ظٹطھ\nط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ: (15:$homeStock15, 16:$homeStock16, 17:$homeStock17)");
  }

  void _showLog() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: const Text("ط³ط¬ظ„ ط§ظ„ط­ط±ظƒط§طھ", textAlign: TextAlign.right),
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
                      const Text("ظ„ط§ طھظˆط¬ط¯ ط­ط±ظƒط§طھ ظ…ط³ط¬ظ„ط© ط¨ط¹ط¯"),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: inventoryLog.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (c, i) => _buildLogItem(inventoryLog[i], isDark),
                ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _undoStack.isEmpty
                      ? null
                      : () async {
                          final selectedIndex = await showModalBottomSheet<int>(
                            context: context,
                            showDragHandle: true,
                            backgroundColor: _dialogBg(context),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                            ),
                            builder: (sheetCtx) {
                              final items = _undoStack.reversed.toList();
                              return Directionality(
                                textDirection: TextDirection.rtl,
                                child: SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.undo_rounded, size: 18),
                                            const SizedBox(width: 8),
                                            const Expanded(
                                              child: Text(
                                                "ط§ط®طھط± ط§ظ„ط¹ظ…ظ„ظٹط© ط§ظ„طھظٹ طھط±ظٹط¯ ط§ظ„طھط±ط§ط¬ط¹ ط¹ظ†ظ‡ط§",
                                                style: TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1),
                                      Flexible(
                                        child: ListView.separated(
                                          shrinkWrap: true,
                                          itemCount: items.length,
                                          separatorBuilder: (_, __) => const Divider(height: 1),
                                          itemBuilder: (_, i) {
                                            final s = items[i];
                                            final realIndex = _undoStack.length - 1 - i;
                                            return ListTile(
                                              title: Text(s.label, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                                              subtitle: Text(_formatUndoIso(s.at), textAlign: TextAlign.right),
                                              trailing: const Icon(Icons.undo_rounded),
                                              onTap: () => Navigator.pop(sheetCtx, realIndex),
                                            );
                                          },
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () => Navigator.pop(sheetCtx),
                                                icon: const Icon(Icons.close_rounded, size: 18),
                                                label: const Text("ط¥ظ„ط؛ط§ط،"),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () => Navigator.pop(sheetCtx, _undoStack.length - 1),
                                                icon: const Icon(Icons.undo_rounded, size: 18),
                                                label: const Text("ط¢ط®ط± ط¹ظ…ظ„ظٹط©"),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );

                          if (!mounted) return;
                          if (selectedIndex == null) return;

                          final picked = _undoStack[selectedIndex];
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c2) => AlertDialog(
                              backgroundColor: _dialogBg(context),
                              surfaceTintColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
                              title: const Text("طھط£ظƒظٹط¯ ط§ظ„طھط±ط§ط¬ط¹", textAlign: TextAlign.right),
                              content: Text(
                                "ط³ظٹطھظ… ط§ظ„ط±ط¬ظˆط¹ ظ„ظ„ط­ط§ظ„ط© ظ‚ط¨ظ„ ط§ظ„ط¹ظ…ظ„ظٹط©:\n${picked.label}\n${_formatUndoIso(picked.at)}\n\nظ…ظ„ط§ط­ط¸ط©: ط£ظٹ ط¹ظ…ظ„ظٹط§طھ طھظ…طھ ط¨ط¹ط¯ظ‡ط§ ط³ظٹطھظ… ط¥ظ„ط؛ط§ط¤ظ‡ط§.",
                                textAlign: TextAlign.right,
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text("ط¥ظ„ط؛ط§ط،")),
                                ElevatedButton(onPressed: () => Navigator.pop(c2, true), child: const Text("طھط±ط§ط¬ط¹")),
                              ],
                            ),
                          );
                          if (!mounted) return;
                          if (confirm != true) return;

                          final ok = await _undoToIndex(selectedIndex);
                          if (!mounted) return;
                          if (ctx.mounted) Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? "طھظ… ط§ظ„طھط±ط§ط¬ط¹ ط¨ظ†ط¬ط§ط­" : "ظ„ط§ ظٹظˆط¬ط¯ ظ…ط§ ظٹظ…ظƒظ† ط§ظ„طھط±ط§ط¬ط¹ ط¹ظ†ظ‡")),
                          );
                        },
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text("طھط±ط§ط¬ط¹"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: inventoryLog.isEmpty ? null : _confirmClearLog,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  label: const Text("ظ…ط³ط­ ط§ظ„ط³ط¬ظ„"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text("ط¥ط؛ظ„ط§ظ‚"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCustomersDatabase() {
    final searchCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<Map<String, String>> filtered = List<Map<String, String>>.from(customers);
    bool selectionMode = false;
    final selectedKeys = <String>{};

    String formatIso(String iso) {
      try {
        final dt = DateTime.parse(iso).toLocal();
        return "${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}";
      } catch (_) {
        return iso;
      }
    }

    String customerKey(Map<String, String> c) {
      final phone = _normalizePhone(c['phone'] ?? '');
      if (phone.isNotEmpty) return 'p:$phone';
      final addr = _normalizeArabicName(c['address'] ?? '');
      if (addr.isNotEmpty) return 'a:$addr';
      return 'n:${_normalizeArabicName(c['name'] ?? '')}|g:${_normalizeArabicName(c['governorate'] ?? '')}';
    }

    bool orderMatchesCustomer(Map<String, String> o, Map<String, String> c) {
      final cPhone = _normalizePhone(c['phone'] ?? '');
      final cPhones = (c['phones'] ?? '').split(',').map(_normalizePhone).where((x) => x.isNotEmpty).toSet();
      if (cPhone.isNotEmpty || cPhones.isNotEmpty) {
        final op = _normalizePhone(o['phone'] ?? '');
        final oPhones = (o['phones'] ?? '').split(',').map(_normalizePhone).where((x) => x.isNotEmpty).toSet();
        if (cPhone.isNotEmpty && (op == cPhone || oPhones.contains(cPhone))) return true;
        for (final p in cPhones) {
          if (p.isNotEmpty && (op == p || oPhones.contains(p))) return true;
        }
      }

      final cAddr = _normalizeArabicName(c['address'] ?? '');
      if (cAddr.isNotEmpty) {
        final oa = _normalizeArabicName(o['address'] ?? '');
        if (oa.isNotEmpty && (oa.contains(cAddr) || cAddr.contains(oa))) return true;
      }

      final cName = _normalizeArabicName(c['name'] ?? '');
      if (cName.isNotEmpty) {
        final on = _normalizeArabicName(o['name'] ?? '');
        if (on.isNotEmpty && (on == cName || on.contains(cName) || cName.contains(on))) {
          final cGov = _normalizeArabicName(c['governorate'] ?? '');
          if (cGov.isEmpty) return true;
          final og = _normalizeArabicName(o['governorate'] ?? '');
          return og.isNotEmpty && (og.contains(cGov) || cGov.contains(og));
        }
      }

      return false;
    }

    Future<void> normalizeOrders() async {
      int changed = 0;
      for (final o in orders) {
        final beforePhone = o['phone'] ?? '';
        final beforePhones = o['phones'] ?? '';

        final list = <String>[];
        final p = _normalizePhone(beforePhone);
        if (p.isNotEmpty) list.add(p);
        if (beforePhones.trim().isNotEmpty) {
          for (final raw in beforePhones.split(',')) {
            final n = _normalizePhone(raw);
            if (n.isNotEmpty) list.add(n);
          }
        }
        final unique = list.toSet().toList();
        final nextPhone = unique.isNotEmpty ? unique.first : '';
        final nextPhones = unique.length > 1 ? unique.join(',') : '';

        if (nextPhone != _normalizePhone(beforePhone) || nextPhones != beforePhones.trim()) {
          o['phone'] = nextPhone;
          if (nextPhones.isEmpty) {
            o.remove('phones');
          } else {
            o['phones'] = nextPhones;
          }
          changed++;
        }
      }

      _rebuildCustomersFromOrders();
      await _saveData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("طھظ… طھظ†ط¸ظٹظپ ط£ط±ظ‚ط§ظ… ط§ظ„ظ‡ظˆط§طھظپ (طھط­ط¯ظٹط« $changed ط£ظˆط±ط¯ط±)")));
    }

    Future<void> deleteCustomer(Map<String, String> customer) async {
      final key = customerKey(customer);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: _dialogBg(context),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
          title: const Text("ظ…ط³ط­ ط¹ظ…ظٹظ„", textAlign: TextAlign.right),
          content: Text(
            "ط¯ظ‡ ظ‡ظٹظ…ط³ط­ ظƒظ„ ط£ظˆط±ط¯ط±ط§طھ ط§ظ„ط¹ظ…ظٹظ„ ط¯ظ‡ ظ…ظ† ط§ظ„طھط·ط¨ظٹظ‚.\n\nط§ظ„ط¹ظ…ظٹظ„: ${customer['name'] ?? '-'}\nط§ظ„ظ‡ط§طھظپ: ${customer['phone'] ?? '-'}\n\nظ…طھط£ظƒط¯طں",
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("ط¥ظ„ط؛ط§ط،")),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("ظ…ط³ط­", style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm != true) return;

      final before = orders.length;
      orders.removeWhere((o) => orderMatchesCustomer(o, customer));
      final removed = before - orders.length;

      _rebuildCustomersFromOrders();
      await _saveData();
      selectedKeys.remove(key);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("طھظ… ظ…ط³ط­ $removed ط£ظˆط±ط¯ط±")));
    }

    Future<void> deleteSelectedCustomers(StateSetter setStateDialog) async {
      if (selectedKeys.isEmpty) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: _dialogBg(context),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
          title: const Text("ظ…ط³ط­ ط§ظ„ظ…ط­ط¯ط¯", textAlign: TextAlign.right),
          content: Text(
            "ط¯ظ‡ ظ‡ظٹظ…ط³ط­ ظƒظ„ ط£ظˆط±ط¯ط±ط§طھ ط§ظ„ط¹ظ…ظ„ط§ط، ط§ظ„ظ…ط­ط¯ط¯ظٹظ† (${selectedKeys.length}).\nظ…طھط£ظƒط¯طں",
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("ط¥ظ„ط؛ط§ط،")),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("ظ…ط³ط­", style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm != true) return;

      int removedOrders = 0;
      final keysNow = selectedKeys.toList();
      for (final k in keysNow) {
        final customer = customers.firstWhere(
          (c) => customerKey(c) == k,
          orElse: () => <String, String>{},
        );
        if (customer.isEmpty) continue;
        final before = orders.length;
        orders.removeWhere((o) => orderMatchesCustomer(o, customer));
        removedOrders += before - orders.length;
      }

      _rebuildCustomersFromOrders();
      await _saveData();

      setStateDialog(() {
        selectedKeys.clear();
        selectionMode = false;
        filtered = List<Map<String, String>>.from(customers);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("طھظ… ظ…ط³ط­ $removedOrders ط£ظˆط±ط¯ط±")));
    }

    Future<void> editCustomer(Map<String, String> customer) async {
      final nameCtrl = TextEditingController(text: customer['name'] ?? '');
      final phoneCtrl = TextEditingController(text: customer['phone'] ?? '');
      final govCtrl = TextEditingController(text: customer['governorate'] ?? '');
      final addrCtrl = TextEditingController(text: customer['address'] ?? '');
      final oldPhone = _normalizePhone(customer['phone'] ?? '');
      final oldAddr = _normalizeArabicName(customer['address'] ?? '');
      final oldName = _normalizeArabicName(customer['name'] ?? '');
      final oldGov = _normalizeArabicName(customer['governorate'] ?? '');

      final saved = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: _dialogBg(context),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
          title: const Text("طھط¹ط¯ظٹظ„ ط¨ظٹط§ظ†ط§طھ ط¹ظ…ظٹظ„", textAlign: TextAlign.right),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "ط§ظ„ط§ط³ظ…")),
                const SizedBox(height: 8),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "ط§ظ„ظ‡ط§طھظپ")),
                const SizedBox(height: 8),
                TextField(controller: govCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "ط§ظ„ظ…ط­ط§ظپط¸ط©")),
                const SizedBox(height: 8),
                TextField(controller: addrCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "ط§ظ„ط¹ظ†ظˆط§ظ†")),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("ط¥ظ„ط؛ط§ط،")),
            ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("ط­ظپط¸")),
          ],
        ),
      );

      if (saved != true) return;

      final newName = nameCtrl.text.trim();
      final newPhone = _normalizePhone(phoneCtrl.text);
      final newGov = govCtrl.text.trim();
      final newAddr = addrCtrl.text.trim();

      int updated = 0;
      for (final o in orders) {
        if (!orderMatchesCustomer(o, customer)) continue;

        if (newName.isNotEmpty) o['name'] = newName;
        if (newGov.isNotEmpty) o['governorate'] = newGov;
        if (newAddr.isNotEmpty) o['address'] = newAddr;

        if (newPhone.isNotEmpty) {
          final extras = <String>{};
          final op = _normalizePhone(o['phone'] ?? '');
          if (op.isNotEmpty) extras.add(op);
          final beforeExtras = (o['phones'] ?? '').split(',').map(_normalizePhone).where((x) => x.isNotEmpty);
          extras.addAll(beforeExtras);
          extras.add(newPhone);

          o['phone'] = newPhone;
          final list = extras.toList();
          list.removeWhere((x) => x == newPhone);
          if (list.isEmpty) {
            o.remove('phones');
          } else {
            o['phones'] = list.join(',');
          }
        }

        updated++;
      }

      _rebuildCustomersFromOrders();
      await _saveData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("طھظ… طھط­ط¯ظٹط« $updated ط£ظˆط±ط¯ط± ظ„ظ‡ط°ط§ ط§ظ„ط¹ظ…ظٹظ„")));
    }

    void applyFilter(StateSetter setStateDialog) {
      final q = _normalizeArabicName(searchCtrl.text);
      setStateDialog(() {
        if (q.isEmpty) {
          filtered = List<Map<String, String>>.from(customers);
        } else {
          filtered = customers.where((c) {
            final name = _normalizeArabicName(c['name'] ?? '');
            final phone = _normalizePhone(c['phone'] ?? '');
            final gov = _normalizeArabicName(c['governorate'] ?? '');
            final address = _normalizeArabicName(c['address'] ?? '');
            return name.contains(q) || phone.contains(_normalizePhone(q)) || gov.contains(q) || address.contains(q);
          }).toList();
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: _dialogBg(context),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
          title: Row(
            children: [
              IconButton(
                tooltip: selectionMode ? "ط¥ظ„ط؛ط§ط، ط§ظ„طھط­ط¯ظٹط¯" : "طھط­ط¯ظٹط¯",
                onPressed: () {
                  setStateDialog(() {
                    selectionMode = !selectionMode;
                    if (!selectionMode) selectedKeys.clear();
                  });
                },
                icon: Icon(selectionMode ? Icons.check_box_outline_blank_rounded : Icons.checklist_rounded),
              ),
              if (selectionMode)
                IconButton(
                  tooltip: "طھط­ط¯ظٹط¯ ط§ظ„ظƒظ„",
                  onPressed: () {
                    setStateDialog(() {
                      for (final c in filtered) {
                        selectedKeys.add(customerKey(c));
                      }
                    });
                  },
                  icon: const Icon(Icons.select_all_rounded),
                ),
              if (selectionMode)
                IconButton(
                  tooltip: "ظ…ط³ط­ ط§ظ„ظ…ط­ط¯ط¯",
                  onPressed: selectedKeys.isEmpty ? null : () => deleteSelectedCustomers(setStateDialog),
                  icon: Icon(Icons.delete_sweep_rounded, color: selectedKeys.isEmpty ? null : Colors.red),
                ),
              const Spacer(),
              const Expanded(
                flex: 3,
                child: Text("ط¯ط§طھط§ ط§ظ„ط¹ظ…ظ„ط§ط،", textAlign: TextAlign.right),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 480,
            child: Column(
              children: [
                TextField(
                  controller: searchCtrl,
                  textAlign: TextAlign.right,
                  onChanged: (_) => applyFilter(setStateDialog),
                  decoration: InputDecoration(
                    hintText: "ط§ط¨ط­ط« ط¨ط§ظ„ط§ط³ظ… ط£ظˆ ط§ظ„ط±ظ‚ظ… ط£ظˆ ط§ظ„ط¹ظ†ظˆط§ظ†",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              searchCtrl.clear();
                              applyFilter(setStateDialog);
                              FocusScope.of(context).unfocus();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text("ظ„ط§ ظٹظˆط¬ط¯ ط¹ظ…ظ„ط§ط،"))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            final cnt = c['orders_count'] ?? '0';
                            final lastAt = c['last_order_at'] ?? '';
                            final extraPhones = (c['phones'] ?? '').trim();
                            final k = customerKey(c);
                            final selected = selectedKeys.contains(k);
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
                                  if (selectionMode) {
                                    setStateDialog(() {
                                      if (selected) {
                                        selectedKeys.remove(k);
                                      } else {
                                        selectedKeys.add(k);
                                      }
                                    });
                                    return;
                                  }
                                  await editCustomer(c);
                                  applyFilter(setStateDialog);
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        if (selectionMode)
                                          Checkbox(
                                            value: selected,
                                            onChanged: (v) {
                                              setStateDialog(() {
                                                if (v == true) {
                                                  selectedKeys.add(k);
                                                } else {
                                                  selectedKeys.remove(k);
                                                }
                                              });
                                            },
                                          ),
                                        if (!selectionMode)
                                          IconButton(
                                            tooltip: "ظ…ط³ط­ ط§ظ„ط¹ظ…ظٹظ„",
                                            onPressed: () async {
                                              await deleteCustomer(c);
                                              applyFilter(setStateDialog);
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
                                    Text("ط§ظ„ظ‡ط§طھظپ: ${c['phone'] ?? '-'}"),
                                    if (extraPhones.isNotEmpty) Text("ط£ط±ظ‚ط§ظ… ط¥ط¶ط§ظپظٹط©: $extraPhones"),
                                    Text("ط§ظ„ظ…ط­ط§ظپط¸ط©: ${c['governorate'] ?? '-'}"),
                                    Text("ط§ظ„ط¹ظ†ظˆط§ظ†: ${(c['address'] ?? '').isEmpty ? '-' : c['address']!}"),
                                    Text("ط¹ط¯ط¯ ط§ظ„ط£ظˆط±ط¯ط±ط§طھ: $cnt"),
                                    if (lastAt.isNotEmpty) Text("ط¢ط®ط± ط£ظˆط±ط¯ط±: ${formatIso(lastAt)}"),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await normalizeOrders();
                applyFilter(setStateDialog);
              },
              child: const Text("طھظ†ط¸ظٹظپ ط§ظ„ط£ط±ظ‚ط§ظ…"),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ط¥ط؛ظ„ط§ظ‚")),
          ],
        ),
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
    final isSale = entry.contains('ظ…ط¨ظٹط¹ط§طھ') || entry.contains('ط®طµظ…') || entry.contains('AI');
    final isSupply = entry.contains('طھظˆط±ظٹط¯') || entry.contains('ط¥ط¶ط§ظپط©');
    final color = isSale ? Colors.red : isSupply ? Colors.green : Colors.orange;
    final icon = isSale ? Icons.trending_down_rounded : isSupply ? Icons.add_box_rounded : Icons.inventory_2_rounded;

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
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
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
    final lines = details.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final tripleRegExp = RegExp(r'15:([+\-]?\d+),\s*16:([+\-]?\d+),\s*17:([+\-]?\d+)');

    for (final line in lines) {
      final match = tripleRegExp.firstMatch(line);
      if (match != null) {
        result.add(
          _tripleValuesRow(
            _normalizeLogLineTitle(line),
            match.group(1)!, match.group(2)!, match.group(3)!, accent, isDark,
          ),
        );
      } else {
        result.add(Padding(padding: const EdgeInsets.only(top: 2), child: Text(line, textDirection: TextDirection.rtl, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))));
      }
    }
    return result;
  }

  Widget _tripleValuesRow(String title, String v15, String v16, String v17, Color accent, bool isDark) => Container(
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$model Pro Max", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text("$value ط¬ظ‡ط§ط²", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w900)),
        ],
      ),
    ),
  );

  String _normalizeLogLineTitle(String line) {
    if (line.contains("ط¥ط¶ط§ظپط©")) return "ط§ظ„ط¥ط¶ط§ظپط©";
    if (line.contains("ط§ظ„ط±طµظٹط¯ ط¨ط¹ط¯")) return "ط§ظ„ط±طµظٹط¯ ط¨ط¹ط¯ ط§ظ„ط¹ظ…ظ„ظٹط©";
    if (line.contains("ظ‚ط¨ظ„ ط§ظ„ط¬ط±ط¯")) return "ظ‚ط¨ظ„ ط§ظ„ط¬ط±ط¯";
    if (line.contains("ط¨ط¹ط¯ ط§ظ„ط¬ط±ط¯")) return "ط¨ط¹ط¯ ط§ظ„ط¬ط±ط¯";
    if (line.contains("ط¨ظٹط¹")) return "ط§ظ„ظ…ط¨ظٹط¹ط§طھ";
    if (line.contains("ط§ظ„ظ…طھط¨ظ‚ظٹ")) return "ط§ظ„ظ…طھط¨ظ‚ظٹ";
    return "طھظپط§طµظٹظ„";
  }

  double _toDoubleSafe(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    String s = value.toString().trim();
    if (s.isEmpty || s == '-' || s == 'null') return 0.0;
    
    const arabicNums = {'\u0660': '0', '\u0661': '1', '\u0662': '2', '\u0663': '3', '\u0664': '4', '\u0665': '5', '\u0666': '6', '\u0667': '7', '\u0668': '8', '\u0669': '9', '\u06f0': '0', '\u06f1': '1', '\u06f2': '2', '\u06f3': '3', '\u06f4': '4', '\u06f5': '5', '\u06f6': '6', '\u06f7': '7', '\u06f8': '8', '\u06f9': '9'};
    arabicNums.forEach((k, v) => s = s.replaceAll(k, v));

    s = s.replaceAll('\u066b', '.').replaceAll('\u060c', ',').replaceAll(' ', '');
    final commaCount = ','.allMatches(s).length;
    if (commaCount > 0) {
      if (!s.contains('.') && commaCount == 1) {
        final part = s.split(',');
        final decimals = part.length == 2 ? part[1].length : 0;
        if (decimals <= 2) s = s.replaceAll(',', '.');
        else s = s.replaceAll(',', '');
      } else s = s.replaceAll(',', '');
    }
    s = s.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (s.isEmpty || s == '-' || s == '.') return 0.0;
    return double.tryParse(s) ?? 0.0;
  }

  void _showPriceDialog() {
    TextEditingController p15 = TextEditingController(text: price15ProMax.toString());
    TextEditingController p16 = TextEditingController(text: price16ProMax.toString());
    TextEditingController p17 = TextEditingController(text: price17ProMax.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        title: const Text("ط£ط³ط¹ط§ط± ط§ظ„ط´ط±ط§ط،"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _priceField(p15, "ط³ط¹ط± ط§ظ„ظ€ 15"), const SizedBox(height: 8),
            _priceField(p16, "ط³ط¹ط± ط§ظ„ظ€ 16"), const SizedBox(height: 8),
            _priceField(p17, "ط³ط¹ط± ط§ظ„ظ€ 17"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                price15ProMax = double.tryParse(p15.text) ?? price15ProMax;
                price16ProMax = double.tryParse(p16.text) ?? price16ProMax;
                price17ProMax = double.tryParse(p17.text) ?? price17ProMax;
              });
              _saveData();
              Navigator.pop(ctx);
            },
            child: const Text("طھط­ط¯ظٹط«"),
          ),
        ],
      ),
    );
  }

  void _showMyAccountDialog() {
    final ctrl = TextEditingController(text: myAccountBalance.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        title: const Text("ط­ط³ط§ط¨ظٹ"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                labelText: "ط±طµظٹط¯ ط­ط³ط§ط¨ظٹ", suffixText: "ط¬.ظ…",
                filled: true, fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ط¥ظ„ط؛ط§ط،")),
          ElevatedButton(
            onPressed: () {
              final newValue = _toDoubleSafe(ctrl.text);
              setState(() => myAccountBalance = newValue);
              _saveData();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("طھظ… طھط­ط¯ظٹط« ط­ط³ط§ط¨ظٹ")));
            },
            child: const Text("ط­ظپط¸"),
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
      labelText: label, labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      filled: true, fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );

  Color _dialogBg(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF111111) : Colors.white;
  Color _dialogBorder(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12;
}

class WarehousePage extends StatefulWidget {
  const WarehousePage({super.key, required this.initialStock, this.title = 'ط§ظ„ظ…ط®ط²ظ†', this.saveLabel = 'ط­ظپط¸ ط§ظ„ظ…ط®ط²ظ†'});
  final Map<String, Map<String, int>> initialStock;
  final String title;
  final String saveLabel;

  @override
  State<WarehousePage> createState() => _WarehousePageState();
}

class _WarehousePageState extends State<WarehousePage> {
  static const Map<String, List<String>> _modelColors = {
    '15 Pro Max': ['ط³ظ„ظپط±', 'ط§ط³ظˆط¯', 'ط§ط²ط±ظ‚'],
    '16 Pro Max': ['ط³ظ„ظپط±', 'ط¯ظ‡ط¨ظٹ', 'ط§ط³ظˆط¯'],
    '17 Pro Max': ['ط¨ط±طھظ‚ط§ظ„ظٹ', 'ط³ظ„ظپط±', 'ط§ط³ظˆط¯', 'ط¯ظ‡ط¨ظٹ', 'طھظٹطھط§ظ†ظٹظˆظ…', 'ظƒط­ظ„ظٹ'],
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
    setState(() => stock[model]![color] = next);
  }

  Future<void> _editQty(String model, String color) async {
    final ctrl = TextEditingController(text: (stock[model]![color] ?? 0).toString());
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF111111) : Colors.white,
        title: Text('طھط¹ط¯ظٹظ„ $model - $color', textAlign: TextAlign.right),
        content: TextField(
          controller: ctrl, keyboardType: TextInputType.number, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), decoration: const InputDecoration(hintText: '0'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ط¥ظ„ط؛ط§ط،')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text) ?? 0), child: const Text('ط­ظپط¸')),
        ],
      ),
    );

    if (value == null || value < 0) return;
    setState(() => stock[model]![color] = value);
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF111111) : Colors.white,
        title: const Text('ظ…ط³ط­ ط§ظ„ظ…ط®ط²ظ†', textAlign: TextAlign.right),
        content: const Text('طھط£ظƒظٹط¯ طھطµظپظٹط± ظƒظ„ ظƒظ…ظٹط§طھ ط§ظ„ظ…ط®ط²ظ†طں', textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ط¥ظ„ط؛ط§ط،')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('طھطµظپظٹط±')),
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
      for (final entry in stock.entries)
        entry.key: Map<String, int>.from(entry.value),
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
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _clearAll, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'طھطµظپظٹط± ط§ظ„ظƒظ„'),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _isDark ? const Color(0xFF121212) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _isDark ? Colors.white12 : Colors.black12)),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, color: Color(0xFF64D2FF)),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('ط¥ط¬ظ…ط§ظ„ظٹ ط§ظ„ط£ط¬ظ‡ط²ط©', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  Text(_grandTotal.toString(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF64D2FF))),
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
                  label: Text(widget.saveLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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
      decoration: BoxDecoration(color: _isDark ? const Color(0xFF121212) : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _isDark ? Colors.white12 : Colors.black12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF64D2FF).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                child: Text(_modelTotal(model).toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF64D2FF))),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(model, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
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
                        child: Text(qty.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
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
                                decoration: BoxDecoration(color: _isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(8)),
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
                                decoration: BoxDecoration(color: const Color(0xFF0A84FF).withValues(alpha: 0.22), borderRadius: BorderRadius.circular(8)),
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

class _UndoSnapshot {
  const _UndoSnapshot({
    required this.label,
    required this.at,
    required this.price15ProMax,
    required this.price16ProMax,
    required this.price17ProMax,
    required this.stock15,
    required this.stock16,
    required this.stock17,
    required this.homeStock15,
    required this.homeStock16,
    required this.homeStock17,
    required this.colorStock,
    required this.homeColorStock,
    required this.orders,
    required this.customers,
    required this.inventoryLog,
    required this.netProfit,
    required this.myShare,
    required this.partnerShare,
    required this.myAccountBalance,
    required this.collectionText,
    required this.expensesText,
    required this.count15Text,
    required this.count16Text,
    required this.count17Text,
    required this.customerStatusOverrides,
  });

  final String label;
  final String at;

  final double price15ProMax;
  final double price16ProMax;
  final double price17ProMax;

  final int stock15;
  final int stock16;
  final int stock17;

  final int homeStock15;
  final int homeStock16;
  final int homeStock17;

  final Map<String, Map<String, int>> colorStock;
  final Map<String, Map<String, int>> homeColorStock;

  final List<Map<String, String>> orders;
  final List<Map<String, String>> customers;
  final List<String> inventoryLog;

  final double netProfit;
  final double myShare;
  final double partnerShare;
  final double myAccountBalance;

  final String collectionText;
  final String expensesText;
  final String count15Text;
  final String count16Text;
  final String count17Text;

  final Map<String, String> customerStatusOverrides;

  static _UndoSnapshot? fromEncoded(String encoded) {
    try {
      final raw = base64Decode(encoded);
      final jsonBytes = gzip.decode(raw);
      final text = utf8.decode(jsonBytes);
      final obj = jsonDecode(text);
      if (obj is! Map<String, dynamic>) return null;
      return _UndoSnapshot.fromJson(obj);
    } catch (_) {
      return null;
    }
  }

  String toEncoded() {
    final text = jsonEncode(toJson());
    final bytes = utf8.encode(text);
    final compressed = gzip.encode(bytes);
    return base64Encode(compressed);
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'at': at,
        'price15ProMax': price15ProMax,
        'price16ProMax': price16ProMax,
        'price17ProMax': price17ProMax,
        'stock15': stock15,
        'stock16': stock16,
        'stock17': stock17,
        'homeStock15': homeStock15,
        'homeStock16': homeStock16,
        'homeStock17': homeStock17,
        'colorStock': colorStock,
        'homeColorStock': homeColorStock,
        'orders': orders,
        'customers': customers,
        'inventoryLog': inventoryLog,
        'netProfit': netProfit,
        'myShare': myShare,
        'partnerShare': partnerShare,
        'myAccountBalance': myAccountBalance,
        'collectionText': collectionText,
        'expensesText': expensesText,
        'count15Text': count15Text,
        'count16Text': count16Text,
        'count17Text': count17Text,
        'customerStatusOverrides': customerStatusOverrides,
      };

  static _UndoSnapshot fromJson(Map<String, dynamic> j) {
    Map<String, Map<String, int>> readStock(dynamic v) {
      final out = <String, Map<String, int>>{};
      if (v is! Map) return out;
      for (final entry in v.entries) {
        final model = entry.key.toString();
        final colors = entry.value;
        if (colors is! Map) continue;
        out[model] = {
          for (final ce in colors.entries)
            ce.key.toString(): (ce.value is num) ? (ce.value as num).toInt() : int.tryParse(ce.value.toString()) ?? 0,
        };
      }
      return out;
    }

    List<Map<String, String>> readListMap(dynamic v) {
      if (v is! List) return <Map<String, String>>[];
      return v.whereType<Map>().map((m) {
        return Map<String, String>.fromEntries(
          m.entries.map((e) => MapEntry(e.key.toString(), (e.value ?? '').toString())),
        );
      }).toList();
    }

    List<String> readListString(dynamic v) => (v is List) ? v.map((e) => (e ?? '').toString()).toList() : <String>[];
    Map<String, String> readMapString(dynamic v) => (v is Map) ? v.map((k, val) => MapEntry(k.toString(), (val ?? '').toString())) : <String, String>{};

    double d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
    String s(dynamic v) => (v ?? '').toString();

    return _UndoSnapshot(
      label: s(j['label']),
      at: s(j['at']),
      price15ProMax: d(j['price15ProMax']),
      price16ProMax: d(j['price16ProMax']),
      price17ProMax: d(j['price17ProMax']),
      stock15: i(j['stock15']),
      stock16: i(j['stock16']),
      stock17: i(j['stock17']),
      homeStock15: i(j['homeStock15']),
      homeStock16: i(j['homeStock16']),
      homeStock17: i(j['homeStock17']),
      colorStock: readStock(j['colorStock']),
      homeColorStock: readStock(j['homeColorStock']),
      orders: readListMap(j['orders']),
      customers: readListMap(j['customers']),
      inventoryLog: readListString(j['inventoryLog']),
      netProfit: d(j['netProfit']),
      myShare: d(j['myShare']),
      partnerShare: d(j['partnerShare']),
      myAccountBalance: d(j['myAccountBalance']),
      collectionText: s(j['collectionText']),
      expensesText: s(j['expensesText']),
      count15Text: s(j['count15Text']),
      count16Text: s(j['count16Text']),
      count17Text: s(j['count17Text']),
      customerStatusOverrides: readMapString(j['customerStatusOverrides']),
    );
  }
}
