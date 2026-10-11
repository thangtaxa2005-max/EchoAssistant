# EchoAssistant

Ứng dụng nhắc việc dạng chat cho Android. Dữ liệu việc và hội thoại lưu bằng SQLite/Drift trên thiết bị. Câu nhắc đơn giản được hiểu bằng luật tiếng Việt; khi người dùng nhập khóa API, câu khó sẽ thử Gemini rồi Groq. Khóa API lưu bằng secure storage.

## Những gì đã có

- Giao diện chat, xác nhận trước khi đặt nhắc, danh sách việc và cài đặt.
- Tạo, xem, dời, hoàn tất, bỏ và xóa việc. Hiểu “việc đó” là việc vừa thao tác gần nhất.
- Giờ/ngày/thời lượng/lặp ngày hoặc tuần bằng parser tiếng Việt. Khi thiếu giờ, Echo hỏi lại.
- Thông báo đúng giờ và giục sau 10 phút; nút Xong, Lùi 15p, Bỏ. Android tự phục hồi lịch thông báo sau khi khởi động lại.
- Nhận giọng nói tiếng Việt ở chế độ on-device khi thiết bị có gói nhận dạng ngoại tuyến; chữ được đưa vào ô soạn để sửa trước khi gửi.
- Bộ 50 câu kiểm thử parser tại `test/widget_test.dart` với ngưỡng đạt 90%.

## Chạy dự án

Máy phát triển cần **Flutter SDK** (script tự dùng `.flutter-sdk` nếu thư mục này có sẵn), JDK 17+, Android SDK Platform 36 và Android Studio hoặc công cụ Android CLI. Trong thư mục này, chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\setup.ps1
```

Script tạo phần Android chuẩn của Flutter, chép cấu hình thông báo và micro, tải thư viện, sinh mã Drift, phân tích, chạy test và đóng gói APK debug. APK đã tạo tại `build/app/outputs/flutter-apk/app-debug.apk`.

Trên điện thoại, cấp quyền **Thông báo**, **Báo thức & lời nhắc**, **Micro**. Để nhắc sát giờ trên các hãng giới hạn chạy nền, bỏ tối ưu pin cho EchoAssistant. Để dùng micro ngoại tuyến, cài gói tiếng Việt cho dịch vụ nhận dạng giọng nói của thiết bị.

## Giới hạn hiện tại

Đã chạy `flutter analyze` (không lỗi), bộ test 50 câu (đạt ngưỡng ≥90%), và tạo APK debug. Đã kiểm tra trên máy ảo và điện thoại TECNO KI7: tạo việc, nhận thông báo đúng giờ, bấm **Xong** để cập nhật việc và hủy lần giục sau 10 phút. Chưa kiểm tra thông báo sau khi khởi động lại hoặc micro ngoại tuyến trên điện thoại. Giọng nói đọc nội dung nhắc khi thông báo đến chưa được triển khai; hiện thông báo dùng âm báo hệ thống và nội dung thân thiện. Các tính năng bản tin sáng/tối, bộ nhớ cá nhân, năng lượng, đồng bộ lịch và sao lưu (P5–P8) chưa được triển khai.

Không có máy chủ riêng. Nếu nhập API key, câu nhắc chưa hiểu được sẽ gửi trực tiếp từ điện thoại đến nhà cung cấp AI; các câu được parser xử lý sẽ ở trên máy. Việc dùng miễn phí phụ thuộc hạn mức tài khoản Gemini/Groq của người dùng.
