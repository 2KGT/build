# .github/scripts/modules/fb_handler.py
import os
import subprocess
import sys

# Tối ưu hóa: Thêm thư mục scripts vào đường dẫn tìm kiếm của hệ thống
# Điều này cho phép module này truy cập được engine_core.py bất kể nó được load như thế nào
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import engine_core as core

# Hệ thống build_engine.py sẽ quét thấy file này thông qua IDENTIFIER
IDENTIFIER = "facebook"

def setup(proj, config):
    """
    Thiết lập môi trường chuyên biệt cho dự án Facebook.
    """
    core.log("FB-HANDLER", f"Đang khởi tạo môi trường chuyên biệt cho dự án: {proj}")
    
    # Tạo thư mục cấu hình đặc thù cho Facebook
    fb_config_path = os.path.join(os.getcwd(), proj, "config_fb")
    os.makedirs(fb_config_path, exist_ok=True)
    
    core.log("FB-HANDLER", "Thiết lập Facebook hoàn tất. Sẵn sàng build!")
