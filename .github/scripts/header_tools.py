# .github/scripts/header_tools.py
"""
Cầu nối giữa Dump-Unified (headers/<App>Header/) và quá trình build tweak.

HỢP ĐỒNG DUMP <-> BUILD
  Dump-Unified ghi:   headers/<App>Header/*.h, Bridge.h, ClassList.txt (và Selectors.txt nếu bật)
  Handler (modules/)  gọi link_dump(): tìm thư mục trên, symlink vào <Dự án>/<App>Header
  Tweak.x             import:  #import "<App>Header/Bridge.h"
"""
import os
import shutil
import subprocess


def repo_root():
    return os.environ.get("GITHUB_WORKSPACE") or os.getcwd()


def log(tag, msg):
    print(f"   [{tag}] {msg}")


def find_dump(candidates, root=None):
    root = root or repo_root()
    for name in candidates:
        path = os.path.join(root, "headers", name)
        if os.path.isdir(path):
            return path
    return None


def _read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            return [l.strip() for l in fh if l.strip()]
    except OSError:
        return []


def ensure_bridge(dump, tag):
    """Dump-Unified đã sinh Bridge.h; nếu thiếu mà có ClassList.txt thì sinh lại cho khớp định dạng."""
    bridge = os.path.join(dump, "Bridge.h")
    classes = _read_lines(os.path.join(dump, "ClassList.txt"))
    if os.path.exists(bridge) or not classes:
        return
    log(tag, "📝 Sinh Bridge.h từ ClassList.txt")
    with open(bridge, "w", encoding="utf-8") as fh:
        fh.write("// Bridge Header tự sinh – KHÔNG sửa tay\n#pragma once\n")
        fh.write("#import <Foundation/Foundation.h>\n#import <UIKit/UIKit.h>\n\n")
        fh.writelines(f"@class {c};\n" for c in classes)


def log_interesting(dump, class_kw, sel_kw, tag, limit=15):
    for fname, kws, label in (("ClassList.txt", class_kw, "class"), ("Selectors.txt", sel_kw, "selector")):
        if not kws:
            continue
        lines = _read_lines(os.path.join(dump, fname))
        if not lines:
            continue
        hits = [l for l in lines if any(k.lower() in l.lower() for k in kws)]
        log(tag, f"🎯 {len(hits)} {label} tiềm năng:")
        for h in hits[:limit]:
            print(f"       • {h}")
        if len(hits) > limit:
            print(f"       … (+{len(hits) - limit} {label} khác)")


def link_or_copy(src, dst, tag):
    if os.path.lexists(dst):
        log(tag, f"Đã có {os.path.basename(dst)}")
        return
    try:
        os.symlink(src, dst)
        log(tag, f"🔗 {os.path.basename(dst)}")
    except OSError:
        shutil.copytree(src, dst)
        log(tag, f"📋 {os.path.basename(dst)}")


def link_dump(proj_dir, candidates, tag, class_kw=(), sel_kw=()):
    """Tìm headers/<candidate> đã dump, kiểm tra Bridge.h, rồi nối vào thư mục dự án."""
    dump = find_dump(candidates)
    if not dump:
        log(tag, "⚠️  Chưa có header dump. Đã thử: " + ", ".join(f"headers/{c}" for c in candidates))
        log(tag, f"   → Chạy Dump-Unified với app_name = {candidates[0]} trước.")
        return None
    name = os.path.basename(dump)
    ensure_bridge(dump, tag)
    log_interesting(dump, class_kw, sel_kw, tag)
    link_or_copy(dump, os.path.join(proj_dir, name), tag)
    log(tag, f"✅ Tweak.x dùng: #import \"{name}/Bridge.h\"")
    return dump


def clone_external(name, url, proj_dir, tag):
    """Kho header bên ngoài (PoomSmart...): clone vào $THEOS/include, cập nhật nếu đã có, rồi symlink vào dự án."""
    theos = os.environ.get("THEOS", "/opt/theos")
    central = os.path.join(theos, "include", name)
    if not os.path.isdir(central):
        log(tag, f"Đang tải {name}...")
        os.makedirs(os.path.dirname(central), exist_ok=True)
        subprocess.run(["git", "clone", "--quiet", "--depth=1", url, central], check=True)
    else:
        # cache Theos sống lâu nên kho này dễ cũ: cập nhật tốt nhất có thể, lỗi mạng không làm hỏng build
        subprocess.run(["git", "-C", central, "pull", "--quiet", "--ff-only"],
                       check=False, timeout=120, capture_output=True)
    link_or_copy(central, os.path.join(proj_dir, name), tag)
