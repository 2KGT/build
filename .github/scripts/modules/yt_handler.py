# .github/scripts/modules/yt_handler.py
import os
import re
import subprocess


def is_project_match(target_dir):
    # 1. Tìm file 'control' của Theos trong thư mục dự án
    control_path = os.path.join(target_dir, "control")
    
    if os.path.exists(control_path):
        with open(control_path, 'r', encoding='utf-8') as f:
            content = f.read()
            # Kiểm tra nếu trong file control có chứa BundleID của YouTube
            if "com.google.ios.youtube" in content:
                return True
                
    # 2. Hoặc tìm file .plist (nếu có)
    for root, dirs, files in os.walk(target_dir):
        for file in files:
            if file.endswith(".plist"):
                # Dùng regex để check nội dung plist nhanh mà không cần parse toàn bộ
                with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                    if "com.google.ios.youtube" in f.read():
                        return True
                        
    return False
    # ... (Giữ nguyên logic clone và symlink như cũ) ...
    # Module này giờ sẽ tự động chạy cho BẤT KỲ dự án nào có BundleID khớp


def setup(target_dir):
    theos_path = os.environ.get('THEOS', '/opt/theos')
    
    # Danh sách các kho cần thiết
    repositories = {
        "YouTubeHeader": "https://github.com/PoomSmart/YouTubeHeader.git",
        "PSHeader": "https://github.com/PoomSmart/PSHeader.git"
    }
    
    for folder_name, repo_url in repositories.items():
        central_repo = os.path.join(theos_path, "include", folder_name)
        
        # 1. Clone vào kho chung nếu chưa có
        if not os.path.exists(central_repo):
            print(f"   [YT-HANDLER] Đang tải {folder_name}...")
            os.makedirs(os.path.dirname(central_repo), exist_ok=True)
            subprocess.run(["git", "clone", "--depth=1", repo_url, central_repo], check=True)
            
        # 2. Tạo cầu nối (Symlink) vào dự án
        project_link = os.path.join(target_dir, folder_name)
        if not os.path.exists(project_link):
            print(f"   [YT-HANDLER] Tạo cầu nối: {folder_name}")
            os.symlink(central_repo, project_link)

