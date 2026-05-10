package RaceResults;

use Carp;
use Data::Dumper;
use FindBin;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} });
our @EXPORT = qw();

our $BASEDIR  = "$FindBin::Bin/..";
our $DBDIR    = $BASEDIR . '/db';
our $INITDIR  = $BASEDIR . '/init';
our $CACHEDIR = $BASEDIR . '/cache';

# Slurp in a file and return the contents as a string.
sub slurp {
    my ($file, $type, $split) = @_;
    my ($FP, $txt, @list);

    $type //= 'SCALAR';
    $split //= "\n";

    open($FP, '<' . $file) || croak "Could not open file for reading! ($file)\n";
    local $/; # enable localized slurp mode
    $txt = <$FP>;
    close $FP;

    @list = split($split, $txt) if $type eq 'ARRAY';

    return $type eq 'ARRAY' ? @list : $txt;
}

# Stolen from BikeLog...
# Returns number of seconds from the HH::MM::ss format
sub convert2sec {
    my ($time) = @_;
    return if !defined $time;
    my ($s,$m,$h) = reverse(split(/:/, $time));

    return ($h * 3600.00 + $m * 60.00 + $s);
}

# Returns HH:MM:ss format given seconds
sub convert2time {
    my ($seconds) = @_;

    my $time = sprintf "%2.2d:%2.2d:%2.2d",
                       int($seconds / 3600),
                       ($seconds / 60) % 60,
                       $seconds % 60;
    return $time;
}

sub normalize_string {
    my ($str) = @_;

    return undef if !defined $str;

    # Trim all leading/trailing white spaces.
    #   and reduce all internal tabs/spaces to a single space.
    $str =~ s/^[\s\t]*//;
    $str =~ s/[\s\t]*$//;
    $str =~ s/[\s\t][\s\t]/ /g;

    return $str;
}

sub parse_name {
    my ($name, $name2) = @_;
    my ($first, $last, @l);

    # If we have 2 names passed it, assume it was parsed for us and just do normailzation.

    if (defined $name2) {
        $first = &normalize_string($name);
        $last = &normailize_string($name2);
    } else {
        # The combined name field, usually first last ordered
        if ($name =~ /,/) {
            ($last, $first) = split(/,\s*/, $name);
        } else {
            ($first, @l) = split(/[\s\t]+/, $name);
            $last = join(' ', @l);
        }
        $first = &normalize_string($first);
        $last = &normailize_string($last);
    }

    return $first, $last;
}

1;

