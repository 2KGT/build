# .github/scripts/plan.py
"""
LẬP KẾ HOẠCH BUILD ĐA DỰ ÁN (chạy ở job `plan`, thay cho check_project.py + bước dò dự án trong YAML)

Quyết định "build những dự án nào" rồi xuất matrix cho job `forge` (mỗi dự án một runner, song song):
  • Bấm tay, chọn 1 dự án      -> [dự án đó]
  • Bấm tay, để None           -> DỪNG NGAY với lỗi rõ ràng (chống bấm Run nhầm, đỡ tốn phút build)
  • Push đổi <Dự án>/control   -> TẤT CẢ dự án có control đổi trong khoảng push (không chỉ dự án đầu)
  • Không có dự án nào         -> count=0 (push) hoặc báo lỗi rõ ràng (bấm tay quên chọn)

Biến môi trường: EVENT_NAME, MANUAL_PROJECT, BEFORE_SHA, GITHUB_SHA, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY
"""
import json
import os
import re
import subprocess
import sys

NONE_TOKEN = "None"
WORKFLOW_FILE = os.path.join(".github", "workflows", "tweaks.yml")


def discover(root="."):
    """Mọi thư mục cấp 1 có control (+ Makefile): ứng viên build. Không cần khai báo tay khi thêm dự án mới."""
    found = []
    for name in sorted(os.listdir(root)):
        path = os.path.join(root, name)
        if name.startswith(".") or not os.path.isdir(path) or os.path.islink(path):
            continue
        if os.path.isfile(os.path.join(path, "control")):
            has_make = any(os.path.isfile(os.path.join(path, m)) for m in ("Makefile", "makefile", "GNUmakefile"))
            found.append((name, has_make))
    return found


def changed_projects(before, sha):
    zero = "0" * 40
    ok_before = bool(before) and before != zero and subprocess.run(
        ["git", "cat-file", "-e", f"{before}^{{commit}}"], capture_output=True).returncode == 0
    cmd = (["git", "diff", "--name-only", before, sha] if ok_before
           else ["git", "diff-tree", "--no-commit-id", "--name-only", "-r", sha])
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    names = []
    for line in out.splitlines():
        m = re.fullmatch(r"([^/]+)/control", line.strip())   # control ở gốc repo bị bỏ qua
        if m and m.group(1) not in names:
            names.append(m.group(1))
    return names


def dropdown_options():
    """Đọc danh sách dự án trong ô chọn của tweaks.yml để cảnh báo khi dự án mới chưa có trong đó."""
    try:
        text = open(WORKFLOW_FILE, encoding="utf-8").read()
        m = re.search(r"project:.*?options:\s*\[(.*?)\]", text, re.S)
        return {o.strip().strip("'\"") for o in m.group(1).split(",")} if m else set()
    except OSError:
        return set()


def out(key, value):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(f"{key}={value}\n")


def summary(lines):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")


def fail(msg, hint=""):
    print(f"\n❌ [PLAN] {msg}")
    if hint:
        print(f"💡 {hint}")
    summary([f"## ❌ Không lập được kế hoạch build", f"{msg}", f"_{hint}_" if hint else ""])
    sys.exit(1)


def main():
    event = os.environ.get("EVENT_NAME", "")
    manual = os.environ.get("MANUAL_PROJECT", "").strip()
    candidates = discover()
    names = [n for n, _ in candidates]
    print(f"🔎 [PLAN] Sự kiện: {event} | Dự án phát hiện: {', '.join(names) or '(không có)'}")

    if event == "workflow_dispatch":
        if manual in ("", NONE_TOKEN):
            fail("Chưa chọn dự án (đang để None).", "Chọn đúng một dự án trong ô chọn rồi chạy lại. Chưa tốn phút build macOS nào.")
        if manual not in names:
            fail(f"Không thấy '{manual}/control' trong repo.", "Kiểm tra tên dự án trong ô chọn.")
        projects = [manual]
    elif event == "push":
        projects = [p for p in changed_projects(os.environ.get("BEFORE_SHA", ""), os.environ.get("GITHUB_SHA", "HEAD")) if p in names]
    else:
        fail(f"Sự kiện không được hỗ trợ: '{event}'")

    # Tự động hoá thông minh: nhắc đồng bộ ô chọn dự án khi có dự án mới
    options = dropdown_options()
    missing = [n for n in names if options and n not in options]
    if missing:
        print(f"::warning::Dự án chưa có trong ô chọn của tweaks.yml: {', '.join(missing)} (thêm vào options của input 'project').")

    out("matrix", json.dumps({"project": projects}, ensure_ascii=False))
    out("count", str(len(projects)))

    lines = ["## 🗺️ Kế hoạch build", f"- Số dự án: **{len(projects)}**"]
    lines += [f"  - `{p}`" for p in projects] or ["  - _(không có dự án nào cần build)_"]
    if missing:
        lines.append(f"- ⚠️ Chưa có trong ô chọn: {', '.join(f'`{m}`' for m in missing)}")
    summary(lines)
    print(f"✅ [PLAN] Sẽ build {len(projects)} dự án: {', '.join(projects) or '(không)'}")


if __name__ == "__main__":
    main()
