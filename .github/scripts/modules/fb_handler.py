# .github/scripts/modules/fb_handler.py
import os
import header_tools as ht

IDENTIFIER = "facebook"
TAG = "FB-HANDLER"
HEADER_DIRS = ["FacebookHeader"]


def setup(proj_dir, config):
    os.makedirs(os.path.join(proj_dir, "config_fb"), exist_ok=True)
    ht.link_dump(proj_dir, HEADER_DIRS, TAG)
