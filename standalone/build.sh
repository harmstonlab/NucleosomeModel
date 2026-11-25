#!/usr/bin/env bash
#
# Builds dist/nucleosome_prediction-<version>-<os>-<cpu>, e.g.
# nucleosome_prediction-1.0.0-el10-x86_64. This is a single executable made with PAR::Packer
# that contains nucleosome_prediction.pl and everything it needs to run. The version number
# comes from the VERSION file. See README.md.
#
# Run it with "make standalone". You can set:
#   LIBSTDCXX5  the libstdc++.so.5 to bundle (default lib/libstdc++.so.5)
#   OUT         where to write the executable (default is the name above, in dist/)
#
# The first run installs PAR::Packer into standalone/.perl5. It's compiled for the perl you
# ran it with, so use the same perl for later builds (or delete standalone/.perl5).

set -euo pipefail

die() { echo "build.sh: error: $*" >&2; exit 1; }

# Short name for the OS, used in the file name. RHEL, Rocky, AlmaLinux etc. give el<major
# version> (e.g. el10). Anything else gives the ID and version from /etc/os-release (e.g.
# ubuntu24.04).
os_tag() {
   [ -r /etc/os-release ] || { echo linux; return; }
   (
      . /etc/os-release
      version=${VERSION_ID:-}
      case " ${ID:-} ${ID_LIKE:-} " in
         *" rhel "*) echo "el${version%%.*}" ;;
         *)          echo "${ID:-linux}$version" ;;
      esac
   ) | tr -cd 'A-Za-z0-9._-'
}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=$(tr -cd 'A-Za-z0-9._-' < "$ROOT/VERSION") || die "can't read $ROOT/VERSION"
[ -n "$VERSION" ] || die "$ROOT/VERSION doesn't contain a version number"
LIBSTDCXX5=${LIBSTDCXX5:-$ROOT/lib/libstdc++.so.5}
OUT=${OUT:-$ROOT/dist/nucleosome_prediction-$VERSION-$(os_tag)-$(uname -m)}
PERL_LOCAL=$ROOT/standalone/.perl5
PAR_PACKER_VERSION=1.064

# Options that were used to make the example outputs in the repo (occ_output.*, raw_output.*).
# They use the default -c 0.1, not the -c 0.03 from the README example.
REF_ARGS=(-t Example -s input.fa -c 0.1 -temp 1 -tab -gxp)

# Check libstdc++.so.5, which lib/libxerces-c.so.27 needs
[ -f "$LIBSTDCXX5" ] || die "can't find $LIBSTDCXX5. Set LIBSTDCXX5 to an x86_64 libstdc++.so.5 (see README.md)."

elf_info=$(readelf -h -d -V "$LIBSTDCXX5" 2>/dev/null) || die "$LIBSTDCXX5 is not an ELF file"
grep -q 'Class:.*ELF64' <<<"$elf_info" \
   && grep -q 'Machine:.*X86-64' <<<"$elf_info" \
   || die "$LIBSTDCXX5 is not a 64-bit x86 library"
grep -q 'SONAME.*\[libstdc++\.so\.5\]' <<<"$elf_info" || die "$LIBSTDCXX5 is not libstdc++.so.5 (wrong SONAME)"
grep -q 'GLIBCPP_3\.2' <<<"$elf_info" || die "$LIBSTDCXX5 doesn't have the GLIBCPP_3.2 symbols that libxerces-c needs"

# Install PAR::Packer if it isn't there yet
export PERL5LIB="$PERL_LOCAL/lib/perl5${PERL5LIB:+:$PERL5LIB}"
export PATH="$PERL_LOCAL/bin:$PATH"

if ! perl -MPAR::Packer -e 1 2>/dev/null; then
   command -v cpanm >/dev/null \
      || die "PAR::Packer isn't installed and there's no cpanm to install it with. You may need to load a Perl module first."
   echo "Installing PAR::Packer $PAR_PACKER_VERSION into $PERL_LOCAL ..."
   cpanm --notest --local-lib-contained "$PERL_LOCAL" "PAR::Packer@$PAR_PACKER_VERSION"
fi
command -v pp >/dev/null || die "pp (from PAR::Packer) not found"

# Copy everything that goes into the executable to a temporary directory
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/nucpred-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
B=$STAGE/bundle
mkdir -p "$B/lib" "$B/bin" "$B/models" "$B/templates"

cp "$ROOT/nucleosome_prediction.pl" "$B/"
cp "$ROOT"/lib/*.pl "$B/lib/"
cp -L "$ROOT"/lib/*.so* "$B/lib/"
cp -L "$LIBSTDCXX5" "$B/lib/libstdc++.so.5"
cp "$ROOT/bin/map_learn_static" "$B/bin/"
cp "$ROOT"/models/*.gxw "$B/models/"
cp "$ROOT"/templates/*.map "$B/templates/"
chmod 644 "$B"/*.pl "$B"/lib/* "$B"/models/* "$B"/templates/*
chmod 755 "$B/bin/map_learn_static"

# make install replaces EXE_BASE_DIR in the scripts with the path of this checkout, but the
# launcher needs EXE_BASE_DIR. If make install has been run, change it back in the copies.
BASE=$(sed -n 's|^require "\(.*\)/lib/load_args.pl";.*|\1|p' "$B/nucleosome_prediction.pl" | head -n 1)
[ -n "$BASE" ] || die "can't find the install path in nucleosome_prediction.pl"
if [ "$BASE" != "EXE_BASE_DIR" ]; then
   echo "make install has been run here, changing $BASE back to EXE_BASE_DIR in the copies ..."
   BASE="$BASE" perl -pi -e 's/\Q$ENV{BASE}\E/EXE_BASE_DIR/g' "$B"/*.pl "$B"/lib/*.pl
   if grep -rlF "$BASE" "$B" >/dev/null; then
      die "these files still contain $BASE: $(grep -rlF "$BASE" "$B" | tr '\n' ' ')"
   fi
fi

# Pack it
mkdir -p "$(dirname "$OUT")"
OUT=$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")

echo "Packing $OUT ..."
# pp doesn't scan the bundled scripts (they're added as data files), so list the modules they use.
pp -o "$OUT" \
   -M POSIX -M File::Basename -M File::Copy -M File::Path -M File::Temp -M Cwd \
   -a "$B;bundle" \
   "$ROOT/standalone/launcher.pl"

# Run the new executable on input.fa and compare the results with the example outputs
if [ -f "$ROOT/occ_output.tab" ] && [ -f "$ROOT/raw_output.tab" ]; then
   echo "Testing $OUT on input.fa ..."
   CHECK=$STAGE/check
   mkdir "$CHECK"
   cp "$ROOT/input.fa" "$CHECK/"
   ( cd "$CHECK" \
       && "$OUT" "${REF_ARGS[@]}" -p occ_output \
       && "$OUT" "${REF_ARGS[@]}" -raw_binding -p raw_output ) > "$CHECK/log" 2>&1 \
      || { cat "$CHECK/log" >&2; die "test run of $OUT failed"; }
   for f in occ_output.tab occ_output.gxp raw_output.tab raw_output.gxp; do
      cmp -s "$CHECK/$f" "$ROOT/$f" || die "$f from the new executable is different from the one in the repo ($OUT was still built)"
   done
   echo "Output matches the example files in the repo."
fi

echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
