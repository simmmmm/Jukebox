#!/usr/bin/env bash
# The runner's home, its user's name (the account's and the full one) and
# the machine's names, out of every text file under the paths given, in
# place: before logs go to the run's artifact or the public screenshots
# branch. The MacBook's home is the owner's full name. The home becomes
# "~", a name "runner". Files that are no text (pictures) are left alone,
# and so is any .git folder.
#
#   bash ci/redact.sh build/logs "$GITHUB_STEP_SUMMARY"
set -u
home=${HOME:-}
names=$(
  {
    id -un
    id -F 2> /dev/null
    # The full name's words too: a first name alone in a computer's name.
    id -F 2> /dev/null | tr ' ' '\n'
    hostname
    hostname -s
    scutil --get ComputerName
    scutil --get LocalHostName
    scutil --get HostName
  } 2> /dev/null | sort -u
)
paths=()
for path in "$@"; do [[ -n $path && -e $path ]] && paths+=("$path"); done
(( ${#paths[@]} )) || exit 0
export REDACT_HOME=$home REDACT_NAMES=$names
# Longest first, so a name inside a longer one goes with it; nothing
# shorter than 4 characters, nor the home "/" (an empty or tiny pattern
# would change every line).
grep -rIl --null --exclude-dir=.git '' "${paths[@]}" 2> /dev/null | while IFS= read -r -d '' file; do
  perl -pi -e '
    BEGIN {
      $home = $ENV{REDACT_HOME};
      @names = sort { length($b) <=> length($a) } grep { length($_) >= 4 } split /\n/, $ENV{REDACT_NAMES};
    }
    s/\Q$home\E/~/g if length($home) > 1;
    for my $name (@names) { s/\Q$name\E/runner/gi }
  ' "$file"
done
exit 0
