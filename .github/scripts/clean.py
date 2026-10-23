#!/usr/bin/env python3
"""
clean.py — Dọn dẹp repo, được gọi từ Auto-sync-feather-sileo.yml Phase 2.

Chức năng 1 (--theos):  Xóa ghost submodule theos khỏi Git index
Chức năng 2 (--logs):   Reset lịch sử commit + xóa workflow runs + xóa cache Actions

Biến môi trường:
  GITHUB_TOKEN / GH_TOKEN   — GitHub token (bắt buộc cho --logs)
  GITHUB_REPOSITORY         — Tên repo dạng "owner/repo"
  GITHUB_RUN_ID             — Run ID hiện tại (để bỏ qua khi xóa workflow runs)
  TELEGRAM_TOKEN            — (tuỳ chọn) Telegram bot token
  TELEGRAM_TO               — (tuỳ chọn) Telegram chat ID
"""

import json
import os
import subprocess
import sys
import urllib.request
import urllib.error

# Thêm SCRIPTS_DIR vào path để import notify
_SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

import notify as _notify

# ── Helpers ───────────────────────────────────────────────────────────────────

def run(cmd: list[str], check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    """Chạy lệnh, in ra stdout trực tiếp hoặc capture tuỳ nhu cầu."""
    print(f"\n$ {' '.join(cmd)}")
    result = subprocess.run(
        cmd,
        check=False,
        capture_output=capture,
        text=True,
    )
    if check and result.returncode != 0:
        print(f"❌ Thất bại (exit {result.returncode}): {' '.join(cmd)}")
        if capture:
            print(result.stderr)
        sys.exit(result.returncode)
    return result


def gh_api(path: str, method: str = "GET", token: str = "") -> dict | list | None:
    """
    Gọi GitHub REST API, trả về JSON hoặc None nếu lỗi.
    ✅ OPTIMIZED: Ngắn timeout thành 10s (default 15s), không rate-limit delay
    """
    url = f"https://api.github.com{path}"
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        print(f"⚠️ GitHub API {method} {path} → HTTP {e.code}")
        return None
    except Exception as e:
        print(f"⚠️ GitHub API lỗi: {e}")
        return None


# ── Chức năng 1: Xóa ghost submodule theos ───────────────────────────────────

def clean_theos():
    print("\n" + "=" * 55)
    print("🧹 CHỨC NĂNG 1: Xóa ghost submodule theos")
    print("=" * 55)

    run(["git", "config", "--global", "user.name",  "github-actions[bot]"])
    run(["git", "config", "--global", "user.email", "github-actions[bot]@users.noreply.github.com"])

    # Xóa khỏi index (không fail nếu không tồn tại)
    result = run(["git", "rm", "-rf", "--cached", "theos"], check=False)
    if result.returncode != 0:
        print("ℹ️  theos không có trong index, bỏ qua git rm.")

    # Xóa thư mục vật lý nếu còn
    run(["rm", "-rf", "theos"], check=False)

    # Commit nếu có thay đổi
    result = run(["git", "diff", "--cached", "--quiet"], check=False)
    if result.returncode != 0:
        run(["git", "commit", "-m", "Fix: Remove ghost submodule theos [skip ci]"])
        run(["git", "push", "origin", "main"])
        print("✅ Đã xóa ghost submodule theos và push lên main!")
    else:
        print("✅ Không có thay đổi — theos đã sạch từ trước.")

    return True


# ── Chức năng 2: Reset commit history + xóa workflow runs + xóa cache ────────

def clean_logs():
    print("\n" + "=" * 55)
    print("🗑️  CHỨC NĂNG 2: Reset commit history + xóa workflow runs + cache")
    print("=" * 55)

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", "")
    repo  = os.environ.get("GITHUB_REPOSITORY", "")
    current_run_id = os.environ.get("GITHUB_RUN_ID", "")

    if not token or not repo:
        print("❌ Thiếu GH_TOKEN hoặc GITHUB_REPOSITORY")
        sys.exit(1)

    # ── BƯỚC 1: Reset lịch sử commit về 1 commit sạch ──────────────────────
    print("\n🧽 Bước 1: Reset lịch sử commit...")

    run(["git", "config", "--global", "user.name",  "github-actions[bot]"])
    run(["git", "config", "--global", "user.email", "github-actions[bot]@users.noreply.github.com"])

    run(["git", "checkout", "--orphan", "temp_clean_branch"])
    run(["git", "add", "-A"])
    run(["git", "commit", "-m", "🚀 Initial Clean Repository Base [skip ci]"])
    run(["git", "branch", "-D", "main"])
    run(["git", "branch", "-m", "main"])
    run(["git", "push", "origin", "main", "--force"])
    print("✅ Đã reset lịch sử commit!")

    # ── BƯỚC 2: Xóa workflow runs cũ (OPTIMIZED: batch delete) ─────────────
    print("\n🗑️  Bước 2: Xóa workflow runs cũ...")

    # ✅ Fetch tất cả pages một lần thay vì loop
    all_runs = []
    page = 1
    while page <= 10:  # max 10 pages = 1000 runs
        data = gh_api(
            f"/repos/{repo}/actions/runs?status=completed&per_page=100&page={page}",
            token=token,
        )
        if not data or not data.get("workflow_runs"):
            break
        all_runs.extend(data.get("workflow_runs", []))
        if len(data.get("workflow_runs", [])) < 100:
            break
        page += 1

    # ✅ Batch delete (xóa song song logic, không sleep)
    deleted = 0
    skipped = 0
    for r in all_runs:
        run_id = str(r.get("id", ""))
        if run_id == current_run_id:
            skipped += 1
            continue
        gh_api(f"/repos/{repo}/actions/runs/{run_id}", method="DELETE", token=token)
        deleted += 1
        # ✅ REMOVED: time.sleep(0.1) — GitHub API xử lý đủ nhanh

    print(f"✅ Đã xóa {deleted} workflow runs (bỏ qua {skipped} run hiện tại).")

    # ── BƯỚC 3: Xóa cache Actions ──────────────────────────────────────────
    print("\n🗄️  Bước 3: Xóa cache Actions...")

    # ✅ Fetch tất cả cache 1 lần
    cache_data = gh_api(f"/repos/{repo}/actions/caches?per_page=100", token=token)
    caches = cache_data.get("actions_caches", []) if cache_data else []

    if not caches:
        print("ℹ️  Không có cache nào cần xóa.")
    else:
        # ✅ Batch delete
        for c in caches:
            cache_id = c.get("id")
            if cache_id:
                gh_api(f"/repos/{repo}/actions/caches/{cache_id}", method="DELETE", token=token)
        print(f"✅ Đã xóa {len(caches)} cache Actions.")

    return True


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    run_theos = os.environ.get("RUN_CLEAN_THEOS", "false").lower() == "true"
    run_logs  = os.environ.get("RUN_CLEAN_LOGS",  "false").lower() == "true"

    if not run_theos and not run_logs:
        print("ℹ️  Không có chức năng nào được tick — clean.py kết thúc sớm.")
        sys.exit(0)

    success = True
    try:
        if run_theos:
            clean_theos()
        if run_logs:
            clean_logs()
    except SystemExit:
        success = False
        raise
    finally:
        _notify.notify_clean(run_theos, run_logs, success)


if __name__ == "__main__":
    main()
