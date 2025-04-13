package BikeLog::Tables::trainer;

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
	[ 'date', 'DATE' ],
	[ 'time', 'TIME' ],
	[ 'fk_bike_id', 'INTEGER', 'NOT NULL CONSTRAINT fk_trainer_bike_id REFERENCES bike(id) ON DELETE CASCADE' ],
	[ 'note', 'TEXT' ],
	[ 'cadence', 'INTEGER' ],
	[ 'power', 'INTEGER' ],
);

sub create {
	&BikeLog::Tables::create( 'trainer', @schema );

	# Triggers for the bike field in the trainer table
	&BikeLog::Tables::create_fk_triggers('trainer', 'fk_bike_id', 'bike', 'id');

	&BikeLog::Tables::create_date_triggers( 'time', 'date');
	&BikeLog::Tables::create_time_triggers( 'time', 'time');
}

sub insert {
	my (@what) = @_;
	debug ("In BikeLog::Tables::trainer::insert([" . join(',', @what) . "])", 1);

	die "Need " . ( scalar @schema ). " value(s) to insert into trainer table\n\tDate Time Bike Notes Cadence Power\n"
		if ( scalar @what != scalar @schema );

	# Massage the date field (today or yesterday)
	$what[0] = &BikeLog::Tables::convert_date($what[0]);

	# Massage the bike field.
	$what[2] = &BikeLog::Tables::get_key('bike', 'name', $what[2]);

	&BikeLog::Tables::insert('trainer', @what);
}

sub report {
	my (@args) = @_;
	my ($sql, $groupby, @totals);

	my $arg = shift @args;

	# The summary options.
	if ( defined $arg and $arg eq 'time' ) {
		my ($time) = &BikeLog::Tables::get_data('trainer', 'time', @args);

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
	} elsif ( !defined $arg || $arg eq 'this' || $arg eq 'last' || $arg eq 'year' || $arg eq 'month' || $arg eq 'start' || $arg eq 'end' ) {

		unshift @args, $arg if ( defined $arg );

		my (@f, @t, @w, %j, @s);
		# Get the schema from the other module's tables
		my (@polar_schema) = &BikeLog::Tables::_get_schema('polar');
		my (@netathlon2_schema) = &BikeLog::Tables::_get_schema('netathlon2');

		# Build the schema for our query result
		push @s, @schema[&BikeLog::Tables::_find_schema_field('date', \@schema)];
		push @s, @schema[&BikeLog::Tables::_find_schema_field('time', \@schema)];
		push @s, ( ['bike', 'TEXT'] );
		push @s, ( ['weight', 'REAL'] );
		push @s, @polar_schema[&BikeLog::Tables::_find_schema_field('hr', \@polar_schema)];
		push @s, ( ['zone', 'INTEGER'] );
		push @s, @polar_schema[&BikeLog::Tables::_find_schema_field('max', \@polar_schema)];
		push @s, @polar_schema[&BikeLog::Tables::_find_schema_field('calories', \@polar_schema)];
		push @s, ( ['cal/hr', 'INTEGER'] );
		push @s, ( ['zone', 'INTEGER'] );
		push @s, ( ['power', 'INTEGER' ] );
		push @s, ( ['zone', 'INTEGER'] );
		push @s, ( ['cadence', 'INTEGER' ] );
		push @s, @schema[&BikeLog::Tables::_find_schema_field('note', \@schema)];

		$sql = 'SELECT trainer.date,trainer.time,bike.name,weight.weight,polar.hr,polar.max,polar.calories,polar.time,trainer.power,trainer.cadence,trainer.note
			FROM trainer
			LEFT JOIN bike ON trainer.fk_bike_id = bike.id
			LEFT JOIN weight ON trainer.date = weight.date
			LEFT JOIN polar ON trainer.date = polar.date AND trainer.time = polar.time
		';
		($sql, $groupby) = &BikeLog::Tables::process_date('trainer', $sql, @args) if ( scalar @args );
		my $data = &BikeLog::Tables::_sql($sql, 1);

		# Add the speed, Calories per Hour and training zone columns and calculate totals.
		&BikeLog::Tables::update_data($data, \@totals, {
			TIME => 1,
			WEIGHT => 3,
			HR => 4,
			CALORIES => 7,
			CALORIETIME => 8,
			KcalPH => 8,
			POWER => 10,
			CADENCE => 12,
			MAX => [ 6, 8, 10 ],
		});

		&BikeLog::Tables::print_results( $data, \@s, \@totals );

	# barf
	} else {
		die "Don't understand 'report trainer $arg'\n";
	}
}

sub graph {
	my (@args) = @_;
	my ($type) = shift @args;
	die "Don't understand 'graph trainer $type'\n" if ( $type ne 'time' );
	my ($time) = &BikeLog::Tables::get_data('trainer', 'time', @args);
	my (@data, @k, @d, %totals);
	map {
		push @d, $time->{$_}->{'sum'};
		$totals{'Total Trainer Time'} += $time->{$_}->{'sum'};
	} sort keys %{$time};
	@k = sort keys %{$time};
	@data = ( [ @k ], [ @d ] );

	map {
		$totals{$_} = &BikeLog::Tables::convert_seconds($totals{$_});
	} keys %totals;

	&BikeLog::Tables::create_graph(
		'trainer',
		'Trainer Time',
		'Month',
		'Time (HH:MM:SS)',
		undef,
		'trainer',
		\%totals,
		@data,
	);
}

1;

__END__
