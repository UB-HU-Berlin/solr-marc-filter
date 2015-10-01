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
use Net::OpenSSH;
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
		
		# skip global ini vars
		next if $verbund eq '_';
	
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
						if($err eq ''){
							print $inOut "$fileName\n";
							&logMessage("INFO", "($verbund) $fileName successfully downloaded");
						}
						# else .. remove file and go to next core
						else{
							&logMessage("ERROR", "($verbund) unable to download Updates! ($err)");
							&logMessage("INFO", "($verbund) remove uncomplete file $fileName ..");
							unlink $pathToUpdates.$fileName;
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
						unlink $pathToUpdates.$fileName;
						
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
				
				# path to private key
				my $privateKeyPath = $ENV{"HOME"} . "/.ssh/id_rsa";

				if(-e $privateKeyPath){
					&logMessage("INFO", "($verbund) using private key $privateKeyPath for public key authentication on remote server");
				}
				else{
					&logMessage("ERROR", "($verbund) cannot find private key $privateKeyPath for public key authentication");
					last SSH;
				}				
				
				# get the updates and deletions via scp
				my @allFiles;
				my @allUpdateFiles;
				my $host = $configs->{$verbund}->{'sshHost'};
				my $user = $configs->{$verbund}->{'sshUser'};
				my $pathToSshData = $configs->{$verbund}->{'sshDataPath'};
				my $newUpdatesFound = 0;
				
				# read SSH Variables from etc/env
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
				
				# set important SSH Env vars
				$ENV{"SSH_AGENT_PID"} = $SSH_AGENT_PID;
				$ENV{"SSH_AUTH_SOCK"} = $SSH_AUTH_SOCK;
				
				# open an ssh session
				my $ssh = Net::OpenSSH->new($user . "@" . $host,
					key_path => $privateKeyPath	
				);
				if($ssh->error){
					&logMessage("ERROR", "($verbund) Couldn't establish SSH connection! ". $ssh->error);
					$configs->{$verbund}->{updateIsRunning} = 0;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					last SSH;
				}
				
				# run command on remote server
				my $cmd = "ls $pathToSshData";
				@allFiles = $ssh->capture($cmd);
				if($ssh->error){
					&logMessage("ERROR", "($verbund) Couldn't run command on remote! ". $ssh->error);
					$configs->{$verbund}->{updateIsRunning} = 0;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					last SSH;
				}
				chomp @allFiles;
				
				# check which files to download
				foreach my $updateFile(@allFiles){
					# core specific handling
					if($verbund eq 'gbv'){
						if($updateFile =~ /^gbv.+delete.+\.txt$/ or $updateFile =~ /^gbv.+update.+\.mrc\.tar\.gz$/){
					    	push(@allUpdateFiles, $updateFile);
						}
					}
					# in all other cases
					else{
						&logMessage("WARNING", "($verbund) invalid value for updateFormat in config.ini") if(not $updateFormat =~ /(mrc|xml)/);
						
						# Updates must have form File.txt(.tar|.tar.gz) or File.mrc(.tar|.tar.gz) or File.xml(.tar|.tar.gz)
						if( $updateFile =~ /^.+\.(txt|$updateFormat)(\.(tar|tar\.gz))?$/){
							push(@allUpdateFiles, $updateFile);
						}
					}
				}
				@allUpdateFiles = sort(@allUpdateFiles);
				
				# just download the new updates (and not also the lastUpdates)
				my %lastUp = map {$_ => 1} @lastUpdates;
				my @updates = grep {not $lastUp{$_}} @allUpdateFiles;
				
				# if there are updates left - they must be new updates
				if(@updates){
					&logMessage("INFO", "($verbund) Found ". scalar(@updates) ." new Updates for $verbund: @updates");
					push(@verbuendeWithNewUpdates, $verbund);
					
					
					# now download the updates
					foreach my $fileName(@updates){
						my $latestUpdate = $fileName;
						&logMessage("INFO", "($verbund) downloading $pathToSshData$fileName from $host ..");
						$ssh->scp_get({verbose => 1, timeout => 120}, $pathToSshData.$fileName, $pathToUpdates);
												
						if($ssh->error){
							my $brokenFile = $pathToUpdates.$fileName;
							&logMessage("ERROR", "($verbund) Error while trying to download file $fileName from server: ". $ssh->error);
							
							# remove fileName from list so we will not try to unpack it
							@updates = grep { $_ ne  $fileName} @updates;
							
							# remove file from dir if it exists
							unlink $brokenFile if(-e $brokenFile);
						}
						else{
							print $inOut "$latestUpdate\n";
						}
					}
				}
				else{
					&logMessage("INFO", "($verbund) is up to date ..");
					$configs->{$verbund}->{updateIsRunning} = 0;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					last SSH;
				}
				
				# now extract all downloaded files and delete the .tgz afterwords
				foreach my $fileName(@updates){
					if($fileName =~ /.+\.(tar|tar\.gz)$/){
						&logMessage("INFO", "($verbund) extracting $fileName .. ");
						$Archive::Extract::PREFER_BIN = 1;
						my $ae = Archive::Extract->new( archive => "$pathToUpdates$fileName");
						my $export = $ae->extract(to => $pathToUpdates) or print $!;
						
						if($ae->error){
							&logMessage("ERROR", "($verbund) unable to extract archive $pathToUpdates$fileName !");
							next;
						}
						
						&logMessage("INFO", "($verbund) removing downloaded archive $fileName ..");
						unlink $pathToUpdates.$fileName;
					}
				}
				
				if(@updates){
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
					last OAI;
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
				
				my ($firstDatestamp, $firstDatestampDel, $lastDatestamp, $lastDatestampUpdatefile);
				
				# iterate over all records but only if there is no error
				while( not ($listRecs->is_error) and my $rec = $listRecs->next){
					$total++;
					my $status = $rec->header->status;
					my $currID = $rec->header->identifier;
					my $currDatestamp = $rec->header->datestamp;
					
					$firstDatestamp = $currDatestamp if($total == 1); #if($total % $maxRecordsPerUpdatefile == 1); #TODO: noch falsch ..
					$firstDatestampDel = $currDatestamp if($total == 1);  # just set it once!
					
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
						if($verbund eq "b3kat"){
							my $recXML = $rec->{metadata}->{current}->firstChild->firstChild;
							# find end of record and append field(s)
							$recXML =~ s/<\/marc:record>$/<marc:datafield tag="990" ind1=" " ind2=" "><marc:subfield code="a">$currDatestamp<\/marc:subfield><\/marc:datafield>\n<marc:datafield tag="999" ind1=" " ind2=" "><marc:subfield code="a">$currID<\/marc:subfield><\/marc:datafield>\n<\/marc:record>\n/;
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
						
						$firstDatestamp = $lastDatestamp;
						$lastDatestampUpdatefile = $lastDatestamp;
						
						$n++;
						# make new file for the updates
						my $filename = "$pathToUpdates"."updates_$from"."_$until"."_$n.$updateFormat";
						open($OUTupd, "> $filename") or die("ERROR: Could not open $filename file of $verbund: $!");
						binmode $OUTupd, ":utf8";
						print $OUTupd '<?xml version="1.0" encoding="ISO-8859-1" ?><marc:collection xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">'."\n";
						print $inOut "$currDatestamp\n";
						&logMessage("INFO", "($verbund) got updates until $currDatestamp.");
					}
					
					# build new file if there are too many deletions for the given period
					if(scalar(@deletions) % $maxRecordsPerUpdatefile == 0 and scalar(@deletions) != 0 and $d < scalar(@deletions)){
						close($OUTdel);
						
						# rename the deletion file - because now we know the timestamp slots
						my $oldFileName = $pathToUpdates . "deletions_" . $from . "_" . $until . "_" . $d . ".txt";
						my $newFileName = $pathToUpdates . "deletions_" . $firstDatestampDel . "_" . $lastDatestamp . ".txt";
						&renameFile($oldFileName, $newFileName, $verbund);
						
						$firstDatestampDel = $lastDatestamp;
						$lastDatestampUpdatefile = $lastDatestamp;
						
						# make new file for the deletions
						$d = scalar(@deletions);
						my $filename = $pathToUpdates . "deletions_" . $from . "_" . $until . "_" . $d . ".txt";
						$now = &getTimeStr();
						open($OUTdel, "> $filename") or die("($now) ERROR: ($verbund) Could not open $filename file of $verbund: $!\n");
					}
				}
	
				## if an error occured - log this and rename last deletion-file and delete the last update-file
				if($listRecs->is_error){
					
					# update the config.ini file when the last valid update was downloaded
					$configs->{$verbund}->{'lastUpdate'} = $lastDatestampUpdatefile;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					
					my $httpStatus = $listRecs->{_rc};
					&logMessage("ERROR", "($verbund) OAI-Update failed (HTTP-status: $httpStatus)!");
					&logMessage("INFO", "($verbund) Not all updates could be downloaded. Try again next time (update will start at last correct update).");
					
					# delete the last update file because its propably broken
					my $badUpdateFile = $pathToUpdates . "updates_" . $from . "_" . $until . "_" . $n . ".xml";
					&logMessage("INFO", "($verbund) delete last update file $badUpdateFile");
					unlink $badUpdateFile;
				}
				## no error
				else{
					print $inOut "$lastDatestamp\n";
					print $OUTupd "\n".'</marc:collection>';
					
					# update the config.ini file when the last update was downloaded
					$configs->{$verbund}->{'lastUpdate'} = $lastDatestamp;
					Config::INI::Writer->write_file($configs, $pathConfigIni);
					
					&logMessage("INFO", "($verbund) got updates until $lastDatestamp.");
					
					# delete empty file if there are no updates
					if($u == 0){
						my $emptyUpdatesFile = $pathToUpdates . "updates_" . $from . "_" . $until . "_" . $n . ".xml";
						unlink $emptyUpdatesFile;
					}
					# .. or rename it
					else{
						# rename the update file
						my $oldFileName = $pathToUpdates . "updates_" . $from . "_" . $until . "_" . $n . ".xml";
						my $newFileName = $pathToUpdates . "updates_" . $firstDatestamp . "_" . $lastDatestamp . ".xml";
						&renameFile($oldFileName, $newFileName, $verbund);
					}
				}
				close $inOut;
				close $OUTdel;
				close $OUTupd;
				
				# regardless of whether error or not ..
				# if there are deletions - rename the deletion file
				if(scalar(@deletions) > 0 and scalar(@deletions) % $maxRecordsPerUpdatefile != 0){
					my $oldFileName = $pathToUpdates . "deletions_" . $from . "_" . $until . "_" . $d . ".txt";
					my $newFileName = $pathToUpdates . "deletions_" . $firstDatestampDel . "_" . $lastDatestamp . ".txt";
					&renameFile($oldFileName, $newFileName, $verbund);
				}
				# .. or delete it
				else{
					my $emptyDeletionFile = $pathToUpdates . "deletions_" . $from . "_" . $until . "_" . $d . ".txt";
					&logMessage("INFO", "($verbund) delete last deletion file $emptyDeletionFile");
					unlink $emptyDeletionFile;					
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
	&logMessage("SYS", "($verbund) rename $oldFileName -> $newFileName");
	rename $oldFileName, $newFileName;
}

if($ARGV[0]){
	&getUpdates($ARGV[0]);
}
1;
