#!/usr/bin/env python3
# version: 1.2.0 | 2026-11-06 | list-dumps/latest-dump (tự chọn thư mục), dựng fingerprint từ lịch sử git, báo tên dump sai kèm danh sách hợp lệ, check-all xuất broken/broken_dumps
# .github/scripts/hooks.py
"""
KIỂM TRA HOOK & THEO DÕI THAY ĐỔI CỦA APP — không gắn riêng với app nào

  Dump-Unified (khi có bản app mới)            Build Tweak (job plan)
  ─────────────────────────────────            ──────────────────────
  hooks.py dump-report                         hooks.py check-all
    • so dump cũ ↔ mới → CHANGES.md              • hook của dự án còn khớp header không?
    • meta.json (phiên bản app)                  • class mất → gợi ý theo fingerprint
    • fingerprints.json (chỉ class bị hook)      • selector mất → gợi ý tên gần giống

Nguyên lý
  • Hook   : đọc %hook / method trong *.x *.xm (bỏ %new, %subclass)
  • Header : đọc @interface / method / @property trong headers/<App>Header/*.h (định dạng ipsw class-dump)
  • Nối dự án ↔ thư mục dump: handler trong scripts/modules (IDENTIFIER khớp .plist của dự án, HEADER_DIRS)
  • Fingerprint của một class = superclass + protocol + ivar + tập selector → chấm điểm giống nhau
Kết quả chỉ để CẢNH BÁO: script luôn thoát mã 0, không bao giờ chặn build.

Lệnh:
  hooks.py check-all   --matrix '{"project":["A","B"]}'
  hooks.py dump-report --dump YouTubeHeader --old DIR --new DIR --out DIR [--partial] [--version V] [--bundle B]
  hooks.py fix         --dump YouTubeHeader [--body FILE] [--dry]    tự sửa tên class (chỉ khi tin cậy cao) + viết nội dung PR
  hooks.py list-dumps                     các thư mục dump có dự án dùng (mới dump nhất trước) — để workflow tự chọn
  hooks.py latest-dump                    thư mục dump mới nhất
  hooks.py projects-for --dump YouTubeHeader

Phạm vi của `fix` (cố ý hẹp để an toàn):
  • CHỈ đổi tên class khi có đúng một ứng viên, điểm >= 0.8 và hơn ứng viên thứ hai >= 0.15
  • KHÔNG tự sửa selector (đổi tham số kéo theo sửa thân hàm và %orig) — chỉ ghi vào báo cáo để người sửa
  • Chỉ sửa file Logos của dự án trong repo; hook sinh từ upstream không đụng tới
  • Luôn đi qua Pull Request để người duyệt; không commit thẳng vào nhánh chính
Chạy từ thư mục gốc của repo.
"""
import difflib
import glob
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

__version__ = "1.2.0"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

LOGOS_EXT = (".x", ".xm", ".xi", ".xmi")
SKIP_DIRS = {"packages", ".theos", "obj", "headers", ".git"}
SUGGEST_MIN = 0.5          # điểm tối thiểu để đưa ra gợi ý
CONFIDENT = 0.8            # điểm "tin cậy"
CONFIDENT_GAP = 0.15       # và phải hơn ứng viên thứ hai ít nhất chừng này
MAX_LINES = 40             # giới hạn dòng mỗi mục trong báo cáo


# ───────────────────────── tiện ích văn bản ─────────────────────────
def strip_noise(text):
    """Bỏ comment, chuỗi, ký tự — giữ nguyên số dòng."""
    out, i, n = [], 0, len(text)
    while i < n:
        c, two = text[i], text[i:i + 2]
        if two == "//":
            while i < n and text[i] != "\n":
                i += 1
        elif two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("\n" * text.count("\n", i, j))
            i = j
        elif c in "\"'":
            q, i = c, i + 1
            while i < n and text[i] != q:
                i += 2 if text[i] == "\\" else 1
            i += 1
            out.append(q + q)
        else:
            out.append(c)
            i += 1
    return "".join(out)


def strip_parens(s):
    """Bỏ nội dung trong ngoặc tròn (kể cả lồng nhau như kiểu block): '(void (^)(id))x' -> '()x'."""
    out, depth = [], 0
    for ch in s:
        if ch == "(":
            if depth == 0:
                out.append("(")
            depth += 1
        elif ch == ")":
            depth = max(depth - 1, 0)
            if depth == 0:
                out.append(")")
        elif depth == 0:
            out.append(ch)
    return "".join(out)


def selector_of(sig):
    """'(void)foo:(id)a bar:(int)b' -> 'foo:bar:'   |   '(id)name' -> 'name'."""
    s = re.sub(r"^\s*\(\)\s*", "", strip_parens(sig).strip(), count=1)
    keys = re.findall(r"([A-Za-z_]\w*)\s*:", s)
    if keys:
        return ":".join(keys) + ":"
    m = re.match(r"\s*([A-Za-z_]\w*)", s)
    return m.group(1) if m else None


def tokens(selector):
    parts = re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])", selector.replace(":", " "))
    return {p.lower() for p in parts}


def jaccard(a, b):
    a, b = set(a), set(b)
    union = a | b
    return len(a & b) / len(union) if union else None


def read(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            return fh.read()
    except OSError:
        return ""


# ───────────────────────── hook (Logos) ─────────────────────────
RE_HOOK = re.compile(r"^%hook\s+([A-Za-z_]\w*)")
RE_SUBCLASS = re.compile(r"^%subclass\b")
RE_METHOD_START = re.compile(r"^[-+]\s*\(")
SUB = "<subclass>"


def parse_logos(text, path=""):
    """Danh sách hook: {class, selector, kind('-'|'+'), file, line}. Bỏ %new và %subclass."""
    hooks, cur, depth, pending, pending_ln, new_flag = [], None, 0, None, 0, False
    for ln, raw in enumerate(strip_noise(text).split("\n"), 1):
        line = raw.strip()
        if cur is None:
            m = RE_HOOK.match(line)
            if m:
                cur, depth, pending, new_flag = m.group(1), 0, None, False
            elif RE_SUBCLASS.match(line):
                cur, depth, pending, new_flag = SUB, 0, None, False
            continue
        if pending is None and depth == 0:
            if line.startswith("%end"):
                cur = None
                continue
            if line.startswith("%new"):
                new_flag = True
                line = line[4:].strip()
                if not line:
                    continue
            if RE_METHOD_START.match(line):
                pending, pending_ln = line, ln
            else:
                depth = max(depth + line.count("{") - line.count("}"), 0)
                continue
        elif pending is not None:
            pending += " " + line
        elif depth > 0:
            depth = max(depth + line.count("{") - line.count("}"), 0)
            continue
        if pending is not None and ("{" in pending or ";" in pending):
            head = re.split(r"[{;]", pending, 1)[0]
            if cur != SUB and not new_flag:
                sel = selector_of(head.strip()[1:])
                if sel:
                    hooks.append({"class": cur, "selector": sel, "kind": head.strip()[0],
                                  "file": path, "line": pending_ln})
            new_flag = False
            tail = pending[len(head):]
            depth = max(tail.count("{") - tail.count("}"), 0)
            pending = None
    return hooks


def project_sources(proj_dir):
    files = []
    for root, dirs, names in os.walk(proj_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not os.path.islink(os.path.join(root, d))]
        for name in sorted(names):
            if name.endswith(LOGOS_EXT) and not name.startswith("Upstream_"):
                files.append(os.path.join(root, name))
    return files


def project_hooks(proj_dir):
    hooks = []
    for f in project_sources(proj_dir):
        hooks += parse_logos(read(f), f)
    return hooks


# ───────────────────────── header (class-dump) ─────────────────────────
RE_IFACE = re.compile(r"^@interface\s+([A-Za-z_]\w*)\s*(?::\s*([A-Za-z_]\w*))?\s*(?:\(\s*([A-Za-z_]\w*)?\s*\))?\s*(?:<([^>]*)>)?")
RE_IVAR = re.compile(r"([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*;")


def new_class():
    return {"super": "", "protocols": set(), "ivars": set(), "sel": set()}


def parse_header(text, classes):
    cur, in_ivars, pending = None, False, None
    for raw in strip_noise(text).split("\n"):
        line = raw.strip()
        if not line:
            continue
        if pending is not None:
            pending += " " + line
            if ";" in pending:
                _add_method(classes[cur], pending)
                pending = None
            continue
        m = RE_IFACE.match(line)
        if m:
            cur = m.group(1)
            info = classes.setdefault(cur, new_class())
            if m.group(2):
                info["super"] = m.group(2)
            if m.group(4):
                info["protocols"].update(p.strip() for p in m.group(4).split(",") if p.strip())
            in_ivars = line.rstrip().endswith("{")
            continue
        if cur is None:
            continue
        if line.startswith("@end"):
            cur, in_ivars = None, False
        elif in_ivars:
            if line.startswith("}"):
                in_ivars = False
            elif not line.startswith("@"):
                im = RE_IVAR.search(line)
                if im:
                    classes[cur]["ivars"].add(im.group(1))
        elif line == "{":
            in_ivars = True
        elif line.startswith("@property"):
            _add_property(classes[cur], line)
        elif RE_METHOD_START.match(line):
            if ";" in line:
                _add_method(classes[cur], line)
            else:
                pending = line


def _add_method(info, text):
    head = text.split(";", 1)[0].strip()
    sel = selector_of(head[1:])
    if sel:
        info["sel"].add(head[0] + sel)


def _add_property(info, line):
    m = re.match(r"^@property\s*(?:\(([^)]*)\))?\s*(.*?);", line)
    if not m:
        return
    attrs, decl = m.group(1) or "", m.group(2)
    block = re.search(r"\(\s*\^\s*(\w+)\s*\)", decl)
    name = block.group(1) if block else (re.search(r"(\w+)\s*(?:\[[^\]]*\])?\s*$", decl) or [None, None])[1]
    if not name:
        return
    getter = re.search(r"getter\s*=\s*(\w+)", attrs)
    setter = re.search(r"setter\s*=\s*([\w:]+)", attrs)
    info["sel"].add("-" + (getter.group(1) if getter else name))
    if "readonly" not in attrs:
        info["sel"].add("-" + (setter.group(1) if setter else "set" + name[:1].upper() + name[1:] + ":"))


def load_headers(directory):
    classes = {}
    if not directory or not os.path.isdir(directory):
        return classes
    for name in sorted(os.listdir(directory)):
        if name.endswith(".h") and name != "Bridge.h":
            parse_header(read(os.path.join(directory, name)), classes)
    return classes


# ───────────────────────── fingerprint & chấm điểm ─────────────────────────
def fingerprint(info):
    return {"super": info["super"], "protocols": sorted(info["protocols"]),
            "ivars": sorted(info["ivars"]), "sel": sorted(info["sel"])}


def score(fp, info):
    sel = jaccard(fp.get("sel", []), info["sel"])
    sup = None if not fp.get("super") else (1.0 if fp["super"] == info["super"] else 0.0)
    proto = jaccard(fp.get("protocols", []), info["protocols"])
    ivar = jaccard(fp.get("ivars", []), info["ivars"])
    parts = [(0.60, sel), (0.15, sup), (0.15, proto), (0.10, ivar)]
    used = [(w, v) for w, v in parts if v is not None]
    return sum(w * v for w, v in used) / sum(w for w, _ in used) if used else 0.0


def build_index(classes):
    index = {}
    for name, info in classes.items():
        for s in info["sel"]:
            index.setdefault(s, set()).add(name)
    return index


def rename_candidates(fp, classes, index, exclude=()):
    """Top 3 class có fingerprint gần nhất. Trả về [(tên, điểm)] đã sắp xếp."""
    shared = {}
    for s in fp.get("sel", []):
        owners = index.get(s, ())
        if 0 < len(owners) <= 50:                   # bỏ selector quá phổ biến (init, dealloc...)
            for o in owners:
                shared[o] = shared.get(o, 0) + 1
    top = sorted(shared, key=lambda o: -shared[o])[:30]
    scored = sorted(((o, round(score(fp, classes[o]), 3)) for o in top if o not in exclude), key=lambda t: -t[1])
    return [t for t in scored if t[1] >= SUGGEST_MIN][:3]


def selector_suggestions(missing, kind, info, fp):
    """Gợi ý selector mới trong cùng class có tên gần giống selector đã mất."""
    old = set(fp.get("sel", [])) if fp else set()
    pool = [s[1:] for s in info["sel"] if s[0] == kind and s not in old] or [s[1:] for s in info["sel"] if s[0] == kind]
    want, colons, out = tokens(missing), missing.count(":"), []
    for cand in pool:
        diff = abs(cand.count(":") - colons)
        if diff > 1:
            continue
        sim = jaccard(want, tokens(cand))
        if sim is not None:
            sim *= 0.9 if diff else 1.0          # lệch một tham số: phạt nhẹ
            if sim >= SUGGEST_MIN:
                out.append((cand, round(sim, 3)))
    return sorted(out, key=lambda t: -t[1])[:3]


def is_confident(cands):
    return bool(cands) and cands[0][1] >= CONFIDENT and (len(cands) == 1 or cands[0][1] - cands[1][1] >= CONFIDENT_GAP)


# ───────────────────────── đối chiếu hook ↔ header ─────────────────────────
def inherited(classes, name, key, seen=()):
    sup = classes.get(name, {}).get("super", "")
    if not sup or sup in seen or sup not in classes:
        return False
    return key in classes[sup]["sel"] or inherited(classes, sup, key, seen + (name,))


def check_hooks(hooks, classes, fps):
    """Trả về danh sách kết quả {status, hook, ...}. status: ok | removed | unverified | missing_class | external."""
    index, results = build_index(classes), []
    for h in hooks:
        cls, key = h["class"], h["kind"] + h["selector"]
        fp = fps.get(cls)
        if cls in classes:
            info = classes[cls]
            if key in info["sel"] or inherited(classes, cls, key):
                results.append({"status": "ok", "hook": h})
            elif fp and (key in fp.get("sel", []) or key in fp.get("lost", [])):
                results.append({"status": "removed", "hook": h, "suggest": selector_suggestions(h["selector"], h["kind"], info, fp)})
            else:
                results.append({"status": "unverified", "hook": h,
                                "suggest": selector_suggestions(h["selector"], h["kind"], info, fp)})
        elif fp:
            results.append({"status": "missing_class", "hook": h, "candidates": rename_candidates(fp, classes, index)})
        else:
            results.append({"status": "external", "hook": h})
    return results


def summarize(results):
    counts = {}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    return counts


def render_results(results, with_annotations=False):
    """Dòng markdown cho các kết quả cần chú ý + (tuỳ chọn) chú thích ::warning:: của GitHub."""
    lines, seen_class = [], set()
    for r in results:
        h, st = r["hook"], r["status"]
        where = f"`{os.path.basename(h['file'])}:{h['line']}`" if h.get("file") else ""
        if st == "missing_class":
            if h["class"] in seen_class:
                continue
            seen_class.add(h["class"])
            c = r["candidates"]
            if c:
                tag = "tin cậy" if is_confident(c) else "cần xem lại"
                text = "; ".join(f"`{n}` ({s})" for n, s in c)
                msg = f"class `{h['class']}` không còn trong dump → ứng viên ({tag}): {text}"
            else:
                msg = f"class `{h['class']}` không còn trong dump và chưa tìm được ứng viên"
            lines.append(f"- ⚠️ {msg} {where}")
        elif st == "removed":
            sug = r["suggest"]
            extra = (" → gợi ý: " + "; ".join(f"`{h['kind']}{n}` ({s})" for n, s in sug)) if sug else ""
            msg = f"`{h['kind']}{h['selector']}` trên `{h['class']}` đã biến mất{extra}"
            lines.append(f"- ⚠️ {msg} {where}")
        else:
            continue
        if with_annotations and h.get("file"):
            print(f"::warning file={h['file']},line={h['line']}::{msg.replace('`', '')}")
    return lines


# ───────────────────────── nối dự án ↔ thư mục dump (qua handler) ─────────────────────────
def handler_table():
    """[(IDENTIFIER, [HEADER_DIRS])] đọc bằng regex, không import handler."""
    table = []
    for path in sorted(glob.glob(os.path.join(SCRIPT_DIR, "modules", "*_handler.py"))):
        text = read(path)
        ident = re.search(r'^IDENTIFIER\s*=\s*"([^"]+)"', text, re.M)
        dirs = re.search(r"^HEADER_DIRS\s*=\s*\[([^\]]*)\]", text, re.M)
        if ident and dirs:
            table.append((ident.group(1).lower(), re.findall(r'"([^"]+)"', dirs.group(1))))
    return table


def signature(proj_dir):
    try:
        import build_engine
        return build_engine.project_signature(proj_dir)
    except Exception:
        return ""


def dumps_for_project(proj_dir):
    sig, found = signature(proj_dir), []
    for ident, dirs in handler_table():
        if ident in sig:
            found += [d for d in dirs if d not in found]
    return found


def all_projects(root="."):
    return sorted(n for n in os.listdir(root)
                  if not n.startswith(".") and os.path.isfile(os.path.join(root, n, "control")))


def projects_for_dump(dump, root="."):
    return [p for p in all_projects(root) if dump in dumps_for_project(os.path.join(root, p))]


def git_out(*args):
    r = subprocess.run(["git", *args], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout if r.returncode == 0 else ""


def recover_fingerprint(dump, cls):
    """Dựng lại fingerprint của class đã biến mất từ lịch sử git: lấy header của nó ở commit ngay trước khi bị xoá."""
    path = f"headers/{dump}/{cls}.h"
    sha = git_out("log", "-1", "--diff-filter=D", "--format=%H", "--", path).strip()
    if not sha:
        return None
    classes = {}
    parse_header(git_out("show", f"{sha}^:{path}"), classes)
    return fingerprint(classes[cls]) if cls in classes else None


def ensure_fingerprints(dump, hooks, classes, fps):
    """Bổ sung fingerprint còn thiếu cho class bị hook nhưng không còn trong dump (fingerprints.json thiếu/mới)."""
    for cls in sorted({h["class"] for h in hooks}):
        if cls not in classes and cls not in fps:
            fp = recover_fingerprint(dump, cls)
            if fp:
                fps[cls] = fp
                print(f"ℹ️ Dựng lại fingerprint của `{cls}` từ lịch sử git")
    return fps


def list_dumps(root="."):
    """[(tên, ngày dump)] của các thư mục headers/* có ít nhất một dự án dùng và có hook Logos; mới nhất trước."""
    base, found = os.path.join(root, "headers"), []
    if not os.path.isdir(base):
        return found
    for name in sorted(os.listdir(base)):
        if not os.path.isdir(os.path.join(base, name)):
            continue
        projects = projects_for_dump(name, root)
        if any(project_hooks(os.path.join(root, p)) for p in projects):
            meta = load_json(os.path.join(base, name, "meta.json"), {})
            found.append((name, meta.get("dumped_at", "")))
    return sorted(found, key=lambda t: (t[1], t[0]), reverse=True)


def all_dump_dirs(root="."):
    base = os.path.join(root, "headers")
    return sorted(n for n in os.listdir(base) if os.path.isdir(os.path.join(base, n))) if os.path.isdir(base) else []


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1, sort_keys=True)
        fh.write("\n")


def summary_write(lines):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")


# ───────────────────────── check-all (Build Tweak) ─────────────────────────
def cmd_check_all(matrix_json):
    try:
        projects = json.loads(matrix_json or "{}").get("project", [])
    except ValueError:
        projects = []
    out = ["## 🪝 Kiểm tra hook", ""]
    broken_total, broken_dumps = 0, []
    for proj in projects:
        hooks = project_hooks(proj)
        if not hooks:
            out.append(f"- `{proj}`: không có hook Logos trong repo (hook upstream do tác giả upstream lo) — bỏ qua")
            continue
        dumps = [d for d in dumps_for_project(proj) if os.path.isdir(os.path.join("headers", d))]
        if not dumps:
            out.append(f"- `{proj}`: {len(hooks)} hook nhưng chưa có dump phù hợp trong `headers/` — chạy Dump-Unified cho app này")
            continue
        dump = dumps[0]
        classes = load_headers(os.path.join("headers", dump))
        fps = ensure_fingerprints(dump, hooks, classes, load_json(os.path.join("headers", dump, "fingerprints.json"), {}))
        meta = load_json(os.path.join("headers", dump, "meta.json"), {})
        results = check_hooks(hooks, classes, fps)
        counts = summarize(results)
        n_broken = counts.get("removed", 0) + counts.get("missing_class", 0)
        if n_broken:
            broken_total += n_broken
            if dump not in broken_dumps:
                broken_dumps.append(dump)
        ver = f" · app {meta['app_version']}" if meta.get("app_version") else ""
        out.append(f"### `{proj}` — dump `{dump}`{ver}")
        out.append(f"- ✅ {counts.get('ok', 0)} hook khớp · ⚠️ {counts.get('removed', 0) + counts.get('missing_class', 0)} có vấn đề"
                   f" · ℹ️ {counts.get('unverified', 0) + counts.get('external', 0)} chưa kiểm chứng được (kế thừa / class hệ thống / thiếu fingerprint)")
        out += render_results(results, with_annotations=True)[:MAX_LINES]
        out.append("")
    if not projects:
        out.append("_Không có dự án nào để kiểm tra._")
    text = "\n".join(out)
    print(text)
    summary_write(out)
    set_output("broken", str(broken_total))
    set_output("broken_dumps", ",".join(broken_dumps))


# ───────────────────────── dump-report (Dump-Unified) ─────────────────────────
def cmd_dump_report(args):
    dump, old_dir, new_dir, out_dir = args["dump"], args["old"], args["new"], args["out"]
    old, new = load_headers(old_dir), load_headers(new_dir)
    old_meta = load_json(os.path.join(old_dir, "meta.json"), {})
    old_fps = load_json(os.path.join(old_dir, "fingerprints.json"), {})
    partial = args.get("partial", False)

    # hook của các dự án dùng dump này
    projects = projects_for_dump(dump)
    hooks = []
    for p in projects:
        hooks += project_hooks(p)
    hooked = sorted({h["class"] for h in hooks})

    # fingerprint của các class bị hook:
    #   • còn trong dump mới  -> lấy từ dump mới + 'lost' = selector bị hook từng có ở bản cũ nhưng nay mất
    #   • mất khỏi dump mới   -> GIỮ fingerprint từ dump cũ để còn tìm được tên mới
    fps = {}
    for cls in hooked:
        if cls in new:
            fp = fingerprint(new[cls])
            if cls in old:
                lost = sorted({h["kind"] + h["selector"] for h in hooks if h["class"] == cls}
                              & (old[cls]["sel"] - new[cls]["sel"]))
                if lost:
                    fp["lost"] = lost
            fps[cls] = fp
        elif cls in old:
            fps[cls] = fingerprint(old[cls])
        elif cls in old_fps:
            fps[cls] = old_fps[cls]

    results = check_hooks(hooks, new, fps)
    added = sorted(set(new) - set(old))
    removed = [] if partial else sorted(set(old) - set(new))
    sel_added = sel_removed = 0
    for name in set(old) & set(new):
        sel_added += len(new[name]["sel"] - old[name]["sel"])
        sel_removed += len(old[name]["sel"] - new[name]["sel"])

    ver_old, ver_new = old_meta.get("app_version", ""), args.get("version", "")
    lines = [f"# Thay đổi dump · {dump}", ""]
    if ver_new:
        lines.append(f"- Phiên bản app: **{ver_old or '?'} → {ver_new}**")
    lines += [f"- Class: **+{len(added)}** mới" + ("" if partial else f" · **−{len(removed)}** mất") + (" _(dump một phần, bỏ qua phần mất)_" if partial else ""),
              f"- Selector (trong class còn tồn tại): **+{sel_added}** · **−{sel_removed}**",
              f"- Dự án có hook dùng dump này: {', '.join(f'`{p}`' for p in projects) or '_chưa có_'}", ""]
    if hooks:
        counts = summarize(results)
        lines += ["## 🪝 Hook của bạn", f"- ✅ {counts.get('ok', 0)} khớp · ⚠️ {counts.get('removed', 0) + counts.get('missing_class', 0)} có vấn đề"
                  f" · ℹ️ {counts.get('unverified', 0) + counts.get('external', 0)} chưa kiểm chứng được"]
        lines += render_results(results)[:MAX_LINES] or ["- Không có hook nào hỏng."]
        lines.append("")
    if removed:
        lines += ["## Class mất (tối đa %d)" % MAX_LINES] + [f"- `{c}`" for c in removed[:MAX_LINES]] + [""]
    if added:
        lines += ["## Class mới (tối đa %d)" % MAX_LINES] + [f"- `{c}`" for c in added[:MAX_LINES]] + [""]

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "CHANGES.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    save_json(os.path.join(out_dir, "fingerprints.json"), fps)
    save_json(os.path.join(out_dir, "meta.json"), {
        "app_version": ver_new or old_meta.get("app_version", ""), "bundle_id": args.get("bundle", "") or old_meta.get("bundle_id", ""),
        "dumped_at": datetime.now(timezone.utc).strftime("%Y-%m-%d"), "classes": len(new) if not partial else len(set(new) | set(old)),
        "previous_version": ver_old})
    print("\n".join(lines))
    summary_write(lines)


# ───────────────────────── fix (tự sửa tên class, sinh nội dung PR) ─────────────────────────
def set_output(key, value):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(f"{key}={value}\n")


def apply_rename(proj, old, new, dry):
    """Đổi toàn bộ token `old` -> `new` trong các file Logos của dự án. Trả về {file: số lần đổi}."""
    pattern, changed = re.compile(r"\b" + re.escape(old) + r"\b"), {}
    for path in project_sources(proj):
        text = read(path)
        count = len(pattern.findall(text))
        if count:
            changed[path] = count
            if not dry:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(pattern.sub(new, text))
    return changed


def cmd_fix(args):
    dump, dry = args["dump"], args.get("dry", False)
    body_path = args.get("body") or os.path.join(os.environ.get("RUNNER_TEMP", "."), "HOOKFIX.md")
    if dump == "auto":
        found = list_dumps()
        dump = found[0][0] if found else dump
    head_dir = os.path.join("headers", dump)
    if not os.path.isdir(head_dir):
        valid = ", ".join(n for n, _ in list_dumps()) or ", ".join(all_dump_dirs()) or "(chưa có thư mục nào trong headers/)"
        print(f"::error::Không có thư mục dump '{dump}'. Tên hợp lệ: {valid}")
        sys.exit(1)
    classes = load_headers(head_dir)
    fps = load_json(os.path.join(head_dir, "fingerprints.json"), {})
    meta = load_json(os.path.join(head_dir, "meta.json"), {})
    version = meta.get("app_version", "")
    applied, pending, touched = [], [], []

    if not classes:
        lines = [f"Không có dump `{dump}` trong `headers/` — chạy Dump-Unified trước."]
        projects = []
    else:
        projects = projects_for_dump(dump)
        for proj in projects:
            hooks = project_hooks(proj)
            ensure_fingerprints(dump, hooks, classes, fps)
            hooked_now = {h["class"] for h in hooks}
            used_targets, seen = set(), set()
            for r in check_hooks(hooks, classes, fps):
                h, st = r["hook"], r["status"]
                if st == "missing_class" and h["class"] not in seen:
                    seen.add(h["class"])
                    cands = r["candidates"]
                    top = cands[0][0] if cands else None
                    if top and is_confident(cands) and top not in hooked_now and top not in used_targets:
                        used_targets.add(top)
                        changes = apply_rename(proj, h["class"], top, dry)
                        if changes:
                            applied.append({"project": proj, "old": h["class"], "new": top, "score": cands[0][1], "files": changes})
                            touched += [f for f in changes if f not in touched]
                            continue
                    pending.append({"project": proj, "kind": "class", "hook": h, "cands": cands})
                elif st == "removed":
                    pending.append({"project": proj, "kind": "selector", "hook": h, "cands": r["suggest"]})

        title = f"🔧 Sửa hook cho {dump}" + (f" — app {version}" if version else "")
        lines = [f"## {title}", ""]
        if applied:
            lines += ["### ✅ Đã tự đổi tên class (độ tin cậy cao, cần bạn duyệt)"]
            for a in applied:
                n = sum(a["files"].values())
                files = ", ".join(f"`{f}`" for f in a["files"])
                lines.append(f"- `{a['old']}` → `{a['new']}` (điểm {a['score']}) · {n} vị trí trong {files}")
            lines.append("")
        if pending:
            lines += ["### ⚠️ Cần xem tay (không tự sửa)"]
            for p in pending:
                h, c = p["hook"], p["cands"]
                where = f"`{h['file']}:{h['line']}`"
                if p["kind"] == "class":
                    text = "; ".join(f"`{n}` ({s})" for n, s in c) if c else "chưa tìm được ứng viên"
                    lines.append(f"- class `{h['class']}` không còn trong dump → {text} · {where}")
                else:
                    text = "; ".join(f"`{h['kind']}{n}` ({s})" for n, s in c) if c else "chưa có gợi ý"
                    lines.append(f"- `{h['kind']}{h['selector']}` trên `{h['class']}` đã biến mất → {text} · {where}"
                                 " _(đổi tham số kéo theo sửa thân hàm và `%orig`)_")
            lines.append("")
        if not applied and not pending:
            lines.append("Không có hook nào cần sửa." if projects else "Chưa có dự án nào dùng dump này.")
        lines += ["---", "Công cụ chỉ so tên với header đã dump. Build qua nghĩa là còn biên dịch được, "
                  "**chưa chứng minh hook còn chạy đúng** — hãy thử trên máy trước khi merge."]

    text = "\n".join(lines)
    with open(body_path, "w", encoding="utf-8") as fh:
        fh.write(text + "\n")
    print(text)
    summary_write(lines)
    set_output("changed", "true" if applied and not dry else "false")
    set_output("projects", ",".join(sorted({a["project"] for a in applied})))
    set_output("renames", str(len(applied)))
    set_output("pending", str(len(pending)))
    set_output("version", re.sub(r"[^A-Za-z0-9._-]", "", version))
    set_output("files", ",".join(touched))


# ───────────────────────── CLI ─────────────────────────
def parse_cli(argv):
    cmd, opts, i = argv[0], {}, 1
    while i < len(argv):
        key = argv[i].lstrip("-")
        if key in ("partial", "dry"):
            opts[key] = True
            i += 1
        else:
            opts[key] = argv[i + 1] if i + 1 < len(argv) else ""
            i += 2
    return cmd, opts


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "--version":
        print(__version__)
        return 0
    cmd, opts = parse_cli(argv)
    try:
        if cmd == "check-all":
            cmd_check_all(opts.get("matrix", ""))
        elif cmd == "dump-report":
            for need in ("dump", "old", "new", "out"):
                if need not in opts:
                    sys.exit(f"Thiếu --{need}")
            cmd_dump_report(opts)
        elif cmd == "fix":
            if "dump" not in opts:
                sys.exit("Thiếu --dump")
            cmd_fix(opts)
        elif cmd == "list-dumps":
            print("\n".join(n for n, _ in list_dumps()))
        elif cmd == "latest-dump":
            found = list_dumps()
            print(found[0][0] if found else "")
        elif cmd == "projects-for":
            print("\n".join(projects_for_dump(opts.get("dump", ""))))
        else:
            sys.exit("Lệnh không hợp lệ. Dùng: check-all | dump-report | fix | list-dumps | latest-dump | projects-for")
    except SystemExit:
        raise
    except Exception as exc:          # công cụ cảnh báo, không bao giờ làm hỏng workflow
        print(f"::warning::hooks.py gặp lỗi và bỏ qua: {exc!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
