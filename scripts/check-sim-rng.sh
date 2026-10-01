#!/usr/bin/env bash
# Determinism lint rule (issue #3): simulation code must not call the unseeded system RNG.
#
# All sim randomness must come from the seeded `PCG32` owned by the sim world so that
# recorded input streams replay bit-identically (docs/PLAN.md §2).
#
# How the rule works: a character-level scanner (awk) walks every Swift file in the sim
# modules with a lexical context stack: code, nested block comment, single-line string
# (regular or `#`-prefixed raw, hash level tracked), multiline string (regular or raw),
# and string-interpolation code (`\(...)` in regular strings and `\#(...)` at the
# matching hash level in raw strings are lexed AS CODE, so calls hidden in interpolation
# are scanned too). Interpolation closes only at the `)` that matches the
# interpolation's own opening paren (paren- and brace-depth tracked), so nested calls
# like `"\(String(1) + String(Int.random(in: 0...10)))"` cannot end the interpolation
# early and hide an RNG call as string content. Every call site of `.random(`,
# `.randomElement(`, `.shuffled(`, or `.shuffle(` is captured with its own full argument
# text (paren-depth and nesting aware; the name-to-paren link resolves across
# whitespace/comments; backticked member names like `` Int.`random`(...) `` are matched;
# args join across lines).
#
# A call is seeded ONLY when its LAST top-level parameter is `using : &generator` (space
# before the colon allowed) — where generator is an identifier or dotted member chain
# (`&rng`, `&self.rng`, `&world.rng`). A value-typed `using: rng` does not compile against
# seeded overloads and is flagged. Anything else is unseeded.
#
# Additionally, a fail-closed FILE-LEVEL rule flags any sim file whose CODE text mentions
# `SystemRandomNumberGenerator` at all: passing the system generator by inout still
# replays non-deterministically, and no initializer/alias/cast spelling whitelist can
# catch every way to build one — so sim code must not reference it (use the seeded PCG32).
# CODE text = characters lexed as code, INCLUDING string-interpolation code (`\(...)` /
# raw `\#(...)` interiors), so `"\(roll(using: SystemRandomNumberGenerator()))"` is
# caught. Comments and string-literal interiors never count, so documentation and quoted
# mentions may name the type.
#
# Gate contract (documented boundary): the rule is defined over COMPILING code —
# unterminated strings/comments do not compile and CI `swift test` fails on them
# independently. String-interpolation code IS lexed and scanned: an unseeded call there
# is flagged, and (fail-closed by design) a seeded call written INSIDE string
# interpolation is also flagged — keep every RNG call in a real statement, not in a
# string literal. A generator expression with subscripts/operators in the `using:`
# argument (e.g. `using: &dict["k"]`) must be stored in a local/property first.
#
# Scope: the platform-neutral sim modules (CBCore, CBSim, CBPlays, CBAI, CBAnimation,
# CBAssets, CBGame). Presentation modules (CBRender, CBHUD, CBAudio, CBInput) are exempt —
# only the sim loop must be deterministic. A scan error aborts with exit 2 (never clean).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_MODULES=(
  "Packages/CraftBowlKit/Sources/CBCore"
  "Packages/CraftBowlKit/Sources/CBSim"
  "Packages/CraftBowlKit/Sources/CBPlays"
  "Packages/CraftBowlKit/Sources/CBAI"
  "Packages/CraftBowlKit/Sources/CBAnimation"
  "Packages/CraftBowlKit/Sources/CBAssets"
  "Packages/CraftBowlKit/Sources/CBGame"
)

cd "$REPO_ROOT"
missing=0
for dir in "${SIM_MODULES[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "error: sim module directory '$dir' is missing" >&2
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  echo "FAIL: sim module layout changed; update scripts/check-sim-rng.sh" >&2
  exit 1
fi

# Collect the Swift files to scan (NUL-safe; abort if the scan set is empty).
files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find "${SIM_MODULES[@]}" -name '*.swift' -type f -print0)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "error: no Swift files found under the sim modules — scan set is empty" >&2
  exit 2
fi

if ! scan="$(awk '
  function trim(s) { gsub(/^[ \t\r\n]+/, "", s); gsub(/[ \t\r\n]+$/, "", s); return s }
  function hstr(k,  s) { s = ""; while (k-- > 0) s = s "#"; return s }
  function emitLevel(d,  last) {   # defer the seeded/unseeded verdict to the file boundary
    pendCount++
    pLineA[pendCount] = pLine[d]
    pNameA[pendCount] = pName[d]
    pArgsA[pendCount] = trim(pArgs[d])
    pLastA[pendCount] = trim(substr(pArgs[d], pLast[d] + 1))
  }
  function flushFile(  i, last, ok) {
    # Fail-closed file-level rule: sim code must not reference the system generator at all.
    # Any initializer/cast/alias shape that mentions the type defeats name-based harvesting,
    # so a plain occurrence scan over the code text of the file is the sound rule.
    if (index(fileCode, "SystemRandomNumberGenerator") > 0)
      printf "BAD\t%s:1: file references SystemRandomNumberGenerator — sim code must use only the seeded PCG32 of the world\n", fname
    for (i = 1; i <= pendCount; i++) {
      last = pLastA[i]
      ok = (last ~ /^using[ \t]*:[ \t]*&[ \t]*[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*[ \t]*$/)
      printf "%s\t%s:%d: %s(%s)\n", (ok ? "OK" : "BAD"), fname, pLineA[i], pNameA[i], pArgsA[i]
    }
    pendCount = 0   # stale slots are never read (loops bounded by pendCount); no array deletes (portable to one-true-awk/BSD awk on macOS runners)
  }
  function openCall(name,  d) {
    appendChar("(")                            # the opening paren belongs to every active call once
    for (d = 1; d <= cs; d++) pDepth[d]++
    cs++
    pName[cs] = name; pLine[cs] = FNR; pArgs[cs] = ""; pLast[cs] = 0; pDepth[cs] = 1
  }
  function appendChar(c,  d) { for (d = 1; d <= cs; d++) pArgs[d] = pArgs[d] c }
  function flagInterpCall(nm) {   # RNG call inside string interpolation: fail closed, never tracked
    if (nm == "") nm = ".random"
    printf "BAD\t%s:%d: RNG call inside string interpolation: %s\n", fname, FNR, nm
  }
  function pushCtx(t) { lx++; ctx[lx] = t; bd[lx] = 0; pd[lx] = 0; hs[lx] = 0 }
  function popCtx() { ctx[lx] = 0; lx-- }
  function newFile(  d) {
    # finalize previous file: report unclosed call levels (cannot compile anyway),
    # then defer-judge every captured call of that file (incl. the file-level
    # SystemRandomNumberGenerator reference rule).
    while (cs > 0) { emitLevel(cs); cs-- }
    flushFile()
    fileCode = ""
    cs = 0; lx = 1; ctx[1] = 0; bd[1] = 0; pd[1] = 0; hs[1] = 0; afterName = 0
  }
  BEGIN { cs = 0; lx = 1; ctx[1] = 0; bd[1] = 0; pd[1] = 0; hs[1] = 0; pendCount = 0; fileCode = "" }   # ctx: 0 code, 1 block, 2 str, 3 mstr, 4 interp-code
  FILENAME != fname { newFile(); fname = FILENAME }
  {
    line = $0
    n = length(line)
    i = 1
    while (i <= n) {
      c = substr(line, i, 1)
      t = ctx[lx]
      if (t == 1) {                                          # block comment
        if (c == "/" && substr(line, i + 1, 1) == "*") { bd[lx]++; i += 2; continue }
        if (c == "*" && substr(line, i + 1, 1) == "/") {
          bd[lx]--; i += 2
          if (bd[lx] == 0) popCtx()
          continue
        }
        i++
        continue
      }
      if (t == 2) {                                          # single-line string (hash level h)
        h = hs[lx]
        if (h > 0) {                                         # raw string: no backslash escapes
          if (c == "\\" && substr(line, i, 2 + h) == "\\" hstr(h) "(") { pushCtx(4); i += 2 + h; continue }
          appendChar(c)
          if (c == "\"" && substr(line, i, 1 + h) == "\"" hstr(h)) popCtx()
          i++
          continue
        }
        if (c == "\\" && substr(line, i + 1, 1) == "(") { pushCtx(4); i += 2; continue }
        appendChar(c)
        if (c == "\\") { nc = substr(line, i + 1, 1); if (nc != "") appendChar(nc); i += 2; continue }
        if (c == "\"") popCtx()
        i++
        continue
      }
      if (t == 3) {                                          # multiline string (hash level h)
        h = hs[lx]
        if (c == "\"" && substr(line, i, 3 + h) == "\"\"\"" hstr(h)) { popCtx(); i += 3 + h; continue }
        if (h > 0) {
          if (c == "\\" && substr(line, i, 2 + h) == "\\" hstr(h) "(") { pushCtx(4); i += 2 + h; continue }
        }
        else {
          if (c == "\\" && substr(line, i + 1, 1) == "\\") { i += 2; continue }   # escaped backslash: literal text, never interpolation
          if (c == "\\" && substr(line, i + 1, 1) == "(") { pushCtx(4); i += 2; continue }
        }
        i++
        continue
      }
      # --- code state: t==0 root code, t==4 interpolation code ---
      if (c == "/" && substr(line, i + 1, 1) == "/") { break }               # line comment: rest of line
      if (c == "/" && substr(line, i + 1, 1) == "*") { pushCtx(1); bd[lx] = 1; i += 2; continue }
      if (t == 4) {
        # Inside interpolation: paren/brace depth decides which `)` closes the interpolation.
        # Chars never append to call args; RNG calls here are reported BAD immediately (fail closed).
        # Interpolation is CODE, so every code char also feeds the file-level harvest below.
        if (c == "{") { bd[lx]++; fileCode = fileCode c; i++; continue }
        if (c == "}") {
          if (bd[lx] == 0 && pd[lx] == 0) popCtx()             # interpolation ended by multi-statement `}`
          else if (bd[lx] > 0) bd[lx]--
          fileCode = fileCode c
          i++
          continue
        }
        if (c == "(") {
          if (afterName) { flagInterpCall(nmPending); afterName = 0 }   # name resolved across whitespace inside interp
          pd[lx]++
          fileCode = fileCode c
          i++
          continue
        }
        if (c == ")") {
          if (bd[lx] == 0 && pd[lx] == 0) popCtx()             # closes the interpolation itself
          else if (pd[lx] > 0) pd[lx]--                        # closes a nested paren instead
          fileCode = fileCode c
          i++
          continue                                             # never closes an outer tracked call
        }
      }
      if (afterName) {
        if (c ~ /[ \t]/) { if (t == 0) appendChar(c); i++; continue }
        if (c == "(") {
          # t==4 never reaches here (the interpolation `(` branch above consumes it first);
          # branch kept as a defensive fail-closed guard.
          if (t == 4) flagInterpCall(nmPending)
          else openCall(nmPending)
          afterName = 0
          i++
          continue
        }
        afterName = 0                                                        # not a call; handle char normally
      }
      if (c == "#") {                                                       # hash run: raw string opener or plain code
        k = 0; j = i
        while (substr(line, j, 1) == "#") { k++; j++ }
        if (substr(line, j, 3) == "\"\"\"") {
          if (t == 0) { appendChar("\""); appendChar("\""); appendChar("\"") }
          pushCtx(3); hs[lx] = k; i = j + 3
          continue
        }
        if (substr(line, j, 1) == "\"") {
          if (t == 0) appendChar("\"")
          pushCtx(2); hs[lx] = k; i = j + 1
          continue
        }
        if (t == 0) for (m = 0; m < k; m++) appendChar("#")                  # e.g. #if / #selector: plain code chars
        i = j
        continue
      }
      if (substr(line, i, 3) == "\"\"\"") {
        if (t == 0) { appendChar("\""); appendChar("\""); appendChar("\"") }
        pushCtx(3); i += 3; continue
      }
      if (c == "\"") { if (t == 0) appendChar(c); pushCtx(2); i++; continue }
      if (c == ".") {
        rest = substr(line, i)
        if (match(rest, /^\.(`?(randomElement|shuffled|shuffle|random)`?)[ \t]*\(/)) {
          if (t == 4) { flagInterpCall(trim(substr(rest, 1, RLENGTH - 1))); pd[lx]++ }   # fail closed; consumed ( keeps pd balanced
          else openCall(substr(rest, 1, RLENGTH - 1))
          i += RLENGTH
          continue
        }
        if (match(rest, /^\.(`?(randomElement|shuffled|shuffle|random)`?)/)) {
          nmPending = substr(rest, 1, RLENGTH)   # name seen; paren may follow after ws/comments
          afterName = 1
          i += RLENGTH
          continue
        }
      }
      # generic code character; interp-code (t==4) never appends (fail-closed empty args)
      if (c == "(") {
        if (t == 0) { appendChar(c); for (d = 1; d <= cs; d++) pDepth[d]++ }
        else pd[lx]++
        i++
        continue
      }
      if (c == ")") {
        for (d = 1; d <= cs; d++) pDepth[d]--
        while (cs > 0 && pDepth[cs] == 0) { emitLevel(cs); cs-- }   # closed calls are judged before this paren
        for (d = 1; d <= cs; d++) pArgs[d] = pArgs[d] c
        i++
        continue
      }
      if (c == ",") {
        if (t == 0) {
          for (d = 1; d <= cs; d++) if (pDepth[d] == 1) pLast[d] = length(pArgs[d]) + 1
          appendChar(c); fileCode = fileCode c " "
        }
        i++
        continue
      }
      if (t == 0) { appendChar(c); fileCode = fileCode c }   # root code: call args + harvest text
      else if (t == 4) fileCode = fileCode c                  # interpolation code: harvest text only (never call args)
      i++
    }
    for (d = 1; d <= cs; d++) pArgs[d] = pArgs[d] " "   # join args across lines
  }
  END { while (cs > 0) { emitLevel(cs); cs-- }; flushFile() }' "${files[@]}")"; then
  echo "error: RNG scan failed (awk error)" >&2
  exit 2
fi

violations="$(printf '%s\n' "$scan" | grep '^BAD' || true)"
if [[ -n "$violations" ]]; then
  count="$(printf '%s\n' "$violations" | wc -l | tr -d ' ')"
  echo "::error:: Unseeded RNG call site(s) in simulation modules — use the world's PCG32 (docs/PLAN.md §2)"
  printf '%s\n' "$violations" | sed 's/^BAD\t/  /'
  echo "FAIL: $count unseeded RNG call site(s); sim code must draw randomness only from the seeded PCG32" >&2
  exit 1
fi

echo "OK: no unseeded RNG calls in simulation modules (${#files[@]} files scanned)"
