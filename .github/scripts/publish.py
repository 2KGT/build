#!/usr/bin/env python3
# version: 2.0.0 | 2026-11-15 | CHỈ CHUYỂN HÀNG theo hàng đợi deb → dylib → Release tới đúng địa chỉ; phân loại/đặt kệ do repo Sileo (intake.py) làm
# .github/scripts/publish.py
"""
PHÁT HÀNH = CHUYỂN HÀNG TỚI ĐÚNG ĐỊA CHỈ (không quyết định kho sắp xếp ra sao)

  Hàng đợi (mỗi bước chờ bước trước XỬ LÝ XONG rồi mới gửi):
     1  debs     → repo/inbox/<lô>/ của repo Sileo  (manifest.json + các .deb)
     2  dylibs   → repo/inbox/<lô>/                  (manifest.json + các .dylib)
     3  release  → GitHub Release của repo Sileo     (asset + ghi chú)
  Bật "Đẩy lên repo Sileo" → chạy bước 1, 2.  Bật "Phát hành releases" → chạy bước 3.  Bật cả hai → đủ 1 → 2 → 3.

  Sau mỗi lô gửi vào inbox, chờ workflow của repo Sileo (Auto-sync-feather-sileo → intake.py → main.py) chạy xong:
    • thành công       → gửi bước kế tiếp
    • thất bại         → DỪNG hàng đợi (không gửi dylib / Release khi deb chưa lên kệ)
    • bị thay bằng lần chạy mới hơn trong hàng đợi (cancelled) → coi như đã được xử lý, chờ kho rảnh rồi đi tiếp
    • không thấy lần chạy nào → cảnh báo (có thể thiếu 'repo/inbox/**' trong paths) rồi đi tiếp

  Việc phân loại, đặt tên, đặt kệ (repo/debs/<tweak>/…, repo/dylibs/<tweak>/…), ghi chú v<ver>.txt, ghi sổ
  đều do repo Sileo làm bằng intake.py. publish.py chỉ biết: đúng địa chỉ + manifest mô tả lô hàng.

Lệnh:  publish.py queue | deliver <debs|dylibs> | release | --version
Biến môi trường:
  PROJECT FINAL_VER REPO_TOKEN ECOSYSTEMS [TARGET_REPO=2KGT/repo] [TARGET_BRANCH=main] [OUTPUT_DIR=output]
  DO_PUBLISH=true|false  DO_RELEASE=true|false        (lệnh queue)
  PUBLISH_WAIT=true      chờ repo Sileo xử lý sau mỗi lô     STOP_ON_FAIL=true
  SILEO_WORKFLOW="Auto sync feather sileo"   SILEO_WAIT_MINUTES=15   SILEO_APPEAR_SECONDS=60   SILEO_POLL_SECONDS=10
  TARGET_URL (ghi đè địa chỉ git — dùng khi thử)   DRY_RUN=true
"""
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone

__version__ = "2.0.0"

PUBLISH_EXT = (".deb", ".dylib")
AUTH_HINTS = ("permission to", "denied", "403", "authentication failed", "could not read username", "invalid username or token", "401")


class StageFail(Exception):
    """Một bước của hàng đợi thất bại."""


def env(key, default=""):
    return os.environ.get(key, default)


def log(tag, msg):
    print(f"[{tag}] {msg}", flush=True)


def fail(msg):
    print(f"::error::{msg}")
    sys.exit(1)


def set_output(key, value):
    path = env("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(f"{key}={value}\n")


def summary(lines):
    path = env("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")


def read(path, default=""):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return default


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "tweak"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ───────────────────────── đầu vào ─────────────────────────
def collect(output_dir):
    if not os.path.isdir(output_dir):
        fail(f"Không thấy thư mục {output_dir}")
    files = sorted(f for f in os.listdir(output_dir) if f.endswith(PUBLISH_EXT))
    if not files:
        fail(f"Không có .deb hoặc .dylib nào trong {output_dir} để phát hành")
    return files


def release_text(output_dir):
    title = read(os.path.join(output_dir, "RELEASE_TITLE.txt")).strip() or f"{env('PROJECT', 'Tweak')} v{env('FINAL_VER', '0')}"
    notes = read(os.path.join(output_dir, "RELEASE_NOTES.md")).strip() or f"Cập nhật phiên bản v{env('FINAL_VER', '0')}"
    return title, notes


def deb_field(path, field):
    r = subprocess.run(["dpkg-deb", "-f", path, field], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def package_id(output_dir, files):
    """Gói của lô hàng: lấy từ control của .deb; nếu chỉ có dylib thì lấy từ tên dylib ngắn nhất."""
    debs = [f for f in files if f.endswith(".deb")]
    if debs:
        pkg = deb_field(os.path.join(output_dir, debs[0]), "Package")
        if pkg:
            return pkg
    ids = sorted((f.split("_")[0] for f in files), key=len)
    return ids[0] if ids else slug(env("PROJECT"))


# ───────────────────────── gh / git ─────────────────────────
def redact(text, token):
    if token:
        text = text.replace(token, "***").replace(base64.b64encode(f"x-access-token:{token}".encode()).decode(), "***")
    return text


def gh(args, token, check=True):
    log("GH", "gh " + " ".join(a for a in args if not a.startswith("--notes-file")))
    if env("DRY_RUN") == "true":
        return subprocess.CompletedProcess(args, 0, "[]", "")
    r = subprocess.run(["gh", *args], env=dict(os.environ, GH_TOKEN=token), text=True, capture_output=True)
    if check and r.returncode != 0:
        raise StageFail(f"gh {args[0]} {args[1]} thất bại: {redact((r.stderr or r.stdout).strip(), token)[:300]}")
    return r


def gh_json(args, token):
    r = gh(args, token, check=False)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout or "[]")
    except ValueError:
        return None


def git(args, cwd, token="", check=True):
    cmd = ["git"]
    if token:
        basic = base64.b64encode(f"x-access-token:{token}".encode()).decode()
        cmd += ["-c", f"http.https://github.com/.extraheader=AUTHORIZATION: basic {basic}"]
    cmd += args
    log("GIT", "git " + " ".join(args))
    r = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
    if check and r.returncode != 0:
        raise StageFail(f"git {args[0]} thất bại: {redact((r.stderr or r.stdout).strip(), token)[:400]}")
    return r


def clone_work(url, branch, token, sparse):
    """Clone NHẸ: chỉ đỉnh nhánh, không tải nội dung file, chỉ checkout các thư mục trong `sparse`."""
    work = os.path.join(tempfile.mkdtemp(prefix="sileo_"), "target")
    r = git(["clone", "--quiet", "--depth", "1", "--filter=blob:none", "--no-checkout", "--branch", branch, url, work], ".", token, check=False)
    if r.returncode == 0:
        ok = git(["sparse-checkout", "set", "--cone", *sparse], work, check=False).returncode == 0 \
            and git(["checkout", "--quiet", branch], work, check=False).returncode == 0
        if ok:
            return work
        log("DELIVER", "Clone nhẹ không dùng được, chuyển sang clone thường")
        shutil.rmtree(work, ignore_errors=True)
    git(["clone", "--quiet", "--depth", "1", "--branch", branch, url, work], ".", token)
    return work


# ───────────────────────── chờ repo Sileo xử lý xong ─────────────────────────
def repo_busy(repo, workflow, token):
    """Số lần chạy đang chạy / xếp hàng của workflow repo Sileo (None nếu không hỏi được)."""
    total = 0
    for status in ("in_progress", "queued"):
        runs = gh_json(["run", "list", "-R", repo, "-w", workflow, "--status", status, "--json", "databaseId", "--limit", "20"], token)
        if runs is None:
            return None
        total += len(runs)
    return total


def wait_processed(repo, token, sha, label):
    """Chờ workflow của repo Sileo xử lý xong lô vừa đẩy (commit `sha`). Trả về 'success'|'cancelled'|'norun'|'timeout'|'skipped'."""
    if env("PUBLISH_WAIT", "true") != "true" or env("DRY_RUN") == "true":
        return "skipped"
    wf = env("SILEO_WORKFLOW", "Auto sync feather sileo")
    poll = float(env("SILEO_POLL_SECONDS", "10"))
    appear = float(env("SILEO_APPEAR_SECONDS", "60"))
    deadline = time.time() + 60 * float(env("SILEO_WAIT_MINUTES", "15"))

    run, t0 = None, time.time()
    while time.time() - t0 < appear:                       # 1) chờ lần chạy mang đúng commit của ta xuất hiện
        runs = gh_json(["run", "list", "-R", repo, "-w", wf, "--commit", sha, "--json", "databaseId,status,conclusion,url", "--limit", "5"], token)
        if runs:
            run = runs[0]
            break
        time.sleep(poll)
    if not run:
        print(f"::warning::Repo Sileo không chạy workflow '{wf}' sau lô {label} (thiếu 'repo/inbox/**' trong paths của workflow?). Đi tiếp, không chờ.")
        return "norun"
    log("WAIT", f"Repo Sileo đang xử lý lô {label}: {run.get('url', '')}")

    while time.time() < deadline:                           # 2) chờ lần chạy đó hoàn tất
        cur = gh_json(["run", "view", str(run["databaseId"]), "-R", repo, "--json", "status,conclusion,url"], token) or run
        if cur.get("status") == "completed":
            run = cur
            break
        time.sleep(poll)
    else:
        print(f"::warning::Hết thời gian chờ repo Sileo xử lý lô {label}. Đi tiếp.")
        return "timeout"

    conclusion = run.get("conclusion") or "unknown"
    if conclusion not in ("success", "cancelled", "skipped", "neutral"):
        raise StageFail(f"Repo Sileo xử lý lô {label} THẤT BẠI ({conclusion}): {run.get('url', '')}")

    idle = 0                                                # 3) chờ kho rảnh (lần chạy của ta có thể đã bị thay bằng lần mới hơn)
    while time.time() < deadline and idle < 2:
        busy = repo_busy(repo, wf, token)
        if busy is None or busy == 0:
            idle += 1
        else:
            idle = 0
        if idle < 2:
            time.sleep(poll)
    return "success" if conclusion == "success" else "cancelled"


# ───────────────────────── bước 1-2: chuyển vào inbox ─────────────────────────
def build_manifest(stage, files_for_stage, out_dir, project, version, package, title, notes):
    ecos = [e for e in re.split(r"[,\s]+", env("ECOSYSTEMS")) if e]
    run_url = ""
    if env("GITHUB_RUN_ID") and env("GITHUB_REPOSITORY"):
        run_url = f"{env('GITHUB_SERVER_URL', 'https://github.com')}/{env('GITHUB_REPOSITORY')}/actions/runs/{env('GITHUB_RUN_ID')}"
    return {
        "schema": 1, "stage": stage, "project": project, "version": version, "package": package,
        "title": title, "notes": notes, "ecosystems": ecos,
        "files": [{"name": f, "kind": os.path.splitext(f)[1][1:], "size": os.path.getsize(os.path.join(out_dir, f)),
                   "sha256": sha256_file(os.path.join(out_dir, f))} for f in files_for_stage],
        "source": {"repository": env("GITHUB_REPOSITORY"), "run_id": env("GITHUB_RUN_ID"), "run_url": run_url,
                   "actor": env("GITHUB_ACTOR"), "sha": env("GITHUB_SHA")},
        "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def stage_deliver(stage, seq, stamp, out_dir, files):
    repo, token, branch = env("TARGET_REPO", "2KGT/repo"), env("REPO_TOKEN"), env("TARGET_BRANCH", "main")
    if not token and not env("TARGET_URL"):
        raise StageFail("Thiếu secret REPO_TOKEN để gửi vào repo Sileo")
    ext = ".deb" if stage == "debs" else ".dylib"
    mine = [f for f in files if f.endswith(ext)]
    title, notes = release_text(out_dir)
    project, version = env("PROJECT", "tweak"), env("FINAL_VER", "0")
    batch = f"{stamp}-{seq}-{stage}-{slug(project)}"          # tên lô: sắp theo tên = đúng thứ tự xử lý (debs trước dylibs)
    manifest = build_manifest(stage, mine, out_dir, project, version, package_id(out_dir, files), title, notes)
    url = env("TARGET_URL") or f"https://github.com/{repo}.git"

    work = clone_work(url, branch, token, ["repo/inbox"])
    git(["config", "user.name", "GitHub Action"], work)
    git(["config", "user.email", "action@github.com"], work)
    msg = os.path.join(os.path.dirname(work), "commit.txt")
    with open(msg, "w", encoding="utf-8") as fh:
        fh.write(f"{title} — {stage}\n\n{notes}\n")           # KHÔNG kèm [skip ci]: repo Sileo cần chạy để nhận hàng

    for attempt in range(1, 6):
        dest = os.path.join(work, "repo", "inbox", batch)
        os.makedirs(dest, exist_ok=True)
        for f in mine:
            shutil.copy2(os.path.join(out_dir, f), os.path.join(dest, f))
        with open(os.path.join(dest, "manifest.json"), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, ensure_ascii=False, indent=1)
        git(["add", "-A", "--", f"repo/inbox/{batch}"], work)
        git(["commit", "--quiet", "-F", msg], work)
        r = git(["push", "origin", f"HEAD:{branch}"], work, token, check=False)
        if r.returncode == 0:
            sha = git(["rev-parse", "HEAD"], work).stdout.strip()
            log("DELIVER", f"Đã gửi lô {batch}: {len(mine)} tệp → repo/inbox/ (commit {sha[:7]})")
            return {"batch": batch, "sha": sha, "files": len(mine)}
        err = redact((r.stderr or r.stdout).strip(), token)
        if any(h in err.lower() for h in AUTH_HINTS):
            raise StageFail("Không có quyền ghi vào repo Sileo. REPO_TOKEN cần quyền Contents: Read and write "
                            f"(PAT cổ điển: scope repo). Chi tiết: {err[:300]}")
        log("DELIVER", f"Lần {attempt}: push bị từ chối ({err.splitlines()[-1][:160] if err else '?'}). Lấy lại đỉnh nhánh rồi gửi lại...")
        time.sleep(min(float(env("SYNC_RETRY_DELAY", "2")) * attempt, 8))
        # Không rebase: bỏ commit của mình, lấy đỉnh nhánh mới, đặt lại lô (chỉ THÊM một thư mục mới nên không thể xung đột)
        git(["fetch", "--quiet", "--depth", "1", "origin", branch], work, token)
        git(["reset", "--quiet", "--hard", "FETCH_HEAD"], work)
    raise StageFail("Không gửi được vào repo Sileo sau 5 lần thử (nhánh liên tục bị đẩy thêm commit)")


# ───────────────────────── bước 3: Release ─────────────────────────
def stage_release(out_dir, files):
    repo, token = env("TARGET_REPO", "2KGT/repo"), env("REPO_TOKEN")
    if not token:
        raise StageFail("Thiếu secret REPO_TOKEN để tạo Release trong repo Sileo")
    title, notes = release_text(out_dir)
    notes_file = os.path.join(tempfile.mkdtemp(prefix="relnotes_"), "notes.md")
    with open(notes_file, "w", encoding="utf-8") as fh:
        fh.write(notes + "\n")
    tag = f"{slug(env('PROJECT', 'tweak'))}-v{env('FINAL_VER', '0')}"
    paths = [os.path.join(out_dir, f) for f in files]

    exists = gh(["release", "view", tag, "-R", repo], token, check=False).returncode == 0
    if exists:                                                # build lại cùng phiên bản → cập nhật Release cũ
        gh(["release", "edit", tag, "-R", repo, "--title", title, "--notes-file", notes_file], token)
        gh(["release", "upload", tag, *paths, "-R", repo, "--clobber"], token)
        log("RELEASE", f"Đã cập nhật Release {tag}")
    else:
        gh(["release", "create", tag, *paths, "-R", repo, "--title", title, "--notes-file", notes_file], token)
        log("RELEASE", f"Đã tạo Release {tag}")
    url = f"https://github.com/{repo}/releases/tag/{tag}"
    set_output("release_url", url)
    set_output("release_tag", tag)
    return {"url": url, "tag": tag, "files": len(files)}


# ───────────────────────── hàng đợi ─────────────────────────
def cmd_queue():
    out_dir, repo, token = env("OUTPUT_DIR", "output"), env("TARGET_REPO", "2KGT/repo"), env("REPO_TOKEN")
    do_pub, do_rel = env("DO_PUBLISH") == "true", env("DO_RELEASE") == "true"
    files = collect(out_dir)
    stages = []
    if do_pub:
        if any(f.endswith(".deb") for f in files):
            stages.append("debs")
        if any(f.endswith(".dylib") for f in files):
            stages.append("dylibs")
    if do_rel:
        stages.append("release")
    if not stages:
        print("ℹ️ Không có bước phát hành nào cần chạy (kiểm tra công tắc và loại tệp đã build).")
        return
    names = {"debs": "Sileo · .deb", "dylibs": "Sileo · .dylib", "release": "Release"}
    log("QUEUE", "Hàng đợi: " + " → ".join(names[s] for s in stages))
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    stop_on_fail = env("STOP_ON_FAIL", "true") == "true"
    rows, pushed, failed, seq = [], False, False, {"debs": 1, "dylibs": 2}

    for i, stage in enumerate(stages, 1):
        if failed and stop_on_fail:
            rows.append(f"| {i} | {names[stage]} | ⏭️ bỏ qua | bước trước thất bại |")
            continue
        log("QUEUE", f"[{i}/{len(stages)}] {names[stage]}")
        try:
            if stage == "release":
                info = stage_release(out_dir, files)
                rows.append(f"| {i} | {names[stage]} | ✅ | [{info['tag']}]({info['url']}) · {info['files']} tệp |")
            else:
                info = stage_deliver(stage, seq[stage], stamp, out_dir, files)
                pushed = True
                set_output("synced", "true")
                set_output("pushed_sha", info["sha"][:7])
                result = wait_processed(repo, token, info["sha"], info["batch"])
                rows.append(f"| {i} | {names[stage]} | ✅ | `{info['batch']}` · {info['files']} tệp · kho: {result} |")
        except StageFail as e:
            failed = True
            print(f"::error::[{names[stage]}] {e}")
            rows.append(f"| {i} | {names[stage]} | ❌ | {str(e)[:120]} |")
    if not pushed:
        set_output("synced", "false")
    summary(["## 📬 Hàng đợi phát hành", "", "| # | Bước | Kết quả | Chi tiết |", "|---|------|---------|----------|"] + rows)
    if failed:
        sys.exit(1)


def cmd_deliver():
    stage = sys.argv[2] if len(sys.argv) > 2 else ""
    if stage not in ("debs", "dylibs"):
        sys.exit("Dùng: publish.py deliver <debs|dylibs>")
    out_dir = env("OUTPUT_DIR", "output")
    files = collect(out_dir)
    try:
        info = stage_deliver(stage, 1 if stage == "debs" else 2, datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S"), out_dir, files)
        set_output("synced", "true")
        set_output("pushed_sha", info["sha"][:7])
        wait_processed(env("TARGET_REPO", "2KGT/repo"), env("REPO_TOKEN"), info["sha"], info["batch"])
    except StageFail as e:
        fail(str(e))


def cmd_release():
    out_dir = env("OUTPUT_DIR", "output")
    try:
        info = stage_release(out_dir, collect(out_dir))
        print(f"🚀 {info['url']} ({info['files']} tệp)")
    except StageFail as e:
        fail(str(e))


COMMANDS = {"queue": cmd_queue, "deliver": cmd_deliver, "release": cmd_release, "--version": lambda: print(__version__)}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit("Dùng: publish.py {queue|deliver <debs|dylibs>|release}")
    COMMANDS[sys.argv[1]]()