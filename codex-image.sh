#!/usr/bin/env bash
# Generate one raster image with OpenAI Codex CLI's built-in image_gen tool, headless.
#
#   codex-image.sh "<prompt>" <out.png> [--ref in.png]... [--size N] [--resume <thread>] [--dry-run]
#   codex-image.sh --help
#
# The prompt goes to Codex as-is; Codex's output is copied untouched unless --size is given.
# Prints thread=<id>: pass it back with --resume for a follow-up ("make it more pink") so
# Codex still has the previous image in context.
#
# Billing: the built-in tool draws on a ChatGPT plan quota (auth_mode=chatgpt). The CLI's
# fallback path (OPENAI_API_KEY) is metered, so this refuses to run if that path is possible.
# How the file is found: `codex exec --json` prints thread.started{thread_id}, and the tool
# saves to $CODEX_HOME/generated_images/<thread_id>/<name>.png (the image item itself is NOT
# in the JSON stream). Read-only sandbox: the save is Codex's own, not a sandboxed shell.
# This relies on observed Codex CLI behaviour (tested on codex-cli 0.160.0) that can change.
# Exit 0 only when a real PNG landed at <out.png>.
#
# Exit codes: 0 ok, 2 usage, 3 billing gate refused, 4 codex missing, 5 codex failed,
#             6 no image produced, 7 output not a PNG.
set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $0 "<prompt>" <out.png> [--ref in.png]... [--size N] [--resume <thread>] [--dry-run]

  --ref in.png     attach a reference image (repeatable)
  --size N         resize the result to fit NxN (needs ImageMagick)
  --resume ID      continue an earlier Codex thread (ID printed as thread=<id>)
  --dry-run        run the billing checks and print the codex command; make no request
EOF
  exit "${1:-2}"
}
case "${1:-}" in -h|--help) usage 0 ;; esac
[ $# -ge 2 ] || usage
prompt=$1 out=$2; shift 2
refs=() size="" resume="" dry=0
while [ $# -gt 0 ]; do
  case $1 in
    --ref) [ -f "${2:-}" ] || { echo "ref not found: ${2:-}" >&2; exit 2; }; refs+=("$2"); shift 2 ;;
    --size) [[ "${2:-}" =~ ^[0-9]+$ ]] || usage; size=$2; shift 2 ;;
    --resume) [[ "${2:-}" =~ ^[0-9a-f-]{36}$ ]] || usage; resume=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -h|--help) usage 0 ;;
    *) usage ;;
  esac
done

CODEX_HOME=${CODEX_HOME:-$HOME/.codex}
# Gate on values, not on the prompt asking nicely.
[ -z "${OPENAI_API_KEY:-}" ] || { echo "OPENAI_API_KEY is set: image gen could bill the API. Refusing." >&2; exit 3; }
[ -f "$CODEX_HOME/auth.json" ] || { echo "no $CODEX_HOME/auth.json: run 'codex login' with your ChatGPT account" >&2; exit 3; }
mode=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("auth_mode","") if not d.get("OPENAI_API_KEY") else "apikey")' "$CODEX_HOME/auth.json")
[ "$mode" = chatgpt ] || { echo "codex auth_mode=$mode, not a ChatGPT plan: could bill the API. Refusing." >&2; exit 3; }
command -v codex >/dev/null || { echo "codex not on PATH" >&2; exit 4; }
[ -z "$size" ] || command -v magick >/dev/null || { echo "--size needs ImageMagick (magick)" >&2; exit 4; }

iargs=() refnote=""
for i in "${!refs[@]}"; do iargs+=(-i "${refs[$i]}"); refnote+="Image $((i+1)) is a reference. "; done

instr="${refnote}${prompt}

(Use your built-in image_gen tool, never the CLI fallback script.)"

if [ "$dry" = 1 ]; then
  echo "dry run: billing checks passed (auth_mode=chatgpt, no OPENAI_API_KEY); no request made"
  if [ -n "$resume" ]; then
    echo "would run: codex exec resume --skip-git-repo-check --json ${iargs[*]} $resume <prompt>"
  else
    echo "would run: codex exec --skip-git-repo-check --json -s read-only -C <tmpdir> ${iargs[*]} -- <prompt>"
  fi
  printf 'prompt:\n%s\n' "$instr"
  exit 0
fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
start=$(date +%s); touch "$work/stamp"
if [ -n "$resume" ]; then
  cmd=(codex exec resume --skip-git-repo-check --json "${iargs[@]}" "$resume" "$instr")
else
  cmd=(codex exec --skip-git-repo-check --json -s read-only -C "$work" "${iargs[@]}" -- "$instr")
fi
if ! (cd "$work" && timeout 600 "${cmd[@]}") >"$work/events.jsonl" 2>"$work/err.log"; then
  echo "codex exec failed (rc != 0); last stderr:" >&2; tail -5 "$work/err.log" >&2; exit 5
fi
tid=$(python3 -c 'import json,sys
for l in open(sys.argv[1]):
    try: d=json.loads(l)
    except ValueError: continue
    if d.get("type")=="thread.started": print(d["thread_id"]); break' "$work/events.jsonl")
[ -n "$tid" ] || { echo "no thread_id in codex output" >&2; exit 5; }
png=$(find "$CODEX_HOME/generated_images/$tid" -name '*.png' -newer "$work/stamp" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || true)
[ -n "$png" ] || { echo "codex finished but generated no image (thread $tid)" >&2; exit 6; }

mkdir -p "$(dirname "$out")"
if [ -n "$size" ]; then magick "$png" -resize "${size}x${size}" -strip "$out"; else cp "$png" "$out"; fi
[ "$(head -c 8 "$out" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ] || { echo "output is not a PNG" >&2; exit 7; }
dims=$(command -v identify >/dev/null && identify -format '%wx%h' "$out" || echo "?")
echo "thread=$tid"
echo "$out $dims $(( $(date +%s)-start ))s src=$png"
