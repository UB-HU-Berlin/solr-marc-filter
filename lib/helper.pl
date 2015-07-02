#!/usr/bin/perl

use warnings;
use strict;
use Config::INI::Reader;
use FindBin;

my $configs = Config::INI::Reader->read_file("$FindBin::Bin/../etc/config.ini");

sub getTimeStr(){
	my @time = localtime(time);
	my $year  	= $time[5] + 1900;
	my $month 	= &leadingZeroScalar($time[4] + 1);
	my $monthDay= &leadingZeroScalar($time[3]);
	my $h = &leadingZeroScalar($time[2]);
	my $m = &leadingZeroScalar($time[1]);
	my $s = &leadingZeroScalar($time[0]);
	
	return "$year-$month-$monthDay"."T$h:$m:$s"."Z";
}

sub leadingZeroScalar($){
	my $i = 0;
	my $elem = $_[0];
	
	if(length($elem) == 1){
		return "0$elem";
	}
	else{
		return "$elem";
	}
}

sub logMessage($$$){
	my $type = $_[0];
	my $text = $_[1];
	my $flag = $_[2];
	my $now = &getTimeStr();
	
	if($type eq 'INFO' or 
	   $type eq 'SYS' or 
	   $type eq 'WARNING' or 
	   $type eq 'ERROR' or 
	   $type eq 'DEBUG'){
	   	
		print "($now) $type: $text\n";
		
		if($flag){
			my $pathToLogFile = $configs->{'_'}->{'pathLogFile'};
			my $pathToFachkatalogGlobal = $configs->{'_'}->{'pathToFachkatalogGlobal'};
			
			# check if $pathToLogFile is a global or relative path
			$pathToLogFile = "$pathToFachkatalogGlobal$pathToLogFile" if($pathToLogFile =~ /^(?!\/).+/);
			
			open(my $LOG, ">> $pathToLogFile") or die $!, " $pathToLogFile";
			binmode $LOG, "utf8";
			print $LOG "($now) $type: $text\n";
			close($LOG);
		}
	}
	else{
		print "wrong usage of function\n";
	}
}
1;
