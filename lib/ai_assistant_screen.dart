import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

typedef DeleteOrderCallback = Future<String> Function(String name, String? governorate);
typedef CancelOrderCallback = Future<String> Function(String name, String? governorate);
typedef AddStockCallback = Future<String> Function(String model, String color, int count);
typedef CheckStockCallback = Future<String> Function();

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({
    super.key,
    required this.onDeleteOrder,
    required this.onCancelOrder,
    required this.onAddStock,
    required this.onCheckStock,
    this.baseUrl = AppConfig.apiBaseUrl,
  });

  final DeleteOrderCallback onDeleteOrder;
  final CancelOrderCallback onCancelOrder;
  final AddStockCallback onAddStock;
  final CheckStockCallback onCheckStock;
  final String baseUrl;

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_Message> _messages = [];
  bool _sending = false;
  bool _testing = false;

  @override
  void dispose() {
    _controller.dispose();
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

    return Scaffold(
      appBar: AppBar(title: const Text('مساعد AI')),
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
    );
  }
}

class _Message {
  const _Message({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}




