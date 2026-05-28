import os
import subprocess

def is_project_match(target_dir):
    return "com.zhiliaoapp.musically" in open(os.path.join(target_dir, "control")).read()

def setup(target_dir):
    # Logic setup cho TikTok
    pass
