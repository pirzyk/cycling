#!/usr/bin/env perl

use strict;
use warnings 'all';

use Carp;
use Data::Dumper;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use RaceResults;
use RaceResults::DB;

sub usage {
    print "Usage: $0 [--debug=N] [--short] --db <DATABASE_NAME> --table <TABLE> <PRIMARY NAME> <ALTERNATE NAME>\n";
    print "\t--db DB\t\tThe SQLite Database (REQUIRED)\n";
    print "\t--short \t\tUse the alternate name for the abbreviation field (only applicable for team table updates)\n";
    print "\t--table TABLE\tWhat table to do the merge in (REQUIRED) currently only team or racer supported\n";
    print "<PRIMARY NAME> will be the official name we use going forward\n";
    print "<ALTERNATE NAME> will be put into the alias table for future lookups\n";
    exit 1; 
}           

my ($WHO, $table, $short, $db);
my $debug = 0;

&Getopt::Long::Configure ("bundling");
GetOptions (
    'db=s'      => \$WHO,
    'table=s'   => \$table,
    'short'     => \$short,
    'debug=i'   => \$debug,
) || usage();

usage() if scalar @ARGV != 2 or !defined $WHO or !defined $table or not ($table eq 'racer' or $table eq 'team');

my ($primary, $alias) = ($ARGV[0], $ARGV[1]);

$db = RaceResults::DB->new(
            file => $RaceResults::DBDIR . '/' . $WHO . '.sqlite',
            debug => $debug
         );

if ($table eq 'team') {
    $db->merge_team($primary, $alias, $short);
} else {
    $db->merge_racer($primary, $alias);
}
$db->close_db;
