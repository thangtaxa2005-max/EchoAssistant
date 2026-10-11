enum CommandKind { create, move, delete, complete, unknown }

class ParsedCommand {
  const ParsedCommand({
    required this.kind,
    this.title,
    this.dueAt,
    this.durationMinutes = 0,
    this.recurrence = 'none',
    this.refersToPrevious = false,
  });

  final CommandKind kind;
  final String? title;
  final DateTime? dueAt;
  final int durationMinutes;
  final String recurrence;
  final bool refersToPrevious;

  bool get needsTime =>
      (kind == CommandKind.create || kind == CommandKind.move) && dueAt == null;
}

/// Deterministic first pass. LLMs are only consulted when this cannot extract
/// both a task and a time; no API key is required for common reminders.
class VietnameseParser {
  ParsedCommand parse(String input, {DateTime? now}) {
    final base = now ?? DateTime.now();
    final raw = input.trim();
    final lower = raw.toLowerCase();
    final previous = ['việc đó', 'việc này', 'lịch đó', 'nhắc đó', ' nó ']
        .any(lower.contains);
    final deleting = ['xóa', 'xoá', 'bỏ ', 'hủy', 'huỷ'].any(lower.contains);
    final completing = ['xong', 'hoàn thành', 'làm rồi'].any(lower.contains);
    final moving = ['dời', 'đổi giờ', 'chuyển', 'lùi', 'sửa giờ'].any(lower.contains);
    final kind = deleting
        ? CommandKind.delete
        : completing
            ? CommandKind.complete
            : moving
                ? CommandKind.move
                : CommandKind.create;

    final timeMatch = RegExp(
      r'(?<!\d)(\d{1,2})(?:\s*(?:h|giờ|:|\.)\s*(\d{1,2})?)?\s*(sáng|trưa|chiều|tối|đêm)?',
      caseSensitive: false,
    ).allMatches(lower).where((m) {
      final token = m.group(0) ?? '';
      return RegExp(r'h|giờ|:|\.|sáng|trưa|chiều|tối|đêm').hasMatch(token) &&
          !RegExp(r'\b\d{1,2}[/.]\d{1,2}\b').hasMatch(token);
    }).firstOrNull;
    int? hour;
    int minute = 0;
    if (timeMatch != null) {
      hour = int.tryParse(timeMatch.group(1) ?? '');
      minute = int.tryParse(timeMatch.group(2) ?? '') ?? 0;
      final period = timeMatch.group(3);
      if (hour != null && period != null) {
        if ((period == 'chiều' || period == 'tối' || period == 'đêm') &&
            hour < 12) {
          hour += 12;
        } else if (period == 'sáng' && hour == 12) {
          hour = 0;
        }
      }
      if (hour == null || hour > 23 || minute > 59) hour = null;
    }

    var day = DateTime(base.year, base.month, base.day);
    var explicitDay = false;
    if (lower.contains('ngày kia') || lower.contains('mốt')) {
      day = day.add(const Duration(days: 2));
      explicitDay = true;
    } else if (lower.contains('ngày mai') || RegExp(r'\bmai\b').hasMatch(lower)) {
      day = day.add(const Duration(days: 1));
      explicitDay = true;
    } else if (lower.contains('hôm nay') || lower.contains('tối nay') || lower.contains('sáng nay') || lower.contains('chiều nay')) {
      explicitDay = true;
    }
    final dateMatch = RegExp(r'(?:ngày\s*)?(\d{1,2})[/-](\d{1,2})(?:[/-](\d{4}))?')
        .firstMatch(lower);
    if (dateMatch != null) {
      final d = int.parse(dateMatch.group(1)!);
      final m = int.parse(dateMatch.group(2)!);
      final y = int.tryParse(dateMatch.group(3) ?? '') ?? base.year;
      final candidate = DateTime(y, m, d);
      if (candidate.day == d && candidate.month == m) {
        day = candidate;
        if (dateMatch.group(3) == null &&
            day.isBefore(DateTime(base.year, base.month, base.day))) {
          day = DateTime(y + 1, m, d);
        }
        explicitDay = true;
      }
    } else {
      const weekdayNames = {
        'thứ hai': DateTime.monday,
        'thứ ba': DateTime.tuesday,
        'thứ tư': DateTime.wednesday,
        'thứ năm': DateTime.thursday,
        'thứ sáu': DateTime.friday,
        'thứ bảy': DateTime.saturday,
        'chủ nhật': DateTime.sunday,
      };
      for (final entry in weekdayNames.entries) {
        if (lower.contains(entry.key)) {
          final delta = (entry.value - day.weekday + 7) % 7;
          day = day.add(Duration(days: delta));
          explicitDay = true;
          break;
        }
      }
    }
    DateTime? due;
    if (hour != null) {
      due = DateTime(day.year, day.month, day.day, hour, minute);
      if (!explicitDay && !due.isAfter(base)) {
        due = due.add(const Duration(days: 1));
      }
    }

    final minutes = RegExp(r'(\d+)\s*(?:phút|phut|p\b)').firstMatch(lower);
    final hours = RegExp(r'(\d+)\s*(?:tiếng|giờ đồng hồ)').firstMatch(lower);
    final duration = (int.tryParse(minutes?.group(1) ?? '') ?? 0) +
        (int.tryParse(hours?.group(1) ?? '') ?? 0) * 60;
    final recurrence = lower.contains('hàng ngày') || lower.contains('mỗi ngày')
        ? 'daily'
        : lower.contains('hàng tuần') || lower.contains('mỗi tuần')
            ? 'weekly'
            : 'none';

    var title = lower
        .replaceAll(RegExp(r'^(nhắc\s+(tớ|mình|tôi|em|anh|chị)\s*|đặt\s+lịch\s*|tạo\s+việc\s*|nhớ\s+)'), '')
        .replaceAll(RegExp(r'(?<!\S)(nhắc|giúp|với|nhé|nha|cho tôi|cho mình|cho tớ|tớ|mình|tôi|nay)(?=\s|$|[,.!?])'), ' ')
        .replaceAll(RegExp(r'\b(hôm nay|tối nay|sáng nay|chiều nay|ngày mai|ngày kia|mai|mốt|mỗi ngày|hàng ngày|mỗi tuần|hàng tuần)\b'), ' ')
        .replaceAll(RegExp(r'\b(thứ hai|thứ ba|thứ tư|thứ năm|thứ sáu|thứ bảy|chủ nhật)\b'), ' ')
        .replaceAll(RegExp(r'\b(việc đó|việc này|lịch đó|nhắc đó)\b'), ' ')
        .replaceAll(RegExp(r'\b(trong|khoảng|lúc|vào|đến|từ)\b'), ' ');
    if (timeMatch != null) title = title.replaceFirst(timeMatch.group(0)!, ' ');
    if (dateMatch != null) title = title.replaceFirst(dateMatch.group(0)!, ' ');
    title = title
        .replaceAll(RegExp(r'\d+\s*(phút|phut|p\b|tiếng|giờ đồng hồ)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s,.:!?]+|[\s,.:!?]+$'), '');
    if (title.isNotEmpty) title = '${title[0].toUpperCase()}${title.substring(1)}';

    return ParsedCommand(
      kind: kind,
      title: title.isEmpty ? null : title,
      dueAt: due,
      durationMinutes: duration,
      recurrence: recurrence,
      refersToPrevious: previous,
    );
  }
}
