import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

typedef DeleteOrderCallback = Future<String> Function(String name, String? governorate);
typedef CancelOrderCallback = Future<String> Function(String name, String? governorate);
typedef AddStockCallback = Future<String> Function(String model, String color, int count);
typedef CheckStockCallback = Future<String> Function();
typedef BulkImportCallback = Future<String> Function(List<Map<String, dynamic>> orders);

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({
    super.key,
    required this.onDeleteOrder,
    required this.onCancelOrder,
    required this.onAddStock,
    required this.onCheckStock,
    required this.onBulkImport,
    this.baseUrl = AppConfig.apiBaseUrl,
    this.initialTabIndex = 0,
  });

  final DeleteOrderCallback onDeleteOrder;
  final CancelOrderCallback onCancelOrder;
  final AddStockCallback onAddStock;
  final CheckStockCallback onCheckStock;
  final BulkImportCallback onBulkImport;
  final String baseUrl;
  final int initialTabIndex;

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final TextEditingController _controller = TextEditingController(); // commands
  final TextEditingController _bulkController = TextEditingController(); // whatsapp bulk
  final List<_Message> _messages = [];
  bool _sending = false;
  bool _testing = false;
  bool _bulkSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _bulkController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_Message(text: text, isUser: true));
      _controller.clear();
      _sending = true;
    });

    try {
      final uri = Uri.parse('${widget.baseUrl}/ai/command');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response format');
      }

      final reply = await _dispatchAction(decoded);
      if (!mounted) return;
      setState(() => _messages.add(_Message(text: reply, isUser: false)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _Message(
            text: '❌ حصلت مشكلة في الاتصال بالسيرفر. اتأكد من تشغيل سيرفر Render.',
            isUser: false,
          ),
        );
      });
    } finally {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      final uri = Uri.parse('${widget.baseUrl}/health');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['ok'] == true) {
          if (!mounted) return;
          setState(() {
            _messages.add(const _Message(text: '✅ الاتصال بالسيرفر شغال (/health)', isUser: false));
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _Message(text: '❌ فشل اختبار الاتصال بالسيرفر', isUser: false),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _Message(text: '❌ السيرفر غير متاح، اتأكد من تشغيل سيرفر Render', isUser: false),
        );
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _sendBulkImport() async {
    final text = _bulkController.text.trim();
    if (text.isEmpty || _bulkSending) return;

    setState(() {
      _messages.add(_Message(text: '📥 استيراد أوردرات واتساب (${text.length} حرف)', isUser: true));
      _bulkSending = true;
    });

    try {
      final uri = Uri.parse('${widget.baseUrl}/ai/parse_orders');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        if (response.statusCode == 404 && response.body.contains('Cannot POST /ai/parse_orders')) {
          throw Exception('السيرفر على Render لسه مش محدث (endpoint /ai/parse_orders مش موجود). اعمل Deploy لآخر كود السيرفر.');
        }
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw Exception('Invalid response format (expected array)');
      }

      final orders = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (orders.isEmpty) {
        if (!mounted) return;
        setState(() => _messages.add(const _Message(text: 'لم يتم العثور على أوردرات في النص.', isUser: false)));
        return;
      }

      final reply = await widget.onBulkImport(orders);
      if (!mounted) return;
      setState(() {
        _messages.add(_Message(text: reply, isUser: false));
        if (reply.startsWith('✅')) _bulkController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _Message(
            text: '❌ فشل استيراد الأوردرات.\n$e',
            isUser: false,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _bulkSending = false);
    }
  }

  Future<String> _dispatchAction(Map<String, dynamic> actionMap) async {
    final action = (actionMap['action'] ?? '').toString();

    switch (action) {
      case 'delete_order':
        return widget.onDeleteOrder(
          (actionMap['name'] ?? '').toString(),
          actionMap['governorate']?.toString(),
        );
      case 'cancel_order':
        return widget.onCancelOrder(
          (actionMap['name'] ?? '').toString(),
          actionMap['governorate']?.toString(),
        );
      case 'add_stock':
        return widget.onAddStock(
          (actionMap['model'] ?? '').toString(),
          (actionMap['color'] ?? '').toString(),
          (actionMap['count'] as num?)?.toInt() ?? 0,
        );
      case 'check_stock':
        return widget.onCheckStock();
      default:
        final message = (actionMap['message'] ?? 'مش فاهم الأمر').toString();
        return '🤖 $message';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مساعد AI'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'أوامر'),
              Tab(text: 'استيراد واتساب'),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Base URL: ${widget.baseUrl}',
                textAlign: TextAlign.left,
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test Connection (/health)'),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Commands
                  Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final alignment = msg.isUser ? Alignment.centerRight : Alignment.centerLeft;
                            final bg = msg.isUser
                                ? const Color(0xFF0A84FF)
                                : (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E7EB));
                            final fg = msg.isUser ? Colors.white : (isDark ? Colors.white : Colors.black87);

                            return Align(
                              alignment: alignment,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(msg.text, style: TextStyle(color: fg)),
                              ),
                            );
                          },
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  onSubmitted: (_) => _sendMessage(),
                                  textInputAction: TextInputAction.send,
                                  decoration: const InputDecoration(
                                    hintText: 'اكتب الأمر...',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: _sending ? null : _sendMessage,
                                icon: _sending
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.send),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Bulk WhatsApp import
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _bulkController,
                              maxLines: null,
                              expands: true,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                hintText: 'الصق أوردرات الواتساب هنا...\nثم اضغط "تحليل واستيراد"',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _bulkSending
                                      ? null
                                      : () {
                                          _bulkController.clear();
                                          FocusScope.of(context).unfocus();
                                        },
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('مسح'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  onPressed: _bulkSending ? null : _sendBulkImport,
                                  icon: _bulkSending
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.auto_awesome),
                                  label: const Text('تحليل واستيراد'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message {
  const _Message({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}




