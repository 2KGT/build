# version: 1.1.0 | 2026-11-06 | thêm HEADER_DIRS (dump của người dùng) để hooks.py nối dự án YouTube với headers/YouTubeHeader
# .github/scripts/modules/yt_handler.py
# API chung của mọi handler (build_engine.py gọi):
#   IDENTIFIER : chuỗi (bundle ID của app đích) xuất hiện trong control/*.plist của dự án
#   setup(proj_dir, config) : proj_dir là đường dẫn tuyệt đối tới thư mục dự án
import header_tools as ht

IDENTIFIER = "com.google.ios.youtube"
TAG = "YT-HANDLER"

# Thư mục dump của người dùng (Dump-Unified). Chỉ dùng cho hooks.py (kiểm tra hook);
# khác với kho PoomSmart cùng tên trong EXTERNAL bên dưới, kho này vẫn được clone như cũ.
HEADER_DIRS = ["YouTubeHeader"]

# Kho header ngoài, dùng chung cho mọi tweak YouTube
EXTERNAL = {
    "YouTubeHeader": "https://github.com/PoomSmart/YouTubeHeader.git",
    "PSHeader": "https://github.com/PoomSmart/PSHeader.git",
}


def setup(proj_dir, config):
    for name, url in EXTERNAL.items():
        ht.clone_external(name, url, proj_dir, TAG)
