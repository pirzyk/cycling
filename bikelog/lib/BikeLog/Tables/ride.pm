package BikeLog::Tables::ride;

use strict;
use warnings;

use FindBin;
use Data::Dumper;
use lib "$FindBin::Bin/../lib";

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
	[ 'fk_unit_id', 'INTEGER', 'NOT NULL CONSTRAINT fk_ride_unit_id REFERENCES unit(id) ON DELETE CASCADE' ],
	[ 'time', 'TIME' ],
	[ 'fk_bike_id', 'INTEGER', 'NOT NULL CONSTRAINT fk_ride_bike_id REFERENCES bike(id) ON DELETE CASCADE' ],
	[ 'note', 'TEXT' ],
	[ 'max', 'REAL' ],
);

our @with_schema = (
	[ 'id', 'INTEGER', 'NOT NULL PRIMARY KEY AUTOINCREMENT' ],
	[ 'name', 'TEXT', 'UNIQUE NOT NULL' ],
);

our @link_with_schema = (
	[ 'fk_ride_id', 'INTEGER', 'NOT NULL CONSTRAINT fk_link_with_ride_id REFERENCES ride(id) ON DELETE CASCADE' ],
	[ 'fk_with_id', 'INTEGER', 'NOT NULL CONSTRAINT fk_link_with_with_id REFERENCES with(id) ON DELETE CASCADE' ],
);

sub create {
	&BikeLog::Tables::create( 'ride', @schema );
	&BikeLog::Tables::create( 'with', @with_schema );
	&BikeLog::Tables::create( 'link_with', @link_with_schema );

	# FIXME: SQLite does not support foreign keys completely w/o triggers
	# so setup the triggers

	# Triggers for the bike field in the ride table
	&BikeLog::Tables::create_fk_triggers('ride', 'fk_bike_id', 'bike', 'id');

	# Triggers for the unit field in the ride table
	&BikeLog::Tables::create_fk_triggers('ride', 'fk_unit_id', 'unit', 'id');

	# Triggers for the ride field in the link_with table
	&BikeLog::Tables::create_fk_triggers('link_with', 'fk_ride_id', 'ride', 'id');

	# Triggers for the with field in the link_with table
	&BikeLog::Tables::create_fk_triggers('link_with', 'fk_with_id', 'with', 'id');

	&BikeLog::Tables::create_date_triggers( 'ride', 'date');
	&BikeLog::Tables::create_time_triggers( 'ride', 'time');
}

sub insert {
	my (@what) = @_;
	debug ("In BikeLog::Tables::ride::insert([" . join(',', @what) . "])", 1);

	die "Need " . ( scalar @schema ). " value(s) to insert into ride table\n\tDate Distance (Mi/Km) Time With Bike Notes MaxSpeed\n"
		if ( scalar @what != (scalar @schema ) );

	# Massage the date field (today or yesterday)
	$what[0] = &BikeLog::Tables::convert_date($what[0]);

	# Massage the unit field (km or mi)
	$what[2] = &BikeLog::Tables::get_key('unit', 'name', $what[2]);

	# Lookup if we have already stored our with entry
	# Save the people who we road with, we will insert them
	# into the with table and insert a record into the link_with table
	# after our ride insert (need the ride_id for the link_with table).
	my @with = split('/', $what[4]);
	splice (@what, 4, 1);

	# Massage the bike field inserting new bike if we need to.
	$what[4] = &BikeLog::Tables::get_key('bike', 'name', $what[4]);

	&BikeLog::Tables::insert('ride(date,distance,fk_unit_id,time,fk_bike_id,note,max)', @what);

	# Now get the ride_id of the record we just inserted.
	my $ride_id = &BikeLog::Tables::_sql("SELECT id FROM ride WHERE date = \"$what[0]\" AND distance = \"$what[1]\" AND time = \"$what[3]\"", "SCALAR");

	# Now go back and setup the with and link_with tables.
	foreach my $w ( @with ) {
		my $with_id = &BikeLog::Tables::get_key('with', 'name', $w);
		&BikeLog::Tables::insert('link_with(fk_ride_id,fk_with_id)', $ride_id, $with_id);
	}
}

sub report {
	my (@args) = @_;
	my ($sql, $type, $groupby, @totals);

	my $arg = shift @args;

	if ( defined $arg and ($arg eq 'mileage' or $arg eq 'distance')) {
		my ($data) = &BikeLog::Tables::get_data('ride', 'distance', @args);

		if ( ref $data eq 'HASH' ) {
			my (@s) = ( ['GroupBy', 'INTEGER'], ['Count', 'INTEGER'], ['Distance', 'REAL']);
			my (@l) = ( 7, 7, 9 );
			&BikeLog::Tables::print_header(\@s, \@l);
			map {
				$totals[1] += $data->{$_}->{'count'};
				$totals[2] += $data->{$_}->{'sum'};
				printf "%s\t%d\t%s\n", $_, $data->{$_}->{'count'}, $data->{$_}->{'sum'};
			} sort keys %{$data};
			&BikeLog::Tables::print_hr(\@s, \@l);
			printf "Totals\t%d\t%.2lf\n", $totals[1], $totals[2];
		} elsif (defined $data) {
			print $data . "\n";
		}

	# The summary options.
	} elsif ( defined $arg and $arg eq 'time' ) {
		my $time = BikeLog::Tables::get_data('ride', $arg, @args);
		if ( ref $time eq 'HASH' ) {
			my (@s) = ( ['GroupBy', 'INTEGER'], ['Count', 'INTEGER'], ['Time', 'TIME']);
			my (@l) = ( 7, 7, 9 );
			&BikeLog::Tables::print_header(\@s, \@l);
			map {
				$totals[1] += $time->{$_}->{'count'};
				$totals[2] += $time->{$_}->{'sum'};
				printf "%s\t%d\t%s\n", $_, $time->{$_}->{'count'}, &BikeLog::Tables::convert_seconds($time->{$_}->{'sum'});
			} sort keys %{$time};
			&BikeLog::Tables::print_hr(\@s, \@l);
			printf "Totals\t%d\t%s\n", $totals[1], &BikeLog::Tables::convert_seconds($totals[2]);
		} else {
			print &BikeLog::Tables::convert_seconds($time) . "\n";
		}

	# The full report
	} elsif (!defined $arg or $arg eq 'this' or $arg eq 'last' or $arg eq 'year' or $arg eq 'month' or $arg eq 'start' or $arg eq 'end') {

		unshift @args, $arg if ( defined $arg );

		my (@f, @t, @w, %j, @s);
		# Get the schema from the other module's tables
		my (@unit_schema) = &BikeLog::Tables::_get_schema('unit');
		my (@polar_schema) = &BikeLog::Tables::_get_schema('polar');

		# Build the schema for our query result
		push @s, @schema[&BikeLog::Tables::_find_schema_field('date', \@schema)];
		push @s, @schema[&BikeLog::Tables::_find_schema_field('distance', \@schema)];
		push @s, ( ['unit', 'TEXT'] );
		push @s, @schema[&BikeLog::Tables::_find_schema_field('time', \@schema)];
		push @s, ( ['speed', 'REAL'] );
		push @s, ( ['unit', 'TEXT'] );
		push @s, ( ['max', 'REAL'] );
		push @s, ( ['bike', 'TEXT'] );
		push @s, ( ['weight', 'REAL'] );
		push @s, @polar_schema[&BikeLog::Tables::_find_schema_field('hr', \@polar_schema)];
		push @s, ( ['zone', 'INTEGER'] );
		push @s, @polar_schema[&BikeLog::Tables::_find_schema_field('max', \@polar_schema)];
		push @s, @polar_schema[&BikeLog::Tables::_find_schema_field('calories', \@polar_schema)];
		push @s, ( ['cal/hr', 'INTEGER'] );
		push @s, ( ['zone', 'INTEGER'] );
		push @s, ( ['with', 'TEXT'] );
		push @s, @schema[&BikeLog::Tables::_find_schema_field('note', \@schema)];

		$sql = 'SELECT ride.date,ride.distance,unit.name,ride.time,ride.max,bike.name,weight.weight,polar.hr,polar.max,polar.calories,polar.time,ride.id,ride.note
			FROM ride
			LEFT JOIN unit ON ride.fk_unit_id = unit.id
			LEFT JOIN bike ON ride.fk_bike_id = bike.id
			LEFT JOIN weight ON ride.date = weight.date
			LEFT JOIN polar ON ride.date = polar.date';
		($sql, $groupby) = &BikeLog::Tables::process_date('ride', $sql, @args) if ( scalar @args );
		my $data = &BikeLog::Tables::_sql($sql, 1);

		# replace the ride.id field (12) with the array of people I rode with
		map {
			my $with = &BikeLog::Tables::_sql ("
				SELECT name
				FROM with
				JOIN link_with ON with.id = link_with.fk_with_id 
					AND link_with.fk_ride_id == ${$_}[11]",
			'ARRAY');
			${$_}[11] = join ('/', @$with);
		} @{$data};

		# Add the speed, Calories per Hour and training zone columns and calculate totals.
		&BikeLog::Tables::update_data($data, \@totals, {
			DISTANCE => 1,
			TIME => 3,
			SPEED => 4,
			WEIGHT => 8,
			HR => 9,
			CALORIES => 12,
			CALORIETIME => 13,
			KcalPH => 13,
			MAX => [ 6, 11, 13 ],
		});

		&BikeLog::Tables::print_results( $data, \@s, \@totals );

	# barf
	} else {
		die "Don't understand 'report ride $arg'\n";
	}
}

sub graph {
	my (@args) = @_;
	my (@data, @k, @d, @t, %totals);

	my ($d2) = &BikeLog::Tables::get_data('ride', 'distance', @args);
	my ($t2) = &BikeLog::Tables::get_data('ride', 'time', @args);

	map {
		push @d, $d2->{$_}->{'sum'};
		$totals{'Total Ride Disance'} += $d2->{$_}->{'sum'};
		push @t, $t2->{$_}->{'sum'};
		$totals{'Total Ride Time'} += $t2->{$_}->{'sum'};
	 } sort keys %{$d2};

	$totals{'Total Ride Time'} = &BikeLog::Tables::convert_seconds($totals{'Total Ride Time'});

	@k = sort keys %{$d2};
	@data = ( [ @k ], [ @d ], [ @t ]  );

	&BikeLog::Tables::create_graph(
		'ride',
		'Ride Distance and Time',
		'Month',
		'Mileage',
		'Time (HH:MM:SS)',
		'ride',
		\%totals,
		@data,
	);
}
1;

__END__
