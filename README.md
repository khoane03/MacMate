# MacMate

MacMate là ứng dụng thanh menu cho macOS, tập trung vào quản lý cửa sổ, Clipboard, phím tắt, cuộn chuột và mở Mission Control bằng tổ hợp chuột.

Hỗ trợ macOS 15 trở lên trên máy Mac dùng Apple Silicon hoặc Intel.

## Tính năng

- **Quản lý cửa sổ:** chuyển đổi cửa sổ bằng Alt-Tab, chia/căn giữa/phóng to cửa sổ và chuyển cửa sổ giữa các màn hình.
- **Clipboard:** lưu lịch sử sao chép, tìm kiếm, ghim mục, dán nhanh và mở Clipboard HUD bằng phím tắt.
- **Phím tắt:** tùy chỉnh tổ hợp phím cho các thao tác cửa sổ và Clipboard.
- **Cuộn chuột:** bật cuộn mượt, chỉnh tốc độ/độ mượt và đảo chiều cuộn cho chuột ngoài.
- **Mission Control:** bấm đồng thời chuột trái và phải để mở Mission Control; có thể bật/tắt tính năng này trong ứng dụng.

## Cài đặt

1. Trong mục **Assets** của [GitHub Releases](https://github.com/khoane03/MacMate/releases), tải file `MacMate-X.Y.Z.zip`.
2. Giải nén, kéo `MacMate.app` vào thư mục **Applications**.
3. Mở ứng dụng từ Applications. MacMate chạy trên thanh menu, không hiện biểu tượng trong Dock.

**Lưu ý:** Không tải các mục **Source code (zip)** hoặc **Source code (tar.gz)**. Đây là mã nguồn GitHub tự tạo, không phải ứng dụng để cài đặt.

Nếu macOS cảnh báo ứng dụng tải từ Internet, mở **System Settings → Privacy & Security** và chọn **Open Anyway** sau lần thử mở ứng dụng đầu tiên. Bạn cũng có thể Control-click `MacMate.app`, chọn **Open**, rồi xác nhận. Không cần tắt Gatekeeper.

## Quyền macOS

- **Trợ năng (Accessibility):** cần cho phím tắt toàn cục, quản lý cửa sổ, cuộn chuột và tổ hợp chuột mở Mission Control.
- **Ghi màn hình (Screen Recording):** tùy chọn, dùng để hiển thị ảnh xem trước cửa sổ trong trình chuyển đổi Alt-Tab; MacMate không ghi video màn hình.

Cấp hoặc thay đổi quyền trong **System Settings → Privacy & Security**. MacMate kiểm tra và yêu cầu quyền Trợ năng khi cần.

## Cập nhật

MacMate hiện không cập nhật tự động trong ứng dụng. Tải phiên bản mới từ [GitHub Releases](https://github.com/khoane03/MacMate/releases) và thay `MacMate.app` cũ trong Applications.
