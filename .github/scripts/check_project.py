# .github/scripts/check_project.py
import os
import sys

def main():
    # Lấy các biến môi trường từ GitHub
    event_name = os.getenv("EVENT_NAME", "")
    manual_project = os.getenv("MANUAL_PROJECT", "")
    
    # Đọc trực tiếp PROJECT_NAME từ hệ thống (tránh lỗi khai báo lồng của YAML)
    push_project = os.getenv("PROJECT_NAME", "")

    print("🔍 [CHECK] Đang xác thực thông tin dự án...")

    # Tự động gộp biến thông minh (Thay thế hoàn toàn cho logic || của YAML)
    final_project = "None"
    
    if event_name == "workflow_dispatch":
        if manual_project and manual_project != "None":
            final_project = manual_project
    elif event_name == "push":
        if push_project and push_project != "None":
            final_project = push_project

    # Tiến hành kiểm tra chặn lỗi theo 3 điều kiện: trống, không xác định, chưa chọn
    if not final_project or final_project.strip() == "" or final_project == "None":
        print("\n❌ [LỖI HỆ THỐNG - CHẶN CHẠY NGAY LẬP TỨC]")
        print("📍 Trạng thái: Chưa chọn dự án, dự án không xác định hoặc để trống dự án!")
        if event_name == "workflow_dispatch":
            print("💡 Gợi ý: Vui lòng chọn một Tweak cụ thể từ danh sách thay vì để mặc định là 'None'.")
        else:
            print("💡 Gợi ý: Không tìm thấy file 'control' nào thay đổi trong commit này để nhận diện Tweak cần build.")
        sys.exit(1) # Bắn lỗi làm sập hệ thống ngay tại giây này

    print(f"✅ [OK] Xác định dự án hợp lệ: {final_project}. Cấp phép chạy Build Engine!")
    
    # Ghi ngược lại biến INPUT_PROJECT vào GITHUB_ENV để script build_engine.py phía sau sử dụng
    github_env = os.getenv('GITHUB_ENV')
    if github_env:
        with open(github_env, 'a') as f:
            f.write(f"INPUT_PROJECT={final_project}\n")

if __name__ == "__main__":
    main()
