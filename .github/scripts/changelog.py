# .github/scripts/changelog.py
"""Ghi nhật ký build vào <dự án>/CHANGELOG.md (bản mới nhất ở trên cùng)."""

import hashlib
import os
import re
import subprocess
import time
from datetime import datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:  # Python < 3.9
    ZoneInfo = None

HEADER = ("# Changelog — {proj}\n\n"
          "Ghi tự động bởi hệ thống build. Bản mới nhất ở trên cùng.\n\n")
SKIP_SUBJECT = re.compile(r"^(🔖|📝)|\[skip ci\]", re.I)


def _now():
    if ZoneInfo:
        try:
            return datetime.now(ZoneInfo("Asia/Ho_Chi_Minh"))
        except Exception:
            pass
    return datetime.now(timezone(timedelta(hours=7)))


def _git(args, cwd):
    try:
        out = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True, timeout=30)
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def recent_changes(proj, repo_root, limit=15):
    """Các commit liên quan dự án kể từ lần ghi CHANGELOG trước (bỏ commit tự động của bot)."""
    base = _git(["log", "-1", "--format=%H", "--", f"{proj}/CHANGELOG.md"], repo_root)
    rng = [f"{base}..HEAD"] if base else ["-n", "30"]
    raw = _git(["log", "--no-merges", "--pretty=%h\x1f%s"] + rng + ["--", proj], repo_root)
    items = []
    for line in raw.splitlines():
        sha, _, subject = line.partition("\x1f")
        if subject and not SKIP_SUBJECT.search(subject):
            items.append(f"`{sha}` {subject}")
    return items[:limit]


def log_stats(log_path):
    warnings = errors = 0
    if log_path and os.path.exists(log_path):
        with open(log_path, encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                low = line.lower()
                warnings += "warning:" in low
                errors += "error:" in low
    return warnings, errors


def deb_info(output_dir):
    result = []
    if not os.path.isdir(output_dir):
        return result
    for name in sorted(os.listdir(output_dir)):
        if name.endswith(".deb"):
            path = os.path.join(output_dir, name)
            sha = hashlib.sha256(open(path, "rb").read()).hexdigest()[:12]
            result.append((name, os.path.getsize(path), sha))
    return result


def _fmt_size(n):
    return f"{n / 1024:.1f} KB" if n < 1024 * 1024 else f"{n / 1024 / 1024:.2f} MB"


def build_entry(i):
    """i: dict thông tin build -> chuỗi markdown của một mục."""
    now = _now().strftime("%Y-%m-%d %H:%M")
    lines = [f"## [{i['version']}] — {now} (GMT+7)", ""]

    if i.get("bumped"):
        lines.append(f"- **Cấp độ:** {i['level_label']} · {i['old_version']} → {i['version']}")
    else:
        lines.append(f"- **Cấp độ:** giữ nguyên version {i['version']} (build lại)")

    run = i.get("run_url")
    build = f"[#{i['run_id']}]({run})" if run and i.get("run_id") else "build cục bộ"
    meta = [build]
    if i.get("runner"):
        meta.append(i["runner"])
    if i.get("sha"):
        meta.append(f"commit `{i['sha'][:7]}`")
    if i.get("actor"):
        meta.append(f"bởi @{i['actor']}")
    lines.append("- **Build:** " + " · ".join(meta))

    for name, size, sha in i.get("debs", []):
        lines.append(f"- **Gói:** `{name}` ({_fmt_size(size)}, sha256 `{sha}…`)")

    lines.append(f"- **Nhật ký:** {i['warnings']} cảnh báo, {i['errors']} lỗi, {i['duration']:.0f} giây"
                 + (f" — build lại {i['attempts'] - 1} lần do upstream lỗi biên dịch" if i.get("attempts", 1) > 1 else ""))

    for u in i.get("upstreams", []):
        title = u.get("title") or u.get("name")
        if u.get("ok"):
            prev, sha = u.get("prev_sha"), u.get("sha")
            if not prev:
                note = "lần đồng bộ đầu tiên"
            elif prev != sha:
                note = f"CÓ CẬP NHẬT MỚI (trước đó `{prev}`)"
            else:
                note = "không đổi so với lần build trước"
            lines.append(f"- **{title}** ({u['repo']} @ `{sha}`): v{u.get('version') or '?'} · "
                         f"{u.get('license') or '?'} — {note}")
        else:
            lines.append(f"- **{title}**: không kèm trong bản này ({u.get('reason') or 'không rõ lý do'})")

    changes = i.get("changes") or []
    if changes:
        lines += ["", "### Thay đổi"] + [f"- {c}" for c in changes]
    return "\n".join(lines) + "\n"


def update_changelog(proj_dir, proj, version, entry):
    path = os.path.join(proj_dir, "CHANGELOG.md")
    text = open(path, encoding="utf-8").read() if os.path.exists(path) else HEADER.format(proj=proj)

    m = re.search(r"(?m)^## \[", text)
    head, rest = (text[:m.start()], text[m.start():]) if m else (text.rstrip("\n") + "\n\n", "")
    sections = [s for s in re.split(r"(?m)^(?=## \[)", rest) if s.strip()]

    marker = f"## [{version}]"
    replaced = False
    for idx, section in enumerate(sections):
        if section.startswith(marker):
            sections[idx] = entry + "\n"
            replaced = True
            break
    if not replaced:
        sections.insert(0, entry + "\n")

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(head + "".join(sections).rstrip("\n") + "\n")
    return path


def _prev_upstream_sha(text, title):
    """Mã commit upstream trong mục CHANGELOG gần nhất có nhắc tới `title`."""
    m = re.search(r"\*\*" + re.escape(title) + r"\*\* \(.*? @ `([0-9a-f]{4,40})`\)", text)
    return m.group(1) if m else None


def record_build(repo_root, proj_dir, proj, version, old_version, bumped, level_label,
                 output_dir, started_ts, upstream, attempts, log_path):
    """Gom thông tin lần build rồi ghi vào <dự án>/CHANGELOG.md. Trả về đường dẫn file."""
    changelog_path = os.path.join(proj_dir, "CHANGELOG.md")
    existing = open(changelog_path, encoding="utf-8").read() if os.path.exists(changelog_path) else ""

    ups = []
    for r in upstream or []:
        item = dict(r)
        item["prev_sha"] = _prev_upstream_sha(existing, r.get("title") or r.get("name", ""))
        ups.append(item)

    warnings, errors = log_stats(log_path)
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    info = {
        "version": version,
        "old_version": old_version,
        "bumped": bumped,
        "level_label": level_label or "",
        "run_id": os.environ.get("GITHUB_RUN_NUMBER", run_id),
        "run_url": f"{server}/{repo}/actions/runs/{run_id}" if repo and run_id else "",
        "runner": os.environ.get("RUNNER_OS", ""),
        "sha": os.environ.get("GITHUB_SHA", ""),
        "actor": os.environ.get("GITHUB_ACTOR", ""),
        "debs": deb_info(output_dir),
        "warnings": warnings,
        "errors": errors,
        "duration": max(0.0, time.time() - started_ts),
        "attempts": attempts,
        "upstreams": ups,
        "changes": recent_changes(proj, repo_root),
    }
    return update_changelog(proj_dir, proj, version, build_entry(info))
