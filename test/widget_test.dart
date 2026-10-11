import 'package:echo_assistant/core/vietnamese_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = VietnameseParser();
  final now = DateTime(2026, 10, 11, 10);
  const corpus = <(String, int, int, int, int, String)>[
    ('8h tối nay nhắc tớ học từ vựng 30p', 0, 20, 0, 30, 'none'),
    ('20:00 hôm nay học từ vựng', 0, 20, 0, 0, 'none'),
    ('nhắc mình gọi mẹ lúc 21h30 tối nay', 0, 21, 30, 0, 'none'),
    ('7h sáng mai chạy bộ 20 phút', 1, 7, 0, 20, 'none'),
    ('mai 8 giờ sáng đi học', 1, 8, 0, 0, 'none'),
    ('ngày kia 9h họp nhóm', 2, 9, 0, 0, 'none'),
    ('mốt 19:15 đọc sách', 2, 19, 15, 0, 'none'),
    ('hôm nay 11h nấu cơm', 0, 11, 0, 0, 'none'),
    ('12h trưa ăn cơm', 0, 12, 0, 0, 'none'),
    ('3h chiều tập thể dục', 0, 15, 0, 0, 'none'),
    ('6h tối giặt đồ', 0, 18, 0, 0, 'none'),
    ('8h sáng thứ hai gửi email', 1, 8, 0, 0, 'none'),
    ('9h thứ ba gặp bác sĩ', 2, 9, 0, 0, 'none'),
    ('10h thứ tư đi chợ', 3, 10, 0, 0, 'none'),
    ('11h thứ năm thanh toán tiền điện', 4, 11, 0, 0, 'none'),
    ('12h thứ sáu ăn trưa cùng An', 5, 12, 0, 0, 'none'),
    ('13h thứ bảy dọn nhà', 6, 13, 0, 0, 'none'),
    ('14h chủ nhật gọi bà', 0, 14, 0, 0, 'none'),
    ('15h ngày 12/10 làm báo cáo', 1, 15, 0, 0, 'none'),
    ('16h 13/10 nộp bài', 2, 16, 0, 0, 'none'),
    ('17h 14-10 đón con', 3, 17, 0, 0, 'none'),
    ('18h ngày 15/10/2026 đi ăn', 4, 18, 0, 0, 'none'),
    ('19h mai học tiếng Anh 1 tiếng', 1, 19, 0, 60, 'none'),
    ('20h mai làm bài tập 45 phút', 1, 20, 0, 45, 'none'),
    ('21h mai thiền 15p', 1, 21, 0, 15, 'none'),
    ('22h mai uống thuốc', 1, 22, 0, 0, 'none'),
    ('23h mai ngủ sớm', 1, 23, 0, 0, 'none'),
    ('0h mai kiểm tra hệ thống', 1, 0, 0, 0, 'none'),
    ('1h mai xem máy chủ', 1, 1, 0, 0, 'none'),
    ('2h mai sao lưu dữ liệu', 1, 2, 0, 0, 'none'),
    ('8h mỗi ngày uống nước', 1, 8, 0, 0, 'daily'),
    ('9h hàng ngày đọc tin', 1, 9, 0, 0, 'daily'),
    ('7h sáng mỗi ngày chạy bộ', 1, 7, 0, 0, 'daily'),
    ('20h mỗi tuần học đàn', 0, 20, 0, 0, 'weekly'),
    ('21h hàng tuần xem kế hoạch', 0, 21, 0, 0, 'weekly'),
    ('10:30 mai họp dự án', 1, 10, 30, 0, 'none'),
    ('11:45 mai đi siêu thị', 1, 11, 45, 0, 'none'),
    ('14:05 mai tưới cây', 1, 14, 5, 0, 'none'),
    ('15:10 mai gọi khách hàng', 1, 15, 10, 0, 'none'),
    ('16:20 mai gửi tài liệu', 1, 16, 20, 0, 'none'),
    ('17:25 mai đi bộ', 1, 17, 25, 0, 'none'),
    ('18:35 mai nấu tối', 1, 18, 35, 0, 'none'),
    ('19:40 mai học toán', 1, 19, 40, 0, 'none'),
    ('20:50 mai xem phim', 1, 20, 50, 0, 'none'),
    ('21:55 mai chuẩn bị đồ', 1, 21, 55, 0, 'none'),
    ('8h tối mai học từ vựng 30 phút', 1, 20, 0, 30, 'none'),
    ('7h sáng mai viết nhật ký 10p', 1, 7, 0, 10, 'none'),
    ('6h chiều mai gọi mẹ 15 phút', 1, 18, 0, 15, 'none'),
    ('9 giờ tối mai nghe podcast', 1, 21, 0, 0, 'none'),
    ('10 giờ sáng mai phỏng vấn', 1, 10, 0, 0, 'none'),
  ];

  test('50 câu nhắc việc tiếng Việt', () {
    expect(corpus.length, 50);
    var passed = 0;
    for (final item in corpus) {
      final result = parser.parse(item.$1, now: now);
      final expectedDate = DateTime(now.year, now.month, now.day + item.$2);
      final due = result.dueAt;
      if (result.kind == CommandKind.create &&
          result.title != null && result.title!.isNotEmpty &&
          due?.year == expectedDate.year && due?.month == expectedDate.month &&
          due?.day == expectedDate.day && due?.hour == item.$3 &&
          due?.minute == item.$4 && result.durationMinutes == item.$5 &&
          result.recurrence == item.$6) {
        passed++;
      }
    }
    expect(passed, greaterThanOrEqualTo(45), reason: 'Cần đạt ít nhất 90% trên 50 câu.');
  });

  test('không đoán giờ khi thiếu và hiểu lệnh theo ngữ cảnh', () {
    expect(parser.parse('mai học từ vựng', now: now).needsTime, isTrue);
    expect(parser.parse('xóa việc đó', now: now).kind, CommandKind.delete);
    expect(parser.parse('dời việc đó sang mai 8h', now: now).kind, CommandKind.move);
    expect(parser.parse('xong việc đó', now: now).kind, CommandKind.complete);
  });
}
