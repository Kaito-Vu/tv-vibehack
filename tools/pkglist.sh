# shellcheck shell=bash
# Sourced by disable.sh and restore.sh. Reads a debloat list and prints one package name per line.
#
# Every name is checked against the shape of an Android package name before anything is sent to the
# TV, because each one ends up inside a shell command there. A list is community-contributed text:
# one bad line (for example "com.foo;settings put ...") refuses the whole list instead of running.
pkg_list() {
  local out bad
  [ -f "$1" ] && [ -r "$1" ] || { echo "ERROR: cannot read $1" >&2; return 1; }
  # tr, not sed, drops the carriage returns: BSD sed (macOS) reads "\r" as the letter r and would cut the
  # last r off every name that ends in one. The $'...' makes bash write the three BOM bytes into the pattern
  # itself, since BSD sed has no \x escapes either; a BOM at the top of the file is a Windows editor's doing.
  out=$(tr -d '\r' < "$1" | LC_ALL=C sed -E $'1s/^\xEF\xBB\xBF//; s/#.*$//' | awk 'NF { $1 = $1; print }')
  # A line is a package name and nothing else (the PowerShell scripts require the same): a second word is
  # an error, not something to drop silently.
  bad=$(printf '%s' "$out" | grep -vxE '[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+' || true)
  if [ -n "$bad" ]; then
    echo "ERROR: $1 has lines that are not package names; nothing was sent to the TV:" >&2
    printf '%s\n' "$bad" >&2
    return 1
  fi
  if [ -z "$out" ]; then
    echo "ERROR: $1 lists no packages (every line is a comment or blank)." >&2
    return 1
  fi
  printf '%s\n' "$out"
}
