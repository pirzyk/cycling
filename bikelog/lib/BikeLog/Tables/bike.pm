package BikeLog::Tables::bike;

use strict;
#use warnings;

use FindBin;
use Data::Dumper;
use lib "$FindBin::Bin/../lib";

use BikeLog;
use BikeLog::Tables;

require Exporter;
our @ISA         = qw (BikeLog::Tables);
our %EXPORT_TAGS = ( 'all' => [qw( create add_module set_zone )] );
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT      = qw();

our @bike_schema = (
	[ 'id', 'INTEGER', 'NOT NULL PRIMARY KEY AUTOINCREMENT' ],
	[ 'name', 'TEXT', 'UNIQUE NOT NULL' ],
	[ 'serial', 'TEXT' ],
);

our @unit_schema = (
	[ 'id', 'INTEGER', 'PRIMARY KEY AUTOINCREMENT' ],
	[ 'name', 'TEXT' ],
);

our @module_schema = (
	[ 'name', 'TEXT', 'PRIMARY KEY' ]
);

our @zone_schema = (
	[ 'zone', 'INTEGER', 'PRIMARY KEY' ],
	[ 'hr', 'INTEGER' ],
	[ 'power', 'INTEGER' ],
	[ 'calorie', 'INTEGER' ],
);

sub create {
	debug ("In BikeLog::Tables::bike::create()", 1);

	&BikeLog::Tables::create( 'module', @module_schema );
	&BikeLog::Tables::create( 'bike', @bike_schema );
	&BikeLog::Tables::create( 'unit', @unit_schema );
	&BikeLog::Tables::create( 'zone', @zone_schema );

	# setup the zone table entries
	for (my $i = 0; $i <= 6; $i++ ) {
		&BikeLog::Tables::_sql ("INSERT INTO zone VALUES ($i, -1, -1, -1)");
	}

	# Preload the unit tables with some values
	&BikeLog::Tables::insert('unit(unit)', 'Mi');
	&BikeLog::Tables::insert('unit(unit)', 'Km');
	&BikeLog::Tables::insert('unit(unit)', 'LBs');
	&BikeLog::Tables::insert('unit(unit)', 'Kg');
}

sub insert {
	my (@what) = @_;
	debug ("In BikeLog::Tables::bike::insert([" . join(',', @what) . "])", 1);

	die "Need 2 value(s) to insert into bike table\n\tName Serial\n"
		if ( scalar @what != 2 );

	&BikeLog::Tables::insert('bike(name,serial)', @what);
}

sub add_module {
	my ($module) = @_;
	debug ("In BikeLog::Tables::bike::add_module($module)", 0);

	# When enabling a module, first add it to the module table
	# If it is already there, just ignore it, since it is a single
	# tuple table.
	&BikeLog::Tables::_sql(
		"INSERT OR IGNORE INTO module(name) VALUES (\"$module\")"
	);

	# Now load the perl module
	&BikeLog::load_module($module);

	# Then create the table in the database.
	my $code = 'BikeLog::Tables::' . $module . '::create';
	{ no strict; &{$code}(); }
}

sub set_zone {
	my ($what, $value) = @_;
	debug ("In BikeLog::Table::zone::set($what, $value)", 2);

	# Determine if we don't have a valid field name...
	my @f;
	foreach my $field ( @zone_schema ) {
		push @f, ${$field}[0]
			if ( ${$field}[0] ne 'zone' );
	} 
	die "Don't understand $what, needs to be one of the following:\n\t" . join ("\n\t", @f) . "\n"
		if ( ! grep (/$what/, @f) );

	# The MAX value will be stored at
	my (@values);

	# Percentage ranges based on Garmin software
	# Calculate the zone min values based on the percentage of MAX.
	$values[0] = 0;
	$values[1] = int(.5 * $value);	# Recovery
	$values[2] = int(.6 * $value);
	$values[3] = int(.7 * $value);
	$values[4] = int(.8 * $value);
	$values[5] = int(.9 * $value);
	$values[6] = $value;			# Max

	for (my $i = 0; $i < scalar @values; $i++ ) {
		&BikeLog::Tables::_sql(
			"UPDATE OR REPLACE zone SET $what = $values[$i] WHERE zone = $i"
		);
	}
}

1;

__END__
