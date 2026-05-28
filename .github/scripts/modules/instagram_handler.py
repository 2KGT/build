import os
import subprocess

def is_project_match(target_dir):
    return "com.burbn.instagram" in open(os.path.join(target_dir, "control")).read()

def setup(target_dir):
    # Thêm các link repo header cho Instagram của bạn tại đây
    repos = {"IGHeader": "https://github.com/someone/IGHeader.git"}
    # ... logic clone & symlink tương tự yt_handler ...
