#!/usr/bin/perl

use warnings;
use strict;

use Archive::Extract;
use Config::INI::Reader;
use Config::INI::Writer;
use Date::Simple qw(date);
use FindBin;
use HTTP::OAI;
use LWP::UserAgent;
use LWP::Simple;
use Net::SCP;
use Net::SSH qw(sshopen2);
use Net::SSH qw(sshopen3);
use Text::Unidecode; # use this for wide character in print
use Time::Piece;
use WWW::Curl::Easy;

require "$FindBin::Bin/helper.pl";
our $ini_pathToFachkatalogGlobal;
our $reIsGlobalPath;
our $timeFormat;

sub getUpdates(@){
	my $pathConfigIni = "$FindBin::Bin/../etc/config.ini";
	my $configs = Config::INI::Reader->read_file($pathConfigIni);
	my @verbuende = @_;
	my @verbuendeWithNewUpdates;
			
	&logMessage("INFO", "Begin to look for updates .. in @verbuende");
	
	foreach my $verbund(@verbuende){
		# check if the path is relative or global
		my $pathToUpdates = $configs->{$verbund}->{updates};
		$pathToUpdates = "$ini_pathToFachkatalogGlobal$pathToUpdates" if($pathToUpdates =~ $reIsGlobalPath);
		
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
			$path = "$ini_pathToFachkatalogGlobal$path" if($path =~ $reIsGlobalPath);
			
			open($inOut, "< $path"."lastUpdates.txt") or die("ERROR: Could not open lastUpdates file of $verbund: $!, $path");
			while(my $currLine = <$inOut>){
				chomp $currLine;
				push(@lastUpdates, $currLine);
			}
			@lastUpdates = sort @lastUpdates;
			close $inOut;
			open($inOut, ">> $path"."lastUpdates.txt") or die("ERROR: Could not open lastUpdates file of $verbund: $!, $path");
		}
		
		HTTP: {
			## HTTP
			if($configs->{$verbund}->{'updateType'} eq "http"){
				$configs->{$verbund}->{updateIsRunning} = 1;
				Config::INI::Writer->write_file($configs, $pathConfigIni);
				
				my $updateURL = $configs->{$verbund}->{'httpUrl'};
				my $deletionURL = $configs->{$verbund}->{'httpUrlDeletions'};
				
				my $ua = LWP::UserAgent->new();
				$ua->show_progress(1);
				$ua->timeout(20);
				
				my $responseUpd = $ua->get($updateURL);
				my $responseUpdRQ = $ua->request(HTTP::Request->new(GET => $updateURL));
				
				my $responseDel = $ua->get($deletionURL);
				my $responseDelRQ = $ua->request(HTTP::Request->new(GET => $deletionURL));
				
				if($responseUpd->is_success && $responseDel->is_success){
					# parse the names of the hypelinks to get to the content of the updates and deletions
					my $contentUpd = $responseUpd->content();
					my $contentDel = $responseDel->content();
					
					my @allUpdateFiles;
					
					# handle different Cores differently
					if($verbund eq 'swb'){
						while($contentUpd =~ /<a href="(od-up_bsz-tit_\d{6}_\d{1,2}\.xml\.tar\.gz)">/g){
							push(@allUpdateFiles, $1);
						}
						while($contentDel =~ /<a href="(od_del_bsz-tit_\d{6}_\d{2}\.txt\.tar\.gz)">/g){
							push(@allUpdateFiles, $1);
						}
					}
					else{
						while($contentUpd =~ /^.+\.(txt|mrc|xml|tar|tar\.gz)$/g){
							&logMessage("WARNING", "($verbund) all files in target updateURL will be added!");
							push(@allUpdateFiles, $1);
						}
						while($contentDel =~ /^.+\.(txt|mrc|xml|tar|tar\.gz)$/g){
							&logMessage("WARNING", "($verbund) all files in target updateURLDeletions will be added!");
							push(@allUpdateFiles, $1);
						}
					}
					@allUpdateFiles = uniq(@allUpdateFiles);
					@allUpdateFiles = sort(@allUpdateFiles);
									
					# get the difference of AllUpdates-LastUpdates=LatestUpdates
					my %lastUp = map {$_ => 1} @lastUpdates;
					my @updates = grep {not $lastUp{$_}} @allUpdateFiles;
					my $now = &getTimeStr();
					
					if(@updates){
						&logMessage("INFO", "($verbund) Found new Updates: @updates");
						push(@verbuendeWithNewUpdates, $verbund);
					}
					else{
						&logMessage("INFO", "($verbund) is up to date ..");
						$configs->{$verbund}->{updateIsRunning} = 0;
						Config::INI::Writer->write_file($configs, $pathConfigIni);
						next;
					}
					
					# now download the updates if they ain't in the lastUpdates file
					foreach my $fileName(@updates) {
	
						my $latestUpdate = $fileName;
						&logMessage("INFO", "($verbund) downloading $fileName ..");
						
						## Handeling Download with CURL
						my $curl = new WWW::Curl::Easy;
						my $url;
						
						if ($fileName =~ /\.$updateFormat(\.tar\.gz)?$/){
							#getstore($updateURL.$fileName, $pathToUpdates.$fileName) or &logMessage("ERROR", "($verbund) Could not download $fileName from $updateURL");
							$url = $updateURL.$fileName;
						}
						
						if ($fileName =~ /\.txt(\.tar\.gz)?$/){
							#getstore($deletionURL.$fileName, $pathToUpdates.$fileName) or &logMessage("ERROR", "($verbund) Could not download $fileName from $deletionURL");
							$url = $deletionURL.$fileName;
						}
						
						open(my $outFile, "> $pathToUpdates$fileName") or die("Could not open file: $!");
						
						$curl->setopt(CURLOPT_URL, $url);
						$curl->setopt(CURLOPT_WRITEDATA, $outFile);
						#$curl->setopt(CURLOPT_TIMEOUT, 20);		# just for testing - std-timeout is to long
						$curl->perform;
						
						my $err = $curl->errbuf;
						close($outFile);
						
						# if no error happened
						if($err != ''){
							print $inOut "$fileName\n";
							&logMessage("INFO", "($verbund) $fileName successfully downloaded");
						}
						# else .. remove file and go to next core
						else{
							&logMessage("ERROR", "($verbund) unable to download Updates!");
							&logMessage("INFO", "($verbund) remove uncomplete file $fileName ..");
							system("rm $pathToUpdates$fileName");
							$configs->{$verbund}->{updateIsRunning} = 0;
							Config::INI::Writer->write_file($configs, $pathConfigIni);
							last HTTP;
						}
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
					&logMessage("ERROR", "($verbund) an error occured! " . $responseUpd->status_line . "; " . $responseDel->status_line);
					
				}
				$configs->{$verbund}->{updateIsRunning} = 0;
				Config::INI::Writer->write_file($configs, $pathConfigIni);
			}
		
		}
	
		SSH: {
			## SSH, SCP
			if($configs->{$verbund}->{'updateType'} eq "ssh"){
				$configs->{$verbund}->{updateIsRunning} = 1;
				Config::INI::Writer->write_file($configs, $pathConfigIni);
				
				# get the updates and deletions via scp
				my @allUpdateFiles;
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
				sshopen2("$user\@"."$host", *READER, *WRITER, "$cmd") || die  &logMessage("ERROR", "($verbund) sshError: $!");
				
				&logMessage("WARNING", "($verbund) all files in target sshDataPath will be added!") if not $verbund eq 'gbv';
				
				while (<READER>) {
					chomp();
					my $debug = $_;
					
					if($_ =~ /.*Datei oder Verzeichnis nicht gefunden/){
						&logMessage("WARNING", "($verbund) path $pathToSshData could not be found!");
						&logMessage("WARNING", "($verbund) Skipping $verbund ..");
						$configs->{$verbund}->{updateIsRunning} = 0;
						Config::INI::Writer->write_file($configs, $pathConfigIni);
						last SSH;
					}
					#TODO: very specific for 'gbv' -> make more independent
					if($verbund eq 'gbv'){
						if($_ =~ /^gbv.+delete.+\.txt$/ or $_ =~ /^gbv.+update.+\.mrc\.tar\.gz$/){
					    	push(@allUpdateFiles, $_);
						}
					}
					else{
						$_ =~ /^.+\.(txt|mrc|xml|tar|tar\.gz)$/;
						push(@allUpdateFiles, $_);
					}
				}
				close(READER);
				close(WRITER);
				
				@allUpdateFiles = sort(@allUpdateFiles);
				
				# get the difference of AllUpdates-LastUpdates=LatestUpdates
				my %lastUp = map {$_ => 1} @lastUpdates;
				my @updates = grep {not $lastUp{$_}} @allUpdateFiles;
				
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
		}
		
		OAI: {
			## OAI
			if($configs->{$verbund}->{'updateType'} eq "oai"){
				
				$configs->{$verbund}->{updateIsRunning} = 1;
				Config::INI::Writer->write_file($configs, $pathConfigIni);
				
				# get the updates and deletions via oai interface..
				my $h = HTTP::OAI::Harvester->new(
					baseURL => $configs->{$verbund}->{'oaiUrl'},
					resume  => 0
				);
				
				# lastDate is either the last time-stamp from oai interface which dates the last correct update
				# or if this is the first update it will be the oldest possible updated because there a no updates
				# before this specific date
				my $lastDate;
				my $oaiOldestUpdate = $configs->{$verbund}->{'oaiOldestUpdate'};
				
				if(scalar(@lastUpdates) == 0){
					$lastDate = $oaiOldestUpdate; 
				}
				else{
					$lastDate = pop @lastUpdates;
					while($lastDate eq ''){
						$lastDate = pop @lastUpdates;
					}
					# just to catch the case that the lastUpdate-file is full with newlines
					if($lastDate eq ''){
						$lastDate = $oaiOldestUpdate;
					}
				}
				# if the last Update printed into the lastUpdate.txt is older than oaiOldestUpdate, take the newer date
				my $diff = Time::Piece->strptime($oaiOldestUpdate, $timeFormat) - Time::Piece->strptime($lastDate, $timeFormat); 
				if($diff > 0){
					$lastDate = $oaiOldestUpdate;
				}
							
				my $maxRecordsPerUpdatefile = int($configs->{$verbund}->{oaiMaxRecordsPerUpdatefile}) 	if $configs->{$verbund}->{oaiMaxRecordsPerUpdatefile};
				$maxRecordsPerUpdatefile = 0 unless $maxRecordsPerUpdatefile;
				my $maxDaysPerUpdatefile 	= int($configs->{$verbund}->{oaiMaxDaysPerUpdatefile})		if $configs->{$verbund}->{oaiMaxDaysPerUpdatefile};
				$maxDaysPerUpdatefile = 0 unless $maxDaysPerUpdatefile;
				
				if($maxRecordsPerUpdatefile == 0 and $maxDaysPerUpdatefile == 0 or $maxRecordsPerUpdatefile != 0 and $maxDaysPerUpdatefile != 0){
					&logMessage("ERROR", "($verbund) Either maxRecordsPerUpdatefile or maxDaysPerUpdatefile has to be 0!");
					&logMessage("INFO", "($verbund) Change maxRecordsPerUpdatefile or maxDaysPerUpdatefile in config.ini and restart update!");
					$configs->{$verbund}->{updateIsRunning} = 0;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					next;
				}
				
				# OAI paramters
				my $from = $lastDate;
				my $now = &getTimeStr();
				my $until = $now;
	
				# because the interface needs time to upload the new data there is a delay to the newest updates per default
				# one day difference should be enough time
				my $yesterday = date(substr($until, 0, 10)) - 1 . substr($until, 10);
				$until = $yesterday;			
				
				my $listRecs = $h->ListRecords(
					verb => 'ListRecords',
					metadataPrefix => 'marc21',
					from => $from,
					until => $until
					#handlers=>{metadata=>'HTTP::OAI::Metadata::OAI_DC'}
				);
				
				# number of total updates (updated records + deleted records)
				my $total = 0;
				# number of updates (only updated records without deleted records)
				my $u = 0;
				# number of update files
				my $n = 0;
				
				# in case of an error
				if($listRecs->is_error){
					my $httpStatus = $listRecs->{_rc};
					&logMessage("ERROR", "($verbund) OAI-Update failed (HTTP-status: $httpStatus)!");
					# unlock the core in config.ini
					$configs->{$verbund}->{updateIsRunning} = 0;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					next;
				}
				
				# maxResultsPerReq is the standard value how many results will be returned at once on oai api (normally its 30)
				my $maxResultsPerReq = scalar @{$listRecs->{content}[0]->{item}} if($listRecs->{content}[0]->{item});
				&logMessage("INFO", "($verbund) There are no new updates between $from and $until!") unless $maxResultsPerReq;
				$configs->{$verbund}->{updateIsRunning} = 0;
				Config::INI::Writer->write_file($configs, $pathConfigIni) unless $maxResultsPerReq;
				next unless $maxResultsPerReq;
				push(@verbuendeWithNewUpdates, $verbund) if $maxResultsPerReq;
				
				my @deletions;
				my $d = scalar(@deletions);	# for filename of deletions
				&logMessage("INFO", "($verbund) found new updates (download will take some minutes, maybe hours)");
				&logMessage("DEBUG", "($verbund) maxResultsPerReq: $maxResultsPerReq");
				
				# check if the path is relative or global
				my $pathToUpdates = $configs->{$verbund}->{'updates'};
				$pathToUpdates = "$ini_pathToFachkatalogGlobal$pathToUpdates" if($pathToUpdates =~ $reIsGlobalPath);
				
				open(my $OUTupd, "> $pathToUpdates"."updates_$from"."_$until"."_$n.xml") or die("($now) ERROR: ($verbund) Could not open $pathToUpdates"."updates_$from"."_$until.xml: $!\n");
				binmode $OUTupd, ":utf8";
				open(my $OUTdel, "> $pathToUpdates"."deletions_$from"."_$until" . "_" . $d .".txt") or die("($now) ERROR: ($verbund) Could not open $pathToUpdates"."deletions_$from"."_$until.txt: $!\n");
				
				# prepare the xml file for the updates
				print $OUTupd '<?xml version="1.0" encoding="ISO-8859-1" ?><marc:collection xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">'."\n";
				
				my ($firstDatestamp, $lastDatestamp, $lastDatestampUpdatefile);
				
				# iterate over all records but only if there is no error
				while( not ($listRecs->is_error) and my $rec = $listRecs->next){
					$total++;
					my $status = $rec->header->status;
					my $currID = $rec->header->identifier;
					my $currDatestamp = $rec->header->datestamp;
					
					$firstDatestamp = $currDatestamp if($total % $maxRecordsPerUpdatefile == 1);
					$lastDatestamp = $currDatestamp; 
					
					# either we have deletions
					if($status and $status eq "deleted"){
						# push id to array and to file (id is the id which has to be deleted from database)
						push(@deletions, $currID);
						print $OUTdel $currID, "\n";
					}
					# .. or we have updates
					else{
						# count update and print updates metadata into file
						$u++;
						
						# note: b3kat (http://www.bib-bvb.de/web/b3kat/open-data) does not print the oai-identifier 
						#		into the xml records - so it is needed to print the id into field 999 manually because
						#		this id is used to index the update-record when it is pushed to the Solr-Core
						if($verbund =~ /b3kat/i){
							my $recXML = $rec->{metadata}->{current}->firstChild->firstChild;
							$recXML =~ s/<\/marc:record>$/<marc:datafield tag="999" ind1=" " ind2=" "><marc:subfield code="a">$currID<\/marc:subfield><\/marc:datafield><\/marc:record>/;
							print $OUTupd $recXML;
						}
						else{
							my $recXML = $rec->{metadata}->{current}->firstChild->firstChild;
							print $OUTupd $recXML;
						}
					}
					
					&logMessage("DEBUG", "$total, ($u): ". $currDatestamp. ", ". $currID. ", ". $status, 0)  if $status;
					&logMessage("DEBUG", "$total, ($u): ". $currDatestamp. ", ". $currID, 0)  unless $status;
					
					# the list goes on so get resumption token to get all the updates
					if($total % $maxResultsPerReq == 0){
						my $rToken = $listRecs->resumptionToken();
						$listRecs = $h->ListRecords(
							verb => 'ListRecords',
							resumptionToken => $rToken->resumptionToken,
						) if $rToken;
						&logMessage("DEBUG", "($verbund) rToken: $rToken->{resumptionToken}", 0);
					}
					
					# build new file if there are too many updates for the given period
					if($maxRecordsPerUpdatefile != 0 and $u % $maxRecordsPerUpdatefile == 0 and $u != 0){
						
						print $OUTupd "\n".'</marc:collection>';
						close $OUTupd;
						
						# rename the update file - because now we know the timestamp slots
						my $oldFileName = $pathToUpdates . "updates_" . $from . "_" . $until . "_" . $n . ".xml";
						my $newFileName = $pathToUpdates . "updates_" . $firstDatestamp . "_" . $lastDatestamp . ".xml";
						&renameFile($oldFileName, $newFileName, $verbund);
						$lastDatestampUpdatefile = $lastDatestamp;
						
						$n++;
						# make new file for the updates
						my $filename = "$pathToUpdates"."updates_$from"."_$until"."_$n.$updateFormat";
						open($OUTupd, "> $filename") or die("ERROR: Could not open $filename file of $verbund: $!");
						binmode $OUTupd, ":utf8";
						print $OUTupd '<?xml version="1.0" encoding="ISO-8859-1" ?><marc:collection xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">'."\n";
						print $inOut "$currDatestamp\n";
						&logMessage("INFO", "($verbund) got updates until $currDatestamp.");
						
						# not needed to close and open again..
						#close($inOut);
						#open($inOut, ">> $pathToUpdates"."lastUpdates.txt") or die("ERROR: Could not open lastUpdates file of $verbund: $!");
					}
					
					# build new file if there are too many deletions for the given period
					if(scalar(@deletions) % $maxRecordsPerUpdatefile == 0 and scalar(@deletions) != 0 and $d < scalar(@deletions)){
						close($OUTdel);
						
						# rename the deletion file - because now we know the timestamp slots
						my $oldFileName = $pathToUpdates . "deletions_" . $from . "_" . $until . "_" . $d . ".txt";
						my $newFileName = $pathToUpdates . "deletions_" . $firstDatestamp . "_" . $lastDatestamp . ".txt";
						&renameFile($oldFileName, $newFileName, $verbund);
						
						# make new file for the deletions
						$d = scalar(@deletions);
						my $filename = $pathToUpdates . "deletions_" . $from . "_" . $until . "_" . $d . ".txt";
						$now = &getTimeStr();
						open($OUTdel, "> $filename") or die("($now) ERROR: ($verbund) Could not open $filename file of $verbund: $!\n");
					}
				}
	
				## if an error occured - log this and rename last deletion-file and delete the last update-file
				if($listRecs->is_error){
					close $OUTdel;
					close $OUTupd;
					
					# update the config.ini file when the last valid update was downloaded
					$configs->{$verbund}->{'lastUpdate'} = $lastDatestampUpdatefile;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					
					my $httpStatus = $listRecs->{_rc};
					&logMessage("ERROR", "($verbund) OAI-Update failed (HTTP-status: $httpStatus)!");
					&logMessage("INFO", "($verbund) Not all updates could be downloaded. Try again next time (update will start at last correct update).");
					
					# delete the last update file because its propably broken
					my $badUpdateFile = $pathToUpdates . "updates_" . $from . "_" . $until . "_" . $n . ".xml";
					&logMessage("INFO", "($verbund) delete last update file $badUpdateFile");
					system("rm $badUpdateFile");
				}
				## no error
				else{
					print $inOut "$lastDatestamp\n";
					close $inOut;
					print $OUTupd "\n".'</marc:collection>';
					close $OUTupd;
					close $OUTdel;
					
					# update the config.ini file when the last update was downloaded
					$configs->{$verbund}->{'lastUpdate'} = $lastDatestamp;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					
					&logMessage("INFO", "($verbund) got updates until $lastDatestamp.");
					
					# delete empty file if there are no updates
					if($u == 0){
						my $emptyUpdatesFile = $pathToUpdates . "updates_" . $from . "_" . $until . "_" . $n . ".xml";
						system("rm $emptyUpdatesFile");
					}
					# .. or rename it
					else{
						# rename the update file
						my $oldFileName = $pathToUpdates . "updates_" . $from . "_" . $until . "_" . $n . ".xml";
						my $newFileName = $pathToUpdates . "updates_" . $firstDatestamp . "_" . $lastDatestamp . ".xml";
						&renameFile($oldFileName, $newFileName, $verbund);
					}
				}
				
				# regardless of whether error or not ..
				# if there are deletions - rename the deletion file
				if(scalar(@deletions) > 0 and scalar(@deletions) % $maxRecordsPerUpdatefile != 0){
					my $oldFileName = $pathToUpdates . "deletions_" . $from . "_" . $until . "_" . $d . ".txt";
					my $newFileName = $pathToUpdates . "deletions_" . $firstDatestamp . "_" . $lastDatestamp . ".txt";
					&renameFile($oldFileName, $newFileName, $verbund);
				}
				# .. or delete it
				else{
					my $emptyDeletionFile = $pathToUpdates . "deletions_" . $from . "_" . $until . "_" . $d . ".txt";
					&logMessage("INFO", "($verbund) delete last deletion file $emptyDeletionFile");
					system("rm $emptyDeletionFile");					
				}
				
				&logMessage("INFO", "($verbund) number of deletions: ". scalar(@deletions) . " of $total in total");
				&logMessage("INFO", "($verbund) number of updates: $u of $total in total");
				
				# unlock the core in config.ini
				$configs->{$verbund}->{updateIsRunning} = 0;
				Config::INI::Writer->write_file($configs, $pathConfigIni);
			}
		}
	}
	
	return @verbuendeWithNewUpdates;
}

sub renameFile($$){
	my $oldFileName = $_[0];
	my $newFileName = $_[1];
	my $verbund = $_[2];
	&logMessage("SYS", "($verbund) mv $oldFileName $newFileName");
	system("mv $oldFileName $newFileName");
}

&getUpdates(("swb")); #just for testing

1;