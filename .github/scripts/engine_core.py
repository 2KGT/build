# version: 2.1.0 | 2026-11-13 | build nhiều hệ sinh thái (Rootless/Rootful/Dylib), tự soạn mô tả vào control tạm thời, thu .dylib; không đổi cách gọi cũ
# .github/scripts/engine_core.py
import os
import subprocess
import shutil
import sys
import re
import tempfile

# Log build được ghi ra file này để bước "Tổng kết & Phân tích lỗi" trong workflow đọc
BUILD_LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build.log")
_ANSI = re.compile(r"\x1b\[[0-9;]*m")

def _write_log(line):
    try:
        with open(BUILD_LOG, "a", encoding="utf-8") as fh:
            fh.write(_ANSI.sub("", line) + "\n")
    except OSError:
        pass

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
        for line in process.stdout:
            print(f"   [MAKE] {line.strip()}")
            _write_log(line.rstrip())
        if process.wait() != 0: raise subprocess.CalledProcessError(process.returncode, cmd)
    except Exception as e:
        log("ERROR", f"Lệnh {' '.join(cmd)} thất bại: {e}")
        sys.exit(1)

VARIANTS = {
    # THEOS_PACKAGE_SCHEME ghi đè giá trị trong Makefile (tham số dòng lệnh luôn thắng); rỗng = rootful
    "rootless": {"scheme": "rootless", "label": "Rootless"},
    "rootful": {"scheme": "", "label": "Rootful"},
}


def plan_variants(ecosystems):
    """Danh sách bản build cần chạy: [(tên, xuất_deb, xuất_dylib)]. Dylib được lấy từ bản Rootful (không phụ thuộc /var/jb)."""
    if ecosystems is None:
        return [("default", True, False)]
    want = set(ecosystems)
    plan = []
    if "rootless" in want:
        plan.append(("rootless", True, False))
    if "rootful" in want or "dylib" in want:
        plan.append(("rootful", "rootful" in want, "dylib" in want))
    return plan


def _dpkg_field(deb, field):
    r = subprocess.run(["dpkg-deb", "-f", deb, field], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def extract_dylibs(deb_path, output_dir):
    """Lấy .dylib trong .deb, đặt tên <package>_<version>_<arch>.dylib (đúng quy ước repo Sileo/Feather)."""
    pkg, ver, arch = (_dpkg_field(deb_path, f) for f in ("Package", "Version", "Architecture"))
    tmp = tempfile.mkdtemp(prefix="dylib_")
    r = subprocess.run(["dpkg-deb", "-x", deb_path, tmp], capture_output=True, text=True)
    if r.returncode != 0 or not (pkg and ver and arch):
        log("WARN", f"Không đọc được {os.path.basename(deb_path)} để lấy dylib")
        return []
    found = []
    for root, _, files in os.walk(tmp):
        for f in files:
            full = os.path.join(root, f)
            if f.endswith(".dylib") and not os.path.islink(full):
                found.append(full)
    found.sort(key=lambda p: -os.path.getsize(p))
    out = []
    for n, path in enumerate(found):
        stem = os.path.splitext(os.path.basename(path))[0]
        name = f"{pkg}_{ver}_{arch}.dylib" if n == 0 else f"{pkg}-{stem}_{ver}_{arch}.dylib"
        shutil.copy2(path, os.path.join(output_dir, name))
        out.append(name)
        log("SUCCESS", f"Đã xuất dylib: {name}")
    shutil.rmtree(tmp, ignore_errors=True)
    return out


def build_and_fix(target_dir, output_dir, new_ver=None, clean=True, ecosystems=None, describe=None):
    """
    ecosystems: None = một lần build như cũ (Makefile tự quyết scheme) | danh sách con của {rootless, rootful, dylib}.
    describe  : hàm (tên_bản_build) -> callback(control_path) trả về nội dung gốc để khôi phục, hoặc None.
                Mô tả được thêm vào control TẠM THỜI trong lúc build rồi khôi phục (không ghi vào repo).
    Module/handler do build_engine.py chạy TRƯỚC khi gọi hàm này (một cơ chế duy nhất).
    """
    target_dir = os.path.abspath(target_dir)
    open(BUILD_LOG, "w").close()  # làm mới log cho lần build này

    # --- BUILD ---
    if not os.path.exists(os.path.join(target_dir, "Makefile")):
        log("ERROR", f"Không tìm thấy Makefile tại {target_dir}")
        sys.exit(1)

    variants = plan_variants(ecosystems)
    if not variants:
        log("ERROR", "Chưa chọn hệ sinh thái nào (Rootless / Rootful / Dylib).")
        sys.exit(1)
    os.makedirs(output_dir, exist_ok=True)
    packages_dir = os.path.join(target_dir, "packages")
    control_path = os.path.join(target_dir, "control")
    exported = 0

    for idx, (name, export_deb, export_dylib) in enumerate(variants):
        log("BUILD", f"Biên dịch {os.path.basename(target_dir)} — {name}")
        if clean or idx > 0:             # đổi scheme bắt buộc make clean để không lẫn object cũ
            run_cmd(["make", "clean"], cwd=target_dir)
        else:
            log("BUILD", "Bỏ qua make clean (clean_build = false)")
        shutil.rmtree(packages_dir, ignore_errors=True)   # chỉ thu .deb của đúng bản build này

        cmd = ["make", "package", "FINALPACKAGE=1"]
        if name in VARIANTS:
            cmd.append(f"THEOS_PACKAGE_SCHEME={VARIANTS[name]['scheme']}")
        original = describe(name)(control_path) if describe else None
        try:
            run_cmd(cmd, cwd=target_dir)
        finally:
            if original is not None:
                with open(control_path, "w", encoding="utf-8") as fh:
                    fh.write(original)

        deb_files = sorted(f for f in os.listdir(packages_dir) if f.endswith(".deb")) if os.path.exists(packages_dir) else []
        if not deb_files:
            log("ERROR", f"Không tìm thấy file .deb nào sau khi build ({name}).")
            sys.exit(1)
        for file in deb_files:
            src = os.path.join(packages_dir, file)
            if export_deb:
                shutil.copy2(src, os.path.join(output_dir, file))
                log("SUCCESS", f"Đã xuất file: {file}")
                exported += 1
            if export_dylib:
                exported += len(extract_dylibs(src, output_dir))

    if not exported:
        log("ERROR", "Build xong nhưng không có tệp nào để xuất.")
        sys.exit(1)
    return True
