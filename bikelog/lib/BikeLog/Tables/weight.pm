package BikeLog::Tables::weight;

use strict;
#use warnings;

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
	[ 'weight', 'INTEGER' ],
	[ 'fk_unit_id', 'INTEGER', 'NOT NULL CONSTRAINT fk_weight_unit_id REFERENCES unit(id) ON DELETE CASCADE' ],
);

sub create {
	BikeLog::Tables::create( 'weight', @schema );

	# Triggers for the unit field in the weight table
	&BikeLog::Tables::create_fk_triggers('weight', 'fk_unit_id', 'unit', 'id');

	&BikeLog::Tables::create_date_triggers( 'weight', 'date');
}

sub insert {
	my (@what) = @_;
	debug ("In BikeLog::Tables::weight::insert([" . join(',', @what) . "])", 1);

	die "Need " . ( scalar @schema ). " value(s) to insert into weight table\n\tDate Weight (LBs/Kg)\n"
		if ( scalar @what != (scalar @schema ) );

	# Massage the date field (today or yesterday)
	$what[0] = &BikeLog::Tables::convert_date($what[0]);

	# Massage the unit field (kg or lbs)
	$what[2] = &BikeLog::Tables::get_key('unit', 'name', $what[2]);

	&BikeLog::Tables::insert('weight(date,weight,fk_unit_id)', @what);
}

sub graph {
	my (@args) = @_;
	my $sql = 'SELECT weight,date FROM weight';
	my ($groupby, @d, @w);

	($sql, $groupby) = &BikeLog::Tables::process_date('weight', $sql, @args) if ( scalar @args );

	map {
		push @w, $_->[0];
		push @d, $_->[1];
	} @{&BikeLog::Tables::_sql($sql, 1)};
	my @data = ( [ @d ], [ @w ], );

	&BikeLog::Tables::create_graph(
		'weight',
		'Weight',
		'Date',
		'LBs',
		undef,
		'weight',
		undef,
		@data,
	);
}

1;

__END__
