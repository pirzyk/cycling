#!/usr/bin/env perl

use strict;
use warnings;
use POSIX;

my $idir = '/wordpress/static/mileage';
my $iext = 'png';

sub usage {
	if ( $0 =~ /_mileage_/ ) {
		warn "Usage: $0 MILEAGE\n";
		warn "\tMILEAGE needs to be a real number\n";
	} elsif ( $0 =~ /_time_/ ) {
		warn "Usage: $0 TIME\n";
		warn "\tTIME needs to be in H+:MM:SS format\n";
	}
	exit 0;
}

&usage() if ( scalar @ARGV != 1 || 
	( $0 =~ /_mileage_/ && $ARGV[0] !~ /^\d+(\.\d+)?$/ ) ||
	( $0 =~ /_time_/ && $ARGV[0] !~ /^\d+:\d{2}:\d{2}$/ )
);

my $cnt = 0;
sub print_digit {
	my ($digit, $flag) = @_;
	my ($str);

	printf "document.write(\"<img src=\\\"%s/%s%s.%s\\\" alt=\\\"%s%s\\\">\");\n",
		$idir,
		$digit,
		($flag == 1? 'inv': ''),
		$iext,
		($flag == 1 && !$cnt? '.': ''),
		$digit;

		$cnt++ if ( $flag );
}

# Figure out what the graph file is.
my $year = strftime("%Y", localtime());
my $file = $idir . '/bikelog.' . ($0 =~ /_mileage_/ ? 'ride' : 'trainer') . '.' . $year . '.' . $iext;
my $ofile = $idir . '/bikelog.' . ($0 =~ /_mileage_/ ? 'ride' : 'trainer') . '.' . ($year - 1) . '.' . $iext;

# If we have 0 for time/mileage, do not create a hyperlink.
print "document.write(\"<a href=\\\"$file\\\">\");\n"
	if ( $ARGV[0] !~ /^0+([.:]0+(:0+)?)?$/ );

my $dot=0;
if ($0 =~ /_mileage_/ ) {
	foreach my $ch ( split //, $ARGV[0] ) {
		if ( $ch eq '.' ) {
			$dot = 1;
		} else {
			print_digit($ch, $dot);
		}
	}
} else {
	print "document.write(\"$ARGV[0]\");\n";
}
print "document.write(\"</a>\");\n"
	if ( $ARGV[0] !~ /^0+([.:]0+(:0+)?)?$/ );

# Write out link to last year's data
print "document.write(\"<br aligin=\\\"right\\\"><font size=-2><a href=\\\"$ofile\\\">Last Year</a></font>\");\n";

exit 0;
