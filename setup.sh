#!/usr/bin/env bash
# ==============================================================================
# Script: setup.sh
# Mục đích: Tự động hóa thiết lập thư mục Web an toàn tại /opt/my-app/ cho Bài 5
# Hệ điều hành: Ubuntu 20.04 / 22.04 LTS
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo " BẮT ĐẦU CẤU HÌNH THƯ MỤC WEB AN TOÀN TẠI /opt/my-app/ "
echo "=========================================================="

# 1. Kiểm tra quyền root
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Vui lòng chạy script này với quyền root hoặc sudo."
    exit 1
fi

# 2. Tạo user devops nếu chưa tồn tại
if ! id "devops" &>/dev/null; then
    echo "[+] Đang tạo user 'devops'..."
    useradd -m -s /bin/bash devops
    # Thêm devops vào sudo nếu cần (tùy chọn)
    usermod -aG sudo devops || true
    echo "[✔] Đã tạo user devops thành công."
else
    echo "[✔] User 'devops' đã tồn tại."
fi

# 3. Đảm bảo Nginx đã được cài đặt
if ! command -v nginx &>/dev/null; then
    echo "[+] Đang cập nhật package và cài đặt Nginx..."
    apt-get update -y
    apt-get install -y nginx
fi

# 4. Tạo cấu trúc thư mục tại /opt/my-app/
echo "[+] Tạo thư mục /opt/my-app/html/ và /opt/my-app/logs/..."
mkdir -p /opt/my-app/html
mkdir -p /opt/my-app/logs

# 5. Tạo file index.html mẫu nếu chưa có
if [ ! -f /opt/my-app/html/index.html ]; then
    echo "[+] Tạo tệp tin index.html mẫu..."
    cat <<'EOF' > /opt/my-app/html/index.html
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <title>My App - Safe Web Directory in /opt/</title>
    <style>
        body { font-family: sans-serif; background: #0f172a; color: #f8fafc; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
        .box { background: #1e293b; padding: 30px; border-radius: 12px; text-align: center; border: 1px solid #334155; }
        h1 { color: #38bdf8; }
    </style>
</head>
<body>
    <div class="box">
        <h1>Welcome to My App</h1>
        <p>Triển khai an toàn tại <code>/opt/my-app/html/</code></p>
    </div>
</body>
</html>
EOF
fi

# 6. Phân quyền sở hữu đệ quy: user devops và group www-data
echo "[+] Gán quyền sở hữu devops:www-data cho /opt/my-app..."
chown -R devops:www-data /opt/my-app

# 7. Phân quyền truy cập theo yêu cầu bảo mật:
# - Thư mục gốc /opt/my-app và /opt/my-app/html: 755 (hoặc 750)
#   Owner (devops): rwx (7)
#   Group (www-data): r-x (5)
#   Others: r-x (5) [hoặc --- (0) nếu dùng 750]
echo "[+] Cấu hình quyền truy cập thư mục và tệp tin..."
chmod 755 /opt/my-app
chmod 755 /opt/my-app/html

# - Tệp tin tĩnh: 644 (hoặc 640)
#   Owner (devops): rw- (6)
#   Group (www-data): r-- (4)
#   Others: r-- (4) [hoặc --- (0) nếu dùng 640]
find /opt/my-app/html -type f -exec chmod 644 {} +

# - Thư mục logs: 775 (hoặc 770) để group www-data có toàn quyền ghi file log
#   Owner (devops): rwx (7)
#   Group (www-data): rwx (7 - quyền ghi log)
#   Others: r-x (5)
chmod 775 /opt/my-app/logs

# Đảm bảo Nginx có thể tạo và ghi log files
touch /opt/my-app/logs/access.log /opt/my-app/logs/error.log || true
chown -R devops:www-data /opt/my-app/logs
chmod 664 /opt/my-app/logs/*.log || true

# 8. Cấu hình Server Block của Nginx
echo "[+] Cấu hình Nginx Virtual Host..."
cat <<'EOF' > /etc/nginx/sites-available/my-app.conf
server {
    listen 80;
    server_name localhost _;

    root /opt/my-app/html;
    index index.html index.htm;

    access_log /opt/my-app/logs/access.log;
    error_log /opt/my-app/logs/error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

# Kích hoạt site và gỡ site default nếu đang chiếm port 80
ln -sf /etc/nginx/sites-available/my-app.conf /etc/nginx/sites-enabled/my-app.conf
if [ -L /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
fi

# 9. Kiểm tra cú pháp Nginx và reload dịch vụ
echo "[+] Kiểm tra cấu hình Nginx..."
nginx -t

echo "[+] Khởi động lại Nginx..."
systemctl restart nginx

echo ""
echo "=========================================================="
echo " KIỂM TRA PHÂN QUYỀN VÀ TRẠNG THÁI "
echo "=========================================================="
ls -la /opt/my-app/
ls -la /opt/my-app/html/
ls -la /opt/my-app/logs/

echo ""
echo "[+] Thử ghi file với user devops (không dùng sudo)..."
su - devops -c 'echo "<!-- Update Test by devops -->" >> /opt/my-app/html/index.html'
echo "[✔] User devops đã ghi file thành công!"

echo ""
echo "[+] Gửi request test HTTP..."
curl -I http://localhost/ || true

echo ""
echo "[+] Kiểm tra nội dung access.log phát sinh:"
cat /opt/my-app/logs/access.log | tail -n 5

echo ""
echo "=========================================================="
echo " HOÀN TẤT THIẾT LẬP THÀNH CÔNG! "
echo "=========================================================="
