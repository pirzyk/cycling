package BikeLog::Tables::netathlon2;

use strict;
use warnings;

use FindBin;
use Data::Dumper;
use NetAthlon2::RAW;
use POSIX;
use lib "$FindBin::Bin/../lib";

use BikeLog;
use BikeLog::Tables;

require Exporter;
our @ISA         = qw (BikeLog::Tables);
our %EXPORT_TAGS = ( 'all' => [qw( create insert )] );
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT      = qw();

our @schema = (
	[ 'date', 'DATE', 'PRIMARY KEY' ],
	[ 'time', 'TIME' ],
	[ 'distance', 'REAL' ],
	[ 'speed', 'REAL' ],
	[ 'cadence', 'INTEGER' ],
	[ 'power', 'INTEGER' ],
);

sub create {
	&BikeLog::Tables::create( 'netathlon2', @schema );

	&BikeLog::Tables::create_date_triggers( 'netathlon2', 'date');
	&BikeLog::Tables::create_time_triggers( 'netathlon2', 'time');
}

sub sync {
	my ($dir) = @_;
	debug ("In BikeLog::Tables::netathlon2::sync($dir)", 1);

	my ($dh, $file);
	my $parser = NetAthlon2::RAW->new();
	$NetAthlon2::RAW::timeDelta = 5;
	opendir ($dh, $dir) || die "Could not open dir ($dir)\n";
	while ($file=readdir($dh)) {
		if ( $file =~ /^Bike\d{4}-\d{2}-\d{2} \d{1,2}-\d{2}[ap]m\.RAW$/ ) {
			my $h = $parser->parse($dir . '/' . $file);

			# If we have at least a 10 minute training session,
			# then add it into our database
			if ( $h->{'Elapsed Time'} > (10 * 60) ) {
				my $date = strftime "%Y-%m-%d", localtime($h->{'Start Time'});
				my $time = &BikeLog::Tables::convert_seconds($h->{'Elapsed Time'});
				my $sql = 'INSERT OR IGNORE INTO netathlon2 VALUES (';
				$sql .= '"' . $date . '","' . $time . '",';
				$sql .= $h->{'Distance'} . ',';

				# Round off the speed to 2 decimal places
				$sql .= (int($h->{'Average Speed'} * 100 + .5)/100) . ',';

				$sql .= int($h->{'Average Cadence'} +.5) . ',';
				$sql .= int($h->{'Average Watts'} +.5) . ')';

				&BikeLog::Tables::_sql($sql);
			}
		}
	}
	closedir ($dh);
}

sub report {
	my (@args) = @_;
	my ($sql, $type, $groupby);

	$sql = 'SELECT netathlon2.date,time,distance,speed,weight.weight,cadence,power
			FROM netathlon2
			LEFT JOIN weight ON netathlon2.date = weight.date';

	($sql, $groupby) = &BikeLog::Tables::process_date('netathlon2', $sql, @args) if ( scalar @args );
	my $data = &BikeLog::Tables::_sql($sql, 1);
	my (@totals, @s);

	my (@netathlon2_schema) = &BikeLog::Tables::_get_schema('netathlon2');

	push @s, @schema[&BikeLog::Tables::_find_schema_field('date', \@netathlon2_schema)];
	push @s, @schema[&BikeLog::Tables::_find_schema_field('time', \@netathlon2_schema)];
	push @s, @schema[&BikeLog::Tables::_find_schema_field('distance', \@netathlon2_schema)];
	push @s, @schema[&BikeLog::Tables::_find_schema_field('speed', \@netathlon2_schema)];
	push @s, ( ['weight', 'REAL'] );
	push @s, @schema[&BikeLog::Tables::_find_schema_field('cadence', \@netathlon2_schema)];
	push @s, @schema[&BikeLog::Tables::_find_schema_field('power', \@netathlon2_schema)];
	push @s, ( ['zone', 'INTEGER'] );

	&BikeLog::Tables::update_data($data, \@totals, {
		TIME => 1,
		WEIGHT => 4,
		POWER => 6,
		MAX => [ 3, 6 ],
	});

	&BikeLog::Tables::print_results( $data, \@s, \@totals );
}

1;

__END__
