import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'vietnamese_parser.dart';

class AiInterpreter {
  AiInterpreter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _storage = FlutterSecureStorage();

  Future<void> saveKeys({required String gemini, required String groq}) async {
    await _storage.write(key: 'gemini_key', value: gemini.trim());
    await _storage.write(key: 'groq_key', value: groq.trim());
  }

  Future<(String, String)> loadKeys() async => (
        await _storage.read(key: 'gemini_key') ?? '',
        await _storage.read(key: 'groq_key') ?? '',
      );

  Future<ParsedCommand?> interpret(String input, DateTime now) async {
    final (gemini, groq) = await loadKeys();
    if (gemini.isEmpty && groq.isEmpty) return null;
    final prompt = '''Bạn là bộ phân tích lệnh nhắc việc tiếng Việt. Chỉ trả một JSON object.
Hiện tại: ${now.toIso8601String()} (giờ địa phương trên máy).
Lệnh: ${jsonEncode(input)}
Schema: {"kind":"create|move|delete|complete|unknown","title":string|null,"dueAt":"YYYY-MM-DDTHH:mm:ss"|null,"durationMinutes":integer,"recurrence":"none|daily|weekly","refersToPrevious":boolean}.
Không đoán giờ khi thiếu. Không tạo việc ngoài ý người dùng. Dùng giờ địa phương, không thêm Z.''';
    if (gemini.isNotEmpty) {
      try {
        final response = await _client.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': gemini},
          body: jsonEncode({
            'contents': [{'parts': [{'text': prompt}]}],
            'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0},
          }),
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final text = body['candidates']?[0]?['content']?['parts']?[0]?['text'];
          final parsed = _decode(text);
          if (parsed != null) return parsed;
        }
      } catch (_) {
        // Groq is the explicit fallback. The deterministic parser remains last.
      }
    }
    if (groq.isNotEmpty) {
      try {
        final response = await _client.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $groq'},
          body: jsonEncode({
            'model': 'llama-3.3-70b-versatile',
            'temperature': 0,
            'response_format': {'type': 'json_object'},
            'messages': [{'role': 'user', 'content': prompt}],
          }),
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          return _decode(body['choices']?[0]?['message']?['content']);
        }
      } catch (_) {}
    }
    return null;
  }

  ParsedCommand? _decode(Object? value) {
    if (value is! String) return null;
    try {
      final map = jsonDecode(value) as Map<String, dynamic>;
      final kind = CommandKind.values.where((e) => e.name == map['kind']).firstOrNull ??
          CommandKind.unknown;
      final due = DateTime.tryParse((map['dueAt'] as String?) ?? '');
      return ParsedCommand(
        kind: kind,
        title: map['title'] is String ? (map['title'] as String).trim() : null,
        dueAt: due,
        durationMinutes: (map['durationMinutes'] as num?)?.toInt().clamp(0, 1440).toInt() ?? 0,
        recurrence: {'daily', 'weekly'}.contains(map['recurrence'])
            ? map['recurrence'] as String
            : 'none',
        refersToPrevious: map['refersToPrevious'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
