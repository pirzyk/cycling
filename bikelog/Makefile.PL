#
#  Copyright 2009-2026 Jim Pirzyk / pirzyk.org
#  All rights reserved.
#
#  Makefile.PL
#

use ExtUtils::MakeMaker;
use Config;
use strict;

WriteMakefile(
	NAME			=> 'BikeLog',
	DISTNAME		=> 'bikelog',
	AUTHOR		=> 'Jim Pirzyk <jim+bikelog@pirzyk.org>',
	PERM_RWX		=> 700,
	PERM_RW		=> 600,
	PMLIBDIRS		=> [ 'lib' ],
	VERSION_FROM	=> 'bin/bikelog-cmd.pl',
	PREREQ_PM		=> {
		     'GD' => 0,
		     'DBI' => 0,
     		'DBD::SQLite' => 0,
	},
);
