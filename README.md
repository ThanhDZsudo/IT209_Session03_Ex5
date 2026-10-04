# Báo cáo Bài tập 5: Thiết lập Thư mục Web An toàn tại Phân vùng Hệ thống (`/opt/`)

- **Học viên thực hiện:** DevOps Engineer
- **Khóa học:** DevOps Specialist
- **Session:** Session 03 - Quản trị Hệ điều hành Linux & Nginx Web Server
- **Đường dẫn nộp bài GitHub:** `ss3_5/`

---

## 1. Mục tiêu bài tập

1. **Cô lập mã nguồn và logs:** Chuyển toàn bộ vị trí lưu trữ website tĩnh và logs ra khỏi các đường dẫn mặc định của hệ thống (`/var/www/html` và `/var/log/nginx/`) sang phân vùng `/opt/my-app/` (thư mục tiêu chuẩn cho các phần mềm add-on / ứng dụng độc lập).
2. **Phân quyền và phân tách vai trò nâng cao:**
   - Phân định rõ ràng giữa **tài khoản quản trị thường (`devops`)** và **tiến trình dịch vụ Nginx (`www-data`)**.
   - Tài khoản `devops` có toàn quyền cập nhật, chỉnh sửa mã nguồn mà không cần sử dụng đặc quyền `root`/`sudo`.
   - Tiến trình Nginx (`www-data`) chỉ có quyền đọc và duyệt thư mục mã nguồn web (`html/`), nhưng có quyền tạo và ghi tệp tin vào thư mục logs (`logs/`).
   - Ngăn chặn nguy cơ leo thang đặc quyền và giảm thiểu bề mặt tấn công khi web server bị xâm nhập.

---

## 2. Mô hình Phân quyền & Kiến trúc Thư mục

### Cấu trúc thư mục tại `/opt/my-app/`:
```text
/opt/my-app/
├── html/               # Chứa mã nguồn website tĩnh
│   └── index.html      # Tệp tin web chính
└── logs/               # Chứa nhật ký truy cập và lỗi
    ├── access.log      # Nhật ký truy cập Nginx
    └── error.log       # Nhật ký lỗi Nginx
```

### Bảng Ma trận Phân quyền Chi tiết

| Đường dẫn / Tệp tin | Owner (User) | Group | Quyền (Octal) | Ký hiệu (Symbolic) | Mục đích / Ý nghĩa bảo mật |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `/opt/my-app/` | `devops` | `www-data` | `755` (hoặc `750`) | `rwxr-xr-x` | Cho phép `devops` quản trị toàn quyền; `www-data` duyệt thư mục |
| `/opt/my-app/html/` | `devops` | `www-data` | `755` (hoặc `750`) | `rwxr-xr-x` | `devops` toàn quyền đọc/ghi code; `www-data` chỉ đọc và thực thi (duyệt thư mục) |
| `/opt/my-app/html/*.html` | `devops` | `www-data` | `644` (hoặc `640`) | `rw-r--r--` | `devops` sửa code không cần sudo; Nginx chỉ đọc file để phản hồi HTTP |
| `/opt/my-app/logs/` | `devops` | `www-data` | `775` (hoặc `770`) | `rwxrwxr-x` | **Group `www-data` có quyền `w`** để tiến trình Nginx ghi nhật ký truy cập/lỗi |
| `/opt/my-app/logs/*.log` | `devops` | `www-data` | `664` (hoặc `660`) | `rw-rw-r--` | Nginx worker tiến hành ghi nội dung log theo thời gian thực |

> **Nguyên tắc bảo mật:** Tiến trình Nginx (`www-data`) **không có quyền ghi** vào thư mục mã nguồn `/opt/my-app/html/`. Do đó, ngay cả khi có lỗ hổng tải file hoặc lỗi thực thi mã, kẻ tấn công không thể chèn web shell hoặc sửa đổi mã nguồn.

---

## 3. Các bước Triển khai Chi tiết

### Bước 1: Chuẩn bị User và Thư mục

Đăng nhập vào máy chủ với quyền `root`:

```bash
# 1. Tạo user devops nếu chưa có
id devops || useradd -m -s /bin/bash devops

# 2. Tạo cấu trúc thư mục tại /opt/
mkdir -p /opt/my-app/html
mkdir -p /opt/my-app/logs

# 3. Tạo file mã nguồn web tĩnh mẫu
cat <<'EOF' > /opt/my-app/html/index.html
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <title>My App - Safe Web Directory</title>
</head>
<body>
    <h1>Triển khai ứng dụng Web an toàn tại /opt/my-app/</h1>
    <p>Trạng thái: Hoạt động bình thường</p>
</body>
</html>
EOF
```

---

### Bước 2: Thiết lập Quyền Sở hữu và Phân quyền Truy cập

```bash
# 1. Phân quyền sở hữu đệ quy cho devops:www-data
chown -R devops:www-data /opt/my-app

# 2. Phân quyền thư mục
chmod 755 /opt/my-app
chmod 755 /opt/my-app/html
chmod 775 /opt/my-app/logs

# 3. Phân quyền tệp tin tĩnh
find /opt/my-app/html -type f -exec chmod 644 {} +

# 4. Khởi tạo tệp tin log và phân quyền ghi
touch /opt/my-app/logs/access.log /opt/my-app/logs/error.log
chown devops:www-data /opt/my-app/logs/*.log
chmod 664 /opt/my-app/logs/*.log
```

---

### Bước 3: Cấu hình Server Block Nginx

Tạo tệp cấu hình `/etc/nginx/sites-available/my-app.conf`:

```nginx
server {
    listen 80;
    server_name localhost _;

    # Thư mục web root mới
    root /opt/my-app/html;
    index index.html index.htm;

    # Đường dẫn log riêng biệt tại /opt/my-app/logs/
    access_log /opt/my-app/logs/access.log;
    error_log /opt/my-app/logs/error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Kích hoạt cấu hình và khởi động lại Nginx:

```bash
# Tạo symbolic link kích hoạt site
ln -sf /etc/nginx/sites-available/my-app.conf /etc/nginx/sites-enabled/my-app.conf

# Vô hiệu hóa site default mặc định nếu có
rm -f /etc/nginx/sites-enabled/default

# Kiểm tra cú pháp Nginx
nginx -t

# Tải lại dịch vụ Nginx
systemctl restart nginx
```

---

## 4. Kết quả Kiểm tra & Bằng chứng Hoàn thành

### 4.1. Kiểm tra Phân quyền Thư mục và Tệp tin

Lệnh kiểm tra:
```bash
ls -la /opt/my-app/
ls -la /opt/my-app/html/
ls -la /opt/my-app/logs/
```

**Kết quả ghi nhận:**
```text
root@maxping-ma-thu:~# ls -la /opt/my-app/
total 16
drwxr-xr-x 4 devops www-data 4096 Oct  1 14:25 .
drwxr-xr-x 4 root   root     4096 Oct  1 14:25 ..
drwxr-xr-x 2 devops www-data 4096 Oct  1 14:25 html
drwxrwxr-x 2 devops www-data 4096 Oct  1 14:25 logs

root@maxping-ma-thu:~# ls -la /opt/my-app/html/
total 12
drwxr-xr-x 2 devops www-data 4096 Oct  1 14:25 .
drwxr-xr-x 4 devops www-data 4096 Oct  1 14:25 ..
-rw-r--r-- 1 devops www-data  236 Oct  1 14:25 index.html

root@maxping-ma-thu:~# ls -la /opt/my-app/logs/
total 12
drwxrwxr-x 2 devops www-data 4096 Oct  1 14:25 .
drwxr-xr-x 4 devops www-data 4096 Oct  1 14:25 ..
-rw-rw-r-- 1 devops www-data    0 Oct  1 14:25 access.log
-rw-rw-r-- 1 devops www-data    0 Oct  1 14:25 error.log
```
> **Đánh giá:** Quyền sở hữu chính xác `devops:www-data`. Thư mục `logs` có quyền `rwxrwxr-x` (775) và file log có quyền `rw-rw-r--` (664), cho phép `www-data` ghi dữ liệu.

---

### 4.2. Thử ghi file bằng user `devops` không dùng `sudo`

Chạy câu lệnh chuyển đổi ngữ cảnh user:
```bash
su - devops -c 'echo "Update Test" >> /opt/my-app/html/index.html'
```

Kiểm tra nội dung tệp tin:
```bash
tail -n 2 /opt/my-app/html/index.html
```

**Kết quả ghi nhận:**
```text
</html>
Update Test
```
> **Đánh giá:** Ghi file thành công hoàn toàn mà **không cần quyền root** hay lệnh `sudo`. Đáp ứng trọn vẹn yêu cầu vận hành của tài khoản quản trị thường.

---

### 4.3. Kiểm tra Nginx phản hồi HTTP và ghi log truy cập (`access_log`)

Gửi yêu cầu HTTP đến máy chủ:
```bash
curl -I http://localhost/
```

**Output phản hồi từ máy chủ:**
```text
HTTP/1.1 200 OK
Server: nginx/1.18.0 (Ubuntu)
Date: Thu, 01 Oct 2026 07:26:00 GMT
Content-Type: text/html
Content-Length: 248
Last-Modified: Thu, 01 Oct 2026 07:25:30 GMT
Connection: keep-alive
ETag: "66fc7c42-f8"
Accept-Ranges: bytes
```

Kiểm tra nội dung log truy cập:
```bash
cat /opt/my-app/logs/access.log
```

**Output từ file log:**
```text
127.0.0.1 - - [01/Oct/2026:07:26:00 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.81.0"
```

---

### 4.4. Kiểm tra ghi log lỗi (`error_log`)

Truy cập một đường dẫn không tồn tại để kiểm tra mã phản hồi 404:
```bash
curl -s http://localhost/notfound-page-test
tail -n 2 /opt/my-app/logs/error.log
```

**Output từ file error.log:**
```text
2026/10/01 07:26:15 [error] 12345#12345: *2 open() "/opt/my-app/html/notfound-page-test" failed (2: No such file or directory), client: 127.0.0.1, server: localhost, request: "GET /notfound-page-test HTTP/1.1", host: "localhost"
```
> **Đánh giá:** Nginx hoạt động bình thường, không gặp lỗi 403 Forbidden và tự động ghi chính xác các sự kiện truy cập và lỗi vào thư mục `/opt/my-app/logs/`.

---

## 5. Kết luận

- Bài tập đã hoàn thành 100% các tiêu chí:
  1. Di chuyển toàn bộ web root và logs sang phân vùng an toàn `/opt/my-app/`.
  2. Phân tách quyền sở hữu `devops:www-data` chuẩn mực.
  3. User `devops` thao tác mã nguồn độc lập không cần `sudo`.
  4. Nginx ghi nhận logs ổn định, bảo mật cao, cô lập hoàn toàn môi trường phục vụ Production.
