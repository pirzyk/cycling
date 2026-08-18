package BikeLog::Tables;

use strict;
use warnings;
use Data::Dumper;
use POSIX;
use Date::Calc qw(Today Add_Delta_Days Week_of_Year);

use FindBin;
use lib "$FindBin::Bin/../lib";

use GD::Graph;
use GD::Graph::bars;
use GD::Graph::lines;

use BikeLog;

require Exporter;
our @ISA         = qw (Exporter);
our %EXPORT_TAGS = ( 'all' => [qw( open_db close_db create insert delete print get_key )] );
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT      = qw();

my $dbh = undef;
my $threshold = 1000;

sub open_db {
	my ($db) = @_;
	debug ('In _open_db($db)', 2);

	if ( ! defined $dbh ) {
		$db = defined $db? $db: "$FindBin::Bin/../db";
		my $login = getpwuid($<);
		$dbh = DBI->connect("dbi:SQLite:dbname=$db/BikeLog-$login.sqlite");

		die "Could not open database ($db)\n\t" . $DBI::errstr . "\n"
			if ( ! defined $dbh );

		$dbh->{RaiseError} = 1;

		# Add the REGEXP operator (needed for the date and time triggers)
		$dbh->func('regexp', 2, sub {
			my ($regex, $string) = @_;
			return $string =~ /$regex/;
		}, 'create_function');
			# or die "Could not register REGEXP func()\n\t" . $DBI::errorstr . "\n";

		# Add the Year, Month and Day date operators
		$dbh->func('year', 1, sub {
			my ($date) = @_;
			return  $1 if ( $date =~ /^(\d{4})-\d{2}-\d{2}$/ );
		}, 'create_function');
		$dbh->func('month', 1, sub {
			my ($date) = @_;
			return  $1 if ( $date =~ /^\d{4}-(\d{2})-\d{2}$/ );
		}, 'create_function');
		$dbh->func('day', 1, sub {
			my ($date) = @_;
			return  $1 if ( $date =~ /^\d{4}-\d{2}-(\d{2})$/ );
		}, 'create_function');
		$dbh->func('week', 1, sub {
			my ($date) = @_;
			my ($w) = Week_of_Year(split('-',$date)) if ( $date =~ /^(\d{4})-(\d{2})-(\d{2})$/ );
			return $w;
		}, 'create_function');
		$dbh->func('convert_time', 1, \&convert_time, 'create_function');
		$dbh->func('convert_seconds', 1, \&convert_seconds, 'create_function');

		# set the mode on the file to be very restrictive.
		# should already be owned by $login.
		chmod 0600, "$db/BikeLog-$login.sqlite";

		# query the DB to see if the module table exists,
		# if so, then load all the modules we have configured.
		# FIXME: This is SQLite specific...
		if ( &_sql('SELECT name FROM sqlite_master WHERE type = "table" and name="module"', 'SCALAR') ) {
			map {
				&BikeLog::load_module($_);
			} @{&_sql('SELECT name FROM module', 'ARRAY' )};
		}
	}
}

sub close_db {
	debug ('In close_db()', 1);

	if ( defined $dbh ) {
		$dbh->disconnect() or
			warn "Could not disconnect cleanly\n\t" . $DBI::errorstr . "\n";
		$dbh = undef;
	}
}

sub _sql {
	my ($sql, $type) = @_;
        $type //= '';
	debug ("In BikeLog::Tables::_sql($sql, $type)", 3);

	my ($sth) = $dbh->prepare($sql)
		if ( ! &BikeLog::noop() );

	if ( defined $sth ) {
		$sth->execute;

		if ( defined $type ) {
			my $ref = $sth->fetchall_arrayref;
                        my $r = ref $ref;
			if ( $r eq 'ARRAY' and $type eq 'ARRAY' ) {
				my @a;
				foreach my $i ( @{$ref} ) {
					map { push @a, $_ } @{$i};
				}
				return ( \@a );
			} elsif ( $r eq 'ARRAY' and exists ${$ref}[0][0] and $type eq 'SCALAR' ) {
				debug ("Returing (" . ${$ref}[0][0] . ")", 4);
				return ${$ref}[0][0];
			} else {
				return $ref;
			}
		}
	}
}

sub get_key {
	my ($table, $key, $name) = @_;

	my $id = &_sql( "SELECT id FROM $table WHERE $key = \"$name\"", 'SCALAR');
	if ( !defined $id ) {
		&insert("$table($key)", $name);
		$id = &_sql( "SELECT id FROM $table WHERE $key = \"$name\"", 'SCALAR');
	}
	return $id;
}

sub create {
	my ($table, @schema) = @_;
	debug ("In BikeLog::Tables::create($table, [" . join(',', @schema) . "])", 2);

	my $cmd;
	map {
		if ( defined $cmd ) {
			$cmd .= ', ' . join (' ', @$_)
		} else {
			$cmd = join (' ', @$_)
		}
	} @schema;

	&_sql("CREATE TABLE $table ($cmd)");
}

sub create_date_triggers {
	my ($table, $field) = @_;

	&_sql('CREATE TRIGGER date_ins_' . $table. '_' . $field .
		" BEFORE INSERT ON $table
		FOR EACH ROW BEGIN
			SELECT CASE
				WHEN new.$field NOT REGEXP '^[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]\$'
				THEN RAISE(ABORT, 'insert on table \"$table\" violates date syntax YYYY-MM-DD ($field)')
			END;
		END
	");

	&_sql('CREATE TRIGGER date_upd_' . $table. '_' . $field .
		" BEFORE UPDATE OF $field ON $table
		FOR EACH ROW BEGIN
			SELECT CASE
				WHEN new.$field NOT REGEXP '^[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]\$'
				THEN RAISE(ABORT, 'update on table \"$table\" violates date syntax YYYY-MM-DD ($field)')
			END;
		END
	");
}

sub create_time_triggers {
	my ($table, $field) = @_;

	&_sql('CREATE TRIGGER time_ins_' . $table. '_' . $field .
		" BEFORE INSERT ON $table
		FOR EACH ROW BEGIN
			SELECT CASE
				WHEN new.$field NOT REGEXP '^([0-9]+:)?[0-5][0-9]:[0-5][0-9]\$'
				THEN RAISE(ABORT, 'insert on table \"$table\" violates time syntax (H+:)?MM:SS ($field)')
			END;
		END
	");

	&_sql('CREATE TRIGGER time_upd_' . $table. '_' . $field .
		" BEFORE UPDATE OF $field ON $table
		FOR EACH ROW BEGIN
			SELECT CASE
				WHEN new.$field NOT REGEXP '^([0-9]+:)?[0-5][0-9]:[0-5][0-9]\$'
				THEN RAISE(ABORT, 'update on table \"$table\" violates time syntax (H+:)?MM:SS ($field)')
			END;
		END
	");
}

sub create_fk_triggers {
	my ($my_table, $my_field, $fk_table, $fk_field) = @_;

	# FIXME: SQLite does not support foreign keys completely
	# w/o triggers, so setup the triggers

	# Insert Trigger
	&_sql('CREATE TRIGGER fki_' . $my_table. '_' . $my_field .
		" BEFORE INSERT ON $my_table
		FOR EACH ROW BEGIN
			SELECT CASE
				WHEN ((new.$my_field IS NOT NULL)
					AND ((SELECT $fk_field FROM $fk_table WHERE $fk_field = new.$my_field) IS NULL))
				THEN RAISE(ABORT, 'insert on table \"$my_table\" violates foreign key ($my_field)')
			END;
		END
	");

	# Update Trigger
	&_sql('CREATE TRIGGER fku_' . $my_table. '_' . $my_field .
		" BEFORE UPDATE OF $my_field ON $my_table
		FOR EACH ROW BEGIN
			SELECT CASE
				WHEN ((SELECT $fk_field FROM ${fk_table} WHERE $fk_field = new.$my_field) IS NULL)
				THEN RAISE(ABORT, 'update on table \"$my_table\" violates foreign key ($my_field)')
			END;
		END
	");

	# Delete Trigger
	&_sql('CREATE TRIGGER fkd_' . $my_table. '_' . $my_field .
		" BEFORE DELETE ON $fk_table
		FOR EACH ROW BEGIN
			SELECT CASE
				WHEN ((SELECT $my_field FROM $my_table WHERE $my_field = old.$fk_field) IS NOT NULL)
				THEN RAISE(ABORT, 'delete on table \"$fk_table\" violates foreign key ($my_field)')
			END;
		END
	");
}

sub insert {
	my ($table, @what) = @_;
        my $str;
        {
            no warnings;
            $str = qq("\Q) .  join (qq(\E", "\Q), @what) .  qq(\E");
        }
	debug ("In BikeLog::Tables::insert($table, [$str])", 2);

	&_sql ("INSERT INTO $table VALUES ($str) ON CONFLICT DO NOTHING");
}

sub has_date {
	my (@schema) = @_;
	debug ("In BikeLog::Table::has_date([" . join (', ', @schema) . "])", 2);

	map {
		return 1
			if ( ${$_}[1] eq 'DATE' );
	} @schema;

	return;
}

sub _find_schema_field {
	my ($f, $s) = @_;

	for (my $i=0; $i< @{$s}; $i++) {
		return $i if ( $f eq ${$s}[$i][0] );
	}
	return undef;
}

sub _get_schema {
	my ($table) = @_;
	debug ("In BikeLog::Tables::_get_schema($table)", 3);
	my @schema;

	# FIXME: This is SQLite specific...
	my $sql = &_sql("SELECT sql FROM sqlite_master WHERE type = 'table' AND tbl_name = '$table'", "SCALAR");

	$sql =~ s/^CREATE TABLE $table \(//;
	$sql =~ s/\)$//;
	$sql =~ s/PRIMARY KEY\([^)]*\)//;
	foreach my $f ( split(/,\s*/, $sql)) {
		my @a = split(/\s+/, $f);
		my $name = shift @a;
		my $type = shift @a;
		push @schema, [ $name, $type, join (' ', @a) ];
	}

	return @schema;
}

sub _assemble_sql {
	my ($f, $t, $j, $w) = @_;

	my $sql = 'SELECT ' . join(',', @{$f}) . ' FROM ' . join (',', @{$t});
	if ( defined $j ) {
		foreach my $k ( keys %{$j} ) {
			$sql .= ' LEFT JOIN ' . $k . ' ON ' . join(' AND ', @{$j->{$k}})
		}
	}
	$sql .= ' WHERE ' . join(' AND ', @{$w})
		if ( scalar @{$w});

	return $sql;
}

sub convert_unit {
	my ($from_id, $to_id, $value) = @_;
	my ($from) = ($from_id =~ /^\d+$/
		? &_sql("SELECT name from unit where id = $from_id", 'SCALAR')
		: $from_id);
	
	my ($to) = ( $to_id =~ /^\d+$/
		? &_sql("SELECT name from unit where id = $to_id", 'SCALAR')
		: $to_id);

	if ( $from eq 'Mi' and $to eq 'km' ) {
		return $value * 1.609344;
	} elsif ( $from eq 'km' and $to eq 'Mi' ) {
		return $value * 0.621371192;
	} elsif ( $from eq 'LBs' and $to eq 'kg' ) {
		return $value * 0.45359237;
	} elsif ( $from eq 'kg' and $to eq 'LBs' ) {
		return $value * 2.20462262;
	} else {
		die "Don't know how to convert from $from ($from_id) to $to ($to_id)\n";
	}
}

# Returns number of seconds from the HH::MM::ss format
sub convert_time {
	my ($time) = @_;
        return if !defined $time;
	my ($s,$m,$h) = reverse(split(/:/, $time));

	return ($h * 3600 + $m * 60 + $s);
}

# Only used for the create_graph() case where we have 2 axes
sub convert_seconds2 {
	my ($seconds) = @_;

	return $seconds if ( $seconds < $threshold );

	return &convert_seconds($seconds);
}

# Returns HH:MM:ss format given seconds
sub convert_seconds {
	my ($seconds) = @_;

	my $time = sprintf "%2.2d:%2.2d:%2.2d",
			int($seconds / 3600),
			($seconds / 60) % 60,
			$seconds % 60;
	return $time;
}

sub convert_date {
	my ($date) = @_;
	my @d = Today();
	debug ("In BikeLog::Tables::convert_date($date)", 3);

	if ( lc($date) eq 'today' ) {
		$date = sprintf "%4.4d-%2.2d-%2.2d", $d[0], $d[1], $d[2];
	} elsif ( lc($date) eq 'yesterday' ) {
		@d = Add_Delta_Days(@d, -1);
		$date = sprintf "%4.4d-%2.2d-%2.2d", $d[0], $d[1], $d[2];
	}
	debug ("Returing ($date)", 4);

	return $date;
}

sub print {
	my ($table, $where) = @_;
	debug ("In BikeLog::Table::print($table)", 1);

	my (@schema) = &_get_schema($table);

	# Retrieve the data to print
	my $data = &_sql ( "SELECT * from $table", 1 );

	print "\nTable $table\n\n";

	&print_results( $data, \@schema );

	print "\n\t" . scalar @{$data} . " Rows\n\n";
}

sub print_cell {
    my ($val, $length, $cnt, $type, $last) = @_;
    $val //= '';
    debug ("In BikeLog::Table::print_cell($val, $length, $cnt, $type)", 2);

    print ' ' if ( $cnt );
    if ( $type eq 'HEADER' || !length($val) ) {
        if (defined $last && $last) {
            printf "%s", $val;
        } else {
            printf "%-*.*s", $length, $length, $val;
        }
    } elsif ( $type =~ m/TEXT|CHAR/i and length ($val) ) {
        if (defined $last && $last) {
            printf "%-s", qq($val);
        } else {
            printf "%-*.*s", $length, $length, qq($val);
        }
    } elsif ( $type =~ m/INTEGER/i ) {
        printf "%*d", $length, ($val + 0);
    } elsif ( $type =~ m/REAL/i ) {
        printf '%' . $length . '.3f', ($val + 0.000);
    } else {
        if (defined $last && $last) {
            printf "%s", $val;
        } else {
            printf "%*.*s", $length, $length, $val;
        }
    }
}

sub print_hr {
	my ($s, $l) = @_;

	for (my $i = 0; $i < scalar @{$s}; $i++ ) {
		&print_cell (('-' x $l->[$i]), $l->[$i], $i, 'N/A');
	}
	print "\n";
}

sub print_header {
	my ($s, $l) = @_;

	for (my $i = 0; $i < scalar @{$s}; $i++ ) {
		&print_cell ($s->[$i][0], $l->[$i], $i, 'HEADER', ($i+1 == scalar @{$s}));
	}
	print "\n";
	print_hr($s, $l);
}

sub print_results {
	my ($data, $schema, $totals) = @_;

	if ( ! scalar @{$data} ) {
		warn "No Data!\n";
		return;
	}

	# Construct the field length array
	my (@length, $field);
	for (my $row=0; $row < scalar @{$data}; $row++) {
		for ($field=0; $field < scalar @{$data->[$row]}; $field++) {
			$length[$field] = length($schema->[$field]->[0]) + ($schema->[$field]->[1] =~ m/TEXT|CHAR/i? 2:0)
				if ( ! $row );
			my $l;
			if ( $schema->[$field]->[1] eq 'REAL' ) {
				$l = (defined $data->[$row]->[$field] ? length(substr($data->[$row]->[$field], 0, index($data->[$row]->[$field], '.'))) + 3 : 4);
			} elsif ( $schema->[$field]->[1] =~ m/TEXT|CHAR/i ) {
                                # We may have a null value in the database, so length doesn't return 0 but undef;
                                $l = (defined $data->[$row]->[$field] ? length($data->[$row]->[$field]) : 0) + 2;
			} elsif ( $schema->[$field]->[1] eq 'TIME' ) {
				$l = 9;
			} else {
				$l = defined $data->[$row]->[$field] ? length($data->[$row]->[$field]) : 0;
			}
			$length[$field] = ($length[$field] < $l ? $l:  $length[$field]);
		}
	}

	# Now print out all the data.
	&print_header($schema, \@length);
	foreach my $row ( @{$data} ) {
		for ($field=0; $field < scalar @{$schema}; $field++) {
			&print_cell(${$row}[$field], $length[$field], $field, $schema->[$field][1], ($field+1 == scalar @{$schema}));
		}
		print "\n";
	}

	if ( defined $totals ) {
		print_hr($schema, \@length);
		for ($field=0; $field < scalar @{$schema}; $field++) {
			#&print_cell($totals->[$field], $length[$field], $field, 'TOTALS');
			&print_cell($totals->[$field], $length[$field], $field, $schema->[$field][1], ($field+1 == scalar @{$schema}));
		}
		print "\n\n";
	}
}

sub process_date {
	my ($table, $sql, @args) = @_;
	my ($arg, $year, $mon, $groupby, $start, $end);

	$arg = shift @args;
	if ( defined $arg and $arg eq 'this' || $arg eq 'last' ) {
		if ( scalar @args ) {
			my $oarg = $arg;
			$arg = shift @args;
			$year = strftime("%Y", localtime()) if ( $arg eq 'year' );
			$mon = strftime("%m", localtime()) if ( $arg eq 'month' );
			$year-- if ( $oarg eq 'last' and $arg eq 'year' );
			if ( $oarg eq 'last' and $arg eq 'month' ) {
				if ( $mon > 1 )  {
					$mon--;
				} else {
					$mon = 12;
					$year = strftime("%Y", localtime()) - 1;
				}
			}
			$arg = shift @args;
		} else {
			die "Need either the word 'month' or 'year' to go with 'report $table (mileage|distance) $arg'\n";
		}
	}

	if ( defined $arg and $arg eq 'start' ) {
		if ( scalar @args ) {
			$arg = shift @args;
			if ( $arg =~ /^[1-2]\d{3}-\d{2}-\d{2}$/ ) {
				$start = $arg;
				$arg = shift @args;
			} else {
				die "Can't understand start $arg, should be YYYY-MM-DD\n";
			}
		}
	}

	if ( defined $arg and $arg eq 'end' ) {
		if ( scalar @args ) {
			$arg = shift @args;
			if ( $arg =~ /^[1-2]\d{3}-\d{2}-\d{2}$/ ) {
				$end = $arg;
				$arg = shift @args;
			} else {
				die "Can't understand end $arg, should be YYYY-MM-DD\n";
			}
		}
	}

	if ( defined $arg and $arg eq 'year' ) {
		if ( ! length $year ) {
			$arg = shift @args;
			if ( $arg =~ /^[1-2]\d{3}$/ ) {
				$year = $arg;
				$arg = shift @args;
			} else {
				die "Can't understand year $arg, should be YYYY\n";
			}
		}
	}

	if ( defined $arg and $arg eq 'month' ) {
		if ( ! length $mon ) {
			$arg = shift @args;
			if ( length ($arg) == 2 and $arg > 0 and $arg < 13 ) {
				$mon = $arg;
			} else {
				die "Can't understand month $arg, should be between 01 and 12\n";
			}
			$arg = shift @args;
		}
	}

	if ( defined $arg and $arg eq 'groupby' ) {
		$arg = shift @args;
		if ( $arg eq 'year' and length $year ) {
			die "Can't understand 'year $year groupby year'\n";
		} elsif ( $arg eq 'month' and ! length $year ) {
			$groupby = 'YEAR(date) MONTH(date)'
		} elsif ( $arg eq 'year' ) {
			$groupby = 'YEAR(date)';
		} elsif ( $arg eq 'month' ) {
			$groupby = 'MONTH(date)';
		} elsif ( $arg eq 'week' and ! length $year ) {
			$groupby = 'YEAR(date) WEEK(date)'
		} elsif ( $arg eq 'week' ) {
			$groupby = 'WEEK(date)';
		} elsif ( $arg eq 'bike' ) {
			$groupby = 'fk_bike_id';
		} else {
			die "Can't understand 'groupby $arg', should be 'groupby year, month, week or bike'\n";
		}
		$arg = shift @args;
	}

	die "Can't understand $arg for $table\n"
		if ( defined $arg );

	die "Can't understand " . join (" ", @args) . " for $table\n"
		if ( scalar @args );

	my ($where);

	$where .= "$table.date >= '$start'"
		if ( length $start );

	$where .= (length $where ? ' AND ' : '' ) . "$table.date <= '$end'"
		if ( length $end );

	if ( length $year || length $mon ) {
		if ( length $mon ) {
                        $mon = (length $mon == 2) ? $mon : "0${mon}";
			$year = strftime("%Y", localtime())
				if ( ! length $year );
			$where .= (length $where ? ' AND ' : '' ) . "$table.date >= '$year-$mon-01' AND $table.date <= '$year-$mon-31'";
		} else {
			$where .= (length $where ? ' AND ' : '' ) . "$table.date >= '$year-01-01' AND $table.date <= '$year-12-31'";
		}
	}

	if ( defined $where and length $where ) {
		if ( $sql =~ /WHERE/ ) {
			$sql .= ' AND ' . $where
		} else {
			$sql .= ' WHERE ' . $where
		}
	}

	#$sql .= " GROUP BY $groupby" if ( length $groupby );

	$sql .= " ORDER BY $table.date" if ( $table ne 'bike' );

	debug ("In BikeLog::Tables::process_date() sql => $sql", 1);
	return ($sql, $groupby);
}

sub update_data {
	my ($data, $totals, $opts) = @_;
	my ($field, @cnt, $h, $kcalph);
	my $default_unit = 'km';

	return if ( ! scalar @{$data} );

	$totals->[0] = 'Totals ' . scalar @{$data};
	$totals->[$opts->{'DISTANCE'} + 1 ] = $default_unit
		if ( exists $opts->{'DISTANCE'} );
	$totals->[$opts->{'SPEED'} + 1 ] = $default_unit . '/hr'
		if ( exists $opts->{'SPEED'} and exists $opts->{'DISTANCE'} );

	# Iterate through the data and update fields.
	map {

		# Insert the Speed column into our data array
		if ( exists $opts->{'SPEED'} and exists $opts->{'TIME'} and exists $opts->{'DISTANCE'} ) {
			$h = &BikeLog::Tables::convert_time($_->[$opts->{'TIME'}]) / 3600;
			my $speed = $_->[exists $opts->{'DISTANCE'}] / $h;
			splice (@{$_}, $opts->{'SPEED'}, 0, ($speed, $_->[$opts->{'DISTANCE'}+1] . '/hr'));
		}

		# Insert the HR Zone column
		my $zone;
		if ( exists $opts->{'HR'} ) {
			$zone = (defined $_->[$opts->{'HR'}] and $_->[$opts->{'HR'}] =~ /^[0-9]+$/ ?
				&BikeLog::Tables::_sql('SELECT MAX(zone.zone) FROM zone WHERE ' . $_->[$opts->{'HR'}] . ' >= zone.hr', 'SCALAR')
				: 0);
			splice (@{$_}, $opts->{'HR'} + 1, 0, ($zone));
		}

		# Kilocalories per hour
		if ( exists $opts->{'KcalPH'} and exists $opts->{'CALORIES'} and exists $opts->{'CALORIETIME'} ) {
			$kcalph = undef;
			if ( defined $_->[$opts->{'CALORIES'}] and $_->[$opts->{'CALORIES'}] =~ /^[0-9]+$/ ) {
			    $h = &BikeLog::Tables::convert_time($_->[$opts->{'CALORIETIME'}]) / 3600;
				$cnt[$opts->{'KcalPH'}] += $h;
				$kcalph = int(($_->[$opts->{'CALORIES'}] / $h) + 0.5);
			}
			$_->[$opts->{'CALORIETIME'}] = $kcalph;
		}

		# Insert the Kilocalorie per hour Zone column
		if ( exists $opts->{'CALORIES'} and exists $opts->{'KcalPH'} ) {
			$zone = (defined $_->[$opts->{'KcalPH'}] and $_->[$opts->{'KcalPH'}] =~ /^[0-9]+$/
				? &BikeLog::Tables::_sql('SELECT MAX(zone.zone) FROM zone WHERE ' . $_->[$opts->{'KcalPH'}] . ' >= zone.calorie', 'SCALAR')
				: undef);
			splice (@{$_}, $opts->{'KcalPH'} + 1, 0, ($zone));
		}

		if ( exists $opts->{'POWER'} ) {
                        $zone = (defined $_->[$opts->{'POWER'}] and $_->[$opts->{'POWER'}] =~ /^[0-9]+$/
			        ? &BikeLog::Tables::_sql('SELECT MAX(zone.zone) FROM zone WHERE ' . $_->[$opts->{'POWER'}] . ' >= zone.power', 'SCALAR')
                                : undef);
			splice (@{$_}, $opts->{'POWER'} + 1, 0, ($zone));
		}

		# Totals are SUMS of these fields.
		if ( exists $opts->{'DISTANCE'} ) {
			if ( $default_unit eq $_->[$opts->{'DISTANCE'} + 1] ) {
				$totals->[$opts->{'DISTANCE'}] += $_->[$opts->{'DISTANCE'}];
			} else {
				$totals->[$opts->{'DISTANCE'}] += int(&convert_unit($_->[$opts->{'DISTANCE'} + 1], $default_unit, $_->[$opts->{'DISTANCE'}]) * 100)/100;
			}
		}
		$totals->[$opts->{'CALORIES'}] += $_->[$opts->{'CALORIES'}]
			if ( exists $opts->{'CALORIES'} and defined $_->[$opts->{'CALORIES'}] and $_->[$opts->{'CALORIES'}] =~ /^[0-9]+$/ );
		$totals->[$opts->{'TIME'}] += &BikeLog::Tables::convert_time($_->[$opts->{'TIME'}])
			if ( exists $opts->{'TIME'} );

		# Totals are AVERAGES of these fields.
		if ( exists $opts->{'HR'} and defined $_->[$opts->{'HR'}] and $_->[$opts->{'HR'}] =~ /^[0-9]+$/) {
			$totals->[$opts->{'HR'}] += $_->[$opts->{'HR'}];
			$cnt[$opts->{'HR'}]++;
		}
		if ( exists $opts->{'WEIGHT'} and defined $_->[$opts->{'WEIGHT'}] and $_->[$opts->{'WEIGHT'}] =~ /^[0-9]+(\.[0-9]*)?$/) {
			$totals->[$opts->{'WEIGHT'}] += $_->[$opts->{'WEIGHT'}];
			$cnt[$opts->{'WEIGHT'}]++;
		}
		#if ( exists $opts->{'POWER'} and defined $_->[$opts->{'POWER'}] and $_->[$opts->{'POWER'}] =~ /^[0-9]+$/) {
		#	$totals->[$opts->{'POWER'}] += $_->[$opts->{'POWER'}];
		#	$cnt[$opts->{'POWER'}]++;
		#}
		if ( exists $opts->{'CADENCE'} and defined $_->[$opts->{'CADENCE'}] and $_->[$opts->{'CADENCE'}] =~ /^[0-9]+$/) {
			$totals->[$opts->{'CADENCE'}] += $_->[$opts->{'CADENCE'}];
			$cnt[$opts->{'CADENCE'}]++;
		}

		# Totals are the SUM of these fields
		foreach $field ( @{$opts->{'SUM'}} ) {
			$totals->[$field] += ( defined $_->[$field] and $_->[$field] =~ /^[0-9\.]+$/ ) ? $_->[$field] : 0;
		}

		# Totals are the MAX of these fields
		foreach $field ( @{$opts->{'MAX'}} ) {
                        $totals->[$field] = 0 if !defined $totals->[$field];
			$totals->[$field] = ( defined $_->[$field] and $_->[$field] =~ /^[0-9\.]+$/ and $_->[$field] > $totals->[$field] ? $_->[$field] : $totals->[$field] );
		}
	} @{$data};

	# Now finish updating the totals.
	if ( exists $opts->{'TIME'} ) {
		if ( exists $opts->{'SPEED'} and exists $opts->{'DISTANCE'} and $totals->[$opts->{'TIME'}] > 0 ) {
			$totals->[$opts->{'SPEED'}] = int($totals->[$opts->{'DISTANCE'}] / ($totals->[$opts->{'TIME'}]/3600) * 100 + .5) / 100;
		}
		$totals->[$opts->{'TIME'}] = &BikeLog::Tables::convert_seconds($totals->[$opts->{'TIME'}]);
	}
	if ( exists $opts->{'WEIGHT'} and defined $cnt[$opts->{'WEIGHT'}] and $cnt[$opts->{'WEIGHT'}] > 0 ) {
		$totals->[$opts->{'WEIGHT'}] = int($totals->[$opts->{'WEIGHT'}] / $cnt[$opts->{'WEIGHT'}] + .5);
	}
	#if ( exists $opts->{'POWER'} and $cnt[$opts->{'POWER'}] > 0 ) {
	#	$totals->[$opts->{'POWER'}] = int($totals->[$opts->{'POWER'}] / $cnt[$opts->{'POWER'}] + .5);
	#}
	if ( exists $opts->{'CADENCE'} and defined $cnt[$opts->{'CADENCE'}] and $cnt[$opts->{'CADENCE'}] > 0 ) {
		$totals->[$opts->{'CADENCE'}] = int($totals->[$opts->{'CADENCE'}] / $cnt[$opts->{'CADENCE'}] + .5);
	}
	if ( exists $opts->{'HR'} and $cnt[$opts->{'HR'}] > 0 ) {
		$totals->[$opts->{'HR'}] = int($totals->[$opts->{'HR'}] / $cnt[$opts->{'HR'}] + .5);
	}
	#if ( exists $opts->{'KcalPH'} and $opts->{'CALORIES'} and $cnt[$opts->{'KcalPH'}] > 0 ) {
	#	$totals->[$opts->{'KcalPH'}] = int($totals->[$opts->{'CALORIES'}] / $cnt[$opts->{'KcalPH'}] + .5);
	#}
}

sub get_data {
	my ($table, $what, @args) = @_;
	my ($sql, $groupby);

	if ( $table eq 'polar' ) {
		$sql = "SELECT $what,date FROM $table";
	} elsif ( $table eq 'bike' ) {
		$sql = "SELECT $what FROM $table";
	} else {
		$sql = "SELECT $what,date,bike.name FROM $table, bike WHERE $table.fk_bike_id = bike.id";
	}
	($sql, $groupby) = &BikeLog::Tables::process_date($table, $sql, @args) if ( scalar @args );
	my $data = &BikeLog::Tables::_sql($sql, 1);
	my ($d);
	foreach my $row ( @{$data} ) {
		if ( length $groupby ) {
			my $ndx = $row->[1];
			$ndx =~ s/-\d{2}$// if ( $groupby eq 'YEAR(date) MONTH(date)' );
			$ndx =~ s/-\d{2}-\d{2}$// if ( $groupby eq 'YEAR(date)' );
			if ( $groupby eq 'MONTH(date)' ) {
				$ndx =~ s/^\d{4}-//;
				$ndx =~ s/-\d{2}$//;
			}
			# groupby Week
			if ( $groupby eq 'YEAR(date) WEEK(date)' ) {
			        $ndx =~ s/-\d{2}-\d{2}$//;
				my $w = Week_of_Year(split('-',$row->[1]));
				$w = '0' . $w if ($w < 10);
                                $ndx .= " $w";
			}
			if ( $groupby eq 'WEEK(date)' ) {
				($ndx) = Week_of_Year(split('-',$row->[1]));
				$ndx = '0' . $ndx if ($ndx < 10);
			}
			# groupby bike
			if ( $groupby eq 'fk_bike_id' ) {
				$ndx = $row->[2];
			}
			$d->{$ndx}->{'sum'} = $d->{$ndx}->{'count'} = 0
				if ( ! exists $d->{$ndx} );
			
			$d->{$ndx}->{'sum'} += ( $what eq 'time' )
				? &BikeLog::Tables::convert_time($row->[0])
				: (defined $row->[0] ? $row->[0] : 0);
			$d->{$ndx}->{'count'}++;

                        # Store the unique date in the hash,
                        # so we can merge distinctly.
			$d->{$ndx}->{'days'}->{$row->[1]} = 1;
		} else {
			$d += ( $what eq 'time' )
				? &BikeLog::Tables::convert_time($row->[0])
				: $row->[0];
		}
	}

	return $d;
}

sub report {
	my (@args) = @_;
	my (@totals);
	my $type = shift @args;
        my $max = 6;    # Set for Totals string

	die "Could not understand 'report $type'\n" if ( $type ne 'time' );

	my ($time1) = &BikeLog::Tables::get_data('trainer', 'time', @args) // {};
	my ($time2) = &BikeLog::Tables::get_data('ride', 'time', @args) // {};

	if ( ref $time1 eq 'HASH' ) {
		my (%h, %d, %c);
		# Merge the two hashes
		map {
			$h{$_} = $time1->{$_}->{'sum'};
			$c{$_} = $time1->{$_}->{'count'};
                        foreach my $date (keys %{$time1->{$_}->{'days'}}) {
                            $d{$_}->{$date} = 1;
                        }
                        $max = length($_) if length($_) > $max;
		} sort keys %{$time1};
		map {
			if ( exists $h{$_} ) {
			    $h{$_} += $time2->{$_}->{'sum'};
			    $c{$_} += $time2->{$_}->{'count'};
                            foreach my $date (keys %{$time2->{$_}->{'days'}}) {
                                $d{$_}->{$date} = 1;
                            }
                        } else {
			    $h{$_} = $time2->{$_}->{'sum'};
			    $c{$_} = $time2->{$_}->{'count'};
			}
                        foreach my $date (keys %{$time2->{$_}->{'days'}}) {
                            $d{$_}->{$date} = 1;
                        }
                        $max = length($_) if length($_) > $max;
		} sort keys %{$time2};

		# Now print out the data.
		my (@s) = ( ['GroupBy', 'INTEGER'], ['Count', 'INTEGER'], ['Days', 'INTEGER'], ['Time', 'TIME']);
		my (@l) = ( $max, 5, 4, 9 );
		&print_header(\@s, \@l);
		map {
			$totals[1] += $c{$_};
			$totals[2] += scalar keys %{$d{$_}};
			$totals[3] += $h{$_};
			printf "%-*.*s   %3d  %3d %9.9s\n", $max, $max, $_, $c{$_}, scalar keys %{$d{$_}}, &BikeLog::Tables::convert_seconds($h{$_});
		} sort keys %h;
		&print_hr(\@s, \@l);

		printf "%-*.*s   %3d  %3d %9.9s\n", $max, $max, 'Totals', $totals[1], $totals[2], &BikeLog::Tables::convert_seconds($totals[3]);
	} else {
		print &BikeLog::Tables::convert_seconds($time1 + $time2) . "\n";
	}
}

sub graph {
	my (@args) = @_;
	my $type = shift @args;

	die "Could not understand 'graph $type'\n" if ( $type ne 'time' );

	my ($time1) = &BikeLog::Tables::get_data('trainer', 'time', @args);
	my ($time2) = &BikeLog::Tables::get_data('ride', 'time', @args);
	my (%d, @data, @k, @d1, @d2, %totals);
	map {
		$d{$_} = { d1 => $time1->{$_}->{'sum'} };
	} sort keys %{$time1};
	map {
		if ( ! exists $d{$_} ) {
			$d{$_} = { d2 => $time2->{$_}->{'sum'} };
		} else {
			$d{$_}->{d2} = $time2->{$_}->{'sum'};
		}
	} sort keys %{$time2};
	map {
		if ( exists($d{$_}->{d1}) ) {
			push @d1, $d{$_}->{d1};
			$totals{'Total Trainer Time'} += $d{$_}->{d1};
		} else {
			push @d1, 0;
		}
		if ( exists($d{$_}->{d2}) ) {
			push @d2, $d{$_}->{d2};
			$totals{'Total Ride Time'} += $d{$_}->{d2};
		} else {
			push @d2, 0;
		}
	} sort keys %d;
	@k = sort keys %d;
	@data = ( [ @k ], [ @d1 ], [ @d2 ] );

	map {
		$totals{$_} = &BikeLog::Tables::convert_seconds($totals{$_});
	} keys %totals;

	&BikeLog::Tables::create_graph(
		'time',
		'Combined Ride and Trainer (Saddle) Time',
		'Month',
		'Time (HH:MM:SS)',
		undef,
		'time',
		\%totals,
		@data,
	);
}

sub create_graph {
	my ($table, $title, $x_label, $y_label, $y2_label, $file, $totals, @data) = @_;
	my ($font) = '/System/Library/Fonts/Courier.dfont';

	my ($cnt) = scalar @{$data[0]};

	my ($x) = ($table eq 'weight'
		? 2 * $cnt / ($cnt > 500 ? 2: 1)
		: 66 * $cnt / ($cnt > 20 ? 2: 1));

	# Set a minimum x size.
	$x = ($x < 300 ? 300: $x );
	my ($y) = int($x * 4 / 3);

	my $img = ($table eq 'weight'
		? new GD::Graph::lines($x,$y)
		: new GD::Graph::bars($x,$y));

	my ($max, $min) = &BikeLog::max_min(@{$data[1]});
	my ($max2, $min2) = &BikeLog::max_min(@{$data[2]})
		if ( defined $y2_label );
	if ( $table eq 'time' ) {
		for (my $i=0; $i < scalar @{$data[1]}; $i++) {
			$max = ( $max < ($data[1][$i]+$data[2][$i])
					? ($data[1][$i]+$data[2][$i])
					: $max);
		}
	}

	$img->set_text_clr('black');
	$img->set_title_font($font, 18);

	$img->set_x_label_font($font, 10);
	$img->set_y_label_font($font, 10);

	$img->set_legend_font($font, 6);
	$img->set_x_axis_font($font, 6);
	$img->set_y_axis_font($font, 6);

	$img->set(
		x_label => $x_label,
		x_labels_vertical => 1,
		x_label_skip => ($table eq 'weight'? $cnt / 32: 0),
		x_label_position => 1/2,
		title => $title,
		legendclr => 'black',
		transparent => 0,
	);
	if ( $cnt < 16 ) {
		$img->set(
			show_values => 1,
			text_space => 50,
			values_vertical => 1,
		);
		$img->set (
			values_format => \&BikeLog::Tables::convert_seconds,
		) if ( $table eq 'trainer' );
	}
	if ( defined $y2_label ) {
		$img->set(
			two_axes => 2,
			y1_label => $y_label,
			y1_max_value => $max,
			y2_label => $y2_label,
			y2_max_value => $max2,
			# FIXME: A bug in GD::Graph that it does not support y2_number_format
			y_number_format => \&BikeLog::Tables::convert_seconds2,
			values_format => \&BikeLog::Tables::convert_seconds2,
		);

		# reset the threshold between the distance and the seconds if we can.
		$threshold = $min2-1 if ( $min2 > $max );
	} else {
		$img->set(
			y_label => $y_label,
			y_max_value => $max,
		);
		$img->set(
			y_number_format => \&BikeLog::Tables::convert_seconds,
			values_format => \&BikeLog::Tables::convert_seconds2,
		) if ( $title =~ /time/i and ( $table eq 'trainer' || $table eq 'time' ));
	}
	if ( $table eq 'weight' ) {
		$img->set(
			line_width => 4,
			y_min_value => $min,
			dclrs => [ 'dgray' ],
		);
	} elsif ( $table eq 'ride' ) {
		$img->set(
			dclrs => [ 'dgray', 'lgray' ],
		);
		$img->set_legend ('Distance', 'Time');
	} elsif ( $table eq 'time' ) {
		$img->set(
			cumulate => 1,
			dclrs => [ 'lgray', 'dgray' ],
		);
		$img->set_legend ('Trainer', 'Ride');
	} else {
		$img->set(
			dclrs => [ 'dgray' ],
		);
	}

	my $gd = $img->plot(\@data) ||
		die "Could not create GD object (" . $img->error . ")\n";

	my $black = $gd->colorAllocate(0,0,0);

	# Add totals...
	if ( defined $totals ) {
		my $row = $y - (scalar(keys %{$totals}) * 8 ) - 4;
		foreach my $msg ( sort keys %{$totals} ) {
			$gd->stringFT($black, $font, 8, 0, $x-265, $row, "$msg $totals->{$msg}");
			$row += 8;
		}
	}

	# Add the generated on and copyright strings.
	my $date = strftime("%e %b %Y %r %Z", localtime());
	my $year = strftime("%Y", localtime());
	my ($name,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell,$expire) = getpwuid($<);
	$gd->stringFT($black, $font, 8, 0, 4, $y-4, "Copyright (c) $year by $gcos");
	$gd->stringFT($black, $font, 8, 0, $x-265, $y-4, "Generated on $date");

	# Create the output file
	my $outfile = "bikelog.$file.png";
	open (OUT, ">$outfile") || die "Could not create file ($outfile)\n";
	binmode OUT;
	print OUT $gd->png() ||
		die "Could not write data to ($outfile)\n";
	close OUT;
}

1;

__END__
