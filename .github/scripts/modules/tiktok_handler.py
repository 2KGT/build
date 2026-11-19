# .github/scripts/modules/tiktok_handler.py
import header_tools as ht

IDENTIFIER = "com.zhiliaoapp.musically"
TAG = "TT-HANDLER"
HEADER_DIRS = ["TikTokHeader"]


def setup(proj_dir, config):
    ht.link_dump(proj_dir, HEADER_DIRS, TAG)
