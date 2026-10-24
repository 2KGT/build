# .github/scripts/build_engine.py
import os
import re
import sys
import importlib.util
import plistlib
import engine_core as core
import setup_theos

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

def write_build_info(proj_dir, version):
    """Tạo BuildInfo.h để Tweak.x hiển thị version của chính bản build này."""
    with open(os.path.join(proj_dir, "BuildInfo.h"), "w", encoding="utf-8") as fh:
        fh.write("// Tạo tự động bởi build_engine.py. Không sửa tay.\n")
        fh.write(f'#define TWEAK_BUILD_VERSION @"{version}"\n')

def load_module_from_file(file_path):
    spec = importlib.util.spec_from_file_location("dynamic_module", file_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def get_single_module(bundle_id):
    modules_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "modules")
    for f in os.listdir(modules_dir):
        if f.endswith("_handler.py") and f != "__init__.py":
            file_path = os.path.join(modules_dir, f)
            try:
                mod = load_module_from_file(file_path)
                if hasattr(mod, 'IDENTIFIER') and mod.IDENTIFIER.lower() in bundle_id.lower():
                    return {"name": f[:-3], "path": file_path}
            except Exception as e:
                core.log("WARN", f"Bỏ qua module {f} do lỗi load: {e}")
    return None

def main():
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
    
    # 3. TỰ ĐỘNG PHÁT HIỆN MODULE
    matched_info = None
    plist_path = os.path.join(proj_dir, "Info.plist")
    
    if os.path.exists(plist_path):
        with open(plist_path, 'rb') as f:
            bundle_id = plistlib.load(f).get("CFBundleIdentifier", "").lower()
            matched_info = get_single_module(bundle_id)

    # 4. KHỞI CHẠY MODULE (Nếu có)
    if matched_info:
        core.log("MODULE", f"Đang khởi chạy module chuyên biệt: {matched_info['name']}")
        try:
            mod = load_module_from_file(matched_info['path'])
            mod.setup(proj, {})
        except Exception as e:
            core.log("ERROR", f"Module {matched_info['name']} gặp lỗi: {e}")
            sys.exit(1)
    else:
        core.log("INFO", "Dự án tiêu chuẩn, không sử dụng module chuyên biệt.")

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
        write_build_info(proj_dir, version)

        core.build_and_fix(proj_dir, output_dir, version)
        
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

