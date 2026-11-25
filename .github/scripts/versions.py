#!/usr/bin/env python3
# version: 1.0.0 | 2026-11-06 | tự dựng VERSIONS.md từ dòng version trong file + git log; cảnh báo quên tăng số
# .github/scripts/versions.py
"""
TỰ ĐỘNG HOÁ VERSIONS.md

  python3 .github/scripts/versions.py                 dựng lại .github/VERSIONS.md
  python3 .github/scripts/versions.py --check A B     cảnh báo file đã sửa (A..B) mà chưa tăng số version

Nguồn dữ liệu (không ghi tay gì vào VERSIONS.md):
  • Bảng hiện tại : dòng đầu mỗi file hệ thống
        YAML / Python : # version: 2.1.0 | 2026-11-06 | mô tả ngắn
        Markdown      : <!-- version: 2.1.0 | 2026-11-06 | mô tả ngắn -->
        JSON          : "_version": "2.1.0 | 2026-11-06 | mô tả ngắn"
  • Lịch sử       : git log của từng file — mỗi lần số version đổi là một dòng (theo cả đổi tên file)
Chạy từ thư mục gốc của repo.
"""
import glob
import json
import os
import re
import subprocess
import sys

__version__ = "1.0.0"

OUTPUT = os.path.join(".github", "VERSIONS.md")
PATTERNS = [".github/workflows/*.yml", ".github/scripts/*.py", ".github/scripts/modules/*.py", ".github/*.json"]
RE_LINE = re.compile(r"^(?:#|<!--)\s*version:\s*(\d+\.\d+\.\d+)\s*(?:\|\s*(\d{4}-\d{2}-\d{2}))?\s*(?:\|\s*(.*?))?\s*(?:-->)?\s*$")
RE_JSON = re.compile(r'"_version"\s*:\s*"([^"]+)"')
RE_VERSION = re.compile(r"^(\d+\.\d+\.\d+)\s*(?:\|\s*(\d{4}-\d{2}-\d{2}))?\s*(?:\|\s*(.*))?$")
MAX_HISTORY = 100


def git(*args):
    r = subprocess.run(["git", *args], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout if r.returncode == 0 else ""


def parse(text):
    """Trả về {'version','date','note'} hoặc None nếu file chưa đánh số."""
    for line in text.splitlines()[:8]:
        m = RE_LINE.match(line.strip())
        if m:
            return {"version": m.group(1), "date": m.group(2) or "", "note": (m.group(3) or "").strip()}
    m = RE_JSON.search(text[:2000])
    if m:
        v = RE_VERSION.match(m.group(1).strip())
        if v:
            return {"version": v.group(1), "date": v.group(2) or "", "note": (v.group(3) or "").strip()}
    return None


def managed_files():
    files = set()
    for pattern in PATTERNS:
        files.update(glob.glob(pattern))
    return sorted(f.replace(os.sep, "/") for f in files if os.path.basename(f) != "__init__.py")


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def history(path):
    """Các lần đổi số version của một file, cũ → mới (đi theo cả khi file bị đổi tên)."""
    out = git("log", "--follow", "--name-only", "--format=%x00%H %as", "--", path)
    commits = []
    for chunk in out.split("\x00")[1:]:
        lines = [l for l in chunk.splitlines() if l.strip()]
        if len(lines) >= 2:
            sha, date = lines[0].split(" ", 1)
            commits.append((sha, date, lines[1].strip()))
    rows, prev = [], None
    for sha, date, p in reversed(commits):
        info = parse(git("show", f"{sha}:{p}"))
        if info and info["version"] != prev:
            rows.append({"date": date, "file": path, "version": info["version"], "note": info["note"], "first": prev is None, "sha": sha[:7]})
            prev = info["version"]
    return rows


def cell(text):
    """Ghi chú có ký tự | sẽ làm vỡ bảng markdown nên escape."""
    return (text or "—").replace("|", "\\|")


def short(path):
    return path[len(".github/"):] if path.startswith(".github/") else path


def build():
    files = managed_files()
    table, hist = [], []
    for f in files:
        info = parse(read(f))
        table.append((f, info))
        hist += history(f)
    hist.sort(key=lambda r: (r["date"], r["file"]), reverse=True)

    L = ["<!-- TỰ ĐỘNG TẠO bởi scripts/versions.py — đừng sửa tay. Muốn đổi số: sửa dòng `version:` đầu từng file. -->",
         "# Phiên bản hệ thống build", "",
         "## Hiện tại", "", "| File | Phiên bản | Ngày | Mô tả |", "|------|-----------|------|-------|"]
    for f, info in table:
        if info:
            L.append(f"| `{short(f)}` | **{info['version']}** | {info['date'] or '—'} | {cell(info['note'])} |")
        else:
            L.append(f"| `{short(f)}` | _chưa đánh số_ | — | — |")
    L += ["", "File _chưa đánh số_ sẽ được ghi số ở lần sửa tiếp theo của chính file đó.", "",
          "## Lịch sử đổi phiên bản", ""]
    if hist:
        L += ["| Ngày | File | Phiên bản | Ghi chú | Commit |", "|------|------|-----------|---------|--------|"]
        for r in hist[:MAX_HISTORY]:
            note = cell(r["note"])
            L.append(f"| {r['date']} | `{short(r['file'])}` | {r['version']}{' (lần đầu)' if r['first'] else ''} | {note} | `{r['sha']}` |")
    else:
        L.append("_Chưa có lịch sử git cho các file đã đánh số (sẽ xuất hiện sau commit đầu tiên chứa dòng `version:`)._")
    L += ["", "## Quy ước", "",
          "- `MAJOR`: đổi ô nhập hoặc cách file nối với file khác. `MINOR`: thêm tính năng tương thích. `PATCH`: sửa lỗi.",
          "- Chỉ file được sửa mới tăng số. Workflow cảnh báo nếu file bị sửa mà số không đổi.",
          "- Workflow ghi rõ engine tối thiểu (`REQUIRES_ENGINE`) và dừng sớm ở bước `plan` nếu thiếu.",
          "- Workflow chỉ dùng một đuôi: `.yml`."]
    return "\n".join(L) + "\n"


def cmd_generate():
    content = build()
    old = read(OUTPUT)
    if content == old:
        print("VERSIONS.md đã mới, không đổi gì.")
        return
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as fh:
        fh.write(content)
    print(f"Đã cập nhật {OUTPUT}")


def cmd_check(before, sha):
    zero = "0" * 40
    ok_before = bool(before) and before != zero and bool(git("cat-file", "-t", before).strip())
    names = (git("diff", "--name-only", "--diff-filter=AM", before, sha) if ok_before
             else git("diff-tree", "--no-commit-id", "--name-only", "-r", "--diff-filter=AM", sha)).split()
    managed = set(managed_files())
    warned = 0
    for path in names:
        if path not in managed:
            continue
        new = parse(git("show", f"{sha}:{path}"))
        old = parse(git("show", f"{before}:{path}")) if ok_before else None
        if new is None:
            print(f"::notice file={path}::File hệ thống chưa có dòng version — nên thêm ở lần sửa này.")
        elif old and old["version"] == new["version"]:
            print(f"::warning file={path}::Đã sửa nội dung nhưng version vẫn là {new['version']} — hãy tăng số.")
            warned += 1
    print(f"Kiểm tra version: {warned} file có thể quên tăng số.")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--check"] and len(args) == 3:
        cmd_check(args[1], args[2])
    elif not args:
        cmd_generate()
    elif args == ["--version"]:
        print(__version__)
    else:
        sys.exit("Dùng: versions.py | versions.py --check TRƯỚC SAU | versions.py --version")
