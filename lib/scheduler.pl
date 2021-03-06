#!/usr/bin/perl

## main task of this script: check if time has come for new updates

use warnings;
use strict;

use Config::INI::Reader;
use Config::INI::Writer;
use FindBin;
use Time::Piece;

require "$FindBin::Bin/getUpdates.pl";
require "$FindBin::Bin/updateDelete.pl";
require "$FindBin::Bin/optimize.pl";

require "$FindBin::Bin/helper.pl";
our $timeFormat;

my $configs = Config::INI::Reader->read_file("$FindBin::Bin/../etc/config.ini");
my @verbuendeWithUpdates;

my @verbuende = keys %$configs;
foreach my $verbund(@verbuende){
	
	# skip global ini vars
	next if $verbund eq '_';
	
	if($configs->{$verbund}->{'check'} eq '0'){
		&logMessage("WARNING", "($verbund) will not be checked for updates due to check=0!");
		next;
	}
	elsif($configs->{$verbund}->{'updateIsRunning'} eq '1'){
		&logMessage("WARNING", "($verbund) update already in progress and locked by config.ini");
		next;
	}
	else{
		# check when last update took place
		my $lastUpdate = $configs->{$verbund}->{'lastUpdate'};
		
		my $now = &getTimeStr();
		my $diff = Time::Piece->strptime($now, $timeFormat) - Time::Piece->strptime($lastUpdate, $timeFormat);
		
		my $days = $configs->{$verbund}->{'updateIntervalInDays'};
		if($diff->days > $days){
			my @v = &getUpdates(($verbund));
			push(@verbuendeWithUpdates, @v);
		}
		else{
			&logMessage("INFO", "($verbund) Last update newer than $days days ($lastUpdate). Skip looking for updates.");
		}
	}
}

&logMessage("DEBUG", "verbuendeWithUpdates: @verbuendeWithUpdates");

foreach my $verbund(@verbuendeWithUpdates){
	next if $verbund eq '_';
	
	if($configs->{$verbund}->{'updateIsRunning'} eq '1'){
		&logMessage("WARNING", "($verbund) update in progress - wait for update to apply changes");
		next;
	}
	
	# apply updates and deletions
	&updateDelete($verbund);
	
	# optimize core if possible
	&optimize($verbund);
}
