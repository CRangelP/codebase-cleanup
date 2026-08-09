#!/usr/bin/env bash
# Cleanup metrics: turns the quality checklist into measured evidence.
# Runs once at the start (baseline) and once at the end; the delta is what the report shows.
# Requires bash (macOS 3.2 is fine), POSIX awk, and find with -print0, which is a
# GNU/BSD extension and not POSIX. Usage: metrics.sh [dir]
# Output: one "[metrics] name=value" line per metric, in a fixed order, with no timestamps
# and no absolute paths, so the real use is: metrics.sh . >before ... metrics.sh . >after
# && diff before after.
# Exit 0 = measured · 2 = bad path (the argument is not a reachable directory) ·
# 3 = nothing measurable (no recognized source file under the path).
#
# HONESTY, which is the whole point of this script: every number below is a TEXTUAL
# HEURISTIC, not a parser. Specifically:
#   maxfn / fn_over_50 count the lines between a function-looking line and the brace that
#   closes it (in Python, the dedent that ends it). This is wrong on minified code (the
#   whole file is one line), on closures passed as arguments (an inline callback is counted
#   as its own function while the enclosing call keeps counting), and it can only
#   approximate indentation-sensitive languages, where an unusual dedent silently extends
#   or truncates a function. Braces inside strings, regexes and heredocs count as braces.
#   maxnest is brace depth (indentation steps in Python) and inherits the same lies.
#   loose_types and todo are literal pattern counts: they match inside comments and
#   strings too, on purpose, because deciding otherwise needs a parser.
# Only maxfn / fn_over_50 / maxnest carry the (approx) tag, because only those three
# guess at structure. loc is the one plain count: non-blank, non-comment. loose_types
# and todo are exact and still not what you want -- they are the exact count of a text
# pattern, which is not the count of the problem: a TODO quoted in a comment about
# TODOs is one todo here. This project prefers a declared limit to a pretty false
# number.
#
# These metrics are evidence, not a target: none of them is to be optimized for its own
# sake (Goodhart), because chopping a function in half to lower an average is exactly the
# damage this skill exists to prevent.
set -uo pipefail

target="${1:-.}"
if [[ ! -d $target ]]; then
  echo "[metrics] bad path: '$target' is not a directory" >&2
  exit 2
fi
cd "$target" || {
  echo "[metrics] bad path: '$target' is not a directory we can enter" >&2
  exit 2
}

# One awk program for every file. mode=brace|indent decides how blocks are delimited,
# cstyle=hash|slash decides what a comment looks like. Per-file totals come back on one
# line so the shell can aggregate them; the shell never has to re-read the file.
awk_prog='
function walk(s,   i, n, ch, len) {
  n = length(s)
  for (i = 1; i <= n; i++) {
    ch = substr(s, i, 1)
    if (ch == "{") {
      depth++
      if (depth > maxnest) maxnest = depth
      if (cand && !opened) { fnstart[depth] = FNR; opened = 1 }
    } else if (ch == "}") {
      if (depth in fnstart) {
        len = FNR - fnstart[depth] + 1
        if (len > maxfn) { maxfn = len; maxfnline = fnstart[depth] }
        if (len > 50) over50++
        delete fnstart[depth]
      }
      depth--
      if (depth < 0) depth = 0
    }
  }
}
BEGIN {
  loc = 0; maxfn = 0; maxfnline = 0; over50 = 0; maxnest = 0; loose = 0; todo = 0
  # indstack[0]=0: a top-level line is depth 0, so the first indent inside a def is
  # depth 1, the same as the first brace level in brace mode.
  depth = 0; sp = 0; d = 0; indstack[0] = 0; lastcode = 0
}
{
  line = $0
  sub(/\r$/, "", line)
  t = line
  sub(/^[ \t]+/, "", t)

  # loose_types: each pattern is deleted from the copy as it is counted, so a line like
  # "x: any[]" is one occurrence and not two.
  c = line
  loose += gsub(/@ts-ignore/, "", c)
  loose += gsub(/@ts-expect-error/, "", c)
  loose += gsub(/#[ \t]*type:[ \t]*ignore/, "", c)
  loose += gsub(/interface[ \t]*\{[ \t]*\}/, "", c)
  loose += gsub(/as[ \t]+any/, "", c)
  loose += gsub(/:[ \t]*any/, "", c)
  loose += gsub(/<any>/, "", c)
  loose += gsub(/any[ \t]*\[[ \t]*\]/, "", c)
  c2 = line
  todo += gsub(/TODO|FIXME|HACK|XXX/, "", c2)

  if (t == "") next
  iscomment = 0
  if (cstyle == "hash") {
    if (t ~ /^#/) iscomment = 1
  } else {
    if (t ~ /^\/\// || t ~ /^\/\*/ || t ~ /^\*/) iscomment = 1
  }
  if (iscomment) next
  loc++
  lastcode = FNR

  if (mode == "indent") {
    # Width-agnostic nesting: every deeper indent is one more level, whatever the width.
    ind = match(line, /[^ \t]/) - 1
    while (d > 0 && ind < indstack[d]) d--
    if (ind > indstack[d]) { d++; indstack[d] = ind }
    if (d > maxnest) maxnest = d
    # A def ends at the last code line before something dedents to its own level.
    while (sp > 0 && ind <= pyind[sp]) {
      len = prevcode - pystart[sp] + 1
      if (len > maxfn) { maxfn = len; maxfnline = pystart[sp] }
      if (len > 50) over50++
      sp--
    }
    if (t ~ /^(async[ \t]+)?def[ \t]+/) { sp++; pystart[sp] = FNR; pyind[sp] = ind }
    prevcode = FNR
    next
  }

  # brace mode: does this line look like it opens a function?
  cand = 0
  if (t ~ /^(export[ \t]+)?(default[ \t]+)?(async[ \t]+)?function[ \t]*[A-Za-z0-9_$]*[ \t]*\(/) cand = 1
  else if (t ~ /^func[ \t]*[A-Za-z0-9_$]*[ \t]*\(/ || t ~ /^func[ \t]+\(/) cand = 1
  else if (t ~ /^(fn|sub|def)[ \t]+[A-Za-z0-9_$]/) cand = 1
  else if (line ~ /=>[ \t]*\{/) cand = 1
  else if (t ~ /^[A-Za-z_$][A-Za-z0-9_$]*[ \t]*\(\)[ \t]*\{/) cand = 1
  else if (t ~ /^[A-Za-z_$][A-Za-z0-9_$:<>,\.\*\[\] \t]*[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*\(.*\)[ \t]*(const[ \t]*)?\{[ \t]*$/) cand = 1
  else if (t ~ /^[A-Za-z_$][A-Za-z0-9_$]*[ \t]*\(.*\)[ \t]*\{[ \t]*$/) cand = 1
  # control keywords also read as "name(...) {"; they are blocks, not functions. The
  # optional "else " prefix matters: "else if (x) {" reads as "Type name(args) {" (the
  # C-style rule above), so without it every else-if ladder inflates fn_over_50 -- in
  # exactly the code guard-clauses is aimed at.
  if (t ~ /^(else[ \t]+)?(if|for|while|switch|catch|do|else|elif|try|until|case|with|return)[ \t]*\(/) cand = 0
  opened = 0
  walk(line)
}
END {
  if (mode == "indent") {
    while (sp > 0) {
      len = lastcode - pystart[sp] + 1
      if (len > maxfn) { maxfn = len; maxfnline = pystart[sp] }
      if (len > 50) over50++
      sp--
    }
  }
  print loc, maxfn, maxfnline, over50, maxnest, loose, todo
}
'

files=0
loc=0
maxfn=0
maxfn_at="-"
over50=0
maxnest=0
loose=0
todo=0

# Read-only walk. -print0 + read -d "" because a file name may contain spaces.
while IFS= read -r -d '' f; do
  rel=${f#./}
  case $rel in
    *.sh|*.bash|*.zsh|*.ksh) mode=brace; cstyle=hash ;;
    *.py|*.pyi) mode=indent; cstyle=hash ;;
    *.rb|*.pl|*.pm|*.tf) mode=brace; cstyle=hash ;;
    *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts) mode=brace; cstyle=slash ;;
    *.go|*.java|*.c|*.h|*.cc|*.cpp|*.hpp|*.cs|*.rs|*.php|*.swift|*.kt|*.kts|*.scala|*.m|*.mm)
      mode=brace; cstyle=slash ;;
    *) continue ;;
  esac

  out=$(awk -v mode="$mode" -v cstyle="$cstyle" "$awk_prog" "$f" 2>/dev/null) || continue
  [[ -n $out ]] || continue
  set -- $out
  [[ $# -eq 7 ]] || continue

  files=$((files + 1))
  loc=$((loc + $1))
  over50=$((over50 + $4))
  loose=$((loose + $6))
  todo=$((todo + $7))
  [[ $5 -gt $maxnest ]] && maxnest=$5
  # Ties break on the lexicographically smaller path, so the output does not depend on
  # the order find happened to walk the tree in.
  if [[ $2 -gt $maxfn ]]; then
    maxfn=$2
    maxfn_at="$rel:$3"
  elif [[ $2 -eq $maxfn && $2 -gt 0 && "$rel:$3" < "$maxfn_at" ]]; then
    maxfn_at="$rel:$3"
  fi
done < <(find . \
  \( -name .git -o -name node_modules -o -name vendor -o -name dist -o -name build \
     -o -name target -o -name __pycache__ -o -name .venv -o -name venv \) -prune \
  -o -type f -print0)

if [[ $files -eq 0 ]]; then
  echo "[metrics] nothing measurable: no recognized source file under '$target'" >&2
  exit 3
fi

echo "[metrics] files=$files"
echo "[metrics] loc=$loc"
echo "[metrics] maxfn=$maxfn at=$maxfn_at (approx)"
echo "[metrics] fn_over_50=$over50 (approx)"
echo "[metrics] maxnest=$maxnest (approx)"
echo "[metrics] loose_types=$loose"
echo "[metrics] todo=$todo"
exit 0
