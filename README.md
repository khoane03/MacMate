# MacMate

MacMate là ứng dụng thanh menu cho macOS, tập hợp các tiện ích quản lý cửa sổ, clipboard, phím tắt, cuộn chuột, theo dõi phần cứng và dọn dẹp dung lượng.

Hỗ trợ macOS 15 trở lên trên máy Mac dùng Apple Silicon hoặc Intel. Một số tính năng phần cứng phụ thuộc khả năng hỗ trợ của thiết bị.

## Phiên bản

- **v1.0.0:** Bản đầu tiên với các tiện ích pin, phần cứng, cửa sổ, clipboard, phím tắt và cuộn chuột.
- **v2.0.0:** Thêm **Dọn dẹp**, **Gỡ ứng dụng và dữ liệu**; cải thiện quét Thùng rác và giới hạn sạc.

## Tính năng

- **Pin & Phần cứng:** theo dõi pin, nhiệt độ, nguồn điện và quản lý giới hạn sạc trên thiết bị được hỗ trợ.
- **Tính năng:** quản lý cửa sổ, clipboard, phím tắt và cuộn chuột.
- **Dọn dẹp:** quét rác hệ thống, dữ liệu lập trình, dữ liệu AI Agent và Thùng rác; xem dung lượng từng nhóm trước khi chọn mục cần dọn.

### Dọn dẹp và gỡ ứng dụng

Trong tab **Dọn dẹp**, bấm **Quét** để xem dung lượng. Mở **Xem chi tiết**, chọn các mục cần xử lý, xem trước danh sách đường dẫn rồi xác nhận. MacMate quét lại sau khi dọn để cập nhật số liệu. Các mục **Được bảo vệ** không thể chọn xoá.

Mục **Gỡ ứng dụng và dữ liệu** cho phép chọn ứng dụng bên thứ ba trong `/Applications` hoặc `~/Applications`. MacMate liệt kê ứng dụng và những đường dẫn dữ liệu gắn với mã ứng dụng để bạn xem trước. Thư mục dữ liệu chỉ trùng tên ứng dụng không được chọn sẵn; hãy kiểm tra đường dẫn trước khi tự chọn thêm. Bạn cần thoát ứng dụng trước khi gỡ.

Sau khi xác nhận, ứng dụng và dữ liệu đã chọn được **chuyển vào Thùng rác** để có thể khôi phục. Bước này chưa giải phóng dung lượng. Khi đã chắc chắn không cần khôi phục, dùng **Dọn thùng rác** và xác nhận lần nữa để xoá vĩnh viễn. MacMate không tự xoá dữ liệu AI Agent được bảo vệ, dữ liệu tài khoản trực tuyến, mục trong Chuỗi khoá hoặc thư mục dùng chung; vì vậy việc gỡ cài đặt có thể không xoá mọi dấu vết của ứng dụng.

## Cài đặt

1. Trong mục **Assets** của [GitHub Releases](https://github.com/khoane03/MacMate/releases), tải file `MacMate-X.Y.Z.zip`.
2. Giải nén, kéo `MacMate.app` vào thư mục **Applications**.
3. Mở ứng dụng từ Applications. MacMate chạy trên thanh menu, không hiện biểu tượng trong Dock.

**Lưu ý:** Không tải các mục **Source code (zip)** hoặc **Source code (tar.gz)**. Đây là mã nguồn GitHub tự tạo, không phải ứng dụng để cài đặt.

Nếu macOS cảnh báo ứng dụng tải từ Internet, mở **System Settings → Privacy & Security** và chọn **Open Anyway** sau lần thử mở ứng dụng đầu tiên. Bạn cũng có thể Control-click `MacMate.app`, chọn **Open**, rồi xác nhận. Không cần tắt Gatekeeper.

## Quyền macOS

- **Trợ năng (Accessibility):** cần cho phím tắt toàn cục, quản lý cửa sổ và cuộn chuột.
- **Ghi màn hình (Screen Recording):** dùng để hiển thị ảnh xem trước cửa sổ; MacMate không ghi video màn hình.
- **Truy cập toàn bộ ổ đĩa:** cần để macOS cho phép liệt kê và dọn nội dung Thùng rác. Nếu chưa cấp quyền, tab **Dọn dẹp** sẽ báo rõ và có nút mở trang cài đặt; sau khi cấp quyền, mở lại MacMate rồi bấm **Quét**.
- Một số tính năng tùy chọn có thể yêu cầu quyền Bluetooth, Tự động hóa hoặc quyền quản trị. macOS sẽ hỏi xác nhận khi cần.

Cấp hoặc thay đổi quyền trong **System Settings → Privacy & Security**.

## Cập nhật

MacMate có thể kiểm tra phiên bản mới từ ứng dụng. Bạn cũng có thể tải bản mới nhất tại [GitHub Releases](https://github.com/khoane03/MacMate/releases) và thay `MacMate.app` cũ trong Applications.
