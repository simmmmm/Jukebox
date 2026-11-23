#!/usr/bin/env bash
# The runner's home, its user's name (the account's and the full one) and
# the machine's names, out of every file under the paths given, in place:
# before logs go to the run's artifact or the public screenshots branch.
# The MacBook's home is the owner's full name. The home becomes "~", any
# other /Users/<name> "/Users/runner", a name "runner". Pictures and zips
# (by extension or their first bytes) are left alone, and so is any .git
# folder; every other file is read as bytes, a log with NUL bytes in it too.
#
#   bash ci/redact.sh build/logs "$GITHUB_STEP_SUMMARY"
#   some-command 2>&1 | bash ci/redact.sh -     (a filter, line by line)
set -u
home=${HOME:-}
names=$(
  {
    id -un
    basename "$home"
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
export REDACT_HOME=$home REDACT_NAMES=$names

# Each name as macOS may write it: composed (NFC) and decomposed (NFD, as
# in file names), in lower, upper and its own case, and percent-encoded (in
# URLs and paths), all case-insensitive. Longest first, so a name inside a
# longer one goes with it. A name under 4 letters ("Tim") only as a word of
# its own, so "Timer" stays; one letter is no name. The home "/" never
# (an empty or tiny pattern would change every line).
read -r -d '' prog << 'PERL' || true
use strict;
use warnings;
use Encode qw(decode encode);
use Unicode::Normalize qw(NFC NFD);
my $home = $ENV{REDACT_HOME} // '';
my (%seen, @long, @short);
for my $raw (split /\n/, $ENV{REDACT_NAMES} // '') {
  my $text = decode('UTF-8', $raw);
  $text =~ s/^\s+|\s+$//g;
  next if length($text) < 2;
  for my $form (NFC($text), NFD($text)) {
    for my $case ($form, lc $form, uc $form) {
      my $bytes = encode('UTF-8', $case);
      (my $pct = $bytes) =~ s/([^A-Za-z0-9._~-])/sprintf('%%%02X', ord $1)/ge;
      for my $v ($bytes, $pct) {
        next if $seen{$v}++;
        push @{ length($text) < 4 ? \@short : \@long }, $v;
      }
    }
  }
}
sub alternation { join '|', map { quotemeta } sort { length($b) <=> length($a) } @_ }
my $letter = '[A-Za-z0-9\x80-\xff]';
my @parts;
push @parts, '(?:' . alternation(@long) . ')' if @long;
push @parts, "(?<!$letter)(?:" . alternation(@short) . ")(?!$letter)" if @short;
my $names = @parts ? join('|', @parts) : undef;
$names = qr/$names/i if defined $names;
sub redact {
  my $n = 0;
  $n += ($_[0] =~ s/\Q$home\E/~/g) if length($home) > 1;
  $n += ($_[0] =~ s{/Users/(?!Shared\b|runner\b)[^/\s"'<>:;,|]+}{/Users/runner}g);
  $n += ($_[0] =~ s/$names/runner/g) if defined $names;
  return $n;
}
binmode STDIN;
binmode STDOUT;
if (($ENV{REDACT_MODE} // '') eq 'filter') {
  $| = 1;
  # The contact sheets ci/screenshots.sh prints last are base64 of pictures
  # of the made-up library: left as they are, as a name's letters could
  # turn up in them by chance and break the picture.
  my $sheet = 0;
  while (my $line = <STDIN>) {
    $sheet = 0 if $line =~ /^=====END SHEET /;
    redact($line) unless $sheet;
    $sheet = 1 if $line =~ /^=====BEGIN SHEET /;
    print $line;
  }
  exit 0;
}
my %picture = map { $_ => 1 } qw(png jpg jpeg heic heif gif zip);
local $/ = "\0";
while (my $file = <STDIN>) {
  chomp $file;
  next if $file =~ /\.([^.\/]+)\z/ && $picture{ lc $1 };
  open(my $in, '<:raw', $file) or next;
  my $data = do { local $/; <$in> };
  close $in;
  next unless defined $data;
  next if $data =~ /\A(?:\x89PNG|\xFF\xD8\xFF|PK\x03\x04|GIF8)/ || substr($data, 4, 4) eq 'ftyp';
  next unless redact($data);
  open(my $out, '>:raw', $file) or next;
  print $out $data;
  close $out;
}
PERL

if [[ ${1:-} == - ]]; then
  REDACT_MODE=filter exec perl -e "$prog"
fi
paths=()
for path in "$@"; do [[ -n $path && -e $path ]] && paths+=("$path"); done
(( ${#paths[@]} )) || exit 0
find "${paths[@]}" -name .git -prune -o -type f -print0 2> /dev/null | perl -e "$prog"
exit 0
