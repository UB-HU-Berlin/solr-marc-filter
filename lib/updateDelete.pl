#!/usr/bin/perl

use warnings;
use strict;

use Config::INI::Reader;
use Config::INI::Writer;
use Apache::Solr;
use FindBin;

require "$FindBin::Bin/helper.pl";

#TODO: script is very specific to verbund GBV - make more independent

my $SAFE_IN_LOG = 1;

sub updateDelete(@){
	my $pathConfigIni = "$FindBin::Bin/../etc/config.ini";
	my $configs = Config::INI::Reader->read_file($pathConfigIni);
	#my @verbuende = keys %$configs;
	my @verbuende = @_;
	&logMessage("DEBUG", "verbuende: "."@verbuende", $SAFE_IN_LOG);
	
	my $pathToFachkatalogGlobal = $configs->{'_'}->{'pathToFachkatalogGlobal'};
	
	foreach my $verbund(@verbuende){
		my @deletions = ();
		
		if(not $verbund eq "_"){

			if($configs->{$verbund}->{'check'} eq 0){
				&logMessage("WARNING", "($verbund) update/delete will not be done due to check=0!", $SAFE_IN_LOG);
				next;
			}
			if($configs->{$verbund}->{'updateIsRunning'} eq '1'){
				&logMessage("WARNING", "($verbund) can not update/delete - update already in progress and locked by config.ini", $SAFE_IN_LOG);
				next;
			}
		
			$configs->{$verbund}->{updateIsRunning} = 1;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
			
			my $url = $configs->{'_'}->{'urlSolrDefault'}."$verbund";
			my $solr = Apache::Solr->new(server => $url);
			
			&logMessage("INFO", "Applying updates to $verbund ..", $SAFE_IN_LOG);
			
			# get and check if the path is relative or global
			my $dirDel = $configs->{$verbund}->{'updates'};
			$dirDel = $configs->{'_'}->{'pathToFachkatalogGlobal'}.$dirDel if($dirDel =~ /^(?!\/).+/);
			
			opendir(DIR_DEL, $dirDel) or die $!;
			my @filesWithIDs = ();

			# rename the ending of the file into *.del if necessary
			while(my $file = readdir(DIR_DEL)){

				if($file =~ m/(.*del.+)\.del$/){
					push(@filesWithIDs, $file);
				}
				elsif ($file =~ m/(.*del.+)\.\w{3}$/){
					system("mv \"$dirDel/$file\" \"$dirDel/$1.del\"");
					&logMessage("DEBUG", "mv $file $1.del", $SAFE_IN_LOG);
					push(@filesWithIDs, "$1.del");
				}
			}
			
			@filesWithIDs = sort @filesWithIDs;
			#print "@filesWithIDs\n";
			
			# get and check if the path is relative or global
			my $dirUpd = $configs->{$verbund}->{'updates'};
			$dirUpd = $configs->{'_'}->{'pathToFachkatalogGlobal'}.$dirUpd if($dirUpd =~ /^(?!\/).+/);
			
			opendir(DIR_UPD, $dirUpd) or die $!;
			my @filesWithUpd = ();
			
			while(my $file = readdir(DIR_UPD)){
				if ($file =~ m/\.$configs->{$verbund}->{updateFormat}$/){
					push(@filesWithUpd, $file);
				}
			}
			@filesWithUpd = sort @filesWithUpd;
			
			# get and check if all the given pathes are relative or global
			my $indexFile = $configs->{'_'}->{pathIndexfile};
			$indexFile = $pathToFachkatalogGlobal . $indexFile if($indexFile =~ /^(?!\/).+/);
			
			my $logFile = $configs->{'_'}->{pathLogFileAlternative};
			$logFile = $pathToFachkatalogGlobal . $logFile if($logFile =~ /^(?!\/).+/);
			open(my $alternLOG, ">> $logFile") or die $!;
			print $alternLOG "\n\n". &getTimeStr() . " ($verbund): \n";
			
			my $configProperties = $configs->{$verbund}->{configPropertiesFile};
			$configProperties = $pathToFachkatalogGlobal . $configProperties if($configProperties =~ /^(?!\/).+/);
			
			my @ids = ();
			
			#TODO: code (til line 151) not tested yet with more than one update and delete file
			# prepare list for pairwise deletions
			my $dateFormat = '\d\d\d\d-\d\d-\d\d';
			my $dateLength = length("YYYY-MM-DD");
			my @mixedList = (@filesWithIDs, @filesWithUpd);
			
			#my @s = sort { substr($a, $positionFrom, $dateLength) cmp substr($b, $positionFrom, $dateLength)  } @z;
			my @mixedListSorted = sort { 
				my ($preMatchA, $positionFromA, $preMatchB, $positionFromB);
				$positionFromA = 0;
				$positionFromB = 0;
				
				if($a =~ /$dateFormat/){$positionFromA = length($`); }
				else{					$positionFromA = 0; }
			
				if($b =~ /$dateFormat/){$positionFromB = length($`); }
				else{					$positionFromB = 0; }
				
				substr($a, $positionFromA, $dateLength) cmp substr($b, $positionFromB, $dateLength)  
			} @mixedList;
			
						
			for my $updateOrDeletion(@mixedListSorted){

				# apply deletions and move the deletions afterwords to applied
				if($updateOrDeletion =~ /delete/){

					&logMessage("INFO", "($verbund) Applying deletions from file $updateOrDeletion to solr index ..", $SAFE_IN_LOG);
					&logMessage("SYS", "($verbund) echo -e '\x04' | $indexFile $dirDel$updateOrDeletion $configProperties 2 > $logFile >/dev/null", $SAFE_IN_LOG);
					system("echo -e '\x04' | $indexFile $dirDel$updateOrDeletion $configProperties 2 > $logFile >/dev/null");
						
					# echo -e '\x04' | .. 
					# 	this sends an end of transmission control char 
					#	prevents the $indexFile to read data from stdin (maybe better solution)
						
					&logMessage("INFO", "($verbund) moving file $dirDel$updateOrDeletion to ./applied/", $SAFE_IN_LOG);
					system("mv $dirDel$updateOrDeletion $dirDel"."applied/");
					&logMessage("INFO", "($verbund) update $updateOrDeletion applied ..", $SAFE_IN_LOG);
				}
				
				# apply updates and move the updates afterwords to applied
				elsif($updateOrDeletion =~ /update/){
					&logMessage("INFO", "($verbund) Applying updates from file $updateOrDeletion to solr index ..", $SAFE_IN_LOG);
					&logMessage("SYS", "($verbund) $indexFile $dirUpd$updateOrDeletion $configProperties 2>>$logFile >/dev/null", $SAFE_IN_LOG);
							
					system("$indexFile $dirUpd$updateOrDeletion $configProperties 2>>$logFile >/dev/null");
					&logMessage("INFO", "($verbund) moving update file $dirUpd$updateOrDeletion to ./applied/", $SAFE_IN_LOG);
					system("mv $dirUpd$updateOrDeletion $dirUpd"."applied/");
					&logMessage("INFO", "($verbund) update $updateOrDeletion applied ..", $SAFE_IN_LOG);
				}
				
				else{
					&logMessage("WARNING", "($verbund) ignore File ($updateOrDeletion) for update!", $SAFE_IN_LOG);
				}
			}
			
			$configs->{$verbund}->{updateIsRunning} = 0;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
		}
	}
	return 1;
}
if($ARGV[0]){
	&updateDelete($ARGV[0]);
}
1;
