# Sourced by disable.sh and restore.sh. Reads a debloat list and prints one package name per line.
#
# Every name is checked against the shape of an Android package name before anything is sent to the
# TV, because each one ends up inside a shell command there. A list is community-contributed text:
# one bad line (for example "com.foo;settings put ...") refuses the whole list instead of running.
pkg_list() {
  local out bad
  out=$(sed -E 's/\r$//; s/#.*$//' "$1" | awk 'NF {print $1}')
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
