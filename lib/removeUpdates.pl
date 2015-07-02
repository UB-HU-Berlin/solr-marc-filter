#!/usr/bin/perl

use warnings;
use strict; 

use Config::INI::Reader;
use FindBin;

require "$FindBin::Bin/helper.pl";

my $configs = Config::INI::Reader->read_file("$FindBin::Bin/../etc/config.ini");
my @verbuende = keys %$configs;

foreach my $verbund(@verbuende){
	
	if(not $verbund eq "_"){
		
		# get and check if the path is relative or global
		my $dirUpd = $configs->{$verbund}->{'updates'};
		$dirUpd = $configs->{'_'}->{'pathToFachkatalogGlobal'}.$dirUpd if($dirUpd =~ /^(?!\/).+/);
		$dirUpd .= "applied/";					#TODO: make more variable!
		
		opendir(DIR_DEL, $dirUpd) or die $!;
		my @filesWithIDs = ();
		
		while(my $file = readdir(DIR_DEL)){
			if ($file =~ m/.*del.+\.txt$/){
				push(@filesWithIDs, $file);
			}
		}
		@filesWithIDs = sort @filesWithIDs;
		
		opendir(DIR_UPD, $dirUpd) or die $!;
		my @filesWithUpd = ();
		
		while(my $file = readdir(DIR_UPD)){
			if ($file =~ m/\.$configs->{$verbund}->{updateFormat}$/){
				push(@filesWithUpd, $file);
			}
		}
		
		for my $fileWithIDs(@filesWithIDs){
			&logMessage("INFO", "($verbund) removing file $dirUpd$fileWithIDs ..", 1);
			system("rm $dirUpd$fileWithIDs");
		}
		
		for my $fileWithUpd(@filesWithUpd){
			&logMessage("INFO", "($verbund) removing file $dirUpd$fileWithUpd ..", 1);
			system("rm $dirUpd$fileWithUpd");
		}
		
		if(scalar @filesWithIDs == 0 and scalar @filesWithUpd == 0){
			&logMessage("INFO", "($verbund) update path is clean - nothing to remove ..", 1);
		}
	}
}