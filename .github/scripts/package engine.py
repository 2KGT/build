#!/usr/bin/env python3
# version: 2.0.0 | 2026-11-06 | ký giả/chứng chỉ, tự biên dịch repo:, token none, form gọn
# .github/scripts/package_engine.py
"""
ĐỘNG CƠ ĐÓNG GÓI – thay cho main.yml + cyan_ts.yml + ipa.yml (+ _build_tweaks.yml đã mất)

Mọi nguồn tweak đi qua MỘT danh sách token, rồi qua cùng một "bể" (pool/):

  nguồn (token)                          ->  pool/  ->  [ký giả]  ->  đầu ra (dist/)
  ─────────────────────────────────────      ──────      ────────      ──────────────
  tên catalog   (youpip, ytplus@5.2.1)       .deb       ldid -S       .ipa   (cyan inject)
  preset:youmod                              .dylib                   .cyan  (cgen)
  repo:YouMod   (artifact của tweaks.yml)    .appex                   .zip   (TrollFools)
  https://...deb|dylib|zip                   .framework               .zip   (deb/dylib đã ký)
  file:debs/abc.deb (file trong repo)        .bundle

Lệnh con:
  plan     (Ubuntu) mở rộng + kiểm tra đầu vào, quyết định cần công cụ nào
  resolve  (macOS) tải / build từng mục vào pool/  (repo:X chưa có artifact -> tự biên dịch)
  sign     ký tweak trong pool/ theo SIGN_MODE
  make     tạo đầu ra trong dist/ rồi ký IPA theo SIGN_MODE

SIGN_MODE:
  none   không ký
  fake   ldid -S (TrollStore / TrollFools / jailbreak). IPA: giải nén, ký mọi Mach-O, nén lại
  cert   chứng chỉ thật: tweak bằng codesign, IPA bằng fastlane resign (cần p12 + mobileprovision)

Token đặc biệt: 'none' (một mình) = không tiêm tweak, chỉ ký lại IPA có sẵn.

Biến môi trường: TOKENS EXCLUDE IPA_URL APP_NAME BUNDLE_ID CYAN_FLAGS OUT_IPA OUT_CYAN OUT_TF OUT_DEB
                 SIGN_MODE ENTITLEMENTS HAS_CERT SIGN_IDENTITY SIGN_KEYCHAIN SIGN_PROFILE
                 APP_VERSION IPA_PATH THEOS GITHUB_REPOSITORY GITHUB_RUN_NUMBER BUILD_ENGINE
"""
import difflib
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

__version__ = "2.0.0"   # workflow Package.yml kiểm tra dòng này (REQUIRES_ENGINE)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CATALOG_PATH = os.environ.get("CATALOG_PATH") or os.path.join(SCRIPT_DIR, "..", "tweaks.catalog.json")
ROOT = os.environ.get("GITHUB_WORKSPACE") or os.getcwd()
POOL = os.path.join(ROOT, "pool")
DIST = os.path.join(ROOT, "dist")
SRC = os.path.join(ROOT, ".pkgwork")

DIR_KINDS = {".appex": "appex", ".framework": "framework", ".bundle": "bundle"}
FILE_KINDS = {".deb": "deb", ".dylib": "dylib"}
MACHO_MAGIC = {b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe",
               b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
URL_RE = re.compile(r"^https?://", re.I)


# ───────────────────────── tiện ích chung ─────────────────────────
def env(key, default=""):
    return os.environ.get(key, default)


def flag(key):
    return env(key).strip().lower() == "true"


def log(tag, msg):
    print(f"[{tag}] {msg}", flush=True)


def append_file(path, text):
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(text)


def summary(lines):
    append_file(env("GITHUB_STEP_SUMMARY"), "\n".join(lines) + "\n")


def set_output(key, value):
    append_file(env("GITHUB_OUTPUT"), f"{key}={value}\n")


def die(msg, hint=""):
    print(f"\n❌ {msg}")
    if hint:
        print(f"💡 {hint}")
    summary(["## ❌ Đóng gói dừng lại", msg] + ([f"_{hint}_"] if hint else []))
    sys.exit(1)


def run(cmd, cwd=None, check=True, capture=False, extra_env=None):
    log("RUN", " ".join(cmd) if isinstance(cmd, list) else cmd)
    r = subprocess.run(cmd, cwd=cwd, text=True, capture_output=capture,
                       env=dict(os.environ, **extra_env) if extra_env else None)
    if check and r.returncode != 0:
        if capture:
            print((r.stdout or "") + (r.stderr or ""))
        die(f"Lệnh thất bại ({r.returncode}): {cmd if isinstance(cmd, str) else ' '.join(cmd)}")
    return r


def sh(cmd, cwd=None):
    run(["bash", "-c", cmd], cwd=cwd)


def safe_name(text, fallback="App"):
    text = re.sub(r"[^\w.\-]+", "_", (text or "").strip(), flags=re.UNICODE).strip("_")
    return text or fallback


def under_root(rel):
    path = os.path.normpath(os.path.join(ROOT, rel))
    if path != ROOT and not path.startswith(ROOT + os.sep):
        die(f"Đường dẫn nằm ngoài repo: {rel}")
    return path


# ───────────────────────── token → danh sách mục ─────────────────────────
def load_catalog():
    with open(CATALOG_PATH, encoding="utf-8") as fh:
        cat = json.load(fh)
    cat["_alias"] = {}
    for name, spec in cat.get("tweaks", {}).items():
        cat["_alias"][name.lower()] = name
        for al in spec.get("aliases", []):
            cat["_alias"][al.lower()] = name
    return cat


def split_tokens(text):
    return [t for t in re.split(r"[\s,]+", (text or "").strip()) if t]


def classify(token):
    low = token.lower()
    if low.startswith("preset:"):
        return ("preset", token[7:].lower(), "")
    if low.startswith("repo:"):
        return ("repo", token[5:], "")
    if low.startswith("file:"):
        return ("file", token[5:], "")
    if URL_RE.match(token):
        return ("url", token, "")
    name, _, ver = token.partition("@")
    return ("catalog", name.lower(), ver)


def key_of(token, cat):
    kind, value, _ = classify(token)
    if kind == "catalog":
        return "c:" + cat["_alias"].get(value, value)
    return f"{kind[0]}:{value.lower()}"


def expand_presets(tokens, presets, depth=0):
    if depth > 5:
        die("Preset lồng nhau quá sâu (vòng lặp?)")
    out = []
    for tok in tokens:
        kind, value, _ = classify(tok)
        if kind == "preset":
            if value not in presets:
                die(f"Không có preset '{value}'.", "Preset có sẵn: " + ", ".join(sorted(presets)))
            out += expand_presets(presets[value], presets, depth + 1)
        else:
            out.append(tok)
    return out


def only_none(tokens_text):
    return [t.lower() for t in split_tokens(tokens_text)] == ["none"]


def build_plan(tokens_text, exclude_text, cat):
    if only_none(tokens_text):
        return []
    tokens = expand_presets(split_tokens(tokens_text), cat.get("presets", {}))
    excluded = {key_of(t, cat) for t in split_tokens(exclude_text)}
    tokens = [t for t in tokens if key_of(t, cat) not in excluded]

    entries, index, unknown = [], {}, []

    def add_catalog(name, ver, stack=()):
        canon = cat["_alias"].get(name)
        if canon is None:
            unknown.append(name)
            return
        if canon in stack:
            die(f"Vòng phụ thuộc trong catalog: {' → '.join(stack + (canon,))}")
        spec = cat["tweaks"][canon]
        for dep in spec.get("requires", []):
            if "c:" + dep in excluded:
                log("WARN", f"'{dep}' cần cho '{canon}' nên vẫn được thêm dù nằm trong danh sách bỏ.")
            add_catalog(dep, "", stack + (canon,))
        key = "c:" + canon
        if key in index:
            if ver and not index[key]["ver"]:
                index[key]["ver"] = ver
            return
        index[key] = {"key": key, "type": "catalog", "name": canon, "ver": ver, "spec": spec}
        entries.append(index[key])

    for tok in tokens:
        kind, value, ver = classify(tok)
        if kind == "catalog":
            add_catalog(value, ver)
        else:
            key = key_of(tok, cat)
            if key not in index:
                index[key] = {"key": key, "type": kind, "name": value, "ver": "", "spec": None}
                entries.append(index[key])

    if unknown:
        hints = []
        for name in unknown:
            close = difflib.get_close_matches(name, list(cat["_alias"]), n=3, cutoff=0.5)
            hints.append(f"'{name}'" + (f" (ý bạn là: {', '.join(close)}?)" if close else ""))
        die("Tên tweak không có trong catalog: " + "; ".join(hints),
            "Xem danh sách trong .github/tweaks.catalog.json, hoặc dùng link / repo:Dự_án / file:đường_dẫn.")
    return entries


def describe(entry):
    t, name, ver = entry["type"], entry["name"], entry["ver"]
    if t == "catalog":
        return f"{entry['spec'].get('kind', 'source')}", name + (f"@{ver}" if ver else "")
    return t + (" · tự biên dịch" if entry.get("local_build") else ""), name


# ───────────────────────── plan ─────────────────────────
def find_artifact_run(proj):
    """Id lần chạy tweaks.yml mới nhất còn artifact của dự án. '' = chưa có, None = không hỏi được (thiếu gh/lỗi mạng)."""
    if not shutil.which("gh") or not env("GITHUB_REPOSITORY"):
        return None
    art = f"tweak-release-{proj}"
    r = subprocess.run(["gh", "api", f"repos/{env('GITHUB_REPOSITORY')}/actions/artifacts?name={art}&per_page=10",
                        "--jq", ".artifacts[] | select(.expired==false) | .workflow_run.id"],
                       text=True, capture_output=True)
    if r.returncode != 0:
        return None
    ids = r.stdout.split()
    return ids[0] if ids else ""


def cmd_plan():
    cat = load_catalog()
    mode = env("SIGN_MODE", "none") or "none"
    none_only = only_none(env("TOKENS"))
    entries = build_plan(env("TOKENS"), env("EXCLUDE"), cat)
    outs = {k: flag(k) for k in ("OUT_IPA", "OUT_CYAN", "OUT_TF", "OUT_DEB")}

    if not entries and not none_only:
        die("Danh sách tweak đang trống.", "Nhập tên tweak, preset:youmod, repo:Dự_án, link, file:đường_dẫn — hoặc 'none' để chỉ ký lại IPA.")
    if not any(outs.values()):
        die("Chưa chọn đầu ra nào.", "Chọn một mục ở bước 3 (Đầu ra).")
    if none_only:
        if not outs["OUT_IPA"]:
            die("'none' (không tiêm tweak) chỉ dùng được với đầu ra IPA.", "Chọn đầu ra IPA, hoặc nhập tweak.")
        if mode == "none":
            die("Không tweak và không ký thì không có gì để làm.", "Chọn kiểu ký ở bước 4, hoặc nhập tweak.")
    if outs["OUT_IPA"] and not env("IPA_URL").strip():
        die("Xuất IPA cần link IPA.", "Điền 'Link IPA' hoặc chọn đầu ra khác.")
    if mode == "cert" and not flag("HAS_CERT"):
        die("Chưa có secret chứng chỉ để ký.",
            "Thêm 3 secret trong Settings → Secrets and variables → Actions: SIGN_P12_BASE64, SIGN_P12_PASSWORD, SIGN_PROFILE_BASE64.")
    ent = env("ENTITLEMENTS").strip()
    if ent:
        if mode != "fake":
            log("WARN", "Entitlements chỉ áp dụng cho kiểu 'Ký giả (ldid)' → bỏ qua.")
        elif not os.path.isfile(under_root(ent)):
            die(f"Không thấy file entitlements: {ent}")

    for e in entries:
        if e["type"] == "file":
            if not os.path.exists(under_root(e["name"])):
                die(f"Không thấy file trong repo: {e['name']}")
        elif e["type"] == "repo":
            if not os.path.isfile(os.path.join(ROOT, e["name"], "control")):
                die(f"'repo:{e['name']}' không phải dự án (thiếu {e['name']}/control).")
            run_id = find_artifact_run(e["name"])
            if run_id == "":            # chưa từng build -> tự biên dịch
                if not any(os.path.isfile(os.path.join(ROOT, e["name"], m)) for m in ("Makefile", "makefile", "GNUmakefile")):
                    die(f"'repo:{e['name']}' chưa có artifact và dự án không có Makefile để tự biên dịch.",
                        "Chạy tweaks.yml build dự án này trước.")
                e["local_build"] = True
            elif run_id is None:
                log("WARN", f"Không kiểm tra được artifact của '{e['name']}' → sẽ thử tải, thiếu thì tự biên dịch.")

    local_builds = [e["name"] for e in entries if e.get("local_build")]
    needs_theos = bool(local_builds) or any(e["type"] == "catalog" and e["spec"].get("kind", "source") == "source" for e in entries)
    needs_cyan = outs["OUT_IPA"] and not none_only or outs["OUT_CYAN"]
    needs_ldid = needs_theos or mode == "fake"
    needs_dpkg = outs["OUT_TF"] or outs["OUT_DEB"] or mode != "none" or needs_theos   # Theos đóng gói bằng dpkg-deb
    needs_fastlane = mode == "cert" and outs["OUT_IPA"]
    for key, val in (("count", len(entries)), ("needs_theos", needs_theos), ("needs_cyan", needs_cyan),
                     ("needs_ldid", needs_ldid), ("needs_dpkg", needs_dpkg), ("needs_fastlane", needs_fastlane)):
        set_output(key, str(val).lower() if isinstance(val, bool) else val)

    lines = ["## 🗺️ Kế hoạch đóng gói", ""]
    if entries:
        lines += ["| # | Loại | Mục |", "|---|------|-----|"]
        lines += ["| %d | %s | `%s` |" % ((i,) + describe(e)) for i, e in enumerate(entries, 1)]
    else:
        lines.append("- Không tiêm tweak: chỉ ký lại IPA có sẵn")
    wanted = [label for key, label in (("OUT_IPA", "IPA"), ("OUT_CYAN", ".cyan"), ("OUT_TF", "TrollFools"), ("OUT_DEB", "DEB/dylib")) if outs[key]]
    sign_label = {"none": "không ký", "fake": "ký giả (ldid -S)", "cert": "ký chứng chỉ (codesign + fastlane)"}.get(mode, mode)
    lines += ["", f"- Phiên bản: workflow **{env('PKG_WORKFLOW_VERSION', '?')}** · engine **{__version__}**",
              f"- Đầu ra: **{', '.join(wanted)}**", f"- Ký: **{sign_label}**",
              f"- Cần Theos build: **{'có' if needs_theos else 'không'}**"]
    if local_builds:
        lines.append(f"- Tự biên dịch (chưa có artifact): **{', '.join(local_builds)}**")
    summary(lines)
    for e in entries:
        log("PLAN", "{} {}".format(*describe(e)))
    log("PLAN", f"✅ {len(entries)} mục | ký={mode} theos={needs_theos} cyan={needs_cyan}")


# ───────────────────────── resolve (nhập vào pool/) ─────────────────────────
def pool_dest(name):
    os.makedirs(POOL, exist_ok=True)
    dest, stem, n = os.path.join(POOL, name), name, 1
    while os.path.exists(dest):
        n += 1
        base, ext = os.path.splitext(stem)
        dest = os.path.join(POOL, f"{base}_{n}{ext}")
    return dest


def ingest(path, origin, strict=False):
    """Đưa file/thư mục vào pool/. Trả về danh sách item {name, kind, path, origin}."""
    items = []
    base = os.path.basename(path.rstrip(os.sep))
    ext = os.path.splitext(base)[1].lower()

    if os.path.isdir(path):
        if ext in DIR_KINDS:
            dest = pool_dest(base)
            shutil.copytree(path, dest, symlinks=True)
            return [{"name": os.path.basename(dest), "kind": DIR_KINDS[ext], "path": dest, "origin": origin}]
        for name in sorted(os.listdir(path)):
            items += ingest(os.path.join(path, name), origin)
        return items

    if ext in FILE_KINDS:
        dest = pool_dest(base)
        shutil.copy2(path, dest)
        return [{"name": os.path.basename(dest), "kind": FILE_KINDS[ext], "path": dest, "origin": origin}]
    if ext == ".zip":
        tmp = tempfile.mkdtemp(prefix="pkgzip_")
        run(["unzip", "-q", "-o", path, "-d", tmp])
        found = ingest(tmp, origin)
        if not found and strict:
            die(f"Không thấy .deb/.dylib/.appex... trong {base}")
        return found
    if strict:
        die(f"Định dạng không hỗ trợ: {base}", "Hỗ trợ: .deb .dylib .zip (chứa deb/dylib/appex/framework/bundle)")
    log("SKIP", f"Bỏ qua {base}")
    return []


def download(url, dest_dir):
    name = os.path.basename(url.split("?")[0].rstrip("/")) or "download.bin"
    dest = os.path.join(dest_dir, name)
    run(["curl", "-fL", "--retry", "3", "--silent", "--show-error", "-o", dest, url])
    return dest


def ensure_headers(cat):
    theos = env("THEOS")
    if not theos:
        die("Thiếu biến THEOS để build từ source.")
    for name, url in cat.get("defaults", {}).get("headers", {}).items():
        central = os.path.join(theos, "include", name)
        if not os.path.isdir(central):
            os.makedirs(os.path.dirname(central), exist_ok=True)
            run(["git", "clone", "--quiet", "--depth=1", url, central])
        else:
            subprocess.run(["git", "-C", central, "pull", "--quiet", "--force"], capture_output=True, timeout=120)


def resolve_source(entry, cat):
    name, spec = entry["name"], entry["spec"]
    work = os.path.join(SRC, name)
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(SRC, exist_ok=True)
    if spec.get("commit"):                       # ghim commit: cần clone đầy đủ
        run(["git", "clone", "--quiet", spec["repo"], work])
        run(["git", "-C", work, "checkout", "--quiet", spec["commit"]])
    else:
        cmd = ["git", "clone", "--quiet", "--depth=1"] + (["--branch", spec["ref"]] if spec.get("ref") else [])
        run(cmd + [spec["repo"], work])
    for pre in spec.get("pre", []):
        sh(pre, cwd=work)
    args = (spec.get("build_args") or cat["defaults"]["build_args"]).split()
    run(["make", "clean", "package"] + args, cwd=work)
    debs = sorted(glob.glob(os.path.join(work, "packages", "*.deb")))
    if not debs:
        die(f"'{name}': build xong nhưng không thấy packages/*.deb")
    items = []
    for deb in debs:
        items += ingest(deb, f"build:{name}")
    return items


def resolve_release(entry):
    spec, ver = entry["spec"], entry["ver"] or entry["spec"].get("default_version", "")
    tmp = tempfile.mkdtemp(prefix="pkgrel_")
    tags = [t.format(ver=ver) for t in spec.get("tags", ["v{ver}", "{ver}"])] if ver else [None]
    for tag in tags:
        cmd = ["gh", "release", "download"] + ([tag] if tag else []) + \
              ["-R", spec["repo"], "-p", spec.get("pattern", "*.deb"), "-D", tmp, "--clobber"]
        r = subprocess.run(cmd, text=True, capture_output=True)
        if r.returncode == 0 and os.listdir(tmp):
            log("REL", f"{spec['repo']} tag {tag or '(mới nhất)'}")
            return ingest(tmp, f"release:{spec['repo']}")
        log("REL", f"tag {tag}: không có ({(r.stderr or '').strip()[:120]})")
    die(f"'{entry['name']}': không tải được release từ {spec['repo']} (phiên bản {ver or 'mới nhất'}).",
        "Kiểm tra phiên bản (tweak@5.2.1) hoặc dùng link .deb trực tiếp.")


def resolve_sparse(entry):
    spec = entry["spec"]
    work = os.path.join(SRC, entry["name"])
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(SRC, exist_ok=True)
    run(["git", "clone", "--quiet", "-n", "--depth=1", "--filter=tree:0", spec["repo"], work])
    run(["git", "-C", work, "sparse-checkout", "set", "--no-cone", spec["path"]])
    run(["git", "-C", work, "checkout", "--quiet"])
    target = os.path.join(work, spec["path"])
    if not os.path.exists(target):
        die(f"'{entry['name']}': không thấy {spec['path']} trong {spec['repo']}")
    return ingest(target, f"sparse:{entry['name']}")


def build_project_local(proj):
    """Chưa có artifact: biên dịch ngay dự án trong repo bằng chính build_engine.py (cùng handler, upstream, gating)."""
    out = os.path.join(ROOT, "output")
    shutil.rmtree(out, ignore_errors=True)
    engine = env("BUILD_ENGINE") or os.path.join(SCRIPT_DIR, "build_engine.py")
    run([sys.executable, engine], cwd=ROOT,
        extra_env={"INPUT_PROJECT": proj, "INPUT_VER_TYPE": "", "INPUT_CLEAN_BUILD": "true"})
    debs = sorted(glob.glob(os.path.join(out, "*.deb")))
    if not debs:
        die(f"Tự biên dịch '{proj}' xong nhưng không có .deb trong output/.")
    items = []
    for deb in debs:
        items += ingest(deb, f"build:{proj}")
    return items


def resolve_repo_project(proj):
    run_id = find_artifact_run(proj)
    if not run_id:
        log("REPO", f"'{proj}': chưa có artifact (hoặc không hỏi được) → tự biên dịch")
        return build_project_local(proj)
    art = f"tweak-release-{proj}"
    tmp = tempfile.mkdtemp(prefix="pkgrepo_")
    run(["gh", "run", "download", run_id, "-R", env("GITHUB_REPOSITORY"), "-n", art, "-D", tmp])
    items = ingest(tmp, f"repo:{proj}")
    if not items:
        die(f"Artifact '{art}' không chứa .deb/.dylib nào.")
    return items


def cmd_resolve():
    cat = load_catalog()
    entries = build_plan(env("TOKENS"), env("EXCLUDE"), cat)
    os.makedirs(POOL, exist_ok=True)
    if any(e["type"] == "catalog" and e["spec"].get("kind", "source") == "source" for e in entries):
        ensure_headers(cat)
    manifest = []
    for i, e in enumerate(entries, 1):
        log("POOL", f"({i}/{len(entries)}) {' '.join(describe(e))}")
        if e["type"] == "file":
            items = ingest(under_root(e["name"]), f"file:{e['name']}", strict=True)
        elif e["type"] == "url":
            tmp = tempfile.mkdtemp(prefix="pkgurl_")
            items = ingest(download(e["name"], tmp), "url", strict=True)
        elif e["type"] == "repo":
            items = resolve_repo_project(e["name"])
        else:
            kind = e["spec"].get("kind", "source")
            if kind == "source":
                items = resolve_source(e, cat)
            elif kind == "release":
                items = resolve_release(e)
            elif kind == "sparse":
                items = resolve_sparse(e)
            elif kind == "url":
                tmp = tempfile.mkdtemp(prefix="pkgurl_")
                items = ingest(download(e["spec"]["url"].format(ver=e["ver"] or e["spec"].get("default_version", "")), tmp), "url", strict=True)
            else:
                die(f"Catalog '{e['name']}': kind không hợp lệ '{kind}'")
        for it in items:
            it["entry"] = e["name"]
            log("POOL", f"   + {it['kind']:<9} {it['name']}")
        manifest += items
    with open(os.path.join(POOL, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    lines = ["## 🧺 Bể tweak (pool)", "", "| Loại | Tệp | Nguồn |", "|------|-----|-------|"]
    lines += [f"| {m['kind']} | `{m['name']}` | {m['origin']} |" for m in manifest]
    summary(lines)
    log("POOL", f"✅ {len(manifest)} tệp")


def load_manifest():
    path = os.path.join(POOL, "manifest.json")
    if not os.path.isfile(path):
        die("Chưa có pool/manifest.json (bước resolve chưa chạy).")
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


# ───────────────────────── sign (theo SIGN_MODE) ─────────────────────────
def is_macho(path):
    try:
        with open(path, "rb") as fh:
            return fh.read(4) in MACHO_MAGIC
    except OSError:
        return False


def sign_cmd(path, ent):
    if env("SIGN_MODE") == "cert":
        cmd = ["codesign", "-f", "-s", env("SIGN_IDENTITY")]
        if env("SIGN_KEYCHAIN"):
            cmd += ["--keychain", env("SIGN_KEYCHAIN")]
        return cmd + [path]
    return ["ldid", f"-S{ent}" if ent else "-S", path]


def sign_file(path, ent):
    return subprocess.run(sign_cmd(path, ent), text=True, capture_output=True).returncode == 0


def sign_tree(root, ent):
    done = failed = 0
    for cur, dirs, files in os.walk(root):
        for f in files:
            p = os.path.join(cur, f)
            if os.path.islink(p) or not is_macho(p):
                continue
            if sign_file(p, ent):
                done += 1
            else:
                failed += 1
                log("SIGN", f"⚠️ ký lỗi: {os.path.relpath(p, root)}")
    return done, failed


def entitlements_path():
    ent = env("ENTITLEMENTS").strip()
    return under_root(ent) if ent and env("SIGN_MODE") == "fake" else ""


def check_sign_tools():
    mode = env("SIGN_MODE")
    tool = "codesign" if mode == "cert" else "ldid"
    if not shutil.which(tool):
        die(f"Không tìm thấy {tool} trên runner.")
    if mode == "cert" and not env("SIGN_IDENTITY"):
        die("Thiếu SIGN_IDENTITY (bước nhập chứng chỉ chưa chạy?).")


def cmd_sign():
    check_sign_tools()
    ent = entitlements_path()
    manifest, total, bad = load_manifest(), 0, 0
    for it in manifest:
        if it["kind"] == "dylib":
            ok = sign_file(it["path"], ent)
            total, bad = total + (1 if ok else 0), bad + (0 if ok else 1)
        elif it["kind"] in DIR_KINDS.values():
            d, f = sign_tree(it["path"], ent)
            total, bad = total + d, bad + f
        elif it["kind"] == "deb":
            tmp = tempfile.mkdtemp(prefix="pkgsign_")
            run(["dpkg-deb", "-R", it["path"], tmp])
            d, f = sign_tree(tmp, ent)
            if d:
                new = it["path"] + ".new"
                run(["dpkg-deb", "--root-owner-group", "-b", tmp, new])
                os.replace(new, it["path"])
            total, bad = total + d, bad + f
            shutil.rmtree(tmp, ignore_errors=True)
        log("SIGN", f"{it['kind']:<9} {it['name']}")
    label = "chứng chỉ (codesign)" if env("SIGN_MODE") == "cert" else "giả (ldid -S)"
    summary([f"## ✍️ Ký tweak — {label}", f"- Đã ký: **{total}** tệp Mach-O", f"- Lỗi: **{bad}**"])
    if bad:
        log("SIGN", f"⚠️ {bad} tệp ký lỗi (build vẫn tiếp tục)")
    log("SIGN", f"✅ ký {total} tệp")


def sign_ipa_fake(ipa):
    """ldid -S mọi Mach-O trong .app rồi nén lại IPA (Payload ở gốc)."""
    check_sign_tools()
    tmp = tempfile.mkdtemp(prefix="pkgipa_")
    run(["unzip", "-q", "-o", ipa, "-d", tmp])
    payload = os.path.join(tmp, "Payload")
    if not os.path.isdir(payload):
        die("IPA không có thư mục Payload/.")
    done, bad = sign_tree(payload, entitlements_path())
    os.remove(ipa)
    run(["zip", "-qry", ipa, "Payload"], cwd=tmp)
    shutil.rmtree(tmp, ignore_errors=True)
    log("SIGN", f"IPA ký giả: {done} tệp, lỗi {bad}")
    return done, bad


def sign_ipa_cert(ipa):
    """Ký lại toàn bộ IPA bằng chứng chỉ + mobileprovision (fastlane resign, gọi codesign bên dưới)."""
    for key in ("SIGN_IDENTITY", "SIGN_PROFILE"):
        if not env(key):
            die(f"Thiếu {key} (bước nhập chứng chỉ chưa chạy?).")
    if not shutil.which("fastlane"):
        die("Không tìm thấy fastlane trên runner.")
    cmd = ["fastlane", "run", "resign", f"ipa:{ipa}", f"signing_identity:{env('SIGN_IDENTITY')}",
           f"provisioning_profile:{env('SIGN_PROFILE')}"]
    if env("SIGN_KEYCHAIN"):
        cmd.append(f"keychain_path:{env('SIGN_KEYCHAIN')}")
    if env("APP_NAME").strip():
        cmd.append(f"display_name:{env('APP_NAME')}")
    if env("BUNDLE_ID").strip():
        cmd.append(f"bundle_id:{env('BUNDLE_ID')}")
    run(cmd)


# ───────────────────────── make (đầu ra) ─────────────────────────
def cyan_flag_args(raw):
    """Cờ cyan/cgen dạng argv. 'f' (nhận danh sách tệp) phải nằm cuối: -uwe -> ['-uwef']."""
    toks = (raw or "").split()
    if not toks:
        return ["-f"]
    toks = [t if t.startswith("-") else "-" + t for t in toks]
    if not any("f" in t[1:] for t in toks):
        toks[-1] += "f"
    return toks


def cmd_make():
    manifest = load_manifest()
    os.makedirs(DIST, exist_ok=True)
    base = safe_name(env("APP_NAME"), "Tweaks")
    ver = safe_name(env("APP_VERSION"), "") if env("APP_VERSION") else ""
    run_no = env("GITHUB_RUN_NUMBER", "0")
    tag = (f"_{ver}" if ver else "") + f"_run{run_no}"
    files = [m["path"] for m in manifest]
    made = []

    name_args = (["-n", env("APP_NAME")] if env("APP_NAME").strip() else []) + \
                (["-b", env("BUNDLE_ID")] if env("BUNDLE_ID").strip() else [])

    if flag("OUT_IPA"):
        out = os.path.join(DIST, f"{base}{tag}.ipa")
        if files:
            run(["cyan", "-i", env("IPA_PATH") or "app.ipa", "-o", out] + cyan_flag_args(env("CYAN_FLAGS")) + files + name_args)
        else:                                   # token 'none': giữ nguyên IPA, chỉ ký lại
            shutil.copy2(env("IPA_PATH") or "app.ipa", out)
        mode = env("SIGN_MODE", "none")
        if mode == "fake":
            sign_ipa_fake(out)
        elif mode == "cert":
            sign_ipa_cert(out)
        made.append(out)

    if flag("OUT_CYAN"):
        out = os.path.join(DIST, f"{base}_run{run_no}.cyan")
        run(["cgen"] + cyan_flag_args(env("CYAN_FLAGS")) + files + name_args + ["-o", out])
        made.append(out)

    if flag("OUT_TF"):
        stage = tempfile.mkdtemp(prefix="pkgtf_")
        for m in manifest:
            if m["kind"] == "dylib":
                shutil.copy2(m["path"], stage)
            elif m["kind"] == "bundle":
                shutil.copytree(m["path"], os.path.join(stage, m["name"]), symlinks=True, dirs_exist_ok=True)
            elif m["kind"] == "deb":
                tmp = tempfile.mkdtemp(prefix="pkgdeb_")
                run(["dpkg-deb", "-x", m["path"], tmp])
                for cur, dirs, fs in os.walk(tmp):
                    for d in list(dirs):
                        if d.endswith(".bundle"):
                            shutil.copytree(os.path.join(cur, d), os.path.join(stage, d), symlinks=True, dirs_exist_ok=True)
                            dirs.remove(d)
                    for f in fs:
                        if f.endswith(".dylib") and not os.path.islink(os.path.join(cur, f)):
                            shutil.copy2(os.path.join(cur, f), stage)
                shutil.rmtree(tmp, ignore_errors=True)
        if not os.listdir(stage):
            log("MAKE", "⚠️ TrollFools: không có dylib/bundle nào để đóng gói")
        else:
            out = shutil.make_archive(os.path.join(DIST, f"TrollFools_{base}_run{run_no}"), "zip", stage)
            made.append(out)

    if flag("OUT_DEB"):
        stage = tempfile.mkdtemp(prefix="pkgdebzip_")
        for m in manifest:
            if m["kind"] in ("deb", "dylib"):
                shutil.copy2(m["path"], stage)
        if not os.listdir(stage):
            log("MAKE", "⚠️ DEB/dylib: pool không có .deb hay .dylib")
        else:
            out = shutil.make_archive(os.path.join(DIST, f"{base}_debs_run{run_no}"), "zip", stage)
            made.append(out)

    if not made:
        die("Không tạo được đầu ra nào.")
    lines = ["## 📦 Đầu ra", "", "| Tệp | Dung lượng |", "|-----|-----------|"]
    for p in made:
        lines.append(f"| `{os.path.basename(p)}` | {os.path.getsize(p) / 1048576:.1f} MB |")
    summary(lines)
    for p in made:
        log("MAKE", f"✅ {os.path.basename(p)}")


COMMANDS = {"plan": cmd_plan, "resolve": cmd_resolve, "sign": cmd_sign, "make": cmd_make,
            "version": lambda: print(__version__)}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit("Dùng: package_engine.py {" + "|".join(COMMANDS) + "}")
    COMMANDS[sys.argv[1]]()
