package BikeLog::Tables::race;

use strict;
#use warnings;

use FindBin;
use Data::Dumper;
use lib "$FindBin::Bin/../lib";
use POSIX;

use BikeLog;
use BikeLog::Tables;

require Exporter;
our @ISA         = qw (BikeLog::Tables);
our %EXPORT_TAGS = ( 'all' => [qw( create insert )] );
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT      = qw();

our @schema = (
	[ 'id', 'INTEGER', 'PRIMARY KEY AUTOINCREMENT' ],
	[ 'date', 'DATE' ],
	[ 'distance', 'REAL' ],
	[ 'fk_unit_id', 'INTEGER', 'NOT NULL CONSTRAINT fk_race_unit_id REFERENCES unit(id) ON DELETE CASCADE' ],
	[ 'time', 'TIME' ],
	[ 'fk_bike_id', 'INTEGER', 'NOT NULL CONSTRAINT fk_race_bike_id REFERENCES bike(id) ON DELETE CASCADE' ],
	[ 'power', 'INTEGER' ],
	[ 'note', 'TEXT' ],
);

sub create {
	&BikeLog::Tables::create( 'race', @schema );

	# Triggers for the bike field in the race table
	&BikeLog::Tables::create_fk_triggers('race', 'fk_bike_id', 'bike', 'id');

	# Triggers for the unit field in the race table
	&BikeLog::Tables::create_fk_triggers('race', 'fk_unit_id', 'unit', 'id');

	&BikeLog::Tables::create_date_triggers( 'race', 'date');
	&BikeLog::Tables::create_time_triggers( 'race', 'time');
}

sub insert {
	my (@what) = @_;
	debug ("In BikeLog::Tables::race::insert([" . join(',', @what) . "])", 1);

	die "Need " . ( scalar @schema -1 ). " value(s) to insert into race table\n\tDate Distance (Mi/Km) Time Bike Notes Power(Watts)\n"
		if ( scalar @what != (scalar @schema -1 ) );

	# Massage the date field (today or yesterday)
	$what[0] = &BikeLog::Tables::convert_date($what[0]);

	# Massage the unit field (km or mi)
	$what[2] = &BikeLog::Tables::get_key('unit', 'name', $what[2]);

	# Massage the bike field inserting new bike if we need to.
	$what[4] = &BikeLog::Tables::get_key('bike', 'name', $what[4]);

	&BikeLog::Tables::insert('race(date,distance,fk_unit_id,time,fk_bike_id,note,power)', @what);
}

sub report {
	my (@args) = @_;
	my ($sql, $type, $groupby);

	my $arg = shift @args;

	# The summary options.
	if ( $arg eq 'mileage' || $arg eq 'distance' ) {
		$type = $arg;
		$sql = 'SELECT SUM(distance),fk_unit_id FROM race';

		($sql, $groupby) = &BikeLog::Tables::process_date('race', $sql, @args) if ( scalar @args );
		$sql .= ' GROUP BY fk_unit_id ORDER BY SUM(distance) DESC';

		# Get the unit loopup table.
		my $u = &BikeLog::Tables::_sql('SELECT * FROM unit', 1);

		# Run the SQL
		my $data = &BikeLog::Tables::_sql($sql, 1);
		my ($total, %unit, $default_unit);

		# Look for our default unit type
		foreach my $row ( @{$u} ) {
			$unit{$row->[0]} = $row->[1];
			if ( $type eq 'mileage' && $row->[1] eq 'Mi' ) {
				$default_unit = $row->[0];
			}
		}

		foreach my $row ( @{$data} ) {

			# if we don't have a default unit type, then take the first one,
			# which will be the largest one, since we ordered by
			# SUM(distance) DESC;
			$default_unit = $row->[1]
				if ( ! defined $default_unit );

			if ( $default_unit == $row->[1] ) {
				$total += $row->[0];
			} else {
				$total += &BikeLog::Tables::convert_unit($row->[1], $default_unit, $row->[0]);
			}
		}

		print "$total"
			.  ($type eq 'distance'
				? ' ' . $unit{$default_unit}
				: '')
			.  "\n";

	# The full report
	} elsif ( $arg eq 'this' || $arg eq 'year' || $arg eq 'month' || $arg eq 'start' || $arg eq 'end' || ! defined $arg ) {

		unshift @args, $arg if ( defined $arg );

		my (@f, @t, @w, %j, @s);
		# Get the schema from the other module's tables
		my (@polar_schema) = &BikeLog::Tables::_get_schema('polar');

		# Build the schema for our query result
		push @s, @schema[&BikeLog::Tables::_find_schema_field('date', \@schema)];
		push @s, @schema[&BikeLog::Tables::_find_schema_field('distance', \@schema)];
		push @s, ( ['unit', 'TEXT'] );
		push @s, @schema[&BikeLog::Tables::_find_schema_field('time', \@schema)];
		push @s, ( ['speed', 'REAL'] );
		push @s, ( ['unit', 'TEXT'] );
		push @s, ( ['bike', 'TEXT'] );
		push @s, ( ['weight', 'INTEGER'] );
		push @s, @polar_schema[&BikeLog::Tables::_find_schema_field('hr', \@polar_schema)];
		push @s, ( ['zone', 'INTEGER'] );
		push @s, @polar_schema[&BikeLog::Tables::_find_schema_field('max', \@polar_schema)];
		push @s, @polar_schema[&BikeLog::Tables::_find_schema_field('calories', \@polar_schema)];
		push @s, ( ['cal/hr', 'INTEGER'] );
		push @s, ( ['zone', 'INTEGER'] );
		push @s, @schema[&BikeLog::Tables::_find_schema_field('power', \@schema)];
		push @s, ( ['zone', 'INTEGER'] );
		push @s, @schema[&BikeLog::Tables::_find_schema_field('note', \@schema)];

		$sql = 'SELECT race.date,race.distance,unit.name,race.time,bike.name,weight.weight,polar.hr,polar.max,polar.calories,polar.time,race.power,race.note
			FROM race
			LEFT JOIN unit ON race.fk_unit_id = unit.id
			LEFT JOIN bike ON race.fk_bike_id = bike.id
			LEFT JOIN weight ON race.date = weight.date
			LEFT JOIN polar ON race.date = polar.date
		';
		($sql, $groupby) = &BikeLog::Tables::process_date('race', $sql, @args) if ( scalar @args );
		my $data = &BikeLog::Tables::_sql($sql, 1);
		my (@totals);

		# Add the speed, Calories per Hour and training zone columns and calculate totals.
		&BikeLog::Tables::update_data($data, \@totals, {
			DISTANCE => 1,
			TIME => 3,
			SPEED => 4,
			WEIGHT => 7,
			HR => 8,
			CALORIES => 11,
			CALORIETIME => 12,
			KcalPH => 12,
			POWER => 14,
			MAX => [ 10, 12, 14 ],
		});

		&BikeLog::Tables::print_results( $data, \@s, \@totals );

	# barf
	} else {
		die "Don't understand 'report race $arg'\n";
	}
}

1;

__END__
