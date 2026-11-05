# .github/scripts/modules/yt_handler.py
# API chung của mọi handler (build_engine.py gọi):
#   IDENTIFIER : chuỗi (bundle ID của app đích) xuất hiện trong control/*.plist của dự án
#   setup(proj_dir, config) : proj_dir là đường dẫn tuyệt đối tới thư mục dự án
import header_tools as ht

IDENTIFIER = "com.google.ios.youtube"
TAG = "YT-HANDLER"

# Kho header ngoài, dùng chung cho mọi tweak YouTube
EXTERNAL = {
    "YouTubeHeader": "https://github.com/PoomSmart/YouTubeHeader.git",
    "PSHeader": "https://github.com/PoomSmart/PSHeader.git",
}


def setup(proj_dir, config):
    for name, url in EXTERNAL.items():
        ht.clone_external(name, url, proj_dir, TAG)
