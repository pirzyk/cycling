#!/usr/bin/env perl

use strict;
use warnings 'all';

use Data::Dumper;
use File::Basename;
use Storable qw(dclone);
use FindBin qw($Bin);
use lib "$Bin/../lib";

# Needed because we need to query the DB for race_type.id values
use RaceResults;
use RaceResults::DB;

my $WHO = basename $0;
$WHO =~ s/-.*$//;

# Output file
my $sql_file = $RaceResults::INITDIR . '/' . $WHO . '.sql';

# DB file
my $db_file = $RaceResults::DBDIR . '/' . $WHO . '.sqlite';

my $SQL_race_category = qq/INSERT INTO race_category(id,name,abreviation,fk_race_type_id) VALUES/;
my $SQL_race_category_alias = qq/INSERT INTO race_category_alias(fk_race_category_id,name) VALUES/;

my %bike = (
    'Road Bike' => { short => 'RB' },
    'TT Bike' => { short => 'TT' },
);

# Prefer Female vs Women as it better handles the Junior (i.e. under 18) case.
#   TODO: Do we need to handle the under 18 gender names (boys, girls) as a race_category_alias value?
my %g = (
    'Open' => { alt => 'Men', short => 'O', salt => 'M' },
    'Female' => { alt => 'Women', short => 'F', salt => 'W' },
);

# TODO: These hashes are based on race_type values from the DB and needs to be kept in sync.
my %age = (
    'Time Trial' => [
        [0, 14],
        [15, 18],
        [19, 29],
        [30, 39],
        [40, 49],
        [50, 54],
        [55, 59],
        [60, 64],
        [65, 69],
        [70, 74],
        [75, 79],
        [80, 84],
        [85, 89],
        [90, 94],
        ['95+'],
    ],
    'Team Time Trial' => [
        [0, 18],
        [19, 29],
        [30, 39],
        [40, 49],
        [50, 59],
        [60, 69],
        [70, 79],
        ['80+']
    ],
);

# The performance categories, has implied alternate names (delimiters / and ,)
my %perf = (
    'Time Trial' => [
        [1, 2],
        [3],
        [4, 5],
    ],
    'Team Time Trial' => [
        [1, 2, 3],
        [4, 5],
    ],
);

# The <TOKEN> syntax is to say to iterate through the matching hash name as TOKEN
my %cats = (
    'Time Trial' => [
        { name => '<BIKE> <G> Cat <PERF>', short => '<BIKE> <G> <PERF>' },
        { name => '<BIKE> <G> <AGE>', short => '<BIKE> <G> <AGE>' },
        { name => 'Tandem', short => 'Tand/Rec' },
        { name => 'Recumbent', alt => 'Recumbant' },
        { name => 'Fixed / Single Speed', alt => 'Fixed' => alt2 => 'Single Speed' },
        { name => 'Para Upright (aka can ride a normal bike)', short => 'Para Upright' },
        { name => 'Para Tricycle', short => 'Tricycle' },
        { name => 'Para Tandem (blind)', short => 'Para Tandem' },
        { name => 'Para Handcycle', short => 'Handcycle' },
        { name => 'Eddy Merckx', alt => 'Eddy Merckz' },     # FIXME: Single road bike category pre 2024 and should be inserted into the DB as inactive
    ],
    'Team Time Trial' => [
        { name => '<BIKE> <G> Cat <PERF>', short => '<BIKE> <G> <PERF>' },
        { name => '<BIKE> <G> <AGE>',  short => '<BIKE> <G> <AGE>' },
        { name => '<BIKE> Mixed Gender', short => '<BIKE> Mixed' },
        { name => '<BIKE> Mixed Gender 60 - 80+', short => '<BIKE> Mixed 60-80' },
    ],
);

# Query the DB to get the current fk_race_type_id values
my $db = RaceResults::DB->new(file => $db_file);
my %race_type_ids = ();
foreach my $type (keys %cats) {
    $race_type_ids{$type} = $db->get_race_type($type);
}
$db->close_db;

sub expand_bike_token {
    my ($hcat) = @_;
    my @res;

    for my $b (keys %bike) {
        my $tcat = dclone $hcat;

        for my $k (keys %{$tcat}) {
            if ($k =~ /^s/) {
                $tcat->{$k} =~ s/<BIKE>/$bike{$b}->{short}/g;
            } else {
                $tcat->{$k} =~ s/<BIKE>/$b/g;
            }
        }

        # Pre 2024, we only had TT categories
        # So create a short alternate name of the format <G> <AGE|PERF>
        if ($b eq 'TT Bike' and exists $tcat->{short}) {
            $tcat->{short_b} = $hcat->{short};
            $tcat->{short_b} =~ s/<BIKE> //g;
            $tcat->{salt_b} = $hcat->{short};
            $tcat->{salt_b} =~ s/<BIKE> //g;
        }

        push @res, $tcat;
    }

    return @res;
}

sub expand_g_token {
    my ($hcat) = @_;
    my @res;

    for my $g2 (keys %g) {
        my $tcat = dclone $hcat;

        # Create a new entry if we don't have an existing entry in the category hash
        #   but have an alternate key in the %g hash
        for my $k (keys %{$g{$g2}}) {
            if (!exists $tcat->{$k}) {
                my $k2 = $k =~ /^s/ ? 'short' : 'name';
                $tcat->{$k} = $hcat->{$k2};   # Copied from the original because we know it has not been modifed.
            }
        }

        for my $k (keys %{$tcat}) {

            # Now remove the <G> token in our category.
            if (exists $g{$g2}->{$k}) {
                $tcat->{$k} =~ s/<G>/$g{$g2}->{$k}/g;
            } elsif ($k =~ /^s/) {
                my $g3;
                if ($k =~ /^salt/ ) {
                    $g3 = $g{$g2}->{salt};
                } else {
                    $g3 = $g{$g2}->{short};
                }
                $tcat->{$k} =~ s/<G>/$g3/g;
            } else {
                $tcat->{$k} =~ s/<G>/$g2/g;
            }
        }

        # For the Open Case, create a short one that has no gender token
        if ($g2 eq 'Open' and exists $tcat->{short}) {
            $tcat->{salt_g} = $hcat->{short};
            $tcat->{salt_g} =~ s/<G> //g;
        }
        push @res, $tcat;
    }

    return @res;
}

sub expand_age_token {
    my ($hcat, $type) = @_;
    my @res;

    for my $a (@{$age{$type}}) {
        my $tcat = dclone $hcat;
        my ($agestr, $s_agestr, $s_agestr2);

        if (scalar @${a} eq 2) {

            # Handle the Junior special cases
            if ($a->[0] < 19) {
                if ($a->[0] == 0) {
                    $agestr = "Junior $a->[1] and Under";
                } else {
                    $agestr = "Junior $a->[0] - $a->[1]";
                }

            # The most common case of X - Y
            } else {
                $agestr = "$a->[0] - $a->[1]";
            }
            $s_agestr = "$a->[0]-$a->[1]";
            $s_agestr2 = "$a->[0]+";

        # aka 95+
        } else {
            $agestr = $s_agestr = $a->[0];
        }

        for my $k (keys %{$tcat}) {
            # Now remove the <AGE> token in our category.
            if ($k =~ /^s/) {
                $tcat->{$k} =~ s/<AGE>/$s_agestr/g;
                # Add a <LOWER_AGE>+ category mapping too...
                if (defined $s_agestr2) {
                    $tcat->{"${k}_a"} = $hcat->{$k};
                    $tcat->{"${k}_a"} =~ s/<AGE>/$s_agestr2/g;
                }
            } else {
                $tcat->{$k} =~ s/<AGE>/$agestr/g;
            }
        }

        push @res, $tcat;
    }

    return @res;
}

sub expand_perf_token {
    my ($hcat, $type) = @_;
    my (@res, $i, $j, $j2, $j3);

    $i = 0;
    for my $p (@{$perf{$type}}) {
        my $tcat = dclone $hcat;

        # Trying to support / , and - ...
        if (scalar @{$p} > 2) {
            $j = join('/', @{$p});
            $j2 = join(',', @{$p});
            $j3 = "$p->[0]-$p->[2]";
        } elsif (scalar @{$p} == 2 ) {
            $j = "$p->[0]/$p->[1]";
            $j2 = "$p->[0],$p->[1]";
            $j3 = "$p->[0]-$p->[1]";
        } else {
            $j = $p->[0];
            $j2 = $j3 = undef;
        }

        for my $k (keys %{$tcat}) {
            $i++;
            $tcat->{$k} =~ s/<PERF>/$j/g;

            # The alternate delimiters perf cats
            if (defined $j2) {
                $tcat->{"${k}_${i}"} = $hcat->{$k};
                $tcat->{"${k}_${i}"} =~ s/<PERF>/$j2/g;
            }
            if (defined $j3) {
                $tcat->{"${k}_${i}2"} = $hcat->{$k};
                $tcat->{"${k}_${i}2"} =~ s/<PERF>/$j3/g;
            }
        }
        push @res, $tcat;
    }

    return @res;
}

sub expand_token {
    my ($token, $type, $hcat) = @_;
    my @res;

    if ($token eq '<BIKE>' and $hcat->{name} =~ /${token}/) {
        push @res, &expand_bike_token($hcat);
    } elsif ($token eq '<G>' and $hcat->{name} =~ /${token}/) {
        push @res, &expand_g_token($hcat);
    } elsif ($token eq '<AGE>' and $hcat->{name} =~ /${token}/) {
        push @res, &expand_age_token($hcat, $type);
    } elsif ($token eq '<PERF>' and $hcat->{name} =~ /${token}/) {
        push @res, &expand_perf_token($hcat, $type);
    } else {
        push @res, $hcat;
    }

    return @res;
}

my %exp_cats = ();

my $id = 1;
foreach my $type (keys %cats) {
    my $fk_race_type_id = $race_type_ids{$type};
    @{$exp_cats{$type}->{categories}} = ();
    $exp_cats{$type}->{fk_race_type_id} = $fk_race_type_id;


    foreach my $href (@{$cats{$type}}) {
        my $cat = $href->{name};
        # Expand each of the tokens we know about
        foreach my $a (&expand_token('<BIKE>', $type, $href )) {
            foreach my $b (&expand_token('<G>', $type, $a)) {
                foreach my $c (&expand_token('<AGE>', $type, $b)) {
                    foreach my $d (&expand_token('<PERF>', $type, $c)) {
                        $d->{id} = $id++;
                        push @{$exp_cats{$type}->{categories}}, $d;
                    }
                }
            }
        }
    }
}
#print Dumper (\%exp_cats);

# Now write out our sql statements after we've generated all those permutations.
my $FP;
unlink($sql_file);
open($FP, "> $sql_file") || die "Could not create sql file ($sql_file)\n";
foreach my $type (sort keys %exp_cats) {
    my $h = $exp_cats{$type};
    my $fk_race_type_id = $h->{fk_race_type_id};
    for (my $i = 0; $i < scalar @{$h->{categories}}; $i++) {
        my $j = $h->{categories}[$i];
        printf $FP "%s(%s, %s, %s, %s);\n",
            $SQL_race_category,
            $j->{id},
            "'" . $j->{name} . "'",
            exists $j->{short} ? "'" . $j->{short} . "'": 'NULL',
            $fk_race_type_id;

        # Any alternate fields we created, put them in the alias table.
        for my $field (sort keys %{$j}) {
            next if $field eq 'name' or $field eq 'short' or $field eq 'id';
            if (exists $j->{$field}) {
                printf $FP "%s(%s, %s);\n",
                    $SQL_race_category_alias,
                    $j->{id},
                    "'" . $j->{$field} . "'";
                }
        }
    }
}

close $FP;

exit 0;
