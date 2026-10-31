"""
upstream.py — Tự động đồng bộ mã nguồn tweak mã nguồn mở (YouTube X...) vào dự án mỗi lần build.

Cách hoạt động:
  1. Đọc upstream.json (cùng thư mục) để biết dự án nào cần đồng bộ những repo nào.
  2. Clone bản mới nhất của từng repo (mặc định nhánh main).
  3. CHỈ nhận repo có giấy phép MIT / Apache / BSD. Repo không có giấy phép rõ ràng bị bỏ qua.
  4. Chép file Tweak.x thành <Dự án>/Upstream_<Tên>.x (Makefile tự gom bằng wildcard).
  5. Ghi nguồn gốc + giấy phép vào THIRD_PARTY_LICENSES.md.
  6. Nếu một file upstream làm hỏng biên dịch, build_engine gọi drop() để bỏ riêng file đó và build lại.
"""

import json
import os
import re
import shutil
import subprocess
import tempfile

LICENSE_FILES = ("LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING")
SOURCE_CANDIDATES = ("Tweak.x", "Tweak.xm")

_PERMISSIVE = re.compile(
    r"(MIT License|Permission is hereby granted, free of charge|Apache License"
    r"|Redistribution and use in source and binary forms)",
    re.IGNORECASE,
)

# Dòng lỗi biên dịch có tên file upstream, ví dụ "Upstream_YouTubeX.x:48:26: error: ..."
_ERR_RE = re.compile(r"(Upstream_[A-Za-z0-9_]+)\.xm?:\d+(?::\d+)?: (?:fatal )?error")


def load_config(config_path, project):
    try:
        with open(config_path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return []
    entries = data.get(project, [])
    return entries if isinstance(entries, list) else []


def _git(args, cwd=None, timeout=180):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=timeout)


def _clone(repo, ref, dest):
    """Clone nông theo nhánh/tag. Nếu ref là mã commit thì clone đầy đủ rồi checkout."""
    try:
        r = _git(["clone", "--depth", "1", "--branch", ref, repo, dest])
        if r.returncode == 0:
            return True, ""
        shutil.rmtree(dest, ignore_errors=True)
        r = _git(["clone", repo, dest])
        if r.returncode != 0:
            return False, r.stderr.strip()[-160:]
        r = _git(["checkout", ref], cwd=dest)
        return r.returncode == 0, r.stderr.strip()[-160:]
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, str(e)


def _read_first(directory, names):
    for name in names:
        path = os.path.join(directory, name)
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                return name, fh.read()
    return None, ""


def _license_name(text):
    low = text.lower()
    if "apache license" in low:
        return "Apache-2.0"
    if "mit license" in low or "permission is hereby granted, free of charge" in low:
        return "MIT"
    return "BSD"


def _control_version(directory):
    _, text = _read_first(directory, ("control",))
    m = re.search(r"(?im)^Version:\s*(\S+)", text)
    return m.group(1) if m else "?"


_FORBIDDEN_DIRECTIVES = re.compile(r"(?m)^\s*%(group|ctor|dtor|init|subclass)\b")
_HBLOG_IMPORT = re.compile(r"(?m)^[ \t]*#[ \t]*import[ \t]*<HBLog\.h>[ \t]*$")
_KEY_RE = re.compile(r"^[A-Za-z0-9_]+$")

_HBLOG_SHIM = """#if __has_include(<HBLog.h>)
#import <HBLog.h>
#else
#define HBLogDebug(...) ((void)0)
#define HBLogInfo(...) ((void)0)
#define HBLogWarn(...) ((void)0)
#define HBLogError(...) ((void)0)
#endif"""


def shim_hblog(body):
    """Máy build không có HBLog.h (Cephei) thì dùng bản rỗng để không lỗi biên dịch."""
    return _HBLOG_IMPORT.sub(_HBLOG_SHIM, body)


def gate_source(body, name, toggles):
    """
    Bọc các %hook của file upstream vào nhóm Logos để bật/tắt được bằng NSUserDefaults.
    toggles: [{"key": "kYTXBackground", "default": true, "classes": ["MLVideo", ...]}, {"key": "kYTXAds"}]
      - toggle có "classes" nhận các hook của những class đó; toggle không có "classes" nhận phần còn lại.
    Trả về (text, gated). gated=False nghĩa là không bọc an toàn được -> trả nguyên bản (luôn bật).
    """
    if not toggles or _FORBIDDEN_DIRECTIVES.search(body):
        return body, False
    for t in toggles:
        if not _KEY_RE.match(t.get("key", "")):
            return body, False

    top, hooks, current = [], [], None
    for line in body.split("\n"):
        stripped = line.strip()
        if current is None:
            m = re.match(r"%hook\s+(\w+)", stripped)
            if m:
                current = (m.group(1), [line])
            else:
                top.append(line)
        else:
            current[1].append(line)
            if stripped == "%end":
                hooks.append(current)
                current = None
    if current is not None or not hooks:
        return body, False

    fallback = next((i for i, t in enumerate(toggles) if not t.get("classes")), 0)
    buckets = [[] for _ in toggles]
    for cls, lines in hooks:
        idx = next((i for i, t in enumerate(toggles) if cls in (t.get("classes") or [])), fallback)
        buckets[idx].append("\n".join(lines))

    helper = f"AutoACGateEnabled_{name}"
    out = ["#import <Foundation/Foundation.h>", "\n".join(top).rstrip("\n"), "",
           f"static BOOL {helper}(NSString *key, BOOL fallback) {{",
           "    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];",
           "    return value ? [value boolValue] : fallback;",
           "}", ""]
    inits = []
    for i, (t, hook_texts) in enumerate(zip(toggles, buckets)):
        if not hook_texts:
            continue
        group = f"Upstream_{name}_G{i}"
        out += [f"%group {group}", "", "\n\n".join(hook_texts), "", "%end", ""]
        default = "YES" if t.get("default", True) else "NO"
        inits.append(f'    if ({helper}(@"{t["key"]}", {default})) {{ %init({group}); }}')
    out += ["%ctor {"] + inits + ["}", ""]
    return "\n".join(out), True


def clean_upstream(proj_dir):
    """Xoá file upstream của lần build trước để mỗi lần build bắt đầu từ trạng thái sạch."""
    for name in os.listdir(proj_dir):
        if name.startswith("Upstream_") and name.endswith((".x", ".xm")):
            os.remove(os.path.join(proj_dir, name))


def sync(proj_dir, entries, log=print):
    """Đồng bộ toàn bộ entries. Trả về danh sách kết quả (mỗi phần tử là một dict)."""
    clean_upstream(proj_dir)
    results = []
    tmp_root = tempfile.mkdtemp(prefix="upstream_")
    try:
        for entry in entries:
            name = entry["name"]
            res = {
                "name": name,
                "title": entry.get("title", name),
                "repo": entry["repo"],
                "ref": entry.get("ref", "main"),
                "ok": False,
                "reason": "",
            }
            results.append(res)

            dest = os.path.join(tmp_root, name)
            ok, err = _clone(res["repo"], res["ref"], dest)
            if not ok:
                res["reason"] = f"không tải được repo ({err or 'lỗi mạng'})"
                log(f"   [UPSTREAM] {res['title']}: {res['reason']}")
                continue

            lic_file, lic_text = _read_first(dest, LICENSE_FILES)
            if not _PERMISSIVE.search(lic_text):
                res["reason"] = "không có giấy phép MIT/Apache/BSD rõ ràng nên không tự động nhúng"
                log(f"   [UPSTREAM] {res['title']}: {res['reason']}")
                continue

            src_name = None
            wanted = entry.get("source") or SOURCE_CANDIDATES
            for cand in ([wanted] if isinstance(wanted, str) else wanted):
                if os.path.isfile(os.path.join(dest, cand)):
                    src_name = cand
                    break
            if not src_name:
                res["reason"] = "không tìm thấy Tweak.x / Tweak.xm trong repo"
                log(f"   [UPSTREAM] {res['title']}: {res['reason']}")
                continue

            sha = _git(["rev-parse", "HEAD"], cwd=dest).stdout.strip()[:7] or "?"
            license_id = _license_name(lic_text)
            file_name = f"Upstream_{name}{os.path.splitext(src_name)[1]}"
            with open(os.path.join(dest, src_name), encoding="utf-8", errors="replace") as fh:
                body = shim_hblog(fh.read())
            gated = False
            if entry.get("toggles"):
                body, gated = gate_source(body, name, entry["toggles"])
                if not gated:
                    log(f"   [UPSTREAM] {res['title']}: không bọc được công tắc, giữ nguyên bản gốc (luôn bật)")
            header = (
                f"// Tự động đồng bộ từ {res['repo']} @ {sha} ({license_id}).\n"
                f"// File này bị ghi đè mỗi lần build, không sửa tay. Xem THIRD_PARTY_LICENSES.md.\n"
            )
            with open(os.path.join(proj_dir, file_name), "w", encoding="utf-8") as fh:
                fh.write(header + body)

            res.update(ok=True, file=file_name, sha=sha, version=_control_version(dest),
                       license=license_id, license_text=lic_text, gated=gated)
            log(f"   [UPSTREAM] {res['title']} {res['version']} @ {sha} ({license_id}) -> {file_name}")
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)

    write_licenses(proj_dir, results)
    return results


def failing_upstreams(log_path):
    """Tên các upstream có file xuất hiện trong dòng lỗi biên dịch của log."""
    try:
        with open(log_path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return []
    names = []
    for m in _ERR_RE.finditer(text):
        name = m.group(1)[len("Upstream_"):]
        if name not in names:
            names.append(name)
    return names


def drop(proj_dir, name, results, reason):
    """Bỏ file upstream bị lỗi và ghi lý do vào kết quả."""
    for fname in os.listdir(proj_dir):
        if fname.startswith(f"Upstream_{name}.") and fname.endswith((".x", ".xm")):
            os.remove(os.path.join(proj_dir, fname))
    for res in results:
        if res["name"] == name:
            res["ok"] = False
            res["reason"] = reason


def write_licenses(proj_dir, results):
    """Ghi THIRD_PARTY_LICENSES.md cho các upstream đang được nhúng. Không còn upstream nào thì xoá file."""
    path = os.path.join(proj_dir, "THIRD_PARTY_LICENSES.md")
    active = [r for r in results if r.get("ok")]
    if not active:
        if os.path.exists(path):
            os.remove(path)
        return
    lines = [
        "# Third-party licenses",
        "",
        "Các mã nguồn sau được tự động đồng bộ vào bản build. Mỗi phần giữ nguyên giấy phép gốc.",
        "",
    ]
    for r in active:
        lines += [
            f"## {r['title']}",
            f"- Nguồn: {r['repo']} @ `{r['sha']}` (phiên bản {r['version']})",
            f"- Giấy phép: {r['license']}",
            "",
            "```text",
            r["license_text"].strip(),
            "```",
            "",
        ]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


def build_info_lines(results):
    """Hai dòng #define đưa vào BuildInfo.h để menu hiển thị số upstream đã tích hợp."""
    active = [r for r in results if r.get("ok")]
    info = ", ".join(f"{r['title']} {r['version']}".replace('"', "").replace("\\", "") for r in active)
    lines = [f"#define TWEAK_UPSTREAM_COUNT {len(active)}",
             f'#define TWEAK_UPSTREAM_INFO @"{info}"']
    for r in active:
        if r.get("gated"):
            lines.append(f"#define TWEAK_UPSTREAM_{re.sub(r'[^A-Za-z0-9]', '_', r['name']).upper()}_GATED 1")
    return lines
