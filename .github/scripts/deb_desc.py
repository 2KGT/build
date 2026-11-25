#!/usr/bin/env python3
# version: 1.0.0 | 2026-11-13 | soạn mô tả + ghi chú phiên bản tự động (sửa lỗi / tính năng / chú ý / hỗ trợ tốt nhất) cho .deb, Release, Sileo, Telegram
# .github/scripts/deb_desc.py
"""
SOẠN MÔ TẢ & GHI CHÚ PHIÊN BẢN — một nguồn duy nhất cho mọi nơi hiển thị "có gì mới"

  ghi chú bạn nhập (hoặc tự lấy từ git) + thông tin tự thu thập
        │
        ├─► Description trong control của .deb      (Sileo · Cydia · Zebra · Installer đọc trực tiếp)
        ├─► Release notes của GitHub Release         (repo Sileo đọc làm "Có gì mới")
        ├─► v<phiên bản>.txt + commit message        (đường đẩy file thẳng vào repo Sileo)
        └─► tin nhắn Telegram

Tự thu thập (không cần nhập):
  • Phiên bản app hỗ trợ tốt nhất  ← headers/<App>Header/meta.json (bản app mới nhất đã dump)
  • iOS tối thiểu                   ← Depends: firmware (>= x) trong control
  • Hệ sinh thái / kiến trúc        ← Rootless · Rootful
  • Cảnh báo hook                   ← so hook trong source với header đã dump (hooks.py), nếu có dump

Cách ghi chú (ô "Release notes"): ngăn dòng bằng \\n hoặc "; ". Đầu dòng gõ nhãn để tự xếp mục:
  feat: / thêm:    ✨ Tính năng mới      fix: / sửa lỗi:   🐞 Sửa lỗi
  imp: / cải tiến: 🔧 Cải tiến          note: / chú ý:    ⚠️ Chú ý        info: / ghi chú: 📝 Ghi chú
Không có nhãn → tự đoán theo từ khoá. Để trống → lấy tiêu đề các commit mới của dự án.

Description chỉ được thêm vào control TẠM THỜI lúc build (engine_core khôi phục lại ngay), không ghi vào repo.
"""
import os
import re
import sys
from datetime import datetime, timezone, timedelta

__version__ = "1.0.0"

MARKER = "━━ Cập nhật tự động ━━"
MAX_DESC_CHARS = 1800

SECTIONS = [
    ("feat", "✨ Tính năng mới"),
    ("fix", "🐞 Sửa lỗi"),
    ("imp", "🔧 Cải tiến"),
    ("other", "📌 Thay đổi"),
    ("note", "⚠️ Chú ý"),
    ("info", "📝 Ghi chú"),
]
PREFIXES = {
    "feat": r"feat|feature|add|new|thêm|mới|tính năng",
    "fix": r"fix|fixed|bug|hotfix|vá|sửa lỗi|sửa|lỗi",
    "imp": r"imp|improve|improved|perf|opt|update|cập nhật|tối ưu|cải tiến|refactor",
    "note": r"note|warn|warning|chú ý|lưu ý|cảnh báo|important|!",
    "info": r"info|ghi chú|chú thích|doc|docs",
}
KEYWORDS = {
    "fix": r"\b(fix|bug|crash|lỗi|vá|sửa)\b",
    "feat": r"\b(add|new|thêm|tính năng|hỗ trợ)\b",
    "imp": r"\b(update|improve|opt|tối ưu|cải tiến|cập nhật)\b",
    "note": r"\b(chú ý|lưu ý|cảnh báo|warning)\b",
}
ECOSYSTEM_LABEL = {
    "rootless": "Rootless (iphoneos-arm64)",
    "rootful": "Rootful (iphoneos-arm)",
    "dylib": "Dylib (inject / sideload)",
}


# ───────────────────────── control (RFC822) ─────────────────────────
def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def get_field(control_text, key):
    m = re.search(rf"(?im)^{re.escape(key)}:[ \t]*(.*)$", control_text)
    return m.group(1).strip() if m else ""


def min_ios(control_text):
    m = re.search(r"firmware\s*\(\s*>=\s*([0-9][0-9.]*)\s*\)", get_field(control_text, "Depends"), re.I)
    return m.group(1) if m else ""


def split_description(control_text):
    """Trả về (start, end, [dòng]) của trường Description (gồm các dòng tiếp theo bắt đầu bằng khoảng trắng)."""
    lines = control_text.split("\n")
    for i, line in enumerate(lines):
        if re.match(r"(?i)^Description:", line):
            j = i + 1
            while j < len(lines) and lines[j][:1] in (" ", "\t"):
                j += 1
            return i, j, lines[i:j]
    return None, None, []


def strip_old_block(desc_lines):
    """Bỏ khối tự động của lần trước (nếu còn sót) để không bị nhân đôi."""
    for k, line in enumerate(desc_lines):
        if MARKER in line:
            keep = desc_lines[:k]
            while keep and keep[-1].strip() in (".", ""):
                keep.pop()
            return keep
    return desc_lines


# ───────────────────────── ghi chú ─────────────────────────
def split_notes(raw):
    if not raw:
        return []
    text = raw.replace("\\n", "\n").replace("\r", "")
    parts = []
    for chunk in text.split("\n"):
        parts += re.split(r";\s+", chunk)
    return [p.strip(" \t•-*") for p in parts if p.strip(" \t•-*")]


def classify(item):
    """('feat'|'fix'|'imp'|'note'|'info'|'other', nội dung đã bỏ nhãn)."""
    m = re.match(r"^\s*[\[(]?\s*(" + "|".join(PREFIXES.values()) + r")\s*[\])]?\s*[:\-–—]\s*(.+)$", item, re.I)
    if m:
        label, body = m.group(1).lower(), m.group(2).strip()
        for key, pattern in PREFIXES.items():
            if re.fullmatch(pattern, label, re.I):
                return key, body
    for key in ("note", "fix", "feat", "imp"):
        if re.search(KEYWORDS[key], item, re.I):
            return key, item
    return "other", item


def notes_from_git(proj, root):
    """Không nhập gì → lấy tiêu đề các commit mới của dự án (bỏ commit tự động của bot)."""
    try:
        import changelog
        items = changelog.recent_changes(proj, root, limit=12)
    except Exception:
        return []
    noise = re.compile(r"^(base|init|initial( commit)?|update|updates|wip|fix|test|tmp|merge\b.*)$", re.I)
    out = []
    for it in items:
        text = re.sub(r"^`[0-9a-f]+`\s*", "", it).strip()
        if len(text) >= 8 and not noise.match(text):      # bỏ tiêu đề commit quá ngắn / vô nghĩa
            out.append(text)
    return out


def group_notes(items):
    groups = {key: [] for key, _ in SECTIONS}
    for it in items:
        key, body = classify(it)
        if body and body not in groups[key]:
            groups[key].append(body)
    return [(key, label, groups[key]) for key, label in SECTIONS if groups[key]]


# ───────────────────────── thông tin tự thu thập ─────────────────────────
def supported_target(proj, root):
    """{'name','app_version','bundle_id'} của app đã dump mới nhất mà dự án hook; {} nếu không có."""
    try:
        import hooks
        import json
        for dump in hooks.dumps_for_project(os.path.join(root, proj)):
            meta = os.path.join(root, "headers", dump, "meta.json")
            if os.path.isfile(meta):
                data = json.loads(read(meta) or "{}")
                if data.get("app_version"):
                    name = re.sub(r"(HD)?Header$", "", dump) or dump
                    return {"name": name, "app_version": data["app_version"], "bundle_id": data.get("bundle_id", ""), "dump": dump}
    except Exception:
        pass
    return {}


def hook_health(proj, root, dump):
    """(khớp, tổng, hỏng) hoặc None nếu không kiểm tra được."""
    try:
        import hooks
        hook_list = hooks.project_hooks(os.path.join(root, proj))
        if not hook_list or not dump:
            return None
        head = os.path.join(root, "headers", dump)
        classes = hooks.load_headers(head)
        fps = hooks.ensure_fingerprints(dump, hook_list, classes, hooks.load_json(os.path.join(head, "fingerprints.json"), {}))
        counts = hooks.summarize(hooks.check_hooks(hook_list, classes, fps))
        broken = counts.get("removed", 0) + counts.get("missing_class", 0)
        return counts.get("ok", 0), len(hook_list), broken
    except Exception:
        return None


def vn_date():
    return datetime.now(timezone(timedelta(hours=7))).strftime("%d/%m/%Y")


def build_context(proj, version, ecosystems, raw_notes, root, upstream_names=()):
    control = read(os.path.join(root, proj, "control"))
    items = split_notes(raw_notes)
    auto = False
    if not items:
        items, auto = notes_from_git(proj, root), True
    if not items:
        items = [f"Cập nhật phiên bản v{version}"]
    target = supported_target(proj, root)
    health = hook_health(proj, root, target.get("dump")) if target else None
    ctx = {
        "project": proj, "name": get_field(control, "Name") or proj, "version": version,
        "sections": group_notes(items), "auto_notes": auto, "date": vn_date(),
        "ecosystems": [e for e in ecosystems if e in ECOSYSTEM_LABEL],
        "target": target, "health": health, "min_ios": min_ios(control),
        "upstream": [u for u in upstream_names if u],
    }
    return ctx


# ───────────────────────── xuất nội dung ─────────────────────────
def info_lines(ctx, eco=None):
    """Các dòng thông tin tự thu thập (dùng chung cho notes và Description)."""
    lines = []
    t = ctx["target"]
    if t:
        lines.append(f"📌 Hỗ trợ tốt nhất: {t['name']} {t['app_version']}")
    if ctx["min_ios"]:
        lines.append(f"📱 Yêu cầu: iOS {ctx['min_ios']}+")
    ecos = [eco] if eco else ctx["ecosystems"]
    if ecos:
        lines.append("🧩 Hệ sinh thái: " + " · ".join(ECOSYSTEM_LABEL.get(e, e) for e in ecos))
    if ctx["upstream"]:
        lines.append("🔗 Tích hợp: " + ", ".join(ctx["upstream"]))
    if ctx["health"]:
        ok, total, broken = ctx["health"]
        if broken:
            lines.append(f"⚠️ {broken}/{total} hook có thể chưa khớp bản app mới nhất")
        elif ok == total:
            lines.append(f"✅ Hook khớp bản app mới nhất ({ok}/{total})")
        else:
            lines.append(f"✅ Không phát hiện hook hỏng ({ok}/{total} khớp, còn lại chưa kiểm chứng được)")
    lines.append(f"🗓️ Phát hành: {ctx['date']}")
    return lines


def notes_text(ctx, eco=None):
    """Văn bản Release notes (Markdown nhẹ): dùng cho GitHub Release, v<ver>.txt, Telegram, commit."""
    out = []
    for _, label, items in ctx["sections"]:
        out.append(label)
        out += [f"- {x}" for x in items]
        out.append("")
    out += info_lines(ctx, eco)
    return "\n".join(out).strip() + "\n"


def headline(ctx):
    return f"{ctx['name']} v{ctx['version']}"


def description_block(ctx, eco=None):
    """Các dòng nối tiếp trường Description (đã có tiền tố khoảng trắng; dòng trống thành ' .')."""
    body = [f"{MARKER}", f"{headline(ctx)} — {ctx['date']}", ""]
    for _, label, items in ctx["sections"]:
        body.append(label)
        body += [f"• {x}" for x in items]
        body.append("")
    body += info_lines(ctx, eco)
    lines, size = [], 0
    for ln in body:
        size += len(ln) + 2
        if size > MAX_DESC_CHARS:
            lines.append("…")
            break
        lines.append(ln)
    return [(" " + ln) if ln.strip() else " ." for ln in lines]


def inject(control_path, ctx, eco=None):
    """Thêm khối cập nhật vào Description của control. Trả về nội dung gốc để khôi phục; None nếu không có Description."""
    original = read(control_path)
    start, end, desc = split_description(original)
    if start is None:
        return None
    base = strip_old_block(desc)
    new_desc = base + [" ."] + description_block(ctx, eco)
    lines = original.split("\n")
    lines[start:end] = new_desc
    text = "\n".join(lines)
    if not text.endswith("\n"):
        text += "\n"
    with open(control_path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return original


def restore(control_path, original):
    if original is not None:
        with open(control_path, "w", encoding="utf-8") as fh:
            fh.write(original)


# ───────────────────────── CLI (kiểm tra thử) ─────────────────────────
def _arg(args, key, default=""):
    return args[args.index(key) + 1] if key in args and args.index(key) + 1 < len(args) else default


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] not in ("notes", "desc", "--version"):
        sys.exit("Dùng: deb_desc.py notes|desc --project P --version V [--eco rootless,rootful] [--notes 'fix: ...; feat: ...']")
    if a[0] == "--version":
        print(__version__)
        sys.exit(0)
    c = build_context(_arg(a, "--project"), _arg(a, "--version", "1.0.0"), _arg(a, "--eco", "rootless").split(","),
                      _arg(a, "--notes"), os.getcwd())
    print(notes_text(c) if a[0] == "notes" else "\n".join(description_block(c)))
