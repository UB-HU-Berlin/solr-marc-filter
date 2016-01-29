#!/usr/bin/perl

use warnings;
use strict; 

use Config::INI::Reader;
use Data::Dumper;
use LWP::Simple;
use XML::Simple;
use FindBin;
#use JSON::Parse 'parse_json';

require "$FindBin::Bin/helper.pl";
our $ini_pathResults;
our $ini_resultType;
our $ini_resultsMaxNumber;
our $ini_resultsMaxRecordsPerFile;
our $ini_responseTimeout;
our $ini_pathQuery;
our $ini_urlSolrDefault;

my $configs = Config::INI::Reader->read_file("$FindBin::Bin/../etc/config.ini");

my $queries = Config::INI::Reader->read_file($ini_pathQuery);
my $offset = $ARGV[0];
$offset = 0 unless $offset;
my $saveResults = $ARGV[1];
$saveResults = "y" unless $saveResults;

my @queries = keys %$queries;
@queries = sort(@queries);

# read all search queries
foreach my $request(@queries){
	my $query = $queries->{$request}->{'query'} if $queries->{$request}->{'query'};
	$query = "" unless $query;
	
	# get the core-names where we have to do the search
	my @verbuendeToSearch = split(",", $queries->{$request}->{'verbund'}) if $queries->{$request}->{'verbund'};
	
	&logMessage("WARNING", "no query in $request found .. skipping!") unless $query;
	next unless $query;
	
	my $dateTime = &getTimeStr();
	
	foreach my $verbund(@verbuendeToSearch){
		next if $verbund eq "_";
		$verbund =~ s/\"//g;
		
		my $url = $ini_urlSolrDefault . "$verbund/select?";
		my $base;
		$url.= "q=$query";
		#$url.= "&wt=json";			#TODO: use json instead of xml because of overhead
		
		my $rows = 100;
		my $start = 0 + $offset;
		$url.="&shards.info=true";	# to get special information about different shards
		$url.="&fl=marc_display";	# to get only the field marc_display, because other information is not needed
		
		open(my $output, "> $ini_pathResults"."$request"."_$dateTime"."_$verbund.$ini_resultType") or die("ERROR: Could not create output file: $!");
		binmode $output, ":utf8";
		
		open(my $outputQuery, "> $ini_pathResults"."$request"."_$dateTime"."_$verbund"."_query.txt") or die("ERROR: Could not create output file: $!");
		binmode $outputQuery, ":utf8";
		
		print $outputQuery "Query=$query\n\n";
		print $outputQuery "URL=$url&rows=$rows&start=$start\n";
		close($outputQuery);
		
		my $ua = LWP::UserAgent->new;
		$ua->timeout($ini_responseTimeout);
		my $content = $ua->get($url."&rows=$rows&start=$start");
		&logMessage("DEBUG", $url."&rows=$rows&start=$start");
		
		if($content->is_success){
			
			if(not $content){
				&logMessage("ERROR", "Query $request was possible invalid");
				next;
			}
			
			#my $jsonRef = parse_json ($content->{_content});
			my $xmlRef = XMLin($content->{_content});
			
			my $resultNumber = $xmlRef->{'result'}->{'numFound'};
			$resultNumber = 0 unless $resultNumber;
			
			&logMessage("INFO", "found $resultNumber record(s) for $request");
			
			#TODO: proof
			next if $saveResults eq "n";
			
#			foreach my $shardsInfo(%{$xmlRef->{'lst'}->{'shards.info'}->{'lst'}}){
#				my $shardNumFound = $xmlRef->{'lst'}->{'shards.info'}->{'lst'}->{$shardsInfo}->{'long'}->{'numFound'}->{'content'};
#				#$shardsInfo->{'str'}->{'content'} if exists $shardsInfo->{'str'};
#				#my $shardNumFound = $shardsInfo->{'long'}->{'numFound'}->{'content'} if exists $shardsInfo->{'long'}->{'numFound'};
#				&logMessage("INFO", "\t $shardNumFound record(s) from $shardsInfo", 1) if not ref $shardsInfo eq ref {};
#			}
			
			if($ini_resultsMaxNumber > 0 and $resultNumber > $ini_resultsMaxNumber){
				&logMessage("ERROR", "found more results than allowed (increase resultsMaxNumber in config.ini to continue or use other search query)!");
				next;
			}
			&logMessage("INFO", "Writing result records into file(s)");
			
			# number of update files
			my $n = 0;
			
			# iterate over all the results found
			for (my $i = 0; $i<$resultNumber-$offset; ){
			
				# if there is more than just one result it will be an array
				if(ref ($xmlRef->{result}->{doc}) eq 'ARRAY'){
					
					# iterate over the current records set
					foreach my $field (@{$xmlRef->{result}->{doc}}){
						
						# get the mrc content and replace all the characters
						#if(exists $field->{'str'}->{'marc_display'}){
						if(exists $field->{'str'}->{'content'}){
							
							#my $mrcPlain = $field->{'str'}->{'marc_display'}->{'content'};
							my $mrcPlain = $field->{'str'}->{'content'};
							my $r1 = "\x{1d}";
							my $r2 = "\x{1e}";
							my $r3 = "\x{1f}";
							$mrcPlain =~ s/#29;/$r1/eg;
							$mrcPlain =~ s/#30;/$r2/eg;
							$mrcPlain =~ s/#31;/$r3/eg;
							
							# build new file if the max records per file is reached
							if($i % $ini_resultsMaxRecordsPerFile == 0 and $i != 0){
								$n++;
								close($output);
								open($output, "> $ini_pathResults"."$request"."_$dateTime"."_$verbund"."_$n.$ini_resultType") or die("ERROR: Could not create output file: $!");
								binmode $output, ":utf8";
							}
							print $output $mrcPlain;
						}
						else{
							# should not happen!
							&logMessage("DEBUG", "Record $i has no marc_display entry!");
						}
						$i++;
					}
				}
				# if there is exactly one result it will be a hash
				elsif(ref ($xmlRef->{result}->{doc}) eq 'HASH'){
				
					foreach my $field ($xmlRef->{result}->{doc}){
						
						#if(exists $field->{'str'}->{'marc_display'}){
						if(exists $field->{'str'}){
							
							#my $mrcPlain = $field->{'str'}->{'marc_display'}->{'content'};
							my $mrcPlain = $field->{'str'}->{'content'};
							my $r1 = "\x{1d}";
							my $r2 = "\x{1e}";
							my $r3 = "\x{1f}";
							$mrcPlain =~ s/#29;/$r1/eg;
							$mrcPlain =~ s/#30;/$r2/eg;
							$mrcPlain =~ s/#31;/$r3/eg;
							
							# build new file if the max records per file is reached
							if($i % $ini_resultsMaxRecordsPerFile == 0 and $i != 0){
								$n++;
								open($output, "> $ini_pathResults"."$request"."_$dateTime"."_$verbund"."_$n.$ini_resultType") or die("ERROR: Could not create output file: $!");
								binmode $output, ":utf8";
							}
							print $output $mrcPlain;
						}
						else{
							# should not happen!
							&logMessage("DEBUG", "Record $i has no marc_display entry!");
						}
						$i++;
					}
				}
				else{
					# just to avoid endless loop
					&logMessage("DEBUG", "Else case that should not happen at record $i !");
					$i++;
				}
				
				# reached end of the current records set -> get new ones
				if($i % $rows == 0 and $i != 0){
					$start = $i + $offset;
					$content = $ua->get($url."&rows=$rows&start=$start");
					&logMessage("DEBUG", $url."&rows=$rows&start=$start");
					$xmlRef = XMLin($content->{_content});
				}
			}
			close($output);
			&logMessage("INFO", "wrote results to $ini_pathResults");
			# just to get shure that the results will not be overwritten - sleep one second
			sleep(1);
		}
		else{
			&logMessage("ERROR", $content->status_line);
			next;
		}
	}
}