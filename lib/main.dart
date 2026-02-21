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
    '15 Pro Max': ['سلفر', 'اسود', 'ازرق'],
    '16 Pro Max': ['سلفر', 'دهبي', 'اسود'],
    '17 Pro Max': ['برتقالي', 'سلفر', 'اسود', 'دهبي', 'تيتانيوم', 'كحلي'],
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
      final legacyHome15 = prefs.getInt('hs15') ?? 0;
      final legacyHome16 = prefs.getInt('hs16') ?? 0;
      final legacyHome17 = prefs.getInt('hs17') ?? 0;
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

      bool loadedMainColorStock = false;
      final savedColorStock = prefs.getString('color_stock_v1');
      if (savedColorStock != null && savedColorStock.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedColorStock) as Map<String, dynamic>;
          var touched = 0;
          decoded.forEach((model, colors) {
            if (!_stockModels.containsKey(model) || colors is! Map<String, dynamic>) return;
            final target = colorStock[model]!;
            for (final color in target.keys) {
              target[color] = (colors[color] as num?)?.toInt() ?? 0;
            }
            touched++;
          });
          loadedMainColorStock = touched > 0;
        } catch (_) {}
      }
      if (!loadedMainColorStock) {
        final c15 = _stockModels['15 Pro Max']!.first;
        final c16 = _stockModels['16 Pro Max']!.first;
        final c17 = _stockModels['17 Pro Max']!.first;
        colorStock['15 Pro Max']![c15] = stock15;
        colorStock['16 Pro Max']![c16] = stock16;
        colorStock['17 Pro Max']![c17] = stock17;
        colorStock['15 Pro Max']!['سلفر'] = stock15;
        colorStock['16 Pro Max']!['سلفر'] = stock16;
        colorStock['17 Pro Max']!['سلفر'] = stock17;
      }

      bool loadedHomeColorStock = false;
      final savedHomeColorStock = prefs.getString('home_color_stock_v1');
      if (savedHomeColorStock != null && savedHomeColorStock.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedHomeColorStock) as Map<String, dynamic>;
          var touched = 0;
          decoded.forEach((model, colors) {
            if (!_stockModels.containsKey(model) || colors is! Map<String, dynamic>) return;
            final target = homeColorStock[model]!;
            for (final color in target.keys) {
              target[color] = (colors[color] as num?)?.toInt() ?? 0;
            }
            touched++;
          });
          loadedHomeColorStock = touched > 0;
        } catch (_) {}
      }
      if (!loadedHomeColorStock) {
        final c15 = _stockModels['15 Pro Max']!.first;
        final c16 = _stockModels['16 Pro Max']!.first;
        final c17 = _stockModels['17 Pro Max']!.first;
        homeColorStock['15 Pro Max']![c15] = legacyHome15;
        homeColorStock['16 Pro Max']![c16] = legacyHome16;
        homeColorStock['17 Pro Max']![c17] = legacyHome17;
      }

      for (final model in _stockModels.keys) {
        final allowed = _stockModels[model]!;
        final mainCurrent = colorStock[model] ?? <String, int>{};
        final homeCurrent = homeColorStock[model] ?? <String, int>{};
        colorStock[model] = {for (final c in allowed) c: mainCurrent[c] ?? 0};
        homeColorStock[model] = {for (final c in allowed) c: homeCurrent[c] ?? 0};
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
    final computedHome15 = homeColorStock['15 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? homeStock15;
    final computedHome16 = homeColorStock['16 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? homeStock16;
    final computedHome17 = homeColorStock['17 Pro Max']?.values.fold<int>(0, (a, b) => a + b) ?? homeStock17;
    await prefs.setDouble('p15', price15ProMax);
    await prefs.setDouble('p16', price16ProMax);
    await prefs.setDouble('p17', price17ProMax);
    await prefs.setInt('s15', stock15);
    await prefs.setInt('s16', stock16);
    await prefs.setInt('s17', stock17);
    await prefs.setInt('hs15', computedHome15);
    await prefs.setInt('hs16', computedHome16);
    await prefs.setInt('hs17', computedHome17);
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
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    return s;
  }

  String _normalizeColorNameAny(String colorRaw) {
    final c = _normalizeArabicName(colorRaw);
    if (c.isEmpty) return '';
    if (c.contains('سلفر') || c.contains('سيلفر') || c.contains('سيلڤر') || c.contains('فضي') || c.contains('فضه') || c.contains('ابيض') || c.contains('أبيض') || c.contains('silver') || c.contains('white')) return 'سلفر';
    if (c.contains('اسود') || c.contains('أسود') || c.contains('بلاك') || c.contains('black')) return 'اسود';
    if (c.contains('ازرق') || c.contains('أزرق') || c.contains('بلو') || c.contains('blue')) return 'ازرق';
    if (c.contains('دهبي') || c.contains('ذهبي') || c.contains('جولد') || c.contains('gold')) return 'دهبي';
    if (c.contains('برتقالي') || c.contains('برتقاني') || c.contains('اورنج') || c.contains('اورانج') || c.contains('أورنج') || c.contains('أورانج') || c.contains('orange')) return 'برتقالي';
    if (c.contains('كحلي') || c.contains('كحلى') || c.contains('نيلي') || c.contains('navy')) return 'كحلي';
    if (c.contains('تيتانيوم') || c.contains('طبيعي') || c.contains('ناتشورال') || c.contains('natural')) return 'تيتانيوم';
    return '';
  }

  String _normalizeColorForModel(String modelKey, String colorRaw) {
    final normalized = _normalizeColorNameAny(colorRaw).trim();
    if (normalized.isEmpty) return '';

    final allowed = _stockModels[modelKey] ?? const <String>[];
    if (allowed.contains(normalized)) return normalized;

    // Smart mapping: treat "ازرق" and "كحلي" as the same family depending on model.
    if (normalized == 'ازرق' && allowed.contains('كحلي')) return 'كحلي';
    if (normalized == 'كحلي' && allowed.contains('ازرق')) return 'ازرق';

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

    if (raw.contains('delivered') || raw.contains('تم التسليم') || raw.contains('تسليم')) {
      return (code: 'delivered', label: 'تم التسليم');
    }
    if (raw.contains('returned') || raw.contains('مرتجع') || raw.contains('رجع')) {
      return (code: 'returned', label: 'مرتجع');
    }
    if (raw.contains('canceled') || raw.contains('ملغي') || raw.contains('الغاء')) {
      return (code: 'canceled', label: 'ملغي');
    }
    if (raw.contains('review') || raw.contains('راجع')) {
      return (code: 'review', label: 'راجع');
    }

    // shipped / unknown => infer by age
    if (createdAt != null) {
      final days = now.difference(createdAt).inDays;
      if (days >= _reviewAfterDays) return (code: 'review', label: 'راجع');
    }
    return (code: 'in_transit', label: 'جاري التوصيل');
  }

  ({String code, String label}) _statusFromCode(String code) {
    switch (code) {
      case 'delivered':
        return (code: 'delivered', label: 'تم التسليم');
      case 'review':
        return (code: 'review', label: 'راجع');
      case 'returned':
        return (code: 'returned', label: 'مرتجع');
      case 'canceled':
        return (code: 'canceled', label: 'ملغي');
      case 'in_transit':
      default:
        return (code: 'in_transit', label: 'جاري التوصيل');
    }
  }

  Future<void> _setCustomerStatusOverride(String customerKey, String? statusCode) async {
    _pushUndo("تعديل حالة عميل");
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
    _pushUndo("تنظيف أرقام العملاء");
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
    _pushUndo("تعديل عميل");
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
        title: const Text("تعديل بيانات عميل", textAlign: TextAlign.right),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "الاسم")),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "الهاتف")),
              const SizedBox(height: 8),
              TextField(controller: govCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "المحافظة")),
              const SizedBox(height: 8),
              TextField(controller: addrCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "العنوان")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("إلغاء")),
          ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("حفظ")),
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
    _pushUndo("مسح عميل");
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: _dialogBg(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        title: const Text("مسح عميل", textAlign: TextAlign.right),
        content: Text(
          "ده هيمسح كل أوردرات العميل ده من التطبيق.\n\nالعميل: ${customer['name'] ?? '-'}\nالهاتف: ${customer['phone'] ?? '-'}\n\nمتأكد؟",
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("إلغاء")),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("مسح", style: TextStyle(color: Colors.red))),
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
    _pushUndo("مسح عملاء");
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

      addPart('in_transit', 'جاري');
      addPart('review', 'راجع');
      addPart('delivered', 'تم');
      addPart('returned', 'مرتجع');
      addPart('canceled', 'ملغي');

      c['status_summary'] = parts.join('، ');
      c['last_model'] = _normalizeModelFromAi(last['model'] ?? '');
      c['last_color'] = _normalizeColorNameAny(last['color'] ?? '');

      String buildSummary(Map<String, int> map) {
        if (map.isEmpty) return '';
        final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return entries.map((e) => "${e.key}×${e.value}").join('، ');
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

  // --- تحليل أوردرات الواتساب عبر السيرفر (Render) ---
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
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('AI parse_orders HTTP ${response.statusCode}: ${response.body}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return null;

      return decoded
          .whereType<Map>()
          .map((e) => _dynamicOrderToStringMap(Map<String, dynamic>.from(e)))
          .map((o) {
            final model = (o['model'] ?? '').trim();
            final baseColor = (o['color'] ?? '').trim();
            final normalizedBaseColor = model.isNotEmpty
                ? _normalizeColorForModel(model, baseColor)
                : _normalizeColorNameAny(baseColor);
            if (normalizedBaseColor.isNotEmpty) {
              o['color'] = normalizedBaseColor;
            }

            final models = (o['models'] ?? '')
                .split('|')
                .map((x) => x.trim())
                .where((x) => x.isNotEmpty)
                .toList();
            if (models.isNotEmpty) {
              o['models'] = models.join('|');
            }

            final colors = (o['colors'] ?? '')
                .split('|')
                .map((x) => x.trim())
                .where((x) => x.isNotEmpty)
                .toList();
            if (colors.isNotEmpty) {
              final mapped = List<String>.generate(colors.length, (i) {
                final m = (i < models.length && models[i].isNotEmpty) ? models[i] : model;
                return m.isNotEmpty ? _normalizeColorForModel(m, colors[i]) : _normalizeColorNameAny(colors[i]);
              }).where((x) => x.isNotEmpty).toList();
              if (mapped.isNotEmpty) {
                o['colors'] = mapped.join('|');
                if ((o['color'] ?? '').trim().isEmpty) {
                  o['color'] = mapped.first;
                }
              }
            }
            return o;
          })
          .toList();
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

    final model = _normalizeModelFromAi(s(e['model']));
    final colorsFromArray = colors.map((x) => _normalizeColorNameAny(x)).where((x) => x.isNotEmpty).toList();
    final modelsFromArray = models.map(_normalizeModelFromAi).where((x) => x.isNotEmpty).toList();
    final colorRaw = s(e['color']);
    final color = model.isNotEmpty ? _normalizeColorForModel(model, colorRaw) : _normalizeColorNameAny(colorRaw);

    return <String, String>{
      'name': s(e['name']),
      'governorate': s(e['governorate']),
      'phone': phone,
      if (phones.length > 1) 'phones': phones.join(','),
      'address': s(e['address']),
      'model': model,
      if (modelsFromArray.isNotEmpty) 'models': modelsFromArray.join('|'),
      'color': color,
      if (colorsFromArray.isNotEmpty) 'colors': colorsFromArray.join('|'),
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

  Future<String> _applyIncomingOrdersToHomeStock(List<Map<String, String>> incoming, {String logSource = 'استيراد واتساب AI'}) async {
    if (incoming.isEmpty) return 'لم يتم العثور على أوردرات في النص.';
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
        stockErrors.add("❌ الـ AI لم يستطع استنتاج بيانات الأجهزة للعميل: ${o['name'] ?? '-'}");
        continue;
      }

      bool valid = true;
      final needed = <String, Map<String, int>>{};
      for (final d in devices) {
        final m = (d['model'] ?? '').trim();
        final c = (d['color'] ?? '').trim();
        if (m.isEmpty || !_stockModels.containsKey(m)) {
          stockErrors.add("❌ موديل غير معروف للعميل: ${o['name'] ?? '-'}");
          valid = false;
          break;
        }
        if (c.isEmpty || !_stockModels[m]!.contains(c)) {
          stockErrors.add("❌ لون غير صالح للموديل ($m) للعميل: ${o['name'] ?? '-'}");
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
            stockErrors.add("⚠️ مخزن البيت غير كافي: $m ($c) للعميل ${o['name']} (مطلوب $need / متاح $available)");
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
        repeatHints.add("🔄 ${o['name'] ?? ''} (عميل متكرر)");
      }
    }

    if (stockErrors.isNotEmpty) {
      return stockErrors.take(6).join('\n');
    }

    String logDetails = "تم سحب ${incoming.length} أوردر (بالذكاء الاصطناعي)، وخصم الآتي:\n";
    for (var model in deductedSummary.keys) {
      List<String> colorParts = [];
      deductedSummary[model]!.forEach((color, qty) {
        if (qty > 0) colorParts.add("$qty $color");
      });
      if (colorParts.isNotEmpty) {
        logDetails += "- $model: (${colorParts.join('، ')})\n";
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
    return "✅ تم الاستيراد بنجاح.\n\n${logDetails.trim()}$repeats";
  }

  // --- نافذة الاستيراد الذكي للواتساب ---
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
            Text('استيراد ذكي (AI)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
              hintText: 'الصق أوردرات الواتساب بأي شكل هنا، والـ AI هيفهمها ويخصمها من مخزن البيت...',
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
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (textCtrl.text.trim().isEmpty) return;

              // إظهار Loading 
              showDialog(
                context: ctx,
                barrierDismissible: false,
                builder: (_) => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0A84FF)),
                ),
              );

              // إرسال لـ Gemini
              final incoming = await _parseOrdersWithServerAi(textCtrl.text);
              
              if (!mounted) return;
              Navigator.pop(context); // قفل الـ Loading

              if (incoming == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('❌ حدث خطأ في تحليل الذكاء الاصطناعي! تأكد من الإنترنت.'), backgroundColor: Colors.red),
                );
                return;
              }

              if (incoming.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('لم يتم العثور على أوردرات في النص.')),
                );
                return;
              }

              // الخصم الفعلي من مخزن البيت
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
                  stockErrors.add("❌ الـ AI لم يستطع استنتاج الموديل/اللون للعميل: ${o['name'] ?? '-'}");
                  continue;
                }
                
                final available = tempHome[modelKey]?[colorKey] ?? 0;
                if (available < safeQty) {
                  stockErrors.add("⚠️ مخزن البيت غير كافي: $modelKey ($colorKey) للعميل ${o['name']} (مطلوب $safeQty / متاح $available)");
                  continue;
                }
                
                tempHome[modelKey]![colorKey] = available - safeQty;
                deductedSummary[modelKey]![colorKey] = (deductedSummary[modelKey]![colorKey] ?? 0) + safeQty;
                
                final existingCustomer = _findExistingCustomer(o);
                if (existingCustomer != null) {
                  repeatHints.add("🔄 ${o['name'] ?? ''} (عميل متكرر)");
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

              String logDetails = "تم سحب ${incoming.length} أوردر (بالذكاء الاصطناعي)، وخصم الآتي:\n";
              for (var model in deductedSummary.keys) {
                List<String> colorParts = [];
                deductedSummary[model]!.forEach((color, qty) {
                  if (qty > 0) colorParts.add("$qty $color");
                });
                if (colorParts.isNotEmpty) {
                  logDetails += "- $model: (${colorParts.join('، ')})\n";
                }
              }

              setState(() {
                orders.addAll(incoming);
                homeColorStock = tempHome;
                _syncHomeTotalsFromColorStock();
                _rebuildCustomersFromOrders(); 
              });
              
              await _saveData();
              await _addLogEntry('استيراد ذكي AI', logDetails.trim());

              if (!mounted) return;
              Navigator.pop(ctx); // قفل الشاشة
              
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: _dialogBg(context),
                  title: const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                       Text('تم السحب بنجاح', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
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
                        child: const Text('عرض المتكررين', style: TextStyle(color: Colors.orange)),
                      ),
                    ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('تمام')),
                  ],
                ),
              );
            },
            child: const Text('تحليل وخصم من البيت', style: TextStyle(fontWeight: FontWeight.bold)),
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
      'اسم',
      'الاسم',
      'عميل',
      'العميل',
      'مستلم',
      'المستلم',
      'الانسه',
      'السيد',
      'السيده',
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
      'السيد',
      'سيد',
      'دكتور',
      'الدكتور',
      'استاذ',
      'الأستاذ',
      'الاستاذ',
      'الاستاذه',
      'استاذه',
      'مهندس',
      'الاسم',
      'اسم',
      'العميل',
      'عميل',
      'المستلم',
      'مستلم',
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
    s = s.replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll('محافظه', '').replaceAll('محافظة', '').replaceAll('مدينه', '').replaceAll('مدينة', '').trim();
    s = s.replaceAll(' ', '');
    if (s == 'بورسعيد' || s == 'بورسعيد') return 'بورسعيد';
    if (s == 'كفرالشيخ' || s == 'كفرشيخ') return 'كفرالشيخ';
    if (s == 'الدقهليه' || s == 'دقهليه') return 'الدقهلية';
    if (s == 'الاسماعيليه' || s == 'اسماعيليه') return 'الاسماعيلية';
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

  bool _isOrderClosedForSheetMatch(Map<String, String> order) {
    final status = _normalizeArabicName(order['status'] ?? '');
    if (status == 'delivered' || status == 'cancelled' || status == 'canceled') return true;
    return false;
  }

  bool _governorateMatchesForSheet(String sheetGov, String orderGov) {
    final a = _normalizeGovernorateForMatch(sheetGov);
    final b = _normalizeGovernorateForMatch(orderGov);
    if (a.isEmpty || b.isEmpty) return true;
    return a == b || a.contains(b) || b.contains(a);
  }

  bool _hasTwoConsecutiveWordsForSheet(String sheetName, String orderName) {
    final a = _normalizePersonNameForMatch(sheetName);
    final b = _normalizePersonNameForMatch(orderName);
    final words = a.split(' ').where((w) => w.trim().isNotEmpty).toList();
    if (words.length < 2 || b.isEmpty) return false;
    for (int i = 0; i < words.length - 1; i++) {
      final pair = '${words[i]} ${words[i + 1]}';
      if (b.contains(pair)) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _rankOrdersForSheetRow({
    required String sheetName,
    required String sheetGov,
    Set<int>? excludedOrderIndices,
  }) {
    final targetName = _normalizePersonNameForMatch(sheetName);
    final targetGov = _normalizeGovernorateForMatch(sheetGov);
    if (targetName.isEmpty) return const <Map<String, dynamic>>[];
    final excluded = excludedOrderIndices ?? const <int>{};
    final ranked = <Map<String, dynamic>>[];

    for (int oi = 0; oi < orders.length; oi++) {
      if (excluded.contains(oi)) continue;
      final order = orders[oi];
      if (_isOrderClosedForSheetMatch(order)) continue;

      final orderName = _normalizePersonNameForMatch(order['name'] ?? '');
      if (orderName.isEmpty) continue;

      final orderGov = _normalizeGovernorateForMatch(order['governorate'] ?? '');
      final govOk = _governorateMatchesForSheet(targetGov, orderGov);
      final exact = orderName == targetName;
      final partial = orderName.contains(targetName) || targetName.contains(orderName);
      final twoWords = _hasTwoConsecutiveWordsForSheet(sheetName, order['name'] ?? '');
      final nameScore = _nameMatchScore(sheetName, order['name'] ?? '');
      final acceptedByName = exact || partial || twoWords || nameScore >= 0.45;
      final accepted = govOk && acceptedByName;

      double rank = nameScore;
      if (exact) rank += 1.00;
      if (partial) rank += 0.35;
      if (twoWords) rank += 0.25;
      if (targetGov.isNotEmpty && orderGov == targetGov) rank += 0.15;
      if (!govOk) rank -= 0.50;
      if (!acceptedByName) rank -= 0.40;

      String rejectReason = 'ok';
      if (!govOk) {
        rejectReason = 'governorate_mismatch';
      } else if (!acceptedByName) {
        rejectReason = 'name_too_weak';
      }

      ranked.add({
        'index': oi,
        'order': order,
        'rank': rank,
        'name_score': nameScore,
        'accepted': accepted,
        'reject_reason': rejectReason,
      });
    }

    ranked.sort((a, b) => ((b['rank'] as double)).compareTo(a['rank'] as double));
    return ranked;
  }

  Future<void> _manualMatchUnmatchedRow(Map<String, String> row) async {
    final sheetName = (row['sheet_name'] ?? '').trim();
    final sheetGov = (row['sheet_governorate'] ?? '').trim();
    final blockedIndices = <int>{};
    for (int i = 0; i < orders.length; i++) {
      if ((orders[i]['sheet_matched_pending'] ?? '') == 'true') blockedIndices.add(i);
    }
    final candidates = _rankOrdersForSheetRow(
      sheetName: sheetName,
      sheetGov: sheetGov,
      excludedOrderIndices: blockedIndices,
    ).take(12).toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لا يوجد أوردرات متاحة للمطابقة اليدوية")));
      return;
    }

    final initialIdx = int.tryParse(row['candidate_1_index'] ?? '');
    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int? selected = initialIdx;
        return StatefulBuilder(
          builder: (ctx, setModalState) => AlertDialog(
            backgroundColor: _dialogBg(context),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
            title: const Text("مطابقة يدوية للشحنة", textAlign: TextAlign.right),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("الاسم: $sheetName", textAlign: TextAlign.right),
                  Text("المحافظة: $sheetGov", textAlign: TextAlign.right),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (_, i) {
                        final candidate = candidates[i];
                        final order = candidate['order'] as Map<String, String>;
                        final orderIdx = candidate['index'] as int;
                        final reason = candidate['reject_reason']?.toString() ?? '';
                        final accepted = candidate['accepted'] == true;
                        return RadioListTile<int>(
                          value: orderIdx,
                          groupValue: selected,
                          onChanged: (v) => setModalState(() => selected = v),
                          title: Text(order['name'] ?? '-', textAlign: TextAlign.right),
                          subtitle: Text(
                            "محافظة: ${order['governorate'] ?? '-'}\nموديل/لون: ${order['model'] ?? '-'} / ${order['color'] ?? '-'}\nالحالة: ${accepted ? 'ترشيح قوي' : reason}",
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: selected == null ? null : () => Navigator.pop(ctx, selected),
                child: const Text("تأكيد المطابقة"),
              ),
            ],
          ),
        );
      },
    );

    if (selectedIndex == null) return;
    await _applyManualSheetMatch(row, selectedIndex);
  }

  Future<void> _applyManualSheetMatch(Map<String, String> unmatchedRow, int orderIndex) async {
    if (orderIndex < 0 || orderIndex >= orders.length) return;
    final order = orders[orderIndex];
    if (_isOrderClosedForSheetMatch(order)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الأوردر غير متاح للمطابقة الآن")));
      return;
    }

    final counts = _extractModelCountsFromOrder(order);
    final current15 = _parseIntSafe(count15Controller.text);
    final current16 = _parseIntSafe(count16Controller.text);
    final current17 = _parseIntSafe(count17Controller.text);

    setState(() {
      order['sheet_matched_pending'] = 'true';
      order['sheet_matched_at'] = DateTime.now().toIso8601String();

      count15Controller.text = (current15 + (counts['15'] ?? 0)).toString();
      count16Controller.text = (current16 + (counts['16'] ?? 0)).toString();
      count17Controller.text = (current17 + (counts['17'] ?? 0)).toString();

      _removeUnmatchedRowFromAnalysis(unmatchedRow);

      _lastSheetMatchedRows = [
        {
          'sheet_name': unmatchedRow['sheet_name'] ?? '',
          'sheet_governorate': unmatchedRow['sheet_governorate'] ?? '',
          'sheet_phone': unmatchedRow['sheet_phone'] ?? '',
          'sheet_amount': unmatchedRow['sheet_amount'] ?? '',
          'order_name': order['name'] ?? '',
          'order_governorate': order['governorate'] ?? '',
          'order_model': order['model'] ?? '',
          'order_color': order['color'] ?? '',
          'score': 'manual_user_select',
        },
        ..._lastSheetMatchedRows,
      ];
      _rebuildCustomersFromOrders();
    });

    await _saveData();
    await _addLogEntry(
      "مطابقة يدوية للشيت",
      "الشحنة: ${unmatchedRow['sheet_name'] ?? '-'} / ${unmatchedRow['sheet_governorate'] ?? '-'}\nتم ربطها مع: ${order['name'] ?? '-'}",
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تمت المطابقة اليدوية بنجاح")));
  }

  void _removeUnmatchedRowFromAnalysis(Map<String, String> unmatchedRow) {
    _lastSheetUnmatchedRows = _lastSheetUnmatchedRows
        .where((r) =>
            !(identical(r, unmatchedRow) ||
                ((r['sheet_name'] ?? '') ==
                        (unmatchedRow['sheet_name'] ?? '') &&
                    (r['sheet_governorate'] ?? '') ==
                        (unmatchedRow['sheet_governorate'] ?? '') &&
                    (r['sheet_phone'] ?? '') ==
                        (unmatchedRow['sheet_phone'] ?? '') &&
                    (r['sheet_amount'] ?? '') ==
                        (unmatchedRow['sheet_amount'] ?? ''))))
        .toList();
  }

  Future<void> _manualClassifyUnmatchedRow(Map<String, String> row) async {
    final models = _stockModels.keys.toList();
    var selectedModel = models.first;
    var selectedColor = _stockModels[selectedModel]!.first;
    final countController = TextEditingController(text: '1');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) => AlertDialog(
            backgroundColor: _dialogBg(context),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _dialogBorder(context)),
            ),
            title: const Text("تحديد يدوي بدون داتا", textAlign: TextAlign.right),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("الاسم: ${row['sheet_name'] ?? '-'}", textAlign: TextAlign.right),
                  Text("المحافظة: ${row['sheet_governorate'] ?? '-'}", textAlign: TextAlign.right),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedModel,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الموديل'),
                    items: models
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setModalState(() {
                        selectedModel = v;
                        selectedColor = _stockModels[selectedModel]!.first;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedColor,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'اللون'),
                    items: _stockModels[selectedModel]!
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setModalState(() => selectedColor = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(labelText: 'العدد'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: () {
                  final count = _parseIntSafe(countController.text);
                  if (count <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("اكتب عدد صحيح أكبر من صفر")),
                    );
                    return;
                  }
                  Navigator.pop(ctx, {
                    'model': selectedModel,
                    'color': selectedColor,
                    'count': count.toString(),
                  });
                },
                child: const Text("تأكيد"),
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;
    final model = result['model'] ?? '';
    final color = result['color'] ?? '';
    final count = _parseIntSafe(result['count'] ?? '0');
    if (model.isEmpty || color.isEmpty || count <= 0) return;

    final current15 = _parseIntSafe(count15Controller.text);
    final current16 = _parseIntSafe(count16Controller.text);
    final current17 = _parseIntSafe(count17Controller.text);

    setState(() {
      if (model.startsWith('15')) {
        count15Controller.text = (current15 + count).toString();
      } else if (model.startsWith('16')) {
        count16Controller.text = (current16 + count).toString();
      } else if (model.startsWith('17')) {
        count17Controller.text = (current17 + count).toString();
      }

      _removeUnmatchedRowFromAnalysis(row);
      _lastSheetMatchedRows = [
        {
        'sheet_name': row['sheet_name'] ?? '',
        'sheet_governorate': row['sheet_governorate'] ?? '',
        'sheet_phone': row['sheet_phone'] ?? '',
        'sheet_amount': row['sheet_amount'] ?? '',
        'order_name': 'تحديد يدوي (بدون داتا)',
        'order_governorate': row['sheet_governorate'] ?? '',
        'order_model': '$model x$count',
        'order_color': color,
        'score': 'manual_no_db',
      },
        ..._lastSheetMatchedRows,
      ];
    });

    await _saveData();
    await _addLogEntry(
      "تحديد يدوي من تحليل الشيت",
      "الشحنة: ${row['sheet_name'] ?? '-'} / ${row['sheet_governorate'] ?? '-'}\nالموديل: $model\nاللون: $color\nالعدد: $count",
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم تحديد الشحنة يدويًا")),
    );
  }

  Future<String> _deleteOrderAction(String name, String? governorate) async {
    _pushUndo("حذف أوردر");
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
    await _addLogEntry("حذف أوردر", "الاسم: $name\nالعدد المحذوف: $removed");
    return removed > 0
        ? "✅ حاضر يا هندسة، مسحت أوردر العميل ($name)"
        : "⚠️ ملقتش أوردر بالاسم ده: $name";
  }

  Future<String> _cancelOrderAction(String name, String? governorate) async {
    _pushUndo("إلغاء أوردر");
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
    await _addLogEntry("إلغاء أوردر", "الاسم: $name\nالعدد الملغي: $canceled");
    return canceled > 0
        ? "✅ تم إلغاء أوردر العميل ($name)"
        : "⚠️ ملقتش أوردر لإلغاءه بالاسم ده: $name";
  }

  Future<String> _addStockAction(String model, String color, int count) async {
    final modelKey = _normalizeModelFromAi(model);
    if (modelKey.isEmpty || !_stockModels.containsKey(modelKey)) {
      return "❌ موديل غير معروف: $model";
    }
    if (count <= 0) return "❌ العدد لازم يكون أكبر من صفر";

    String resolvedColor = color.trim();
    final knownColors = _stockModels[modelKey]!;
    final exact = knownColors.where((c) => c == resolvedColor).toList();
    if (exact.isEmpty) {
      final fallback = knownColors.firstWhere((c) => c.toLowerCase() == resolvedColor.toLowerCase(), orElse: () => '');
      if (fallback.isEmpty) return "❌ اللون غير موجود للموديل $modelKey: $color";
      resolvedColor = fallback;
    }

    _pushUndo("توريد AI");
    setState(() {
      colorStock[modelKey]![resolvedColor] = (colorStock[modelKey]![resolvedColor] ?? 0) + count;
      _syncTotalsFromColorStock();
    });
    await _addLogEntry("توريد AI", "الموديل: $modelKey\nاللون: $resolvedColor\nالعدد: +$count");
    return "📦 تمام، زودت المخزن بـ $count أجهزة $modelKey - $resolvedColor";
  }

  Future<String> _checkStockAction() async {
    _syncTotalsFromColorStock();
    _syncHomeTotalsFromColorStock();
    return "📊 المخزن الرئيسي:\n15 Pro Max: $stock15\n16 Pro Max: $stock16\n17 Pro Max: $stock17\n\n🏠 مخزن البيت:\n15 Pro Max: $homeStock15\n16 Pro Max: $homeStock16\n17 Pro Max: $homeStock17";
  }

  Future<String> _bulkImportOrdersAction(List<Map<String, dynamic>> ordersRaw) async {
    final incoming = ordersRaw.map(_dynamicOrderToStringMap).toList();
    if (!mounted) return 'تم الإلغاء.';

    final reviewed = await Navigator.of(context).push<List<Map<String, String>>>(
      MaterialPageRoute(
        builder: (_) => OrderReviewPage(
          orders: incoming,
          modelColors: _stockModels,
          homeStock: homeColorStock,
        ),
      ),
    );

    if (reviewed == null) return 'تم الإلغاء.';

    for (final o in reviewed) {
      final price = _parseIntSafe(o['price'] ?? '');
      final shipping = _parseIntSafe(o['shipping'] ?? '0');
      final discount = _parseIntSafe(o['discount'] ?? '0');
      final codTotal = price > 0 ? (price - discount + shipping) : 0;
      if (codTotal > 0) o['cod_total'] = codTotal.toString();
    }
    return _applyIncomingOrdersToHomeStock(reviewed, logSource: 'استيراد واتساب (مراجعة)');
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
        title: const Text("مسح المخزون", textAlign: TextAlign.right),
        content: const Text("هل أنت متأكد من مسح كل كميات المخزون؟ سيتم تصفير مخزون الأجهزة فقط.", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              _pushUndo("مسح مخزون");
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
            child: const Text("نعم، امسح المخزون", style: TextStyle(color: Colors.red)),
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
      for (final order in orders) {
        if ((order['sheet_matched_pending'] ?? '') == 'true') {
          order['sheet_matched_pending'] = 'false';
          order['sheet_matched_at'] = '';
        }
      }

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

      int amountIndex = findHeaderIndex(['cod amount', 'amount cod', 'cod amt', 'تحصيل']);
      if (amountIndex == -1) amountIndex = findHeaderByAll(['cod', 'amount']);

      int feeIndex = findHeaderIndex(['cod service fee', 'service fee', 'cod fee', 'رسوم']);
      if (feeIndex == -1) feeIndex = findHeaderByAll(['cod', 'fee']);

      int shippingIndex = findHeaderIndex(['total freight', 'shipping cost', 'shipping fee', 'shipping', 'freight', 'شحن']);
      int receiverNameIndex = findHeaderExactPriority(
        ['receiver name', 'consignee name', 'receiver', 'consignee', 'اسم المستلم'],
        ['receiver', 'consignee', 'اسم المستلم', 'receiver name'],
      );
      int destinationIndex = findHeaderExactPriority(
        ['destination', 'governorate', 'city', 'المحافظة', 'المحافظه'],
        ['destination', 'governorate', 'city', 'محافظة', 'المحافظه'],
      );
      int receiverPhoneIndex = findHeaderExactPriority(
        ['receiver mobile', 'receiver phone', 'consignee mobile', 'consignee phone', 'mobile', 'phone', 'رقم الهاتف', 'تليفون'],
        ['receiver', 'consignee', 'mobile', 'phone', 'هاتف', 'تليفون'],
      );

      if (feeIndex == -1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("مش لاقي عمود COD Service Fee")));
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
        final targetName = _normalizePersonNameForMatch(sheetName);
        final targetGov = _normalizeGovernorateForMatch(sheetGov);
        if (targetName.isEmpty) return -1;

        final exactMatches = <int>[];
        for (int oi = 0; oi < orders.length; oi++) {
          if (usedOrderIndices.contains(oi)) continue;
          final order = orders[oi];
          if (_isOrderClosedForSheetMatch(order)) continue;
          final orderName = _normalizePersonNameForMatch(order['name'] ?? '');
          if (orderName == targetName) exactMatches.add(oi);
        }

        if (exactMatches.isNotEmpty) {
          for (final oi in exactMatches) {
            final orderGov = _normalizeGovernorateForMatch(orders[oi]['governorate'] ?? '');
            if (_governorateMatchesForSheet(targetGov, orderGov)) return oi;
          }
          return exactMatches.first;
        }

        final ranked = _rankOrdersForSheetRow(
          sheetName: sheetName,
          sheetGov: sheetGov,
          excludedOrderIndices: usedOrderIndices,
        );
        for (final c in ranked) {
          if (c['accepted'] == true) return c['index'] as int;
        }
        return -1;
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
          final ranked = _rankOrdersForSheetRow(
            sheetName: sheetName,
            sheetGov: sheetGov,
            excludedOrderIndices: usedOrderIndices,
          );
          final top3 = ranked.take(3).toList();
          for (int ci = 0; ci < top3.length; ci++) {
            final cand = top3[ci];
            final candOrder = cand['order'] as Map<String, String>;
            debugPrint(
              'UNMATCHED_DEBUG row=[$sheetName][$sheetGov] cand#${ci + 1}: '
              '${candOrder['name'] ?? '-'} | ${candOrder['governorate'] ?? '-'} | '
              'score=${(cand['name_score'] as double).toStringAsFixed(2)} '
              'accepted=${cand['accepted']} reason=${cand['reject_reason']}',
            );
          }

          final rowData = <String, String>{
            'sheet_name': sheetName,
            'sheet_governorate': sheetGov,
            'sheet_phone': sheetPhone,
            'sheet_amount': amount.toStringAsFixed(0),
            'reason': 'manual_select_needed (name_governorate_only)',
          };

          for (int ci = 0; ci < top3.length; ci++) {
            final cand = top3[ci];
            final candOrder = cand['order'] as Map<String, String>;
            final prefix = 'candidate_${ci + 1}_';
            rowData['${prefix}index'] = (cand['index'] as int).toString();
            rowData['${prefix}name'] = candOrder['name'] ?? '';
            rowData['${prefix}governorate'] = candOrder['governorate'] ?? '';
            rowData['${prefix}model'] = candOrder['model'] ?? '';
            rowData['${prefix}color'] = candOrder['color'] ?? '';
            rowData['${prefix}name_score'] = ((cand['name_score'] as double)).toStringAsFixed(2);
            rowData['${prefix}reason'] = cand['reject_reason']?.toString() ?? '';
          }

          unmatchedRows.add(rowData);
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
      await _addLogEntry("مطابقة تسليم الشيت", "مطابقات بانتظار التأكيد: $matchedDelivered\nحالات غير مؤكدة: $unmatchedDelivered");
      _showResultDialog(count, totalDeductions, totalNet, auto15, auto16, auto17);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text("تم تحليل الشيت بنجاح", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20))),
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
                    _analysisMetricRow("الأوردرات المستلمة", count.toString()),
                    const SizedBox(height: 8),
                    _analysisMetricRow("إجمالي الخصومات", "${ded.toStringAsFixed(2)} ج.م"),
                    const SizedBox(height: 8),
                    _analysisMetricRow("الصافي المحول", "${net.toStringAsFixed(2)} ج.م", highlight: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text("الأجهزة المتعرف عليها", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
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
                  label: const Text("تفاصيل التحليل"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text("إغلاق"),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لا توجد تفاصيل تحليل حالياً")));
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
                const Text("تفاصيل تحليل الشيت", textAlign: TextAlign.right),
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
                    Tab(text: 'اتطابق (${matched.length})'),
                    Tab(text: 'ما اتطابقش (${unmatched.length})'),
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
                    emptyText: "لا توجد شحنات متطابقة",
                    matchedMode: true,
                  ),
                  _buildSheetAnalysisList(
                    rows: unmatched,
                    emptyText: "لا توجد شحنات غير متطابقة",
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
                  child: const Text("إغلاق"),
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
        if (i < 0 || i >= rows.length) return const SizedBox.shrink();
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
              Text("الاسم (الشيت): ${r['sheet_name'] ?? '-'}", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text("المحافظة (الشيت): ${r['sheet_governorate'] ?? '-'}", textAlign: TextAlign.right),
              if ((r['sheet_phone'] ?? '').trim().isNotEmpty) Text("الهاتف (الشيت): ${r['sheet_phone']}", textAlign: TextAlign.right),
              Text("المبلغ: ${r['sheet_amount'] ?? '-'}", textAlign: TextAlign.right),
              if (matchedMode) ...[
                const SizedBox(height: 4),
                Text("تمت مطابقته مع: ${r['order_name'] ?? '-'}", textAlign: TextAlign.right),
                Text("محافظة الأوردر: ${r['order_governorate'] ?? '-'}", textAlign: TextAlign.right),
                Text("الموديل/اللون: ${(r['order_model'] ?? '-')} / ${(r['order_color'] ?? '-')}", textAlign: TextAlign.right),
                Text("درجة التطابق: ${r['score'] ?? '-'}", textAlign: TextAlign.right),
              ] else ...[
                const SizedBox(height: 4),
                Text("السبب: ${r['reason'] ?? 'غير محدد'}", textAlign: TextAlign.right),
                for (int ci = 1; ci <= 3; ci++)
                  if ((r['candidate_${ci}_name'] ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text("مرشح $ci: ${r['candidate_${ci}_name']} | ${r['candidate_${ci}_governorate'] ?? '-'}", textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text("موديل/لون: ${(r['candidate_${ci}_model'] ?? '-')} / ${(r['candidate_${ci}_color'] ?? '-')}", textAlign: TextAlign.right),
                    Text("سبب الرفض: ${(r['candidate_${ci}_reason'] ?? '-')}, score=${r['candidate_${ci}_name_score'] ?? '-'}", textAlign: TextAlign.right),
                  ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _manualMatchUnmatchedRow(r),
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text("مطابقة يدوية"),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _manualClassifyUnmatchedRow(r),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text("تحديد يدوي"),
                  ),
                ),
                if (((r['inferred_15'] ?? '0') != '0') || ((r['inferred_16'] ?? '0') != '0') || ((r['inferred_17'] ?? '0') != '0'))
                  Text("تقدير الأجهزة: 15=${r['inferred_15'] ?? '0'}، 16=${r['inferred_16'] ?? '0'}، 17=${r['inferred_17'] ?? '0'}", textAlign: TextAlign.right),
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
        title: const Text("مسح سجل الحركات", textAlign: TextAlign.right),
        content: const Text("هل أنت متأكد من مسح كل عناصر سجل الحركات؟", textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() => inventoryLog.clear());
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
        title: const Text("شحنات متسلّمة كاش", textAlign: TextAlign.right, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("تم العثور على $cashDeliveredCount شحنة متسلّمة بقيمة 1 جنيه.\nحدد موديل الأجهزة:", textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
          TextButton(onPressed: () => Navigator.pop(ctx, {'15': 0, '16': 0, '17': 0}), child: const Text("تخطي", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ElevatedButton(
            onPressed: () {
              final v15 = int.tryParse(c15.text) ?? 0;
              final v16 = int.tryParse(c16.text) ?? 0;
              final v17 = int.tryParse(c17.text) ?? 0;
              final total = v15 + v16 + v17;

              if (total != cashDeliveredCount) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("مجموع الأجهزة لازم يساوي $cashDeliveredCount")));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("المخزن لا يكفي!"), backgroundColor: Colors.red));
      return;
    }
    
    calculateProfit();
    _pushUndo("مبيعات");

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
    _addLogEntry("مبيعات", "بيع: (15:$s15, 16:$s16, 17:$s17)\nالمتبقي: (15:$stock15, 16:$stock16, 17:$stock17)");
    _clearInputs();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF050505) : const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('حاسبة البيزنس الاحترافية', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2, fontSize: 20)),
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
          const Text("صافي الربح", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 18)),
          Text("${netProfit.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 48, fontWeight: FontWeight.w900)),
          const Divider(color: Colors.white24, height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _shareInfo("نصيبك", myShare),
              _shareInfo("الشريك", partnerShare),
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
      label: const Text("سحب شيت (Excel/CSV)"),
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
              Text("المخزون: $stock", style: TextStyle(fontSize: 15, color: stock > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.w600)),
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
    ],
  );

  Drawer _buildDrawer(bool isDark) => Drawer(
    backgroundColor: isDark ? const Color(0xFF101114) : Colors.white,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text("القائمة", textAlign: TextAlign.right, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)),
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
                  Text("حسابي", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _drawerTile(icon: Icons.inventory_2_rounded, title: "المخزن", onTap: () { Navigator.pop(context); _openWarehousePage(); }),
          _drawerTile(icon: Icons.home_work_rounded, title: "مخزن البيت", onTap: () { Navigator.pop(context); _openHomeWarehousePage(); }),
          _drawerTile(icon: Icons.history_edu_rounded, title: "سجل الحركات", onTap: () { Navigator.pop(context); _showLog(); }),
          _drawerTile(icon: Icons.playlist_add_check_rounded, title: "استيراد أوردرات واتساب", onTap: () { Navigator.pop(context); _openAiAssistant(initialTabIndex: 1); }),
          _drawerTile(icon: Icons.people_alt_rounded, title: "داتا العملاء", onTap: () { Navigator.pop(context); _openCustomersPage(); }),
          _drawerTile(icon: Icons.smart_toy_rounded, title: "مساعد AI", onTap: () { Navigator.pop(context); _openAiAssistant(); }),
          _drawerTile(icon: Icons.delete_sweep_rounded, title: "مسح كل المخزون", danger: true, onTap: () { Navigator.pop(context); _confirmClearStock(); }),
          const SizedBox(height: 8),
          Container(height: 1, color: isDark ? Colors.white12 : Colors.black12),
          const SizedBox(height: 8),
          _drawerTile(icon: Icons.settings_rounded, title: "أسعار الشراء", onTap: () { Navigator.pop(context); _showPriceDialog(); }),
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
          title: 'المخزن الرئيسي',
          saveLabel: 'حفظ المخزن الرئيسي',
        ),
      ),
    );

    if (!mounted || updatedStock == null) return;
    _pushUndo("تعديل مخزن");
    setState(() {
      colorStock = updatedStock;
      _syncTotalsFromColorStock();
    });
    await _saveData();
    await _addLogEntry("تعديل مخزن", "تحديث كميات المخزن من صفحة المخزن\nالإجمالي: (15:$stock15, 16:$stock16, 17:$stock17)");
  }

  Future<void> _openHomeWarehousePage() async {
    final updatedStock = await Navigator.push<Map<String, Map<String, int>>>(
      context,
      MaterialPageRoute(
        builder: (_) => WarehousePage(
          initialStock: _cloneColorStock(homeColorStock),
          title: 'مخزن البيت',
          saveLabel: 'حفظ مخزن البيت',
        ),
      ),
    );

    if (!mounted || updatedStock == null) return;
    _pushUndo("تعديل مخزن البيت");
    setState(() {
      homeColorStock = updatedStock;
      _syncHomeTotalsFromColorStock();
    });
    await _saveData();
    await _addLogEntry("تعديل مخزن البيت", "تحديث كميات مخزن البيت\nالإجمالي: (15:$homeStock15, 16:$homeStock16, 17:$homeStock17)");
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
                                                "اختر العملية التي تريد التراجع عنها",
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
                                                label: const Text("إلغاء"),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () => Navigator.pop(sheetCtx, _undoStack.length - 1),
                                                icon: const Icon(Icons.undo_rounded, size: 18),
                                                label: const Text("آخر عملية"),
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
                              title: const Text("تأكيد التراجع", textAlign: TextAlign.right),
                              content: Text(
                                "سيتم الرجوع للحالة قبل العملية:\n${picked.label}\n${_formatUndoIso(picked.at)}\n\nملاحظة: أي عمليات تمت بعدها سيتم إلغاؤها.",
                                textAlign: TextAlign.right,
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text("إلغاء")),
                                ElevatedButton(onPressed: () => Navigator.pop(c2, true), child: const Text("تراجع")),
                              ],
                            ),
                          );
                          if (!mounted) return;
                          if (confirm != true) return;

                          final ok = await _undoToIndex(selectedIndex);
                          if (!mounted) return;
                          if (ctx.mounted) Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? "تم التراجع بنجاح" : "لا يوجد ما يمكن التراجع عنه")),
                          );
                        },
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text("تراجع"),
                ),
              ),
              const SizedBox(width: 8),
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
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text("إغلاق"),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم تنظيف أرقام الهواتف (تحديث $changed أوردر)")));
    }

    Future<void> deleteCustomer(Map<String, String> customer) async {
      final key = customerKey(customer);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: _dialogBg(context),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
          title: const Text("مسح عميل", textAlign: TextAlign.right),
          content: Text(
            "ده هيمسح كل أوردرات العميل ده من التطبيق.\n\nالعميل: ${customer['name'] ?? '-'}\nالهاتف: ${customer['phone'] ?? '-'}\n\nمتأكد؟",
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("إلغاء")),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("مسح", style: TextStyle(color: Colors.red))),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم مسح $removed أوردر")));
    }

    Future<void> deleteSelectedCustomers(StateSetter setStateDialog) async {
      if (selectedKeys.isEmpty) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: _dialogBg(context),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _dialogBorder(context))),
          title: const Text("مسح المحدد", textAlign: TextAlign.right),
          content: Text(
            "ده هيمسح كل أوردرات العملاء المحددين (${selectedKeys.length}).\nمتأكد؟",
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("إلغاء")),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("مسح", style: TextStyle(color: Colors.red))),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم مسح $removedOrders أوردر")));
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
          title: const Text("تعديل بيانات عميل", textAlign: TextAlign.right),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "الاسم")),
                const SizedBox(height: 8),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "الهاتف")),
                const SizedBox(height: 8),
                TextField(controller: govCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "المحافظة")),
                const SizedBox(height: 8),
                TextField(controller: addrCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "العنوان")),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text("إلغاء")),
            ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text("حفظ")),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم تحديث $updated أوردر لهذا العميل")));
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
                tooltip: selectionMode ? "إلغاء التحديد" : "تحديد",
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
                  tooltip: "تحديد الكل",
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
                  tooltip: "مسح المحدد",
                  onPressed: selectedKeys.isEmpty ? null : () => deleteSelectedCustomers(setStateDialog),
                  icon: Icon(Icons.delete_sweep_rounded, color: selectedKeys.isEmpty ? null : Colors.red),
                ),
              const Spacer(),
              const Expanded(
                flex: 3,
                child: Text("داتا العملاء", textAlign: TextAlign.right),
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
                    hintText: "ابحث بالاسم أو الرقم أو العنوان",
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
                      ? const Center(child: Text("لا يوجد عملاء"))
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
                                            tooltip: "مسح العميل",
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
                                    Text("الهاتف: ${c['phone'] ?? '-'}"),
                                    if (extraPhones.isNotEmpty) Text("أرقام إضافية: $extraPhones"),
                                    Text("المحافظة: ${c['governorate'] ?? '-'}"),
                                    Text("العنوان: ${(c['address'] ?? '').isEmpty ? '-' : c['address']!}"),
                                    Text("عدد الأوردرات: $cnt"),
                                    if (lastAt.isNotEmpty) Text("آخر أوردر: ${formatIso(lastAt)}"),
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
              child: const Text("تنظيف الأرقام"),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إغلاق")),
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
    final isSale = entry.contains('مبيعات') || entry.contains('خصم') || entry.contains('AI');
    final isSupply = entry.contains('توريد') || entry.contains('إضافة');
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
          Text("$value جهاز", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w900)),
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
        title: const Text("أسعار الشراء"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _priceField(p15, "سعر الـ 15"), const SizedBox(height: 8),
            _priceField(p16, "سعر الـ 16"), const SizedBox(height: 8),
            _priceField(p17, "سعر الـ 17"),
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
            child: const Text("تحديث"),
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
                labelText: "رصيد حسابي", suffixText: "ج.م",
                filled: true, fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
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
              setState(() => myAccountBalance = newValue);
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
      labelText: label, labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      filled: true, fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );

  Color _dialogBg(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF111111) : Colors.white;
  Color _dialogBorder(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12;
}

class WarehousePage extends StatefulWidget {
  const WarehousePage({super.key, required this.initialStock, this.title = 'المخزن', this.saveLabel = 'حفظ المخزن'});
  final Map<String, Map<String, int>> initialStock;
  final String title;
  final String saveLabel;

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
    setState(() => stock[model]![color] = next);
  }

  Future<void> _editQty(String model, String color) async {
    final ctrl = TextEditingController(text: (stock[model]![color] ?? 0).toString());
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF111111) : Colors.white,
        title: Text('تعديل $model - $color', textAlign: TextAlign.right),
        content: TextField(
          controller: ctrl, keyboardType: TextInputType.number, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), decoration: const InputDecoration(hintText: '0'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text) ?? 0), child: const Text('حفظ')),
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
          IconButton(onPressed: _clearAll, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'تصفير الكل'),
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
                  const Expanded(child: Text('إجمالي الأجهزة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
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
