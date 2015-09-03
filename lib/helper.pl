#!/usr/bin/perl

use warnings;
use strict;

use Config::INI::Reader;
use FindBin;
use DateTime;

## time format
our $timeFormat = '%Y-%m-%d'.'T'.'%H:%M:%S'.'Z';

## set logging policies (1 -> debug, 0 -> do not debug)
my $log_debug 	= 1;
my $log_info	= 1;
my $log_system	= 1;
my $log_warning	= 1;
my $log_error 	= 1;

## regex negative lookahead - if there is not a / at beginning
#our $re = "^(?!\/).+"; 
our $reIsGlobalPath = "^(?!\/).+";

## read ini values once and make them global
my $configs = Config::INI::Reader->read_file("$FindBin::Bin/../etc/config.ini");

# pathes .. check if path is relative or global
our $ini_pathToFachkatalogGlobal = $configs->{'_'}->{'pathToFachkatalogGlobal'};

our $ini_pathIndexfile = $configs->{'_'}->{'pathIndexfile'};
$ini_pathIndexfile = $ini_pathToFachkatalogGlobal . $ini_pathIndexfile if($ini_pathIndexfile =~ $reIsGlobalPath);

our $ini_pathQuery = $configs->{'_'}->{'pathQuery'};
$ini_pathQuery = $ini_pathToFachkatalogGlobal . $ini_pathQuery if($ini_pathQuery =~ $reIsGlobalPath);

our $ini_pathResults = $configs->{'_'}->{'pathResults'};
$ini_pathResults = $ini_pathToFachkatalogGlobal . $ini_pathResults if($ini_pathResults =~ $reIsGlobalPath);

our $ini_pathLogFile = $configs->{'_'}->{'pathLogFile'};
$ini_pathLogFile = $ini_pathToFachkatalogGlobal . $ini_pathLogFile if($ini_pathLogFile =~ $reIsGlobalPath);

our $ini_pathLogFileAlternative = $configs->{'_'}->{'pathLogFileAlternative'};
$ini_pathLogFileAlternative = $ini_pathToFachkatalogGlobal . $ini_pathLogFileAlternative if($ini_pathLogFileAlternative =~ $reIsGlobalPath);

our $ini_pathToSolrMarcDefault = $configs->{'_'}->{'pathToSolrMarcDefault'};
$ini_pathToSolrMarcDefault = $ini_pathToFachkatalogGlobal . $ini_pathToSolrMarcDefault if($ini_pathToSolrMarcDefault =~ $reIsGlobalPath);

our $ini_pathToSolrCoresDefault = $configs->{'_'}->{'pathToSolrCoresDefault'};
$ini_pathToSolrCoresDefault = $ini_pathToFachkatalogGlobal . $ini_pathToSolrCoresDefault if($ini_pathToSolrMarcDefault =~ $reIsGlobalPath);


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

## helper function to print Message on screen and in Logfile (if flag == 1)
sub logMessage($$$){
	my $type = $_[0];
	my $text = $_[1];

	# var flag forces to log or not to log without 
	# respect to standard value
	my $flag = $_[2];
	my $now = &getTimeStr();
	
	if(defined($flag) && $flag == '0'){
		return;
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

# function compares two dates of format yyyy-mm-ddThh:mm:ssZ
# where y: year, m: month, d: day, h: hour, m: minute, s:second
# T,Z: literal placeholders
# example date: 2015-08-26T00:00:00Z
# returns
#	-1 if date1 is lower than date2
#	0  if dates are equal
#	1  if date1 is greater than date2
sub compareTime($$){
	my $date1 = $_[0];
	my $date2 = $_[1];
	my $dateFormat = '\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ';
	die("wrong date format") if(!($date1 =~ /$dateFormat/) or !($date2 =~ /$dateFormat/));
	
	my $dateTime1 = DateTime->new(
		year 	=> substr($date1, 0, 4),
		month 	=> substr($date1, 5, 2),
		day 	=> substr($date1, 8, 2),
		hour 	=> substr($date1, 11, 2),
		minute 	=> substr($date1, 14, 2),
		second 	=> substr($date1, 17, 2),
	);
	
	my $dateTime2 = DateTime->new(
		year 	=> substr($date2, 0, 4),
		month 	=> substr($date2, 5, 2),
		day 	=> substr($date2, 8, 2),
		hour 	=> substr($date2, 11, 2),
		minute 	=> substr($date2, 14, 2),
		second 	=> substr($date2, 17, 2),
	);
	
	return DateTime->compare($dateTime1, $dateTime2);
}
1;
