#!/bin/bash
# newlib by pspdev developers

## Exit with code 1 when any command executed returns a non-zero exit code.
onerr()
{
  exit 1;
}
trap onerr ERR

## Read information from the configuration file.
source "$(dirname "$0")/../config/psptoolchain-allegrex-config.sh"

## Download the source code.
REPO_URL="$PSPTOOLCHAIN_ALLEGREX_NEWLIB_REPO_URL"
REPO_REF="$PSPTOOLCHAIN_ALLEGREX_NEWLIB_DEFAULT_REPO_REF"
REPO_FOLDER="$(s="$REPO_URL"; s=${s##*/}; printf "%s" "${s%.*}")"

# Checking if a specific Git reference has been passed in parameter $1
if test -n "$1"; then
  REPO_REF="$1"
  printf 'Using specified repo reference %s\n' "$REPO_REF"
fi

if test ! -d "$REPO_FOLDER"; then
  git clone --depth 1 -b "$REPO_REF" "$REPO_URL" "$REPO_FOLDER"
else
  git -C "$REPO_FOLDER" fetch origin
  git -C "$REPO_FOLDER" reset --hard "origin/$REPO_REF"
  git -C "$REPO_FOLDER" checkout "$REPO_REF"
fi

cd "$REPO_FOLDER"

TARGET="psp"

## Determine the maximum number of processes that Make can work with.
PROC_NR=$(getconf _NPROCESSORS_ONLN)

find_llvm_tool()
{
  local tool="$1"
  local override="$2"

  if test -n "$override"; then
    printf '%s\n' "$override"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    local brew_llvm
    brew_llvm="$(brew --prefix llvm 2>/dev/null || true)"
    if test -n "$brew_llvm" && test -x "$brew_llvm/bin/$tool"; then
      printf '%s\n' "$brew_llvm/bin/$tool"
      return 0
    fi
  fi

  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return 0
  fi

  echo "ERROR: Could not find $tool. Install LLVM or set PSPTOOLCHAIN_ALLEGREX_LLVM_BINDIR." >&2
  return 1
}

strip_target_archives()
{
  local dir="$1"

  if [[ "${PSPTOOLCHAIN_ALLEGREX_STRIP_ARCHIVES:-}" != "1" ]]; then
    return 0
  fi

  local llvm_strip
  llvm_strip="$(find_llvm_tool llvm-strip "${PSPTOOLCHAIN_ALLEGREX_LLVM_STRIP:-${PSPTOOLCHAIN_ALLEGREX_LLVM_BINDIR:+$PSPTOOLCHAIN_ALLEGREX_LLVM_BINDIR/llvm-strip}}")"

  while IFS= read -r archive; do
    "$llvm_strip" --strip-debug "$archive"
  done < <(find "$dir" -name '*.a' -type f)
}

write_clang_wrapper()
{
  local path="$1"
  local clang="$2"
  local target="$3"
  local sysroot="$4"
  local flags="$5"
  local extra_flags="$6"

  printf '%s\n' \
    '#!/bin/sh' \
    "exec \"$clang\" -target \"$target\" --sysroot=\"$sysroot\" $flags $extra_flags \"\$@\"" \
    > "$path"
  chmod +x "$path"
}

if [[ "${PSPTOOLCHAIN_ALLEGREX_NEWLIB_NOABICALLS:-}" = "1" ]]; then
  export CFLAGS_FOR_TARGET="${CFLAGS_FOR_TARGET:-} ${PSPTOOLCHAIN_ALLEGREX_NOABICALLS_FLAGS}"
  export CXXFLAGS_FOR_TARGET="${CXXFLAGS_FOR_TARGET:-} ${PSPTOOLCHAIN_ALLEGREX_NOABICALLS_FLAGS}"
  export LIBCFLAGS_FOR_TARGET="${LIBCFLAGS_FOR_TARGET:-} ${PSPTOOLCHAIN_ALLEGREX_NOABICALLS_FLAGS}"
  export CCASFLAGS="${CCASFLAGS:-} ${PSPTOOLCHAIN_ALLEGREX_NOABICALLS_FLAGS}"
fi

if [[ "${PSPTOOLCHAIN_ALLEGREX_NEWLIB_CLANG:-}" = "1" ]]; then
  LLVM_BINDIR="${PSPTOOLCHAIN_ALLEGREX_LLVM_BINDIR:-}"
  CLANG="$(find_llvm_tool clang "${PSPTOOLCHAIN_ALLEGREX_NEWLIB_CLANG_CC:-${LLVM_BINDIR:+$LLVM_BINDIR/clang}}")"
  LLVM_AR="$(find_llvm_tool llvm-ar "${PSPTOOLCHAIN_ALLEGREX_LLVM_AR:-${LLVM_BINDIR:+$LLVM_BINDIR/llvm-ar}}")"
  LLVM_RANLIB="$(find_llvm_tool llvm-ranlib "${PSPTOOLCHAIN_ALLEGREX_LLVM_RANLIB:-${LLVM_BINDIR:+$LLVM_BINDIR/llvm-ranlib}}")"

  CLANG_WRAPPER_DIR="$PWD/.psp-clang-tools"
  CLANG_CC="$CLANG_WRAPPER_DIR/psp-clang"
  CLANG_AS="$CLANG_WRAPPER_DIR/psp-clang-as"
  CLANG_SYSROOT="${PSPTOOLCHAIN_ALLEGREX_NEWLIB_CLANG_SYSROOT:-$PSPDEV/$TARGET}"
  rm -rf "$CLANG_WRAPPER_DIR"
  mkdir -p "$CLANG_WRAPPER_DIR"
  write_clang_wrapper "$CLANG_CC" "$CLANG" "$PSPTOOLCHAIN_ALLEGREX_NEWLIB_CLANG_TARGET" "$CLANG_SYSROOT" "$PSPTOOLCHAIN_ALLEGREX_NEWLIB_CLANG_TARGET_FLAGS" ""
  write_clang_wrapper "$CLANG_AS" "$CLANG" "$PSPTOOLCHAIN_ALLEGREX_NEWLIB_CLANG_TARGET" "$CLANG_SYSROOT" "$PSPTOOLCHAIN_ALLEGREX_NEWLIB_CLANG_TARGET_FLAGS" "-c"

  export CC_FOR_TARGET="$CLANG_CC"
  export AS_FOR_TARGET="$CLANG_AS"
  export AR="$LLVM_AR"
  export RANLIB="$LLVM_RANLIB"
  export AR_FOR_TARGET="$LLVM_AR"
  export RANLIB_FOR_TARGET="$LLVM_RANLIB"
  export CFLAGS_FOR_TARGET="${PSPTOOLCHAIN_ALLEGREX_NEWLIB_CLANG_CFLAGS} ${CFLAGS_FOR_TARGET:-}"
  export LIBCFLAGS_FOR_TARGET="${PSPTOOLCHAIN_ALLEGREX_NEWLIB_CLANG_CFLAGS} ${LIBCFLAGS_FOR_TARGET:-}"
  export CCASFLAGS="-DDISABLE_PREFETCH ${CCASFLAGS:-}"
fi

# Create and enter the toolchain/build directory
rm -rf build-$TARGET && mkdir build-$TARGET && cd build-$TARGET

# Configure the build.
../configure \
	--prefix="$PSPDEV" \
	--target="$TARGET" \
	--with-sysroot="$PSPDEV/$TARGET" \
	--enable-newlib-retargetable-locking \
	--enable-newlib-multithread \
	--enable-newlib-io-c99-formats \
 	--enable-newlib-iconv \
  	--enable-newlib-iconv-encodings=us_ascii,utf8,utf16,ucs_2_internal,ucs_4_internal,iso_8859_1 \
	$TARG_XTRA_OPTS

## Compile and install.
make --quiet -j $PROC_NR clean
make --quiet -j $PROC_NR all
make --quiet -j $PROC_NR install
strip_target_archives "$PSPDEV/$TARGET"
make --quiet -j $PROC_NR clean

# Copy license file
mkdir -p $PSPDEV/psp/share/licenses/newlib
cp ../COPYING.NEWLIB $PSPDEV/psp/share/licenses/newlib/

## Store build information
BUILD_FILE="${PSPDEV}/build.txt"
if [[ -f "${BUILD_FILE}" ]]; then
  sed -i'' '/^newlib /d' "${BUILD_FILE}"
fi
git log -1 --format="newlib %H %cs %s" >> "${BUILD_FILE}"
