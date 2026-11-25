# .github/scripts/modules/bilibili_handler.py
import header_tools as ht

# "bilibili" bao trọn: com.bilibili.bilibiliHD, tv.danmaku.bilibiliHD, com.bilibili.fhmovie ...
IDENTIFIER = "bilibili"
TAG = "BILI-HANDLER"
HEADER_DIRS = ["BilibiliHDHeader"]

CLASS_KEYWORDS = ["Player", "Ad", "Quality", "Download", "Watermark", "Danmaku", "Video", "BAPI"]
SELECTOR_KEYWORDS = ["quality", "watermark", "download", "splash", "feedad", "qn", "defn"]


def setup(proj_dir, config):
    ht.link_dump(proj_dir, HEADER_DIRS, TAG, CLASS_KEYWORDS, SELECTOR_KEYWORDS)
