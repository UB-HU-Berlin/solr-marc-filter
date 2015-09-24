#!/usr/bin/perl

use warnings;
use strict;

use Config::INI::Reader;
use Config::INI::Writer;
use FindBin;
use Text::Unidecode; # use this to stop wide character in print message

require "$FindBin::Bin/helper.pl";
our $ini_pathToSolrCoresDefault;
our $ini_urlSolrDefault;

sub optimize(@){
	my $pathConfigIni = "$FindBin::Bin/../etc/config.ini";
	my $configs = Config::INI::Reader->read_file($pathConfigIni);
	my @verbuende = @_;
	
	## check if there is enough free space (solr itself will not check that!)
	foreach my $verbund(@verbuende){
		
		&logMessage("INFO", "($verbund) Try optimizing core");
		
		my $pathSolrconfig = $ini_pathToSolrCoresDefault . "$verbund/conf/solrconfig.xml";
		my $solrDataDir = `cat $pathSolrconfig | grep dataDir`;
		($solrDataDir) = $solrDataDir =~ /<dataDir>(.+)<\/dataDir>/;
		
		## check if data dir is set global or the default data dir
		# default
		if($solrDataDir =~ /\${solr\.data\.dir:}/){
			$solrDataDir = $ini_pathToSolrCoresDefault . "$verbund/data/index";
		}
		# global
		else{
			$solrDataDir .= "/index";
		}
		
		# space used (MB)
		my $spaceDataUsed = `du -m $solrDataDir`;
		($spaceDataUsed) = $spaceDataUsed =~ /^(\d+)\s/;
		
		# global space left (MB)
		my $spaceGlobalLeft = `df -m $solrDataDir`;
		($spaceGlobalLeft) = $spaceGlobalLeft =~ /\s+\d+\s+\d+\s+(\d+)\s+\d{1,3}%/;
		
		## check if enough space left
		my $needed = 2 * $spaceDataUsed;
		
		if(not defined $spaceGlobalLeft){
			&logMessage("ERROR", "($verbund) Can not figure out disk space") unless $spaceGlobalLeft;
			next;
		}
		
		if($spaceGlobalLeft > $needed){
			&logMessage("INFO", "($verbund) Enough space to optimize core (Needed: $needed MB, Available: $spaceGlobalLeft MB)");
			
			# TODO: check when optimizing is over
			# lock current core -> updateIsRunning
			$configs->{$verbund}->{updateIsRunning} = 1;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
			
			my $response = `curl $ini_urlSolrDefault$verbund/update?optimize=true&maxSegments=10&waitFlush=true`;
			
			$configs->{$verbund}->{updateIsRunning} = 0;
			Config::INI::Writer->write_file($configs, $pathConfigIni);
			
			&logMessage("INFO", "($verbund) core optimized!");
		}
		else{
			&logMessage("WARNING", "($verbund) Not enough space to optimize core (Needed: $needed MB, Available: $spaceGlobalLeft MB)!");
		}
	}
}
if($ARGV[0]){
	&optimize($ARGV[0]);
}
1;