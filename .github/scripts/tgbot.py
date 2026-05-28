# .github/scripts/tgbot.py
#!/usr/bin/env python3
import os
import glob
import json
import requests
from datetime import datetime

def get_vietnamese_time():
    """Lấy thời gian định dạng Tiếng Việt chuẩn chỉnh"""
    days = ["Chủ Nhật", "Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7"]
    now = datetime.now()
    
    time_str = now.strftime("%H:%M")
    day_str = days[int(now.strftime("%w"))]
    date_str = now.strftime("%d/%m/%Y")
    
    return f"{time_str} {day_str} {date_str}"

def get_fallback_project_info():
    """Tự động quét file cấu hình trong mã nguồn để tìm thông tin chính xác khi hệ thống bị lỗi nửa chừng"""
    info = {"name": "Không xác định", "bundle_id": "Unknown", "version": "1.0.0"}
    
    if os.path.exists("control"):
        with open("control", "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("Name:"):
                    info["name"] = line.split(":", 1)[1].strip()
                elif line.startswith("Package:"):
                    info["bundle_id"] = line.split(":", 1)[1].strip()
                elif line.startswith("Version:"):
                    info["version"] = line.split(":", 1)[1].strip()
    return info

def send_telegram():
    token = os.environ.get("TELEGRAM_TOKEN")
    chat_id = os.environ.get("TELEGRAM_TO")
    status = os.environ.get("JOB_STATUS", "failed").upper()
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")

    if not token or not chat_id:
        print("❌ Thiếu TELEGRAM_TOKEN hoặc TELEGRAM_TO")
        return

    base_url = f"https://api.telegram.org/bot{token}"
    time_str = get_vietnamese_time()

    # Nhận diện thông tin Dự án đang được Build
    f_name = os.environ.get("PROJECT_NAME", "").strip()
    f_ver = "1.0.0"
    f_bid = "Unknown"
    
    if not f_name or f_name.lower() in ["none", "unknown", "null", ""]:
        local_info = get_fallback_project_info()
        f_name = local_info["name"]
        f_bid = local_info["bundle_id"]
        f_ver = local_info["version"]

    # Tính dung lượng file .deb thực tế trong output nếu build thành công
    output_dir = os.path.join(os.getcwd(), "output")
    deb_files = glob.glob(os.path.join(output_dir, "*.deb"))
    f_size = "0 KB"
    if deb_files:
        size_bytes = os.path.getsize(deb_files[0])
        f_size = f"{size_bytes / 1024:.1f} KB" if size_bytes < 1024*1024 else f"{size_bytes / (1024*1024):.2f} MB"

    # Menu nút bấm: Cố định nút Add Source dẫn về trang Repo của bạn
    keyboard = {"inline_keyboard": [[{"text": "🌐 Add source", "url": "https://2kgt.github.io/repo/"}]]}

    # PHÂN CHIA TRẠNG THÁI HỆ THỐNG BUILD
    if status == "SUCCESS":
        title = "⚙️ <b>HỆ THỐNG BIÊN DỊCH THÀNH CÔNG</b>"
        info_msg = (
            f"📦 <b>Dự án:</b> <code>{f_name}</code>\n"
            f"📀 <b>Dung lượng:</b> <code>{f_size}</code>\n"
            f"⏲️ <b>Phiên bản:</b> <code>{f_ver}</code>\n"
            f"🆔 <b>Bundle ID:</b> <code>{f_bid}</code>\n"
            f"⚡ <b>Trạng thái:</b> Đã đóng gói hoàn tất tệp .deb"
        )
        rel_name = os.environ.get("REL_NAME", f"Build {f_name}")
        rel_body = os.environ.get("REL_BODY", "Đã biên dịch thành công phiên bản mới nhất.")
        desc_raw = f"{f_name}\n──────────────────\n{rel_name}\n{rel_body}"
    else:
        title = "❌ <b>HỆ THỐNG BIÊN DỊCH THẤT BẠI</b>"
        info_msg = (
            f"📦 <b>Dự án:</b> <code>{f_name}</code>\n"
            f"🆔 <b>Bundle ID:</b> <code>{f_bid}</code>\n"
            f"⚠️ <b>Trạng thái:</b> Lỗi tiến trình đóng gói gói cài đặt"
        )
        # Lấy link dẫn thẳng tới log lỗi của GitHub Actions
        repo_full = os.environ.get("GITHUB_REPOSITORY", "")
        run_id = os.environ.get("GITHUB_RUN_ID", "")
        run_url = f"https://github.com/{repo_full}/actions/runs/{run_id}" if run_id else "#"
        
        desc_raw = f"Quá trình biên dịch mã nguồn {f_name} gặp lỗi hệ thống.\n──────────────────\n👉 Vui lòng nhấp vào liên kết bên dưới để kiểm tra nhật ký log chi tiết."

    # Xử lý ký tự đặc biệt tránh crash cú pháp HTML của Telegram
    desc_escaped = desc_raw.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    # Tổng hợp nội dung tin nhắn dạng khối thoáng đãng, không lỗi dòng kẻ thụt lề
    if status == "SUCCESS":
        msg = (
            f"{title}\n"
            f"──────────────────\n"
            f"{info_msg}\n\n"
            f"📝 <b>Mô tả cập nhật:</b> <blockquote>{desc_escaped}</blockquote>\n"
            f"──────────────────\n"
            f"⏰ <b>Thời gian:</b> <code>{time_str}</code>"
        )
    else:
        # Nếu lỗi thì chèn thêm link xem log ngay trong phần trích dẫn để dễ tương tác
        msg = (
            f"{title}\n"
            f"──────────────────\n"
            f"{info_msg}\n\n"
            f"📝 <b>Chi tiết lỗi:</b> <blockquote>{desc_escaped}\n\n🔗 <a href='{run_url}'>Xem Log Actions tại đây</a></blockquote>\n"
            f"──────────────────\n"
            f"⏰ <b>Thời gian:</b> <code>{time_str}</code>"
        )

    # 1. Bắn tin nhắn text thông báo kèm nút Add source
    requests.post(
        f"{base_url}/sendMessage", 
        json={
            "chat_id": chat_id, 
            "text": msg, 
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
            "reply_markup": keyboard
        }
    )

    # 2. Đẩy file đính kèm trực tiếp lên cuộc trò chuyện (Chỉ khi build thành công)
    if status == "SUCCESS":
        for file_path in deb_files:
            filename = os.path.basename(file_path)
            file_caption = f"📦 <b>File:</b> <code>{filename}</code>"
            with open(file_path, "rb") as f:
                requests.post(
                    f"{base_url}/sendDocument", 
                    data={"chat_id": chat_id, "caption": file_caption, "parse_mode": "HTML"},
                    files={"document": f}, 
                    timeout=120
                )

if __name__ == "__main__":
    send_telegram()

