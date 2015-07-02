#!/usr/bin/perl

use warnings;
use strict;

use Config::INI::Reader;
use Config::INI::Writer;
use FindBin;
use Text::Unidecode; # use this for wide character in print

require "$FindBin::Bin/helper.pl";
my $SAFE_IN_LOG = 1;

sub optimize(@){
	my $pathConfigIni = "$FindBin::Bin/../etc/config.ini";
	my $configs = Config::INI::Reader->read_file($pathConfigIni);
	my @verbuende = @_;
	my $pathToFachkatalogGlobal = $configs->{'_'}->{'pathToFachkatalogGlobal'};
	
	## check if there is enough free space (solr itself will not check that!)
	foreach my $verbund(@verbuende){
		
		&logMessage("INFO", "Try optimizing core $verbund", $SAFE_IN_LOG);
		
		my $pathSolrconfig = $configs->{'_'}->{'pathToSolrCoresDefault'} . "$verbund/conf/solrconfig.xml";
		my $solrDataDir = `cat $pathSolrconfig | grep dataDir`;
		($solrDataDir) = $solrDataDir =~ /<dataDir>(.+)<\/dataDir>/;
		
		## check if data dir is set global or the default data dir
		# default
		if($solrDataDir =~ /\${solr\.data\.dir:}/){
			$solrDataDir = $configs->{'_'}->{'pathToSolrCoresDefault'} . "$verbund/data/index";
		}
		# global
		else{
			$solrDataDir .= "/index";
		}
		
		# space used
		my $spaceDataUsed = `du -m $solrDataDir`;
		($spaceDataUsed) = $spaceDataUsed =~ /^(\d+)\s/;
		
		# global space left
		my $spaceGlobalLeft = `df -m $solrDataDir`;
		($spaceGlobalLeft) = $spaceGlobalLeft =~ /\s+\d+\s+\d+\s+(\d+)\s+\d{1,3}%/;
		
		## check if enough space left
		my $needed = 2 * $spaceDataUsed;
		if($spaceGlobalLeft > $needed){
			&logMessage("INFO", "Enough space to optimize $verbund (Needed: $needed MB, Available: $spaceGlobalLeft MB)", $SAFE_IN_LOG);
			
			# TODO: check when optimizing is over
			# lock current core -> updateIsRunning
			$configs->{$verbund}->{updateIsRunning} = 1;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
			
			my $urlSolrDefault = $configs->{'_'}->{'urlSolrDefault'};
			my $response = `curl $urlSolrDefault$verbund/update?optimize=true&maxSegments=10&waitFlush=true`;
			
			$configs->{$verbund}->{updateIsRunning} = 0;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
			
			&logMessage("INFO", "Verbund $verbund optimized!", $SAFE_IN_LOG);
		}
		else{
			&logMessage("WARNING", "Not enough space to optimize $verbund (Needed: $needed MB, Available: $spaceGlobalLeft MB)", $SAFE_IN_LOG);
		}
	}
}
#&optimize("b3kat"); 	#TODO: just for testing! comment this line
1;