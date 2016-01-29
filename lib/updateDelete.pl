#!/usr/bin/perl

use warnings;
use strict;

use Config::INI::Reader;
use Config::INI::Writer;
use Apache::Solr;
use FindBin;

require "$FindBin::Bin/helper.pl";
our $reIsGlobalPath;
our $ini_pathToFachkatalogGlobal;
our $ini_urlSolrDefault;
our $ini_pathLogFileAlternative;
our $ini_pathIndexfile;

sub updateDelete(@){
	my $pathConfigIni = "$FindBin::Bin/../etc/config.ini";
	my $configs = Config::INI::Reader->read_file($pathConfigIni);
	my @verbuende = @_;
	&logMessage("DEBUG", "verbuende: "."@verbuende");
	
	foreach my $verbund(@verbuende){
		my @deletions = ();
		
		# skip global ini vars
		next if $verbund eq "_";

		if($configs->{$verbund}->{'check'} eq 0){
			&logMessage("WARNING", "($verbund) update/delete will not be done due to check=0!");
			next;
		}
		if($configs->{$verbund}->{'updateIsRunning'} eq '1'){
			&logMessage("WARNING", "($verbund) can not update/delete - update already in progress and locked by config.ini");
			next;
		}
		
		$configs->{$verbund}->{updateIsRunning} = 1;
		Config::INI::Writer->write_file($configs, $pathConfigIni);
		
		my $solr = Apache::Solr->new(server => $ini_urlSolrDefault);
		
		&logMessage("INFO", "($verbund) Applying updates to $verbund ..");
		
		# get and check if the path is relative or global
		my $dirDel = $configs->{$verbund}->{'updates'};
		$dirDel = $ini_pathToFachkatalogGlobal . $dirDel if($dirDel =~ $reIsGlobalPath);
		
		opendir(DIR_DEL, $dirDel) or die $!;
		my @filesWithIDs = ();

		# rename the ending of the file into *.del if necessary
		while(my $file = readdir(DIR_DEL)){

			if($file =~ m/(.*del.+)\.del$/){
				push(@filesWithIDs, $file);
			}
			elsif ($file =~ m/(.*del.+)\.\w{3}$/){
				my $oldFileName = $dirDel."/".$file;
				my $newFileName = $dirDel."/".$1.".del";
				&renameFile($oldFileName, $newFileName, $verbund);
				push(@filesWithIDs, substr($newFileName, length($dirDel."/")));
			}
		}
		@filesWithIDs = sort @filesWithIDs;
		&logMessage("INFO", "($verbund) Found " . scalar(@filesWithIDs) . " local deletion files");
		
		# get and check if the path is relative or global
		my $dirUpd = $configs->{$verbund}->{'updates'};
		$dirUpd = $ini_pathToFachkatalogGlobal . $dirUpd if($dirUpd =~ $reIsGlobalPath);
		
		opendir(DIR_UPD, $dirUpd) or die $!;
		my @filesWithUpd = ();
		my $updateFormat = $configs->{$verbund}->{'updateFormat'};
		
		while(my $file = readdir(DIR_UPD)){
			if ($file =~ m/\.$updateFormat$/){
				push(@filesWithUpd, $file);
			}
		}
		@filesWithUpd = sort @filesWithUpd;
		&logMessage("INFO", "($verbund) Found " . scalar(@filesWithUpd) . " local update files");
		
		open(my $alternLOG, ">> $ini_pathLogFileAlternative") or die $!;
		print $alternLOG "\n\n". &getTimeStr() . " ($verbund): \n";
		close $alternLOG;
		
		my $configProperties = $configs->{$verbund}->{'configPropertiesFile'};
		$configProperties = $ini_pathToFachkatalogGlobal . $configProperties if($configProperties =~ $reIsGlobalPath);
		
		my @ids = ();
		
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
			if($updateOrDeletion =~ /\.del$/){

				&logMessage("INFO", "($verbund) Applying deletions from file $updateOrDeletion to solr index ..");
				&logMessage("SYS", "($verbund) echo -e '\x04' | $ini_pathIndexfile $dirDel$updateOrDeletion $configProperties 2 > $ini_pathLogFileAlternative >/dev/null");
				system("echo -e '\x04' | $ini_pathIndexfile $dirDel$updateOrDeletion $configProperties 2 > $ini_pathLogFileAlternative >/dev/null");
				&logMessage("INFO", "($verbund) update $updateOrDeletion applied ..");
				
				# echo -e '\x04' | .. 
				# 	this sends an end of transmission control char and
				#	prevents the $indexFile to read data from stdin
				
				my $oldFileName = $dirDel.$updateOrDeletion;
				my $newFileName = $dirDel."applied/".$updateOrDeletion;
				&renameFile($oldFileName, $newFileName, $verbund);
			}
			
			# apply updates and move the updates afterwords to applied
			elsif($updateOrDeletion =~ /\.($updateFormat)$/){
				&logMessage("INFO", "($verbund) Applying updates from file $updateOrDeletion to solr index ..");
				&logMessage("SYS", "($verbund) $ini_pathIndexfile $dirUpd$updateOrDeletion $configProperties 2>>$ini_pathLogFileAlternative >/dev/null");
				
				system("$ini_pathIndexfile $dirUpd$updateOrDeletion $configProperties 2>>$ini_pathLogFileAlternative >/dev/null");
				&logMessage("INFO", "($verbund) update $updateOrDeletion applied ..");
				
				my $oldFileName = $dirDel.$updateOrDeletion;
				my $newFileName = $dirDel."applied/".$updateOrDeletion;
				&renameFile($oldFileName, $newFileName, $verbund);
			}
			
			else{
				&logMessage("WARNING", "($verbund) ignore File ($updateOrDeletion) for update!");
			}
		}
		
		$configs->{$verbund}->{'updateIsRunning'} = 0;
		Config::INI::Writer->write_file($configs, $pathConfigIni);
	}
	return 1;
}
if($ARGV[0]){
	&updateDelete($ARGV[0]);
}
1;
