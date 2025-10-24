#!/bin/bash
# file: /opt/automation/run_daily_sync.sh
# Script này tự log các bước thực thi của nó

logfile="/var/log/automation/sync.log"

# Đảm bảo thư mục log tồn tại
mkdir -p "$(dirname "$logfile")"

# Dùng { ... } để group các command
# Mọi output (stdout + stderr) của khối này sẽ được xử lý
{
  echo "=== SYNC JOB STARTED: $(date) ==="

  echo "Step 1: Syncing user data from API..."
  # Giả lập lệnh chạy script Python
  /usr/bin/python3 /opt/scripts/sync_users.py

  echo "Step 2: Syncing product catalog (legacy)..."
  # Giả lập lệnh chạy script PHP
  /usr/bin/php /var/www/html/artisan sync:products

  echo "Step 3: Running a fake error command (để test log lỗi)..."
  # Lệnh này chắc chắn lỗi
  ls /path/that/does/not/exist

  echo "=== SYNC JOB FINISHED: $(date) ==="
  echo "" # Thêm dòng trắng cho dễ đọc

} 2>&1 | tee -a "$logfile"
