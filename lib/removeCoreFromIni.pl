#!/usr/bin/perl

use warnings;
use strict; 

use Config::INI::Reader;
use Config::INI::Writer;
use FindBin;

require "$FindBin::Bin/helper.pl";

die("internal error - missing parameter CORE") if scalar(@ARGV) < 1;

my $pathConfigIni = "$FindBin::Bin/../etc/config.ini";
my $configs = Config::INI::Reader->read_file($pathConfigIni);
my $core = $ARGV[0];
delete $configs->{$core};
Config::INI::Writer->write_file($configs, $pathConfigIni);
&logMessage("WARNING", "($core) has been removed from config.ini", 1);
