#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;
use Config::INI::Reader;
use threads;
use Sys::Info;
use FindBin;

require "$FindBin::Bin/optimize.pl";
require "$FindBin::Bin/helper.pl";
our $ini_pathToFachkatalogGlobal;
our $ini_pathIndexfile;
our $ini_pathConfigIni;
our $reIsGlobalPath;

my @results = ();
my $configs = Config::INI::Reader->read_file("$FindBin::Bin/../etc/config.ini");
my $pathConfigIni = "$FindBin::Bin/../etc/config.ini";
my @verbuende = @ARGV;

my $info = Sys::Info->new();
my $cpu  = $info->device( CPU => my %options );
my $cpuNumber = $cpu->count || 1;
my @threads;

## for each differend core build a new thread
foreach my $verbund(@verbuende){
	next if $verbund eq "_";
	my $thread = threads->new('index', "$verbund");
	push(@threads, $thread);
}

## main-thread should wait for other threads to finish
foreach my $thr(@threads){
	$thr->join();
}

## submethod for indexing the records
sub index(){
	my $verbund = $_[0];

	# lock the core in config.ini
	$configs->{$verbund}->{check} = 0;
	Config::INI::Writer->write_file($configs, $pathConfigIni);
	
	## get path and check if it is relative or global
	my $dirInitial = $configs->{$verbund}->{'initial'};
	$dirInitial = $ini_pathToFachkatalogGlobal . $dirInitial if($dirInitial =~ $reIsGlobalPath);
	
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
	
	## get path and check if it is relative or global
	my $configProperties = $configs->{$verbund}->{'configPropertiesFile'};
	$configProperties = $ini_pathToFachkatalogGlobal . $configProperties if($configProperties =~ $reIsGlobalPath);
		
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
	&optimize($verbund);
	
	# unlock the core in config.ini
	$configs->{$verbund}->{check} = 1;
	Config::INI::Writer->write_file($configs, $pathConfigIni);
	
	return 1;
}