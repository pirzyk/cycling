#!/usr/bin/env perl
#
#	@(#) bikelog-cmd v4.0.0 command line backend for BikeLog Training Program
#

use strict;
#use warnings;
use DBI;
use Data::Dumper;
use GD;
use Getopt::Long;
use File::Path;

use FindBin;
use lib "$FindBin::Bin/../lib";

use BikeLog;
use BikeLog::Tables::bike;

my $dbDir = "$FindBin::Bin/../db";
my $noop = 0;
our $VERSION = '4.0.0';

Getopt::Long::Configure ('bundling');

# Lookup table for the sub and sub-sub commands,
my $cmds = {
	'add' => { 'module' => 'BikeLog::Tables::bike::add_module', },
	'create' => 'create',
	'set' => { 'zone' => 'BikeLog::Tables::bike::set_zone', },
	'sql' => 'sql',
};

sub usage {
	print "Usage: $0 [-hnxV] [-d DB] COMMAND\n";
	print "\t-d DB\tUse DB as the default database\n";
	print "\t-h\tThis help screen\n";
	print "\t-n\tSimulate Execution, don't actually run commands\n";
	print "\t-x\tTrace Execution\n";
	print "\t-V\tVersion ($VERSION)\n";
	print "\nwhere COMMAND is one of the following:\n";
	print "\tcreate\t\tCreate a database in DB directory\n";
	printf "\tinsert TABLE VALUE(s)\tInsert VALUE(s) into TABLE\n";
	printf "\tprint TABLE\t\tPrint out values in TABLE\n";
	printf "\tadd module MODULE \tEnable the module MODULE\n";
	printf "\tset TABLE ...\t\tset some values on TABLE\n";
	printf "\treport MODULE ...\tRun report on module MODULE\n";
	printf "\tgraph MODULE ...\tGraph summary report data on module MODULE\n";
	printf "\tsync MODULE ...\t\tSync data in module MODULE with external source\n";
	exit 0;
}

sub version {
	print "$0: $VERSION\n";
	exit 0;
}

sub cmd {
	my ($sub, @args) = @_;
	debug ("In cmd($sub, [" . join(',', @args) . "])", 0);

	# Start with the command at the table specific level,
	# then the generic table level,
	# finally to the program level
	my $module = shift @args;
	my $code;
	if ( defined $module ) {
		$code = 'BikeLog::Tables::' . $module . '::'. $sub;
		debug ("trying $code", 1);
		eval { no strict; &{$code}( @args ); }
	}
	if ( ! defined $module || $@ =~ /^Undefined subroutine / ) {
		debug ("returned $@", 2);
		if ( defined $module ) {
			unshift @args, ( $module );
			$code = 'BikeLog::Tables::' . $sub;
			debug ("trying $code", 1);
			eval { no strict; &{$code}( @args ); };
		}
		if ( ! defined $module || $@ =~ /^Undefined subroutine / ) {
			debug ("returned $@", 2);
			debug ("trying $sub", 1);
			if ( exists $cmds->{$sub} ) {
				if ( ref $cmds->{$sub} eq 'HASH' ) {
					my $sub2 = shift @args;
					if ( exists $cmds->{$sub}->{$sub2} ) {
						eval { no strict; &{$cmds->{$sub}->{$sub2}}( @args ); };
						die $@ if ( length ($@) );
					} else {
						die "Can't understand ($sub $sub2)\n";
					}
				} else {
					eval { no strict; &{$cmds->{$sub}}( @args ); };
					die $@ if ( length ($@) );
				}
			} else {
				die "Unknown sub command ($sub)\n";
			}
		} elsif ( length ($@) ) {
			die $@;
		}
	} elsif ( length ($@) ) {
		die $@;
	}

	return 0;
}

sub create {
	debug ("In create()", 0);

	mkpath ([$dbDir], 1, 0700)
		if ( ! -d $dbDir );

	# Setup the basic tables
	&BikeLog::Tables::bike::create();
}

# Unadvertised command to run SQL statements on our database
# for what ever reason we missed.
sub sql {
	my (@sql) = @_;
	my ($cmd);
	debug ("In sql([" . join(',', @sql) . "])", 0);

	$cmd = join (' ', @sql);
	map {
		print join(' ', @{$_}) . "\n";
	} @{&BikeLog::Tables::_sql($cmd, '')};
}

# Start the program by checking command line arguments
&usage() if ( !&GetOptions (
	'd=s'	=> \$dbDir,
	'h'		=> \&usage,
	'V'		=> \&version,
	'n'		=> \&BikeLog::set_noop,
	'x+'		=> \&BikeLog::set_debug,
));
&usage()  if ( scalar @ARGV < 1 );

&BikeLog::Tables::open_db($dbDir);

my $err=&cmd ( @ARGV );

&BikeLog::Tables::close_db();

exit $err;

__END__

=head1 NAME

bikelog-cmd - command line backend for BikeLog Training Program

=head1 SYNOPSIS

bikelog-cmd [-hnxV] [-d DB] COMMAND

=head1 DESCRIPTION

=head1 COMMAND(s)

=over 4

=item C<create>

=over 4

=back

=item C<insert> I<TABLE> I<VALUE(s)...>

=over 4

=back

=item C<print> I<TABLE>

=over 4

=back

=item C<add> module I<MODULE>

=over 4

=back

=item C<set> I<TABLE>

=over 4

=back

=item C<report> I<MODULE> I<...>

=over 4

=back

=item C<graph> I<MODULE> I<...>

=over 4

=back

=item C<sync> I<MODULE> I<...>

=over 4

=back

=back

=cut
