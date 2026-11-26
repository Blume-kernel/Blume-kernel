#!/usr/bin/env bash
set -e

: "${KERNEL_SRC:?}"
: "${WORK_DIR:=$GITHUB_WORKSPACE}"

PINS_FILE="${WORK_DIR}/sources/source-pins.json"
[ -f "$PINS_FILE" ] || { echo "[SKIP] No source-pins.json found"; exit 0; }

TARGET_SUB=$(jq -r '.moto_sublevel // ""' "$PINS_FILE")
BASE_LTS=$(jq -r '.gki_lts_base_commit // "0d108e1e8c7b51616fafc1e0c9bef100c9d97d86"' "$PINS_FILE")
TARGET_LTS=$(jq -r '.gki_lts_commit // ""' "$PINS_FILE")

cd "$KERNEL_SRC"

CUR_VER=$(awk -F' *= *' '/^VERSION / {v=$2} /^PATCHLEVEL / {p=$2} /^SUBLEVEL / {s=$2} END {if (v && p && s) print "v"v"."p"."s}' Makefile)
echo "[LTS] Base kernel version: ${CUR_VER:-unknown} | Target: ${TARGET_SUB:-none}"

if [ -z "$TARGET_LTS" ] || [ "$TARGET_LTS" = "null" ] || [ "$TARGET_LTS" = "$BASE_LTS" ] || [ "$CUR_VER" = "$TARGET_SUB" ]; then
  echo "[LTS] Kernel already at target LTS (${CUR_VER}); nothing to apply"
  exit 0
fi

PATCH_B64="/tmp/gki_lts_diff.b64"
PATCH_RAW="/tmp/gki_lts_diff.patch"
rm -f "$PATCH_B64" "$PATCH_RAW"

DIFF_URL="https://android.googlesource.com/kernel/common/+diff/${BASE_LTS}..${TARGET_LTS}?format=TEXT"
echo "[LTS] Fetching Google android13-5.15-lts diff (${BASE_LTS:0:12}..${TARGET_LTS:0:12}) ..."
curl -sfL --retry 3 --retry-delay 5 -o "$PATCH_B64" "$DIFF_URL"
base64 -d "$PATCH_B64" > "$PATCH_RAW"
rm -f "$PATCH_B64"

[ -s "$PATCH_RAW" ] || { echo "[ERROR] Empty LTS diff downloaded"; exit 1; }

python3 - "$PATCH_RAW" "$TARGET_SUB" <<'PY'
import os, re, subprocess, sys

patch_path, target_sub = sys.argv[1], sys.argv[2]
data = open(patch_path, "rb").read()

chunks = re.split(b"(?=^diff --git )", data, flags=re.M)
applied = skipped = failed = 0

for chunk in chunks:
    if not chunk.startswith(b"diff --git "):
        continue
    m_old = re.search(rb"^--- (?:a/(\S+)|(/dev/null))", chunk, flags=re.M)
    m_new = re.search(rb"^\+\+\+ (?:b/(\S+)|(/dev/null))", chunk, flags=re.M)
    old_f = m_old.group(1).decode("utf-8", "replace") if (m_old and m_old.group(1)) else None
    new_f = m_new.group(1).decode("utf-8", "replace") if (m_new and m_new.group(1)) else None

    # Skip Documentation/selftests/gitignore churn that does not affect the kernel Image
    target_f = new_f or old_f or ""
    if target_f.startswith(("Documentation/", "tools/testing/selftests/")) or target_f == ".gitignore":
        skipped += 1
        continue

    if old_f and not os.path.exists(old_f):
        skipped += 1
        continue

    dry = subprocess.run(
        ["patch", "-p1", "--dry-run", "--forward", "--batch", "--fuzz=3"],
        input=chunk,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if dry.returncode == 0:
        res = subprocess.run(
            ["patch", "-p1", "--forward", "--batch", "--fuzz=3"],
            input=chunk,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if res.returncode == 0:
            applied += 1
        else:
            failed += 1
    else:
        failed += 1
        print(f"[LTS-SKIP] conflict in {target_f}")

# Ensure Makefile SUBLEVEL matches target_sub (e.g. v5.15.226 -> 226) even if Makefile had minor context drift
m_sub = re.match(r"^v?\d+\.\d+\.(\d+)$", target_sub.strip())
if m_sub:
    sub = m_sub.group(1)
    mk = open("Makefile", "r", encoding="utf-8", errors="replace").read()
    mk_new = re.sub(r"^SUBLEVEL\s*=\s*\d+", f"SUBLEVEL = {sub}", mk, count=1, flags=re.M)
    if mk_new != mk:
        open("Makefile", "w", encoding="utf-8").write(mk_new)

print(f"[LTS] Applied {applied} file diffs, skipped {skipped}, conflicts skipped {failed}")
PY

rm -f "$PATCH_RAW"

# Clean any .orig / .rej files so setlocalversion never marks the tree -dirty
find . \( -name "*.orig" -o -name "*.rej" \) -delete
git add -A
if ! git diff --cached --quiet; then
  git -c user.name="Blume CI" -c user.email="ci@blume-kernel.local" -c commit.gpgsign=false \
    commit -q -m "Merge android13-5.15-lts ${TARGET_SUB} (${TARGET_LTS:0:12})"
fi

NEW_VER=$(awk -F' *= *' '/^VERSION / {v=$2} /^PATCHLEVEL / {p=$2} /^SUBLEVEL / {s=$2} END {if (v && p && s) print "v"v"."p"."s}' Makefile)
echo "[OK] Kernel updated to ${NEW_VER}"
