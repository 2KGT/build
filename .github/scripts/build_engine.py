import os
import sys
import importlib.util
import plistlib
import engine_core as core
import setup_theos

def set_output(name, value):
    with open(os.environ.get('GITHUB_OUTPUT', '/dev/null'), 'a') as fh:
        print(f"{name}={value}", file=fh)

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
        core.build_and_fix(proj_dir, output_dir, "1.0.0")
        
        # Ghi output để GitHub Actions nhận diện
        set_output("status", "success")
        set_output("display_name", proj)
        set_output("final_ver", "1.0.0")
        set_output("has_deb", "true")
        core.log("SUCCESS", "Quá trình biên dịch hoàn tất!")
    except Exception as e:
        core.log("ERROR", f"Biên dịch thất bại: {e}")
        set_output("status", "failed")
        sys.exit(1)

if __name__ == '__main__':
    main()
