package BikeLog::Tables::polar;

use strict;
use warnings;

use FindBin;
use Data::Dumper;
use lib "$FindBin::Bin/../lib";

use BikeLog;
use BikeLog::Tables;

require Exporter;
our @ISA         = qw (BikeLog::Tables);
our %EXPORT_TAGS = ( 'all' => [qw( create )] );
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT      = qw();

our @schema = (
	[ 'date', 'DATE', 'PRIMARY KEY' ],
	[ 'hr', 'INTEGER' ],
	[ 'calories', 'INTEGER' ],
	[ 'time', 'TIME' ],
	[ 'max', 'INTEGER' ],
);

sub create {
	&BikeLog::Tables::create( 'polar', @schema );

	&BikeLog::Tables::create_date_triggers( 'polar', 'date');
	&BikeLog::Tables::create_time_triggers( 'polar', 'time');
}

sub insert {
	my (@what) = @_;
	debug ("In BikeLog::Tables::polar::insert([" . join(',', @what) . "])", 1);

	die "Need " . ( scalar @schema ). " value(s) to insert into polar table\n\tDate HeartRate Calories Time MaxHeartRate\n"
		if ( scalar @what != (scalar @schema ) );

	# Massage the date field (today or yesterday)
	$what[0] = &BikeLog::Tables::convert_date($what[0]);

	&BikeLog::Tables::insert('polar', @what);
}

sub graph {
	my (@args) = @_;
	my ($title, @d, @k);

	my ($type) = shift @args;
	die "Don't understand 'graph polar $type'\n" if ( $type ne 'calories' && $type ne 'cph' );

	my $d2 = &BikeLog::Tables::get_data('polar', 'calories', @args);

	map {
		push @d, $d2->{$_}->{'sum'};
	} sort keys %{$d2};

	@k = sort keys %{$d2};

	my @data = ( [ @k ], [ @d ], );

	&BikeLog::Tables::create_graph(
		'polar',
		($type eq 'calories' ? 'Calories' : 'Calories per Hour'),
		'Month',
		($type eq 'calories' ? 'Calories' : 'Cal/Hr'),
		undef,
		$type,
		undef,
		@data,
	);
}

sub report {
	my (@args) = @_;
	my ($sql, $type, $groupby);

	$sql = 'SELECT polar.date,time,weight,hr,max,calories,time
		FROM polar
		LEFT JOIN weight ON polar.date = weight.date';

	($sql, $groupby) = &BikeLog::Tables::process_date('polar', $sql, @args) if ( scalar @args );
	my $data = &BikeLog::Tables::_sql($sql, 1);
	my (@totals, @s);

	my (@polar_schema) = &BikeLog::Tables::_get_schema('polar');

	push @s, @schema[&BikeLog::Tables::_find_schema_field('date', \@polar_schema)];
	push @s, @schema[&BikeLog::Tables::_find_schema_field('time', \@polar_schema)];
	push @s, ( ['weight', 'INTEGER'] );
	push @s, @schema[&BikeLog::Tables::_find_schema_field('hr', \@polar_schema)];
	push @s, ( ['zone', 'INTEGER'] );
	push @s, @schema[&BikeLog::Tables::_find_schema_field('max', \@polar_schema)];
	push @s, @schema[&BikeLog::Tables::_find_schema_field('calories', \@polar_schema)];
	push @s, ( ['cal/hr', 'INTEGER'] );
	push @s, ( ['zone', 'INTEGER'] );
	&BikeLog::Tables::update_data($data, \@totals, {
		TIME => 1,
		WEIGHT => 2,
		HR => 3,
		CALORIES => 6,
		CALORIETIME => 7,
		KcalPH => 7,
		MAX => [ 5, 7 ],
	});

	&BikeLog::Tables::print_results( $data, \@s, \@totals );
}

1;

__END__
