#!/usr/bin/perl
#
# Main script of the standalone nucleosome_prediction executable (built by standalone/build.sh).
#
# The executable contains a bundle/ directory with nucleosome_prediction.pl, lib/, bin/, models/
# and templates/. For each run this script sets up a temporary copy of it, like "make install"
# would. EXE_BASE_DIR is replaced with the temporary directory, and the #! line of each Perl
# script is changed to run this executable with --nucpred-perl, so the scripts use the Perl
# packed into it and not the system one. The temporary directory is deleted when the run ends.
#
# For testing you can also run it unpacked (perl standalone/launcher.pl ...). It then uses the
# checkout as the bundle and the current perl.
#
# Set NUCPRED_KEEP_TMP=1 to keep the temporary directory, and SEGAL_LAB_DEBUG=1 to see the
# error messages from map_learn_static.

use strict;
use warnings;

# When a bundled script runs (via its #! line), run it with the Perl in this executable.
if (@ARGV >= 2 and $ARGV[0] eq '--nucpred-perl')
{
   shift @ARGV;
   my $script = shift @ARGV;
   $script = "./$script" unless $script =~ m{^\.?\.?/};   # stop "do" from searching @INC

   -r $script or die "nucleosome_prediction: cannot read script '$script': $!\n";

   $0 = $script;
   do $script;
   if ($@) { print STDERR $@; exit 255; }
   exit 0;
}

# Otherwise this is a normal run.
require Cwd;
require File::Basename;
require File::Path;
require File::Temp;
require POSIX;

my $ME = "nucleosome_prediction";

my $packed = (defined($ENV{PAR_TEMP}) and length($ENV{PAR_TEMP}) > 0);

my ($bundle, $tmp_root);
if ($packed)
{
   $bundle = "$ENV{PAR_TEMP}/inc/bundle";
   # Put the run directory in PAR's temp directory ($TMPDIR/par-<user>). Only this user can
   # access it, and it has to allow running programs anyway because PAR runs from there.
   $tmp_root = File::Basename::dirname($ENV{PAR_TEMP});
}
else
{
   $bundle = Cwd::abs_path(File::Basename::dirname(Cwd::abs_path(__FILE__)) . "/..");
   $tmp_root = (defined($ENV{TMPDIR}) and -d $ENV{TMPDIR}) ? $ENV{TMPDIR} : "/tmp";
}

-f "$bundle/nucleosome_prediction.pl" and -d "$bundle/lib"
   or die "$ME: can't find the bundled files in '$bundle'\n";

# The pipeline scripts put paths into shell commands without quoting them, so only allow
# simple paths.
my $SAFE_PATH = qr{^[A-Za-z0-9_./+-]+$};

my $W = File::Temp::tempdir("nucpred-XXXXXXXX", DIR => $tmp_root);
my $owner_pid = $$;

$W =~ $SAFE_PATH
   or die "$ME: the temporary directory '$W' has characters in its path that the scripts can't handle.\n"
        . "Set TMPDIR (or PAR_GLOBAL_TMPDIR) to a simpler path.\n";

END { remove_work_tree() if (defined($W) and $$ == $owner_pid); }

# The #! line for the bundled scripts
my $shebang;
if ($packed)
{
   my $exe = Cwd::abs_path($ENV{PAR_PROGNAME} // "");
   (defined($exe) and -f $exe)
      or die "$ME: can't find the path of this executable (PAR_PROGNAME='" . ($ENV{PAR_PROGNAME} // "") . "')\n";

   # Keep the name the program was run with, so that PAR reuses the files it has already unpacked.
   (my $name = File::Basename::basename($ENV{PAR_PROGNAME})) =~ s/[^A-Za-z0-9_.+-]/_/g;
   mkdir("$W/.self") or die "$ME: cannot create '$W/.self': $!\n";
   symlink($exe, "$W/.self/$name") or die "$ME: cannot create '$W/.self/$name': $!\n";

   $shebang = "#!$W/.self/$name --nucpred-perl";
}
else
{
   $^X =~ $SAFE_PATH or die "$ME: can't use perl path '$^X' in a #! line\n";
   $shebang = "#!$^X";
}
length($shebang) <= 250
   or die "$ME: the temporary directory path is too long for a #! line. Set TMPDIR to something shorter.\n";

# Set up $W like an installed copy. The Perl scripts are copied with EXE_BASE_DIR and the #!
# line changed, and everything else is symlinked.
for my $dir ("lib", "bin", "models", "templates", "work")
{
   mkdir("$W/$dir") or die "$ME: cannot create '$W/$dir': $!\n";
}

for my $src ("$bundle/nucleosome_prediction.pl", grep { /\.pl$/ } list_dir("$bundle/lib"))
{
   my $rel = substr($src, length($bundle) + 1);

   open(my $in, "<", $src) or die "$ME: cannot read '$src': $!\n";
   my $text = do { local $/; <$in> };
   close($in);

   $text =~ s/EXE_BASE_DIR/$W/g;
   $text =~ s/\A#![^\n]*perl[^\n]*/$shebang/;

   open(my $out, ">", "$W/$rel") or die "$ME: cannot write '$W/$rel': $!\n";
   print $out $text;
   close($out) or die "$ME: cannot write '$W/$rel': $!\n";
   chmod(0755, "$W/$rel");
}

for my $src (map { list_dir("$bundle/$_") } "lib", "bin", "models", "templates")
{
   next if $src =~ /\.pl$/;
   my $rel = substr($src, length($bundle) + 1);

   if ($rel =~ m{^bin/} and not -x $src)
   {
      # map_learn_static isn't executable in a fresh checkout (when run unpacked), so copy it
      # and make the copy executable rather than changing the original.
      require File::Copy;
      File::Copy::copy($src, "$W/$rel") or die "$ME: cannot copy '$src': $!\n";
      chmod(0755, "$W/$rel");
   }
   else
   {
      symlink($src, "$W/$rel") or die "$ME: cannot link '$W/$rel': $!\n";
   }
}

# Run nucleosome_prediction.pl.
# Put the bundled libraries first so they're used instead of any the user has loaded (e.g. a GSL module).
$ENV{LD_LIBRARY_PATH} = "$W/lib" . ((defined($ENV{LD_LIBRARY_PATH}) and length($ENV{LD_LIBRARY_PATH}) > 0) ? ":$ENV{LD_LIBRARY_PATH}" : "");
$ENV{NUCPRED_WORK_DIR} = "$W/work";

$| = 1;
my $child = fork();
defined($child) or die "$ME: fork failed: $!\n";

if ($child == 0)
{
   open(STDIN, "<", "/dev/null");
   { exec { "$W/nucleosome_prediction.pl" } "$W/nucleosome_prediction.pl", @ARGV; }
   print STDERR "$ME: cannot run '$W/nucleosome_prediction.pl': $!\n";
   POSIX::_exit(127);
}

# On Ctrl-C (or TERM/HUP), kill the whole pipeline and not just nucleosome_prediction.pl,
# then clean up.
my %SIGNO = (INT => POSIX::SIGINT(), TERM => POSIX::SIGTERM(), HUP => POSIX::SIGHUP());
my $caught;
for my $sig (keys %SIGNO)
{
   $SIG{$sig} = sub { $caught //= $sig; kill("TERM", $child, descendants($child)); };
}

waitpid($child, 0);
my $status = $?;

remove_work_tree();

exit(128 + $SIGNO{$caught}) if defined($caught);
exit(($status & 127) ? 128 + ($status & 127) : ($status >> 8));


# Sorted list of the files in $dir. Uses readdir because glob would split paths with spaces.
sub list_dir
{
   my ($dir) = @_;

   opendir(my $dh, $dir) or die "$ME: cannot list '$dir': $!\n";
   my @entries = map { "$dir/$_" } sort grep { !/^\.\.?$/ } readdir($dh);
   closedir($dh);
   return @entries;
}

sub remove_work_tree
{
   return unless (defined($W) and -d $W);

   if ($ENV{NUCPRED_KEEP_TMP})
   {
      print STDERR "$ME: kept work directory $W\n";
   }
   else
   {
      File::Path::remove_tree($W);   # deletes the symlinks, not the files they point to
   }
   undef $W;
}

# All descendants of $root (children, their children and so on), found by reading /proc.
sub descendants
{
   my ($root) = @_;

   my %children;
   opendir(my $proc, "/proc") or return ();
   for my $pid (grep { /^\d+$/ } readdir($proc))
   {
      open(my $fh, "<", "/proc/$pid/stat") or next;
      my $stat = <$fh>;
      close($fh);
      next unless defined($stat);

      # The line is "pid (name) state ppid ...". The name can contain spaces, so start after the last ")".
      my (undef, $ppid) = split(" ", substr($stat, rindex($stat, ")") + 1));
      push(@{ $children{$ppid} }, $pid) if defined($ppid);
   }
   closedir($proc);

   my @result;
   my @queue = ($root);
   while (@queue)
   {
      my $pid = shift(@queue);
      for my $kid (@{ $children{$pid} || [] })
      {
         push(@result, $kid);
         push(@queue, $kid);
      }
   }
   return @result;
}
