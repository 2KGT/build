# .github/scripts/setup_theos.py
import os
import subprocess
import engine_core as core

def verify_and_setup():
    """Kiểm tra và thiết lập Theos nếu chưa sẵn sàng"""
    theos_path = os.environ.get('THEOS')
    if not theos_path:
        core.log("ERROR", "Biến môi trường THEOS chưa được đặt.")
        raise SystemExit(1)
    
    # 1. Kiểm tra tồn tại
    if not os.path.exists(theos_path):
        core.log("SETUP", "Theos chưa tồn tại, đang tiến hành cài đặt...")
        subprocess.run(["git", "clone", "--recursive", "https://github.com/theos/theos.git", theos_path], check=True)
        
    # 2. Cài đặt SDKs (Chỉ cài nếu chưa có)
    sdk_path = os.path.join(theos_path, "sdks")
    os.makedirs(sdk_path, exist_ok=True)
    if not os.listdir(sdk_path):
        core.log("SETUP", "Đang tải SDKs cho Theos...")
        # Phải truyền MỘT chuỗi lệnh khi dùng dấu | với shell=True (dạng list làm đường ống không chạy)
        subprocess.run(
            f'curl -fL https://github.com/theos/sdks/archive/master.tar.gz | tar -xz --strip-components=1 -C "{sdk_path}"',
            shell=True, check=True,
        )
        
    core.log("SETUP", "Môi trường Theos đã sẵn sàng.")

if __name__ == "__main__":
    verify_and_setup()
