package RaceResults::DB;

use Carp;
use DBI;
use Data::Dumper;
use RaceResults;
require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} });
our @EXPORT = qw();

our $SCHEMAFILE = $RaceResults::INITDIR . '/schema.sql';

sub set_noop {
    my ($self) = @_;
    $self->{noop} = 1;
    $self->set_debug(4);
}

sub noop {
    my ($self) = @_;
    return $self->{noop};
}

sub set_debug {
    my ($self, $val) = @_;

    $self->{debug} += ($val =~ /^\d+$/? $val: 1);
}

sub debug {
    my ($self, $msg, $level) = @_;

    printf STDERR "%s$msg\n", "\t" x $level
        if $self->{debug} >= $level;
}

sub new {
    my ($class, %opts) = @_;
    my ($self);

    $self = \%opts;

    # Put this after the first self assignment so we have a chance to print it out
    &debug($self, "In RaceResults::DB::new($class, opts)", 2);

    # If no DBI parameters were passed in, set a good default
    $self->{attr}->{RaiseError} = 1
        if !exists $self->{attr};

    if (!exists $self->{dbh} or !defined $self->{dbh}) {
        my $db = $self->{file};
        $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$db", undef, undef, $self->{attr});
        croak "Could not open database ($db)\n\t" . $DBI::errstr . "\n" if ! defined $self->{dbh};
    }

    bless ($self, $class);

    # Enable foreign keys
    $self->_sql('PRAGMA foreign_keys = ON;');

    $self->_get_tables;

    return $self;
}

sub close_db {
    my ($self) = @_;
    if ( exists $self->{dbh} and defined $self->{dbh} ) {
        $self->{dbh}->disconnect() or
            warn "Could not disconnect cleanly\n\t" . $DBI::errorstr . "\n";
        delete $self->{dbh};
    }
}

# This routine mainly is being called by unit tests
# Real DB initialization is done in the race-report.sh script itself.
sub init_db {
    my ($self) = @_;
    $self->debug ("In RaceResults::DB::init_db(${self})", 2);

    croak "Database not opened!\n"
        if !exists $self->{dbh} or !defined $self->{dbh};

    my @schema = &RaceResults::slurp($SCHEMAFILE, 'ARRAY', ';');

    foreach my $s (@schema) {
        croak "Could not initialize the DB! (sql => $s) ($@)\n"
            if !defined $self->_sql($s);
    }

    # Now that we have updated the schema, grab the list of tables
    $self->_get_tables;
}

sub get_race_type {
    my ($self, $name) = @_;

    return $self->_sql('SELECT id FROM race_type WHERE name=?', [ $name ], 'SCALAR');
}

sub get_unit {
    my ($self, $name) = @_;

    return $self->_sql('SELECT id FROM unit WHERE name=? OR abreviation=?', [ $name, $name ], 'SCALAR');
}

sub get_racer_by_name {
    my ($self, $first, $last) = @_;

    my $id = $self->_sql('SELECT id FROM racer WHERE first_name=? and last_name=?', [ $first, $last ], 'SCALAR');

    $id = $self->_sql('SELECT fk_racer_id FROM racer_alias WHERE first_name=? and last_name=?', [ $name, $name ], 'SCALAR')
        if !defined $id;

    return $id;
}

sub get_racer_by_id {
    my ($self, $id, $field) = @_;

    return $self->_sql("SELECT $field FROM racer WHERE id=?", [ $id ], 'SCALAR');
}

sub update_racer {
    my ($self, $id, $field, $value) = @_;

    return $self->_sql("UPDATE racer set $field=? WHERE id=?", [ $value, $id ]);
}

sub add_racer {
    my ($self, $first, $last, $year, $fk_team_id, $team_date) = @_;

    my $sql = 'INSERT INTO racer(first_name, last_name, year_born, fk_team_id, team_start_date) VALUES(?,?,?,?,?);';

    $self->_sql($sql, [ $first, $last, $year, $fk_team_id, $team_date ] );

    return $self->get_racer_by_name($first, $last);
}

sub get_team {
    my ($self, $name) = @_;

    my $id = $self->_sql('SELECT id FROM team WHERE name=? or abreviation=?', [ $name, $name ], 'SCALAR');

    $id = $self->_sql('SELECT fk_team_id FROM team_alias WHERE name=?', [ $name ], 'SCALAR')
        if !defined $id;

    return $id;
}

# FIXME: Do I even need this functionallity?
sub get_team_roster {
    my ($self, $team_name) = @_;

    # First get the team.id value
    my $id = $self->get_team($team_name);

    if (!defined $id) {
        carp "Could not find team ($team_name)\n";
        return undef;
    }

    return $self->_sql('SELECT first_name, last_name FROM racer WHERE fk_team_id=?', [ $id ], 'ARRAY');
}

# Add a new team and return the primary key of what we just entered.
sub add_team {
    my ($self, $name, $abbr) = @_;
    my $sql = 'INSERT INTO team(name, abreviation) VALUES(?,?);';

    $self->_sql($sql, [ $name, $abbr ] );

    return $self->get_team($name);
}

sub get_race_category {
    my ($self, $name) = @_;

    my $id = $self->_sql('SELECT id FROM race_category WHERE active=True AND (name=? or abreviation=?)', [ $name, $name ], 'SCALAR');

    # Second lookup in the race_category_alias table
    $id = $self->_sql('SELECT fk_race_category_id FROM race_category_alias WHERE name=?', [ $name ], 'SCALAR')
        if !defined $id;

    return $id;
}

sub get_race_points {
    my ($self, $name) = @_;

    return $self->_sql('SELECT id FROM race_points WHERE name=?', [ $name ], 'SCALAR');
}

sub get_event {
    my ($self, $name, $date, $type) = @_;

    return $self->_sql('SELECT id FROM event WHERE name=? AND event_date=? AND fk_race_type_id=?', [ $name, $date, $type ], 'SCALAR');
}

sub add_event {
    my ($self, $name, $date, $sheet, $race_type_id, $race_points_id) = @_;

    $self->_sql('INSERT INTO event(name,event_date,google_spreadsheet_id,fk_race_type_id,fk_race_points_id) VALUES(?,?,?,?,?)', [ $name, $date, $sheet, $race_type_id, $race_points_id ]);

    return $self->get_event($name, $date, $race_type_id);
}

sub get_result {
    my ($self, $event_id, $racer_id, $race_category) = @_;

    return $self->_sql('SELECT id FROM result WHERE fk_event_id=? AND fk_racer_id=? AND fk_race_category_id=?', [ $event_id, $racer_id, $race_category ], 'SCALAR');
}

sub add_result {
    my ($self, $event_id, $racer_id, $race_category, $racer_category, $start_time, $duration, $duration_unit_id) = @_;

    $self->_sql('INSERT INTO result(fk_event_id,fk_racer_id,fk_race_category_id,fk_racer_race_category_id,start_time,duration,fk_unit_id) VALUES(?,?,?,?,?,?,?)',
        [ $event_id, $racer_id, $race_category, $racer_category, $start_time, $duration, $duration_unit_id ]);

    return $self->get_result($event_id, $racer_id, $race_category);
}

sub merge_team {
    my ($self, $primary, $alias, $short) = @_;
    $self->debug ("In RaceResults::DB::merge_team(${self}, ${primary}, ${alias}, ${short})", 2);

    my $primary_id = $self->get_team($primary);
    croak "Could not find primary name ($primary) in the DB\n" if !defined $primary_id;

    my $alias_id = $self->get_team($alias);
    croak "Could not find alternate name ($alias) in the DB\n" if !defined $alias_id;

    # FIXME: How do we programmatically determine all tables that need to be updated?
    #        Currently we have:
    foreach my $table (qw(racer racer_former_team team_alias)) {
        $self->_sql("UPDATE $table SET fk_team_id=? WHERE fk_team_id=?", [ $primary_id, $alias_id ]);
    }

    if (defined $short and $short) {
        $self->_sql('UPDATE team SET abreviation=? WHERE id=?', [ $alias, $primary_id ]);
    } else {
        # Now shove a new entry into the team_alias table
        $self->_sql('INSERT INTO team_alias(fk_team_id, name) VALUES(?,?)', [ $primary_id, $alias ]);

        # FIXME: Do we need to also add the abreviation field from the alias entry?
    }

    # and finally delete the now stale entry in the team table.
    return $self->_sql('DELETE FROM team WHERE id=?', [ $alias_id ]);
}

sub merge_racer {
    my ($self, $primary, $alias) = @_;
    $self->debug ("In RaceResults::DB::merge_racer(${self}, ${primary}, ${alias})", 2);

    my ($p_first, $p_last) = &RaceResults::parse_name($primary);
    my $primary_id = $self->get_racer_by_name($p_first, $p_last);
    my $p_href = $self->_sql('SELECT * FROM racer WHERE id=?', [$primary_id], 'HASHREF', 'id');
    croak "Could not find primary name ($primary) in the DB\n" if !defined $primary_id;

    my ($a_first, $a_last) = &RaceResults::parse_name($alias);
    my $alias_id = $self->get_racer_by_name($a_first, $a_last);
    my $a_href = $self->_sql('SELECT * FROM racer WHERE id=?', [$alias_id], 'HASHREF', 'id');
    croak "Could not find alternate name ($alias) in the DB\n" if !defined $alias_id;

    # FIXME: How do we programmatically determine all tables that need to be updated?
    #        Currently we have:
    foreach my $table (qw(racer_former_team link_racer_race_category racer_alias result)) {
        $self->_sql("UPDATE $table SET fk_racer_id=? WHERE fk_racer_id=?", [ $primary_id, $alias_id ]);
    }

    # Now shove a new entry into the racer_alias table
    $self->_sql('INSERT INTO racer_alias(fk_racer_id, first_name, last_name) VALUES(?,?,?)', [ $primary_id, $a_first, $a_last ]);

    # Merge the year born if they are different.
    if ($p_href->{$primary_id}->{year_born} != $a_href->{$alias_id}->{year_born}) {
        # FIXME: not sure if using the "oldest" year is the right answer...
        my $current_year = strftime("%Y", localtime(time));

        # If the alias year is unknown (greater than current year), just ignore it...
        # Or if the primary year is older than our alias year, also ignore it...
        if ($a_href->{$alias_id}->{year_born} < $current_year and $a_href->{$alias_id}->{year_born} < $p_href->{$primary_id}->{year_born}) {
            $self->update_racer($primary_id, 'year_born', $a_href->{$alias_id}->{year_born});
        }
    }

    # Handle the team and start date for the team.
    if ($p_href->{$primary_id}->{fk_team_id} != $a_href->{$alias_id}->{fk_team_id}) {
        # If the team's don't match, then use the more recent team value as the current one
        # and put the the older one in the former table.
        if ($a_href->{$alias_id}->{team_start_date} < $p_href->{$primary_id}->{team_start_date}) {
            $self->_sql('INSERT INTO racer_former_team VALUES(?,?,?)', [
                $primary_id,
                $a_href->{$alias_id}->{fk_team_id},
                $a_href->{$alias_id}->{team_start_date}
            ]);

        # Take the current team and put it into the former table
        } else {
            $self->_sql('INSERT INTO racer_former_team VALUES(?,?,?)', [
                $primary_id,
                $p_href->{$alias_id}->{fk_team_id},
                $p_href->{$alias_id}->{team_start_date}
            ]);
            $self->update_racer($primary_id, 'fk_team_id', $a_href->{$alias_id}->{fk_team_id});
            $self->update_racer($primary_id, 'team_start_date', $a_href->{$alias_id}->{team_start_date});
        }

    } else {
        # the teams matched, so then compare the dates...
        $self->update_racer($primary_id, 'team_start_date', $a_href->{$alias_id}->{team_start_date})
            if $a_href->{$alias_id}->{team_start_date} < $p_href->{$primary_id}->{team_start_date};
    }

    # Merge the license values, if set...
    # If the alias license number is greater, then use that value, otherwise just drop it.
    if (!$a_href->{$alias_id}->{license_number} and
         $p_href->{$primary_id}->{license_number} != $a_href->{$alias_id}->{license_number} and
         $a_href->{$alias_id}->{license_number} > $p_href->{$primary_id}->{license_number}) {
        $self->update_racer($primary_id, 'license_number', $a_href->{$alias_id}->{license_number});
        $self->update_racer($primary_id, 'license_current', $a_href->{$alias_id}->{license_current});
    }

    # and finally delete the now stale entry in the racer table.
    return $self->_sql('DELETE FROM racer WHERE id=?', [ $alias_id ]);
}

#
# Interal Functions - Only called within this file.
#

# Query the DB to get the list of tables, later used in get_*() routines
# to do secondary queries in the <TABLE>_alias tables.
sub _get_tables {
    my ($self) = @_;

    # Purge the old list of tables
    delete $self->{tables} if defined $self->{tables};

    # Now ask for the list of tables, SQLite specific, and map into a hash for quick searches
    map {
        $self->{tables}->{$_} = 1;
    } @{$self->_sql(q(select tbl_name from sqlite_master where type=? and tbl_name not like ?;), [ 'table', 'sqlite%' ], 'ARRAY')}
}

sub _sql {
    my ($self, $sql, $values, $type, $key) = @_;
    $values //= [];
    $self->debug ("RaceResults::_sql($sql, [ @{$values} ], $type, $key)", 4);

    return if $self->noop();

    my ($sth) = $self->{dbh}->prepare($sql);

    return undef if !defined $sth;

    $sth->execute(@{$values}) or return undef;

    if ( defined $type ) {
        if ( $type eq 'ARRAY' ) {
            my $ref = $sth->fetchall_arrayref;
            my @a;
            foreach my $i ( @{$ref} ) {
                map { push @a, $_ } @{$i};
            }
            return ( \@a );
        } elsif ( $type eq 'SCALAR' ) {
            my $ref = $sth->fetchall_arrayref;
            $self->debug ("Returing (" . ${$ref}[0][0] . ")", 4);
            return ${$ref}[0][0];
        } else {
            return $sth->fetchall_hashref($key);
        }
    }

    return '';
}

1;
