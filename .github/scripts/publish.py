#!/usr/bin/env python3
# version: 1.0.0 | 2026-11-13 | phát hành .deb/.dylib: (1) GitHub Release trong repo Sileo, (2) đẩy file thẳng vào repo/debs + repo/dylibs; cùng ghi chú
# .github/scripts/publish.py
"""
PHÁT HÀNH — hai đường độc lập, bật tắt riêng, dùng chung một bộ ghi chú

  release  GitHub Release trong repo Sileo (tag <dự-án>-v<phiên-bản>, tệp .deb + .dylib làm asset).
           Repo Sileo tự chạy khi có Release và đọc nội dung Release làm "Có gì mới".
           Build lại cùng phiên bản → cập nhật Release cũ (tải đè asset), không tạo trùng.
  sync     Chép .deb vào repo/debs/<tweak>/ và .dylib vào repo/dylibs/<tweak>/ của repo Sileo,
           kèm v<phiên-bản>.txt (ghi chú) và commit mang đúng nội dung ghi chú.

Đầu vào lấy từ thư mục output/ do build_engine.py tạo: *.deb, *.dylib, RELEASE_NOTES.md, RELEASE_TITLE.txt.

Biến môi trường: PROJECT FINAL_VER REPO_TOKEN [TARGET_REPO=2KGT/repo] [TARGET_BRANCH=main] [OUTPUT_DIR=output]
                 [TARGET_URL] (ghi đè địa chỉ git, dùng khi thử) [DRY_RUN=true]
"""
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile

__version__ = "1.0.0"

PUBLISH_EXT = (".deb", ".dylib")


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


def read(path, default=""):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return default


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "tweak"


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


def tweak_folder(output_dir, files):
    """Thư mục tweak trong repo Sileo = đoạn cuối của bundle id (com.kyic.autoac → autoac)."""
    debs = [f for f in files if f.endswith(".deb")]
    if debs:
        pkg = deb_field(os.path.join(output_dir, debs[0]), "Package")
    else:
        ids = sorted((f.split("_")[0] for f in files), key=len)   # dylib chính có tên id ngắn nhất
        pkg = ids[0] if ids else ""
    return (pkg.split(".")[-1] if pkg else slug(env("PROJECT"))).lower()


# ───────────────────────── (1) GitHub Release ─────────────────────────
def gh(args, token, check=True):
    e = dict(os.environ, GH_TOKEN=token)
    log("GH", "gh " + " ".join(a for a in args if not a.startswith("--notes-file")))
    if env("DRY_RUN") == "true":
        return subprocess.CompletedProcess(args, 0, "", "")
    r = subprocess.run(["gh", *args], env=e, text=True, capture_output=True)
    if check and r.returncode != 0:
        fail(f"gh {args[0]} {args[1]} thất bại: {(r.stderr or r.stdout).strip()[:300]}")
    return r


def cmd_release():
    out_dir, repo, token = env("OUTPUT_DIR", "output"), env("TARGET_REPO", "2KGT/repo"), env("REPO_TOKEN")
    if not token:
        fail("Thiếu secret REPO_TOKEN để tạo Release trong repo Sileo")
    files = collect(out_dir)
    title, notes = release_text(out_dir)
    notes_file = os.path.join(tempfile.mkdtemp(prefix="relnotes_"), "notes.md")
    with open(notes_file, "w", encoding="utf-8") as fh:
        fh.write(notes + "\n")
    tag = f"{slug(env('PROJECT', 'tweak'))}-v{env('FINAL_VER', '0')}"
    paths = [os.path.join(out_dir, f) for f in files]

    exists = gh(["release", "view", tag, "-R", repo], token, check=False).returncode == 0
    if exists:
        gh(["release", "edit", tag, "-R", repo, "--title", title, "--notes-file", notes_file], token)
        gh(["release", "upload", tag, *paths, "-R", repo, "--clobber"], token)
        log("RELEASE", f"Đã cập nhật Release {tag}")
    else:
        gh(["release", "create", tag, *paths, "-R", repo, "--title", title, "--notes-file", notes_file], token)
        log("RELEASE", f"Đã tạo Release {tag}")
    url = f"https://github.com/{repo}/releases/tag/{tag}"
    set_output("release_url", url)
    set_output("release_tag", tag)
    print(f"🚀 {url} ({len(files)} tệp)")


# ───────────────────────── (2) đẩy thẳng vào repo/debs, repo/dylibs ─────────────────────────
def git(args, cwd, token="", check=True):
    cmd = ["git"]
    if token:
        basic = base64.b64encode(f"x-access-token:{token}".encode()).decode()
        cmd += ["-c", f"http.https://github.com/.extraheader=AUTHORIZATION: basic {basic}"]
    cmd += args
    log("GIT", "git " + " ".join(args))
    r = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
    if check and r.returncode != 0:
        fail(f"git {args[0]} thất bại: {(r.stderr or r.stdout).strip()[:300]}")
    return r


def cmd_sync():
    out_dir, repo, token = env("OUTPUT_DIR", "output"), env("TARGET_REPO", "2KGT/repo"), env("REPO_TOKEN")
    branch, version = env("TARGET_BRANCH", "main"), env("FINAL_VER", "0")
    if not token and not env("TARGET_URL"):
        fail("Thiếu secret REPO_TOKEN để đẩy vào repo Sileo")
    files = collect(out_dir)
    title, notes = release_text(out_dir)
    folder = tweak_folder(out_dir, files)
    url = env("TARGET_URL") or f"https://github.com/{repo}.git"

    work = os.path.join(tempfile.mkdtemp(prefix="sileo_"), "target")
    git(["clone", "--quiet", "--depth", "1", "--branch", branch, url, work], ".", token)
    git(["config", "user.name", "GitHub Action"], work)
    git(["config", "user.email", "action@github.com"], work)

    for kind, ext in (("debs", ".deb"), ("dylibs", ".dylib")):
        mine = [f for f in files if f.endswith(ext)]
        if not mine:
            continue
        dest = os.path.join(work, "repo", kind, folder)
        os.makedirs(dest, exist_ok=True)
        for f in mine:
            shutil.copy2(os.path.join(out_dir, f), os.path.join(dest, f))
        with open(os.path.join(dest, f"v{version}.txt"), "w", encoding="utf-8") as fh:   # "Có gì mới" dùng chung cho mọi kiến trúc
            fh.write(notes + "\n")
        log("SYNC", f"repo/{kind}/{folder}/: {len(mine)} tệp + v{version}.txt")

    git(["add", "-A", "repo/debs", "repo/dylibs"], work)
    if git(["diff", "--cached", "--quiet"], work, check=False).returncode == 0:
        print("ℹ️ Không có thay đổi nào mới để đẩy.")
        set_output("synced", "false")
        return
    msg = os.path.join(os.path.dirname(work), "commit.txt")
    with open(msg, "w", encoding="utf-8") as fh:
        fh.write(f"{title}\n\n{notes}\n")       # KHÔNG kèm [skip ci]: repo Sileo cần chạy để dựng lại Packages
    git(["commit", "--quiet", "-F", msg], work)
    for attempt in range(1, 5):
        if git(["pull", "--rebase", "--autostash", "origin", branch], work, token, check=False).returncode == 0 \
                and git(["push", "origin", f"HEAD:{branch}"], work, token, check=False).returncode == 0:
            set_output("synced", "true")
            print(f"✅ Đã đẩy {len(files)} tệp vào {repo} (repo/debs|dylibs/{folder}/)")
            return
        log("SYNC", f"Đẩy lần {attempt} thất bại, thử lại...")
    fail("Không đẩy được vào repo Sileo sau 4 lần thử")


COMMANDS = {"release": cmd_release, "sync": cmd_sync, "--version": lambda: print(__version__)}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit("Dùng: publish.py {release|sync}")
    COMMANDS[sys.argv[1]]()
