# .github/scripts/modules/instagram_handler.py
import header_tools as ht

IDENTIFIER = "com.burbn.instagram"
TAG = "IG-HANDLER"
HEADER_DIRS = ["InstagramHeader", "IGHeader"]


def setup(proj_dir, config):
    ht.link_dump(proj_dir, HEADER_DIRS, TAG)
