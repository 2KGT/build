# .github/scripts/build_engine.py
import os
import re
import sys
import time
import shutil
import importlib.util
import engine_core as core
import setup_theos
import upstream
import changelog

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)  # để handler import được header_tools

SKIP_DIRS = {"packages", ".theos", "obj", "headers", ".git"}

def set_output(name, value):
    with open(os.environ.get('GITHUB_OUTPUT', '/dev/null'), 'a') as fh:
        print(f"{name}={value}", file=fh)

def read_control_version(proj_dir, default="1.0.0"):
    """Đọc Version thật từ file control của dự án."""
    try:
        with open(os.path.join(proj_dir, "control"), encoding="utf-8") as fh:
            for line in fh:
                if line.lower().startswith("version:"):
                    return line.split(":", 1)[1].strip() or default
    except OSError:
        pass
    return default

def parse_level(text):
    """'Patch (Vá lỗi)' -> 'patch', 'Minor (Tính năng)' -> 'minor', 'Major (Đại tu)' -> 'major'. Rỗng -> None."""
    t = (text or "").strip().lower()
    for key in ("major", "minor", "patch"):
        if t.startswith(key):
            return key
    return None

_VER_RE = re.compile(r"^(\d+)(?:\.(\d+))?(?:\.(\d+))?$")

def bump_version(version, level):
    """
    Tăng version theo cấp độ. Giữ nguyên số phần của version gốc khi có thể:
      patch : 1.1 -> 1.1.1   | 1.1.1 -> 1.1.2
      minor : 1.1 -> 1.2     | 1.1.1 -> 1.2.0
      major : 1.1 -> 2.0     | 1.1.1 -> 2.0.0
    Trả về None nếu version không phải dạng số (vd 1.0-beta) hoặc không có cấp độ.
    """
    m = _VER_RE.match((version or "").strip())
    if not m or level not in ("major", "minor", "patch"):
        return None
    nums = [int(x) for x in m.groups() if x is not None]
    count = len(nums)
    major, minor, patch = (nums + [0, 0, 0])[:3]
    if level == "major":
        parts = [major + 1, 0, 0][:count]
    elif level == "minor":
        parts = [major, minor + 1, 0][:max(count, 2)]
    else:
        parts = [major, minor, patch + 1]
    return ".".join(str(p) for p in parts)

def write_control_version(proj_dir, new_version):
    """Ghi lại dòng 'Version:' trong control, giữ nguyên mọi dòng và kiểu xuống dòng khác."""
    path = os.path.join(proj_dir, "control")
    with open(path, encoding="utf-8", newline="") as fh:
        text = fh.read()
    new_text, n = re.subn(r"(?im)^(Version:[ \t]*)[^\r\n]*", lambda m: m.group(1) + new_version, text, count=1)
    if n == 0:
        raise RuntimeError("Không tìm thấy dòng 'Version:' trong file control.")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(new_text)

def write_build_info(proj_dir, version, upstream_results=()):
    """Tạo BuildInfo.h để Tweak.x hiển thị version của bản build và các tweak đã tích hợp."""
    with open(os.path.join(proj_dir, "BuildInfo.h"), "w", encoding="utf-8") as fh:
        fh.write("// Tạo tự động bởi build_engine.py. Không sửa tay.\n")
        fh.write(f'#define TWEAK_BUILD_VERSION @"{version}"\n')
        for line in upstream.build_info_lines(upstream_results):
            fh.write(line + "\n")

def load_module_from_file(file_path):
    spec = importlib.util.spec_from_file_location("dynamic_module", file_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def project_signature(proj_dir, max_depth=3):
    """Văn bản dùng để nhận diện app đích: mọi file .plist (filter/Info) + dòng Package/Name trong control."""
    chunks = []
    base_depth = proj_dir.rstrip(os.sep).count(os.sep)
    for root, dirs, files in os.walk(proj_dir):
        if root.count(os.sep) - base_depth >= max_depth:
            dirs[:] = []
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not os.path.islink(os.path.join(root, d))]
        for fname in files:
            if fname.endswith(".plist"):
                try:
                    with open(os.path.join(root, fname), encoding="utf-8", errors="ignore") as fh:
                        chunks.append(fh.read())
                except OSError:
                    pass
    try:
        with open(os.path.join(proj_dir, "control"), encoding="utf-8", errors="ignore") as fh:
            chunks += [l for l in fh if l.lower().startswith(("package:", "name:"))]
    except OSError:
        pass
    return "\n".join(chunks).lower()


def find_modules(proj_dir):
    """Một cơ chế duy nhất: handler nào có IDENTIFIER xuất hiện trong chữ ký dự án thì được chạy (có thể nhiều handler)."""
    modules_dir = os.path.join(SCRIPT_DIR, "modules")
    signature = project_signature(proj_dir)
    found = []
    for fname in sorted(os.listdir(modules_dir)):
        if not fname.endswith("_handler.py"):
            continue
        path = os.path.join(modules_dir, fname)
        try:
            mod = load_module_from_file(path)
        except Exception as e:
            core.log("WARN", f"Bỏ qua module {fname} do lỗi load: {e}")
            continue
        ident = getattr(mod, "IDENTIFIER", "")
        if ident and ident.lower() in signature and callable(getattr(mod, "setup", None)):
            found.append({"name": fname[:-3], "mod": mod})
    return found


def main():
    started = time.time()
    # 1. SETUP MÔI TRƯỜNG
    core.log("SYSTEM", "Kiểm tra và chuẩn bị môi trường Theos...")
    setup_theos.verify_and_setup()

    # 2. XÁC ĐỊNH & XÁC THỰC DỰ ÁN
    proj = os.environ.get('INPUT_PROJECT', '').strip()
    if not proj or proj == "None":
        core.log("ERROR", "Dự án đầu vào chưa được xác định (INPUT_PROJECT = None hoặc rỗng).")
        sys.exit(1)
        
    proj_dir = os.path.join(os.getcwd(), proj)
    output_dir = os.path.join(os.getcwd(), "output")
    
    # Kiểm tra tồn tại thư mục project
    if not os.path.exists(proj_dir):
        core.log("ERROR", f"Không tìm thấy thư mục dự án tại: {proj_dir}")
        sys.exit(1)
    
    core.log("SYSTEM", f"Đang xử lý dự án: {proj} tại {proj_dir}")
    
    # 3-4. NHẬN DIỆN & CHẠY HANDLER (nối headers/ từ Dump-Unified vào dự án)
    matched = find_modules(proj_dir)
    if not matched:
        core.log("INFO", "Dự án tiêu chuẩn, không có handler phù hợp.")
    for info in matched:
        core.log("MODULE", f"Chạy handler: {info['name']}")
        try:
            info["mod"].setup(proj_dir, {})
        except Exception as e:
            core.log("ERROR", f"Handler {info['name']} gặp lỗi: {e}")
            sys.exit(1)

    # 5. BUILD & CHỐT KẾT QUẢ
    # Hàm core.build_and_fix bên trong đã có lệnh 'make clean' và 'make package'
    try:
        old_version = read_control_version(proj_dir)
        version = old_version
        bumped = False

        # Tăng version theo cấp độ đã chọn. Chạy push (không chọn cấp độ) thì giữ nguyên.
        level = parse_level(os.environ.get("INPUT_VER_TYPE", ""))
        if level:
            new_version = bump_version(old_version, level)
            if new_version:
                write_control_version(proj_dir, new_version)
                version, bumped = new_version, True
                core.log("VERSION", f"{old_version} -> {new_version} (cấp độ {level})")
            else:
                core.log("WARN", f"Version '{old_version}' không phải dạng số (X.Y.Z) nên bỏ qua tăng version.")
        else:
            core.log("VERSION", f"Giữ nguyên version {old_version} (không chọn cấp độ nâng cấp).")

        # Đồng bộ các tweak mã nguồn mở (YouTube X...) ở bản mới nhất của upstream
        entries, config_path = upstream.resolve_config(proj_dir, SCRIPT_DIR, proj)
        if entries:
            core.log("UPSTREAM", f"Cấu hình: {os.path.relpath(config_path)}")
            core.log("UPSTREAM", f"Đang đồng bộ {len(entries)} tweak mã nguồn mở...")
            results = upstream.sync(proj_dir, entries, log=print)
        else:
            upstream.clean_upstream(proj_dir)
            results = []

        clean_first = os.environ.get("INPUT_CLEAN_BUILD", "true").strip().lower() != "false"

        # Build. Một file upstream lỗi biên dịch thì chỉ bỏ riêng file đó rồi build lại
        attempts = 0
        while True:
            attempts += 1
            write_build_info(proj_dir, version, results)
            try:
                core.build_and_fix(proj_dir, output_dir, version, clean=clean_first or attempts > 1)
                break
            except SystemExit:
                active = [r["name"] for r in results if r.get("ok")]
                if not active or attempts >= 4:
                    raise
                culprits = [n for n in upstream.failing_upstreams(core.BUILD_LOG) if n in active]
                if not culprits:
                    # Không tìm thấy tên file upstream nào trong dòng lỗi: chỉ bỏ cái đứng CUỐI danh sách cấu hình rồi thử lại
                    # (cấu hình đặt tweak quan trọng như YouTube X lên đầu), thay vì bỏ sạch mọi upstream cùng lúc
                    core.log("WARN", "Không xác định được upstream nào gây lỗi, thử bỏ lần lượt từ cuối danh sách.")
                    culprits = [active[-1]]
                for name in culprits:
                    upstream.drop(proj_dir, name, results, "lỗi biên dịch với bản upstream mới nhất, đã tự bỏ qua")
                core.log("WARN", f"Bỏ qua upstream bị lỗi: {', '.join(culprits)}. Biên dịch lại...")
        upstream.write_licenses(proj_dir, results)

        # Nhật ký build + CHANGELOG.md (lỗi ở đây không được làm hỏng build)
        try:
            shutil.copy2(core.BUILD_LOG, os.path.join(output_dir, "build.log"))
        except OSError:
            pass
        try:
            level_label = {"patch": "Patch (Vá lỗi)", "minor": "Minor (Tính năng)", "major": "Major (Đại tu)"}.get(level)
            path = changelog.record_build(
                os.getcwd(), proj_dir, proj, version=version, old_version=old_version, bumped=bumped,
                level_label=level_label, output_dir=output_dir, started_ts=started,
                upstream=results, attempts=attempts, log_path=core.BUILD_LOG)
            core.log("CHANGELOG", f"Đã ghi nhật ký build vào {os.path.relpath(path)}")
        except Exception as e:
            core.log("WARN", f"Không ghi được CHANGELOG.md: {e}")

        # Ghi output để GitHub Actions nhận diện
        set_output("status", "success")
        set_output("display_name", proj)
        set_output("old_ver", old_version)
        set_output("final_ver", version)
        set_output("bumped", "true" if bumped else "false")
        has_deb = os.path.isdir(output_dir) and any(f.endswith(".deb") for f in os.listdir(output_dir))
        set_output("has_deb", "true" if has_deb else "false")
        core.log("SUCCESS", "Quá trình biên dịch hoàn tất!")
    except Exception as e:
        core.log("ERROR", f"Biên dịch thất bại: {e}")
        set_output("status", "failed")
        sys.exit(1)

if __name__ == '__main__':
    main()

