#!/usr/bin/env bash
# Reproduce: a requirement under packages:all with `when: "%cxx"` is applied to
# packages that have no C++ dependency.
#
#   ./reproduce.sh PATH_TO_A_SPACK_CHECKOUT
#
# Needs gcc and g++ on PATH. Uses a configuration and cache of its own below
# ./work, so no Spack configuration of the user is read or changed.
# Exits 1 while the bug is there, 0 once every spec concretizes.
set -uo pipefail

spack_root=$(cd "${1:?usage: ./reproduce.sh PATH_TO_A_SPACK_CHECKOUT}" && pwd)
work=$(pwd)/work
rm -rf "$work"
mkdir -p "$work/config"
export SPACK_USER_CONFIG_PATH=$work/config
export SPACK_USER_CACHE_PATH=$work/cache
export SPACK_SYSTEM_CONFIG_PATH=$work/no-system-config
unset SPACK_DISABLE_LOCAL_CONFIG
spack() { "$spack_root/bin/spack" "$@"; }

echo "Spack $(spack --version)"
echo "$(gcc --version | head -1)"
spack compiler find > /dev/null 2>&1
cp "$work/config/packages.yaml" "$work/externals.yaml"
echo
echo "The only configuration, written by 'spack compiler find':"
cat "$work/externals.yaml"

failed=0

requirement() { # the condition of the requirement on all packages; empty for no requirement
  cp "$work/externals.yaml" "$work/config/packages.yaml"
  echo
  if [ -z "$1" ]; then
    echo "===== No requirement ====="
    return
  fi
  cat >> "$work/config/packages.yaml" <<YAML
  all:
    require:
    - spec: "%cxx=gcc"
      when: "$1"
YAML
  echo "===== packages:all:require: [{spec: \"%cxx=gcc\", when: \"$1\"}] ====="
}

concretizes() { # a spec that has to concretize, with what it depends on for languages
  local out=$work/out.txt
  if timeout 600 "$spack_root/bin/spack" spec --fresh "$1" > "$out" 2>&1; then
    echo "ok      spack spec --fresh $1    ($2)"
  else
    failed=1
    echo "FAILED  spack spec --fresh $1    ($2)"
    sed -n '/==> Error/,$p' "$out" | sed 's/^/        /' | head -8
  fi
}

requirement ""
concretizes libmd  "C only, no dependency that uses C++"
concretizes json-c "C only, built with cmake, which uses C++"
concretizes zlib   "C and C++, built with gmake, which is C only"
concretizes cmake  "C and C++"

requirement "%cxx"
concretizes libmd  "C only, no dependency that uses C++"
concretizes json-c "C only, built with cmake, which uses C++"
concretizes zlib   "C and C++, built with gmake, which is C only"
concretizes cmake  "C and C++"

requirement "%cxx=gcc"
concretizes libmd  "C only, no dependency that uses C++"
concretizes json-c "C only, built with cmake, which uses C++"
concretizes zlib   "C and C++, built with gmake, which is C only"
concretizes cmake  "C and C++"

echo
if [ "$failed" = 1 ]; then
  echo "Reproduced: gcc is the only compiler, so the requirement should change nothing."
else
  echo "Not reproduced: every spec concretizes."
fi
exit "$failed"
