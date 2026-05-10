#!/usr/bin/env perl

use strict;
use warnings 'all';

use Carp;
use Data::Dumper;
use Date::Parse;
use Getopt::Long;
use JSON qw(decode_json);
use POSIX;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use RaceResults;
use RaceResults::DB;

my $max = 20;
my $points = '20 places';
my $duration_units = '1/100th Seconds';
sub usage {
    print "Usage: $0 [--debug=N] --sheet <GOOGLE_SPREADSHEET_ID> --db <DATABASE_NAME>\n";
    print "\t--duration UNIT\tThe duration is recorded in these units (defaults to $duration_units)\n";
    print "\t--max ROWS\tThe maximum number of rows before we fail to find the first racer (defaults to $max)\n";
    print "\t--points NAME\tThe points list we use for the season series (defaults to $points)\n";
    print "\t--sheet ID\tThe Google sheet ID to process (REQUIRED)\n";
    print "\t--db DB\t\tThe SQLite Database (REQUIRED)\n";
    exit 1;
}

my ($WHO, $sheet, $db, $TTT_flag);
my $debug = 0;
my $current_year = strftime("%Y", localtime(time));
my $year_regex = qr/\b20[0-3][0-9]\b/;      # Only works between 2000 and 2039.
my $month_regex = qr/\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(:?ember)?)?|Oct(?:ober)?|(Nov|Dec)(?:ember)?)/;
my $day_regex = qr/\b(:?Sun|Mon|Tue(:?s)?|Wed(:?nes)?|Thu(:?rs)?|Fri|Sat(:?ur)?)(?:day)?\b/;

&Getopt::Long::Configure ("bundling");
GetOptions (
    'db=s'       => \$WHO,
    'duration=s' => \$duration_units,
    'max=i'      => \$max,
    'points=s'   => \$points,
    'sheet=s'    => \$sheet,
    'debug=i'    => \$debug,
) || usage();

usage() if !defined $WHO or !defined $sheet;

my $sheet_base = $RaceResults::CACHEDIR . '/' . $sheet;

# Process the spreadsheet metadata
croak "Cannot find cached Google Spreadsheet metdata file for ($sheet)"
    if ! -f "${sheet_base}.json";

my $json = decode_json RaceResults::slurp("${sheet_base}.json");
#print Dumper($json);

my @tabs;
map {
    push @tabs, $_->{properties}->{title};
} @{$json->{sheets}};

croak "Could not parse (or validate) Google Spreadsheet metadata"
    if !defined $json or
       $json->{spreadsheetId} ne $sheet or                                  # The internal spreadsheet id doesn't match the filename we loaded...
       ! scalar @tabs;

sub normalize_title {
    my ($title) = @_;

    $title = &RaceResults::normalize_string($title);
    # Known spreadsheet title tweaks
    $title =~ s/\s*Start.*$//i;

    return $title;
}

# Try to find the row that contains the first racer data.
# If we've gone more than N rows, we probably should fail.
sub find_first_racer {
    my ($columns, $rows) = @_;

    for (my $row = 0; $row < $max; $row++) {
        next if scalar @{$rows->[$row]} < 7;

        if (grep /Start Time/, @{$rows->[$row]}) {

            # Now loop through the columns in this row to assign values to use later on.
            for (my $col = 0; $col < scalar @{$rows->[$row]}; $col++) {
                my $col_title = $rows->[$row]->[$col];

                $columns->{Bib} = $col if !exists $columns->{Bib} and ($col_title =~ /^(Rider )?Number/i or $col_title =~ /^BIB/i);
                $columns->{Start} = $col if $col_title =~ /^Start Time/i;
                $columns->{Name} = $col if $col_title =~ /^(Rider )?Name/i;
                $columns->{FirstName} = $col if $col_title =~ /^First Name/i;
                $columns->{LastName} = $col if $col_title =~ /^Last Name/i;
                $columns->{Cat} = $col if !exists $columns->{Cat} and ($col_title =~ /^Cat(egory)?$/i or $col_title =~ /^Race Class$/i);
                $columns->{Team} = $col if $col_title =~ m|^(Club/)?Team( Name)?|i;
                $columns->{TimeIn} = $col if $col_title =~ /^([24]0k )?Time In/i;
                $columns->{Duration} = $col if $col_title =~ /^([24]0k )?Finish Time/i or $col_title =~ /^Result/i;
            }
            #print Dumper($columns);

            return ($row+1);
        }
    }

    return undef;
}

sub find_date {
    my ($first_race, $title, $rows) = @_;
    print "In find_date($first_race, $title, $rows)" if $debug > 3;
    my ($race_date, $race_year);

    # Maybe the title has the year defined?
    $race_year = $1 if $title =~ /(${year_regex})/;

    for (my $row = 0; !defined $race_date and $row < $first_race; $row++) {
        for (my $col = 0; !defined $race_date and $col < @{$rows->[$row]}; $col++) {
            # Try to find the date in a format similar to: "Sunday, Sept 8 Camp Shaw Waw Nas See, Manteno, Illinois"
            if ($rows->[$row]->[$col] =~ /((${day_regex})?,? ${month_regex} [0-9]+([a-z][a-z])?,?( ${year_regex})?)/i) {
                my $d = $1;
                # Append the year if we didn't actually match the year
                $d .= " $race_year" if $d !~ /${year_regex}/;
                my $ts = str2time($d);
                if (defined $ts) {
                    $race_date = strftime("%Y-%m-%d", localtime($ts));
                    my $y = strftime("%Y", localtime($ts));
                    $race_year = $y if !defined $race_year;
                }
            }
        }
    }

    print " => ($race_date, $race_year)\n" if $debug > 3;
    return ($race_date, $race_year);
}

# Routine to guess a racer's birth year based on what age categories they participate in
# Eventually the guessed years should converge on our real answer as we process many years
# of race data.  The racer should age up into new age categories, so we should be less and less
# off in our guesses.
sub guess_year_born {
    my ($race_year, $cat, $prev_year) = @_;
    my ($res);
    print "In guess_year_born($race_year, $cat, $prev_year)" if $debug > 3;

    if ($cat =~ /([0-9]+)\s*-\s*([0-9]+)/) {
        my ($oldest_year, $youngest_year) = (($race_year - $2), ($race_year - $1));
        print " ($oldest_year, $youngest_year)" if $debug > 3;

        # If we don't have a previous guess or it is greater than the current year, use the oldest year born
        $res = $oldest_year if !defined $prev_year or $current_year < $prev_year;

        # If our previous guessed year is inbetween the new guesses, leave it alone.
        $res = $prev_year if !defined $res and $oldest_year < $prev_year and $prev_year < $youngest_year;

        # We don't have a match between our guessed_year and what is in the DB

        # If the previous year is greater than our oldest guess, use our new oldest guess.
        $res = $oldest_year if !defined $res and $prev_year < $oldest_year;
        $res = $youngest_year if !defined $res and $prev_year > $youngest_year;

        # If we get here, just don't change it...
        $res = $prev_year if !defined $res;

    } else {
        # Making this a year > current year is a flag that we don't know the real year.
        $res = (defined $prev_year ? $prev_year : 2099);
    }

    print " => $res\n" if $debug > 3;
    return $res;
}

sub calculate_duration {
    my ($duration) = @_;

    if ( $duration eq '#VALUE!') {
        $duration = 0;
    } else {
        my $factor = ($duration_units =~ m|1/100th|)
                     ? 100.00
                     : ($duration_units =~ m|1/10th|)
                       ? 10.00
                       : 1.0;

        $duration = (RaceResults::convert2sec($duration) * $factor);
    }

    return $duration;
}

sub parse_tab {
    my ($title, $tab, $race_points_id, $duration_unit_id) = @_;
    print "In parse_tab($title, $tab, $race_points_id, $duration_unit_id)\n" if $debug > 3;
    my (%columns);

    my $json_val = decode_json RaceResults::slurp("${sheet_base}-${tab}-values.json");
    #print Dumper($json_val);

    croak "Could not parse (or validate) Google Spreadsheet tab ($tab) values"
        if !defined $json_val or !exists $json_val->{values};

    my $first_race = &find_first_racer(\%columns, $json_val->{values});
    croak "Could not parse the spreadsheet header" if !defined $first_race;

    my ($race_date, $race_year) = &find_date($first_race, $title, $json_val->{values});
    croak "Could not find the start date in the spreadsheet" if !defined $race_date;

    # Based on the race title, we select a different race_type value.
    $TTT_flag = ($title =~ /Team/i or $title =~ /(2|Two) person/i) ? 1: 0;
    my $race_type_id = $TTT_flag
                        ? $db->get_race_type('Team Time Trial')
                        : ($title =~ / Crit/)
                            ? $db->get_race_type('Criterium')
                            : ($title =~ / Road Race/)
                                ? $db->get_race_type('Road Race')
                                : $db->get_race_type('Time Trial');

    # Check to see if we already have this event in the DB
    my $event_id = $db->get_event($title, $race_date, $race_type_id);
    $event_id = $db->add_event($title, $race_date, $sheet, $race_type_id, $race_points_id) if !defined $event_id;
    croak "Could not add the event into the DB" if !defined $event_id;

    my $results = $json_val->{values};
    for (my $row = $first_race; $row < scalar @{$results}; $row++) {
        my $bib = defined $columns{Bib} ? $results->[$row]->[$columns{Bib}] : undef;
        my $start_time = defined $columns{Start} ? $results->[$row]->[$columns{Start}] : undef;
        my $cat = defined $columns{Cat} ? $results->[$row]->[$columns{Cat}] : undef;
        my $team = defined $columns{Team} ? $results->[$row]->[$columns{Team}] : undef;
        my $timein = defined $columns{TimeIn} ? $results->[$row]->[$columns{TimeIn}] : undef;
        my $duration = defined $columns{Duration} ? $results->[$row]->[$columns{Duration}] : undef;

        # Stop processing the array once we stop having a Bib number
        last if !defined $bib or $bib !~ /^[0-9]+$/;

        # Find the racer's name
        my ($first, $last, $name);
        my $no_name_flag = 1;
        if (exists $columns{Name}) {
            ($first, $last) =  &RaceResults::parse_name($results->[$row]->[$columns{Name}]);
        } elsif (exists $columns{FirstName} and exists $columns{LastName}) {
            ($first, $last) =  &RaceResults::parse_name($results->[$row]->[$columns{FirstName}], $results->[$row]->[$columns{LastName}]);
        }
        $no_name_flag = 0 if defined $first and $first ne '' and defined $last and $last ne '';

        # Skip if we don't have a name or dns
        next if $no_name_flag or
                !defined $cat or $cat eq '' or $cat =~ /^WIS / or
                (defined $timein and ($timein =~ /^dns$/i or $team =~ /CLOSED/i));

        # Find the team
        $team = &RaceResults::normalize_string($team);
        $team = 'Unattached' if $team eq '';
        my $team_id = $db->get_team($team);
        $team_id = $db->add_team($team) if !defined $team_id;
        croak "Could not add the team ($team) into the DB" if !defined $team_id;

        # Find the race_categories
        $cat = &RaceResults::normalize_string($cat);
        $cat =~ s/,\s*/,/g; # FIXME: tired of adding yet more permuatations on the ability categories... (this handies X,<SP>Y)
        my $race_category_id = $db->get_race_category($cat);
        croak "Could not find the race_category ($cat)" if !defined $race_category_id;
        # TODO: What column is this data in?
        #if ($TTT_flag) {
        #}

        my $racer_id = $db->get_racer_by_name($first, $last);
        if (!defined $racer_id) {
            my $guessed_year = &guess_year_born($race_year, $cat);
            $racer_id = $db->add_racer($first, $last, $guessed_year, $team_id, $race_date);
            croak "Could not add the racer ($first $last, $guessed_year, $team_id, $race_date) into the DB" if !defined $racer_id;

        # Do we need to update the year_born or the team_start_date ?
        } else {

            # If we guessed a different year than what we have in the DB, update it.
            my $cur_year_born = $db->get_racer_by_id($racer_id, 'year_born');
            my $guessed_year = &guess_year_born($race_year, $cat, $cur_year_born);
            $db->update_racer($racer_id, 'year_born', $guessed_year)
                if $cur_year_born != $guessed_year;

            # This race is earlier than the cur_team_date for this racer
            my $cur_team_date = $db->get_racer_by_id($racer_id, 'team_start_date');
            my $cur_team_id = $db->get_racer_by_id($racer_id, 'fk_team_id');
            $db->update_racer($racer_id, 'team_start_date', $race_date)
                if $cur_team_id == $team_id and $race_date lt $cur_team_date;
        }

        # Validate the start time ($start_time) and duration
        $duration = 0 if !defined $duration and defined $timein and $timein =~ /dnf/;
        croak "Could not validate the start time ($start_time)\n" if $start_time !~ /^([0-9]+:)?[0-5][0-9]:[0-5][0-9]$/;
        $duration = &calculate_duration($duration);

        # Now we add the result record
        if (!$db->get_result($event_id, $racer_id, $race_category_id)) {
            # FIXME: handled the TTT case with the racer_race_category
            my $result_id = $db->add_result($event_id, $racer_id, $race_category_id, undef, $start_time, $duration, $duration_unit_id );
        }
    }
}

# Now start parsing the spreadsheet data...
my $title = &normalize_title($json->{properties}->{title});
croak "Could not find the spreadsheet title" if !defined $title;

$db = RaceResults::DB->new(
            file => $RaceResults::DBDIR . '/' . $WHO . '.sqlite',
            debug => $debug
         );

# FIXME: handle the case where we have different race points per tab (aka ominum series)
my $race_points_id = $db->get_race_points($points);
croak "Could not find the race points scale" if !defined $race_points_id;

# Now start collecting the data for each result table entry
my $duration_unit_id = $db->get_unit($duration_units);
croak "Could not find the race result units" if !defined $duration_unit_id;

foreach my $tab (@tabs) {
    &parse_tab($title, $tab, $race_points_id, $duration_unit_id);
}

$db->close_db;

exit 0;
