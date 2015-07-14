#!/usr/bin/perl

use warnings;
use strict;

use Archive::Extract;
use Config::INI::Reader;
use Config::INI::Writer;
use FindBin;
use HTTP::OAI;
use LWP::UserAgent;
use LWP::Simple;
use Net::SCP;
use Net::SSH qw(sshopen2);
use Net::SSH qw(sshopen3);
use Text::Unidecode; # use this for wide character in print

require "$FindBin::Bin/helper.pl";
our $ini_pathToFachkatalogGlobal;

sub getUpdates(@){
	my $pathConfigIni = "$FindBin::Bin/../etc/config.ini";
	my $configs = Config::INI::Reader->read_file($pathConfigIni);
	my @verbuende = @_;
	my @verbuendeWithNewUpdates;
			
	&logMessage("INFO", "Begin to look for updates .. in @verbuende");
	
	foreach my $verbund(@verbuende){
		# check if the path is relative or global
		my $pathToUpdates = $configs->{$verbund}->{updates};
		$pathToUpdates = "$ini_pathToFachkatalogGlobal$pathToUpdates" if($pathToUpdates =~ /^(?!\/).+/);
		
		my $updateFormat = $configs->{$verbund}->{'updateFormat'};
		my @lastUpdates;
		my $inOut;
		
		if($configs->{$verbund}->{'check'} eq '0'){
			&logMessage("WARNING", "($verbund) will not be checked for updates due to check=0!");
			next;
		}
		
		if($configs->{$verbund}->{'updateIsRunning'} eq '1'){
			&logMessage("WARNING", "($verbund) update already in progress and locked by config.ini");
			next;
		}
		
		if(not $verbund eq "_"){
			# get the last updates which were made - look up in file
			my $path = $configs->{$verbund}->{'updates'};
			
			# check if the path is relative or global
			$path = "$ini_pathToFachkatalogGlobal$path" if($path =~ /^(?!\/).+/);
			
			open($inOut, "< $path"."lastUpdates.txt") or die("ERROR: Could not open lastUpdates file of $verbund: $!, $path");
			while(my $currLine = <$inOut>){
				chomp $currLine;
				push(@lastUpdates, $currLine);
			}
			@lastUpdates = sort @lastUpdates;
			close $inOut;
			open($inOut, ">> $path"."lastUpdates.txt") or die("ERROR: Could not open lastUpdates file of $verbund: $!, $path");
		}
		
		## FTP
		if($configs->{$verbund}->{'updateType'} eq "ftp"){
			$configs->{$verbund}->{updateIsRunning} = 1;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
			
			my $updateURL = $configs->{$verbund}->{'ftpUrl'};
			
			my $ua = LWP::UserAgent->new();
			my $response = $ua->get($updateURL);
			
			if($response->is_success){
				my $debug = 1;
				# parse the names of the hypelinks to get to the content of the updates (or deletions)
				my $content = $response->content();
				
				my @allUpdateNames;
				
				if($verbund eq 'swb'){
					while($content =~ /<a href="(od-up_bsz-tit_\d{6}_\d{2}\.xml\.tar\.gz)">/g){
						push(@allUpdateNames, $1);
						#print "$1\n";
					}
				}
				else{
					while($content =~ /.+\.tar\.gz/){
						&logMessage("WARNING", "($verbund) all .tar.gz files in target updateURL will be added!");
						push(@allUpdateNames, $1);
					}
				}
				@allUpdateNames = sort(@allUpdateNames);
				
				# get the difference of AllUpdates-LastUpdates=LatestUpdates
				my %lastUp = map {$_ => 1} @lastUpdates;
				my @updates = grep {not $lastUp{$_}} @allUpdateNames;
				my $now = &getTimeStr();
				
				if(@updates){
					&logMessage("INFO", "($verbund) Found new Updates for $verbund: @updates");
					push(@verbuendeWithNewUpdates, $verbund);
				}
				else{
					&logMessage("INFO", "($verbund) is up to date ..");
					$configs->{$verbund}->{updateIsRunning} = 0;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					next;
				}
				
				# now download the updates if they ain't in the lastUpdates file
				foreach my $fileName(@updates){
					my $latestUpdate = $fileName;
					&logMessage("INFO", "($verbund) downloading $fileName ..");
					getstore($updateURL.$fileName, $pathToUpdates.$fileName) or die "Could not download $fileName from $updateURL";
					print $inOut "$fileName\n";
				}
				
				# now extract all downloaded files and delete the .tgz afterwords
				foreach my $fileName(@updates){
					&logMessage("INFO", "($verbund) extracting $fileName .. ");
					$Archive::Extract::PREFER_BIN = 1;
					my $ae = Archive::Extract->new( archive => "$pathToUpdates$fileName");
					my $export = $ae->extract(to => "$pathToUpdates") or die $ae->error;
					
					&logMessage("INFO", "($verbund) removing downloaded archive $fileName ..");
					system("rm $pathToUpdates$fileName");
					
					# write date for the last correct update into ini file
					$configs->{$verbund}->{'lastUpdate'} = $now;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
				}
			}
			else{
				&logMessage("ERROR", "($verbund) an error occured! " . $response->status_line);
			}
			$configs->{$verbund}->{updateIsRunning} = 0;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
		}
		
		## SSH, SCP
		if($configs->{$verbund}->{'updateType'} eq "ssh"){
			$configs->{$verbund}->{updateIsRunning} = 1;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
			
			# get the updates and deletions via scp
			my @allUpdateNames;	#TODO: rename to allUpdatesFiles
			my $host = $configs->{$verbund}->{'sshHost'};
			my $user = $configs->{$verbund}->{'sshUser'};
			my $pathToSshData = $configs->{$verbund}->{'sshDataPath'};
			my $newUpdatesFound = 0;
			
			# read SSH Variables from fachkatalog/etc/env
			open(my $FILE, "< $ini_pathToFachkatalogGlobal"."etc/env" ) or die "Could not open File $!";
			my ($SSH_AGENT_PID, $SSH_AUTH_SOCK);
			
			while(my $line = <$FILE>){
			
				if($line =~ /SSH_AGENT_PID=(\d+)/){
					$SSH_AGENT_PID = $1;
				}
			
				elsif($line =~ /SSH_AUTH_SOCK=(.+)/){
					$SSH_AUTH_SOCK = $1;
				}
			}
			# setting important SSH Env Vars 
			$ENV{"SSH_AGENT_PID"} = $SSH_AGENT_PID;
			$ENV{"SSH_AUTH_SOCK"} = $SSH_AUTH_SOCK;
			
			my $cmd = "ls $pathToSshData";
			sshopen2("$user\@"."$host", *READER, *WRITER, "$cmd") || die  &logMessage("ERROR", "($verbund) sshError: $!");	#TODO: check if correct
			
			#TODO: make it independet from 'gbv'!
			&logMessage("WARNING", "($verbund) all files in target sshDataPath will be added!") if not $verbund eq 'gbv';
			
			while (<READER>) {
				chomp();
				my $debug = $_;
				
				if($_ =~ /.*Datei oder Verzeichnis nicht gefunden/){
					&logMessage("WARNING", "($verbund) path $pathToSshData could not be found!");
					&logMessage("WARNING", "($verbund) Skipping $verbund ..");
					$configs->{$verbund}->{updateIsRunning} = 0;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					last;
				}
				#TODO: very specific for 'gbv' -> make more independent
				if($verbund eq 'gbv'){
					if($_ =~ /^gbv.+delete.+\.txt$/ or $_ =~ /^gbv.+update.+\.mrc\.tar\.gz$/){
				    	push(@allUpdateNames, $_);
					}
				}
				else{
					$_ =~ /^.+\.(txt|mrc|xml|tar|tar\.gz)$/;
					push(@allUpdateNames, $_);
				}
			}
			close(READER);
			close(WRITER);
			
			@allUpdateNames = sort(@allUpdateNames);
			
			# get the difference of AllUpdates-LastUpdates=LatestUpdates
			my %lastUp = map {$_ => 1} @lastUpdates;
			my @updates = grep {not $lastUp{$_}} @allUpdateNames;
			
			if(@updates){
				&logMessage("INFO", "($verbund) Found ". scalar(@updates) ." new Updates for $verbund: @updates");
				push(@verbuendeWithNewUpdates, $verbund);
				$newUpdatesFound = 1;
			}
			else{
				&logMessage("INFO", "($verbund) is up to date ..");
				$configs->{$verbund}->{updateIsRunning} = 0;
				Config::INI::Writer->write_file($configs, $pathConfigIni);
				next;
			}
			
			# now download the updates if they ain't in the lastUpdates file
			my $scp = Net::SCP->new($host);
			$scp->login();
			
			foreach my $fileName(@updates){
				my $latestUpdate = $fileName;
				&logMessage("INFO", "($verbund) downloading $pathToSshData$fileName from $host ..");
				$scp->cwd($pathToSshData);
				$scp->get("$fileName", $pathToUpdates) or die $scp->{errstr};
				print $inOut "$fileName\n";
			}
			$scp->quit();
			
			# now extract all downloaded files and delete the .tgz afterwords
			foreach my $fileName(@updates){
				if($fileName =~ /.+\.tar\.gz$/){
					&logMessage("INFO", "($verbund) extracting $fileName .. ");
					$Archive::Extract::PREFER_BIN = 1;
					my $ae = Archive::Extract->new( archive => "$pathToUpdates$fileName");
					my $export = $ae->extract(to => $pathToUpdates) or die $ae->error, $pathToUpdates;
					
					&logMessage("INFO", "($verbund) removing downloaded archive $fileName ..");
					system("rm $pathToUpdates$fileName");
				}
			}
			
			if($newUpdatesFound){
				# update the latest updates date in the ini file
				$configs->{$verbund}->{'lastUpdate'} = &getTimeStr();
				Config::INI::Writer->write_file($configs, $pathConfigIni);
			}
			$configs->{$verbund}->{updateIsRunning} = 0;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
		}
		
		## OAI
		if($configs->{$verbund}->{'updateType'} eq "oai"){
			$configs->{$verbund}->{updateIsRunning} = 1;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
			
			# get the updates and deletions via oai interface..
			my $h = HTTP::OAI::Harvester->new(
				baseURL => $configs->{$verbund}->{'oaiUrl'},#?verb=ListRecords',
				#verb => 'ListRecords',
				#version => '2.0',
				resume  => 0
			);
			
			# lastDate is the either the last time-stamp from oai interface which dates the last correct update 
			# or if this is the first update it will be the oldest possible updated because there a no updates 
			# before this specific date
			my $lastDate = pop @lastUpdates;
			if(scalar(@lastUpdates) == 0){
				$lastDate = $configs->{$verbund}->{'oaiOldestUpdate'}; 
			}
			else{
				while($lastDate eq ''){
					$lastDate = pop @lastUpdates;
				}
			}
			my $maxRecordsPerUpdatefile = int($configs->{$verbund}->{oaiMaxRecordsPerUpdatefile}) 	if $configs->{$verbund}->{oaiMaxRecordsPerUpdatefile};
			$maxRecordsPerUpdatefile = 0 unless $maxRecordsPerUpdatefile;
			my $maxDaysPerUpdatefile 	= int($configs->{$verbund}->{oaiMaxDaysPerUpdatefile})		if $configs->{$verbund}->{oaiMaxDaysPerUpdatefile};
			$maxDaysPerUpdatefile = 0 unless $maxDaysPerUpdatefile;
			
			if($maxRecordsPerUpdatefile == 0 and $maxDaysPerUpdatefile == 0 or $maxRecordsPerUpdatefile != 0 and $maxDaysPerUpdatefile != 0){
				&logMessage("ERROR", "($verbund) Either maxRecordsPerUpdatefile or maxDaysPerUpdatefile has to be 0!", 1);
				&logMessage("INFO", "($verbund) Change maxRecordsPerUpdatefile or maxDaysPerUpdatefile in config.ini and restart update!", 1);
				$configs->{$verbund}->{updateIsRunning} = 0;
				Config::INI::Writer->write_file($configs, $pathConfigIni);
				next;
			}
			
			my $from = $lastDate;
			my $until = &getTimeStr();
			
			my $listRecs = $h->ListRecords(
				verb => 'ListRecords',
				metadataPrefix => 'marc21',
				from => $from,
				until => $until
				#handlers=>{metadata=>'HTTP::OAI::Metadata::OAI_DC'},
			);
			
			my $getRec = $h->GetRecord(
				verb => 'GetRecord',
				metadataPrefix => 'marc21',
				from => $from,
				until => $until
			);
			
			# number of total updates (updated records + deleted records)
			my $total = 0;
			# number of updates (only updated records without deleted records)
			my $u = 0;
			# number of update files
			my $n = 0;
			
			# maxResultsPerReq is the standard value how many results will be returned at once on oai api (normally its 30)
			my $maxResultsPerReq = scalar @{$listRecs->{content}[0]->{item}} if($listRecs->{content}[0]->{item});
			&logMessage("INFO", "($verbund) There are no new updates between $from and $until!", 1) unless $maxResultsPerReq;
			$configs->{$verbund}->{updateIsRunning} = 0;
			Config::INI::Writer->write_file($configs, $pathConfigIni) unless $maxResultsPerReq;
			next unless $maxResultsPerReq;
			push(@verbuendeWithNewUpdates, $verbund) if $maxResultsPerReq;
			
			my @deletions;
			&logMessage("INFO", "($verbund) found new updates (download will take some minutes)", 1);
			&logMessage("DEBUG", "($verbund) maxResultsPerReq: $maxResultsPerReq", 1);
			
			# check if the path is relative or global
			my $path = $configs->{$verbund}->{'updates'};
			$path = "$ini_pathToFachkatalogGlobal$path" if($path =~ /^(?!\/).+/);
			
			my $now = &getTimeStr();
			open(my $OUTupd, "> $path"."updates_$from"."_$until.xml") or die("($now) ERROR: ($verbund) Could not open $path"."updates_$from"."_$until.xml: $!\n");
			binmode $OUTupd, ":utf8";
			open(my $OUTdel, "> $path"."deletions_$from"."_$until.txt") or die("($now) ERROR: ($verbund) Could not open $path"."deletions_$from"."_$until.txt: $!\n");
			
			# prepare the xml file for the updates
			print $OUTupd '<?xml version="1.0" encoding="ISO-8859-1" ?><marc:collection xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">'."\n";
			
			my $lastDatestamp;
			while(my $rec = $listRecs->next){
				$total++;
				my $status = $rec->header->status;
				my $currID = $rec->header->identifier;
				my $currDatestamp = $rec->header->datestamp;
				$lastDatestamp = $currDatestamp; 
				
				# either we have deletions
				if($status and $status eq "deleted"){
					# push id to array and to file (id is the id which has to be deleted from database)
					push(@deletions, $currID);
					print $OUTdel $currID, "\n";
				}
				# .. or we have updates
				else{
					# print updates metadata into file
					$u++;
					my $recXML = $rec->{metadata}->{current}->firstChild->firstChild;
					print $OUTupd $recXML;
				}
				#&logMessage("INFO", "$total, ($u): ". $currDatestamp. ", ". $currID. ", ". $status)  if $status;
				#&logMessage("INFO", "$total, ($u): ". $currDatestamp. ", ". $currID)  unless $status;
				
				# the list goes on so get resumption token to get all the updates
				if($total % $maxResultsPerReq == 0){
					my $rToken = $listRecs->resumptionToken();
					#print $rToken->resumptionToken, "\n" if $rToken;
					$listRecs = $h->ListRecords(
						verb => 'ListRecords',
						resumptionToken => $rToken->resumptionToken,
					) if $rToken;
				}
				
				# build new file if there are too many updates for the given period
				if($maxRecordsPerUpdatefile != 0 and $u % $maxRecordsPerUpdatefile == 0 and $u != 0){
					$n++;
					print $OUTupd "\n".'</marc:collection>';
					close $OUTupd;
					
					my $filename = "$path"."updates_$from"."_$until"."_$n.$updateFormat";
					open($OUTupd, "> $filename") or die("ERROR: Could not open $filename file of $verbund: $!");
					binmode $OUTupd, ":utf8";
					print $OUTupd '<?xml version="1.0" encoding="ISO-8859-1" ?><marc:collection xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">'."\n";
					print $inOut "$currDatestamp\n";
					&logMessage("INFO", "($verbund) got updates until $currDatestamp.", 1);
					close($inOut);
					open($inOut, ">> $path"."lastUpdates.txt") or die("ERROR: Could not open lastUpdates file of $verbund: $!");
				}
				
				# build new file if there are too many deletions for the given period
				if(scalar(@deletions) % $maxRecordsPerUpdatefile == 0 and scalar(@deletions) != 0){
					close($OUTdel);
					my $d = scalar(@deletions);
					my $filename = "$path"."deletions_$from"."_$until"."_$d.txt";
					$now = &getTimeStr();
					open($OUTdel, "> $filename") or die("($now) ERROR: ($verbund) Could not open $filename file of $verbund: $!\n");
				}
			}
			print $OUTupd "\n".'</marc:collection>';
			print $inOut "$until\n";
			
			close $OUTdel;
			close $OUTupd;
			close $inOut;
			
			&logMessage("INFO", "($verbund) number of deletions: ". scalar(@deletions) . " of $total in total", 1);
			&logMessage("INFO", "($verbund) number of updates: $u of $total in total", 1);
			&logMessage("ERROR", "($verbund) $listRecs->message", 1) if $listRecs->is_error;
			
			# update the config.ini file when the last update took place
			$configs->{$verbund}->{'lastUpdate'} = $lastDatestamp;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
			
			# delete the updates or the deletions file if there ain't new updates
			if(scalar(@deletions) == 0){
				system("rm $configs->{$verbund}->{updates}"."deletions_$from"."_$until.txt");
			}
			if($u == 0){
				system("rm $configs->{$verbund}->{updates}"."updates_$from"."_$until.xml");
			}
			$configs->{$verbund}->{updateIsRunning} = 0;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
		}
	}
	return @verbuendeWithNewUpdates;
}
#&getUpdates(("b3kat", "gbv", "swb")); #just for testing

1;

