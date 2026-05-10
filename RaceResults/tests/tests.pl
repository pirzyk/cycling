#!/usr/bin/env perl

use strict;
use warnings 'all';

use Data::Dumper;
use Test;
use FindBin qw($Bin);
use lib "$Bin/../lib";

# Numbers are:
#   1) is the number of modules we load
#   2) Number of tests for RaceResults module
#   3) Number of tests for RaceResults::DB module
plan tests => 2 + 4 + 10;

# First test the perl modules
use lib ".";
eval "use RaceResults ();";
ok( $@, "", "Cannot load RaceResults module: ($@)" );
eval "use RaceResults::DB ();";
ok( $@, "", "Cannot load RaceResults::DB module: ($@)" );

# Testing RaceResults methods
ok( $RaceResults::BASEDIR, $Bin . '/..', "Failed to set BASEDIR properly ($RaceResults::BASEDIR)" );
ok( $RaceResults::DBDIR, $Bin . '/../db', "Failed to set DBDIR properly ($RaceResults::DBDIR)" );
ok( $RaceResults::INITDIR, $Bin . '/../init', "Failed to set INITDIR properly ($RaceResults::INITDIR)" );
ok( $RaceResults::CACHEDIR, $Bin . '/../cache', "Failed to set CACHEDIR properly ($RaceResults::CACHEDIR)" );

my $txt = "This is the file contents\nfoo\nbar";
open(my $FP, '>tmp.txt') || die "Could not create tmp file (tmp.txt)\n";
printf $FP $txt;
close $FP;
ok( &RaceResults::slurp('tmp.txt'), $txt, "Failed to slurp file" );
unlink 'tmp.txt';

# Testing RaceResults::DB methods
my $file = $RaceResults::DBDIR . '/testDB.sqlite';

# just in case we kept previous test run around
unlink $file;

my $db = RaceResults::DB->new(file => $file, attr => { RaiseError => 0 });
#$db->set_debug(5);
ok( $@, "", "Failed in RaceResults::DB->new({file => $file}) : ($@)" );
ok( -f $file, 1, "Failed to create the DB file ($file) : ($@)" );
$db->init_db();
ok( $@, "", "Failed in $db->init_db() : ($@)" );
ok( -s $file > 0, 1, "DB file is zero ($file) : ($@)" );
ok( exists $db->{tables}, 1, "Could not find the hash of SQL tables");

# get_race_type()
ok( $db->get_race_type('Time Trial'), 1, "Could not fetch the correct key for 'Time Trial' in the race_type table");
ok( $db->get_race_type('Foo'), undef, "Found a key for what we thought was an undefined race_type");

$db->close_db();
ok( $@, "", "Failed in $db->close_db() : ($@)" );
# This should fail, if we did this outside the eval, then the
# tests.pl script stops.  If we don't use the local block, then
# the next test stil has $@ set to this error.
{
    local $@;
    eval { $db->init_db(); };
    ok( $@, qr/^Database not opened!/, "Failed in $db->init_db() : ($@)" );
}
# This second close should be a no-op effectively
$db->close_db();
