#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;
use Config::INI::Reader;
use threads;
use Sys::Info;
use FindBin;

require "$FindBin::Bin/helper.pl";
our $ini_pathToFachkatalogGlobal;
our $ini_pathIndexfile;
our $ini_pathConfigIni;

my @results = ();
my $configs = Config::INI::Reader->read_file("$FindBin::Bin/../etc/config.ini");
#my @verbuende = keys %$configs;
my @verbuende = @ARGV;

my $info = Sys::Info->new();
my $cpu  = $info->device( CPU => my %options );
my $cpuNumber = $cpu->count || 1;

my @threads;
my $i = 0;

foreach my $verbund(@verbuende){
#	my @runningThreads = threads->list;
		
	#if(scalar(@runningThreads) < $cpuNumber-1 and $i < scalar(@verbuende) and not $verbund eq "_"){
	if(not $verbund eq "_"){
		my $thread = threads->new('index', "$verbund");
		#my $thread = threads->new(&index($verbund));
		#my $thread = threads->create(\&index, $verbund);
		push(@threads, $thread);
		#print threads->list . "\n";
		$i++;
	}
}

foreach my $thr(@threads){
	$thr->join();
	#$thr->detach();
}

sub index(){
	my $verbund = $_[0];
	
	## get and check if the path is relative or global
	my $dirInitial = $configs->{$verbund}->{'initial'};
	$dirInitial = $ini_pathToFachkatalogGlobal . $dirInitial if($dirInitial =~ our $re);
	
	opendir(DIR, $dirInitial) or die $!;
	my @filesToIndex = ();
	
	while(my $fileToIndex = readdir(DIR)){
		my $type = $configs->{$verbund}->{'initialDataFormat'};
		if ($fileToIndex =~ m/\.$type$/){
			push(@filesToIndex, $fileToIndex);
		}
	}
	@filesToIndex = sort @filesToIndex;
	&logMessage("INFO", "($verbund) Trying to push ". scalar(@filesToIndex) ." initial data files to index: @filesToIndex");
		
	my $configProperties = $configs->{$verbund}->{'configPropertiesFile'};
	$configProperties = $ini_pathToFachkatalogGlobal . $configProperties if($configProperties =~ /^(?!\/).+/);
			
	my $logFilePath = $ini_pathToFachkatalogGlobal . "log/log_$verbund.txt";
	system("touch $logFilePath");
	
	for my $fileToIndex(@filesToIndex){
		&logMessage("INFO", "($verbund) pushing $fileToIndex to Solr index..");
		system("$ini_pathIndexfile $dirInitial$fileToIndex $configProperties 2>$logFilePath >/dev/null");
		&logMessage("SYS", "($verbund) $ini_pathIndexfile $dirInitial$fileToIndex $configProperties 2>$logFilePath >/dev/null"); 
		
		if($? == -1){
			&logMessage("ERROR", "failed to index file $fileToIndex with $configProperties for some reason!");
		}
		else{
			&logMessage("INFO", "($verbund) finished pushing $fileToIndex to Solr index..");
		}
	}
	return 1;
}