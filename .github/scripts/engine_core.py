# .github/scripts/engine_core.py
import os
import subprocess
import shutil
import sys
import importlib
import pkgutil
from modules import __path__ as modules_path

def log(stage, msg):
    print(f"\n🚀 [{stage.upper()}] {msg}")

def run_cmd(cmd, cwd=None, env=None):
    full_env = os.environ.copy()
    if env: full_env.update(env)
    
    if 'THEOS' not in full_env:
        default_theos = "/opt/theos"
        if os.path.exists(default_theos): full_env['THEOS'] = default_theos
        else:
            log("ERROR", "Biến môi trường THEOS không tìm thấy!")
            sys.exit(1)

    try:
        process = subprocess.Popen(cmd, cwd=cwd, env=full_env, stdout=subprocess.PIPE, 
                                   stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in process.stdout: print(f"   [MAKE] {line.strip()}")
        if process.wait() != 0: raise subprocess.CalledProcessError(process.returncode, cmd)
    except Exception as e:
        log("ERROR", f"Lệnh {' '.join(cmd)} thất bại.")
        sys.exit(1)

def build_and_fix(target_dir, output_dir, new_ver=None):
    target_dir = os.path.abspath(target_dir)
    
    # --- TỰ ĐỘNG NHẬN DIỆN MODULE ---
    log("SYSTEM", "Đang kiểm tra các module hỗ trợ...")
    for loader, name, is_pkg in pkgutil.iter_modules(modules_path):
        module = importlib.import_module(f"modules.{name}")
        if hasattr(module, 'is_project_match') and module.is_project_match(target_dir):
            log("INFO", f"Phát hiện dự án phù hợp với module: {name}")
            module.setup(target_dir)
    
    # --- BUILD ---
    if not os.path.exists(os.path.join(target_dir, "Makefile")):
        log("ERROR", f"Không tìm thấy Makefile tại {target_dir}")
        sys.exit(1)

    log("BUILD", f"Bắt đầu biên dịch: {os.path.basename(target_dir)}")
    run_cmd(["make", "clean"], cwd=target_dir)
    run_cmd(["make", "package", "FINALPACKAGE=1"], cwd=target_dir)

    # --- THU GOM ---
    packages_dir = os.path.join(target_dir, "packages")
    deb_files = [f for f in os.listdir(packages_dir) if f.endswith(".deb")] if os.path.exists(packages_dir) else []
    
    if not deb_files:
        log("ERROR", "Không tìm thấy file .deb nào sau khi build.")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)
    for file in deb_files:
        shutil.copy2(os.path.join(packages_dir, file), os.path.join(output_dir, file))
        log("SUCCESS", f"Đã xuất file: {file}")
    
    return True
    
    return True
