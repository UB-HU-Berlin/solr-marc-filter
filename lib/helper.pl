#!/usr/bin/perl

use warnings;
use strict;

use Config::INI::Reader;
use FindBin;

## set logging policies (1 -> debug, 0 -> do not debug)
my $log_debug 	= 1;
my $log_info	= 1;
my $log_system	= 1;
my $log_warning	= 1;
my $log_error 	= 1;

# regex negative lookahead - if there is not a / at beginning
our $re = "^(?!\/).+"; 

## read ini values once and make them global
my $configs = Config::INI::Reader->read_file("$FindBin::Bin/../etc/config.ini");

# pathes .. check if path is relative or global
our $ini_pathToFachkatalogGlobal = $configs->{'_'}->{'pathToFachkatalogGlobal'};

our $ini_pathIndexfile = $configs->{'_'}->{'pathIndexfile'};
$ini_pathIndexfile = $ini_pathToFachkatalogGlobal . $ini_pathIndexfile if($ini_pathIndexfile =~ $re);

our $ini_pathQuery = $configs->{'_'}->{'pathQuery'};
$ini_pathQuery = $ini_pathToFachkatalogGlobal . $ini_pathQuery if($ini_pathQuery =~ $re);

our $ini_pathResults = $configs->{'_'}->{'pathResults'};
$ini_pathResults = $ini_pathToFachkatalogGlobal . $ini_pathResults if($ini_pathResults =~ $re);

our $ini_pathLogFile = $configs->{'_'}->{'pathLogFile'};
$ini_pathLogFile = $ini_pathToFachkatalogGlobal . $ini_pathLogFile if($ini_pathLogFile =~ $re);

our $ini_pathLogFileAlternative = $configs->{'_'}->{'pathLogFileAlternative'};
$ini_pathLogFileAlternative = $ini_pathToFachkatalogGlobal . $ini_pathLogFileAlternative if($ini_pathLogFileAlternative =~ $re);

our $ini_pathToSolrMarcDefault = $configs->{'_'}->{'pathToSolrMarcDefault'};
$ini_pathToSolrMarcDefault = $ini_pathToFachkatalogGlobal . $ini_pathToSolrMarcDefault if($ini_pathToSolrMarcDefault =~ $re);

our $ini_pathToSolrCoresDefault = $configs->{'_'}->{'pathToSolrCoresDefault'};
$ini_pathToSolrCoresDefault = $ini_pathToFachkatalogGlobal . $ini_pathToSolrCoresDefault if($ini_pathToSolrMarcDefault =~ $re);


# values .. just save value
our $ini_responseTimeout 			= $configs->{'_'}->{'serverResponseTimeoutSec'};
our $ini_resultType 				= $configs->{'_'}->{'resultType'};
our $ini_resultsMaxRecordsPerFile 	= $configs->{'_'}->{'resultsMaxRecordsPerFile'};
our $ini_resultsMaxNumber 			= $configs->{'_'}->{'resultsMaxNumber'};
our $ini_urlSolrDefault 			= $configs->{'_'}->{'urlSolrDefault'};


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

	# var flag forces to log or not to log without 
	# respect to standard value
	my $flag = $_[2];
	my $now = &getTimeStr();
	
	if($flag && $flag == 0){
		last;
	}
	
	# flag = 0 if not defined
	$flag = 0 unless $flag;
	
	if($type eq 'INFO' and $log_info or 
	   $type eq 'SYS' and $log_system or 
	   $type eq 'WARNING' and $log_warning or 
	   $type eq 'ERROR' and $log_error or 
	   $type eq 'DEBUG'	and $log_debug or
	   $flag
	   ){
	   	
		print "($now) $type: $text\n";
		
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
 
sub uniq {
  my %seen;
  return grep { !$seen{$_}++ } @_;
}

1;
