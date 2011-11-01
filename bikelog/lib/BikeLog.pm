package BikeLog;

use strict;
use warnings;
require Exporter;

use FindBin;
use lib "$FindBin::Bin/../lib";

our @ISA         = qw (Exporter);
our %EXPORT_TAGS = ( 'all' => [qw( debug set_debug noop set_noop load_module )] );
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT      = qw( debug );

our $debug = -1;
our $noop = 0;

sub set_noop {
	$noop = 1;
	&set_debug(4);
}

sub noop {
	return $noop;
}

sub set_debug {
	my ($val) = @_;

	$debug += ($val =~ /^\d+$/? $val: 1);
}

sub debug {
	my ($msg, $level) = @_;

	printf STDERR "%s$msg\n", "\t" x $level
		if ( $debug >= $level );
}

sub load_module {
	my ($module) = @_;
	debug ("BikeLog::load_module($module)", 4);

	my $code = "use BikeLog::Tables::$module;";
	eval $code;
	die "Could not load module $module ($@)\n" if ( $@ );
}

sub max_min {
	my (@list) = @_;
	my ($max, $min) = (-1, 1000000000000);

	map {
		$max = ($_ > $max ? $_ : $max);
		$min = ($_ < $min ? $_ : $min);
	} @list;

	return ($max, $min);
}

1;

__END__
