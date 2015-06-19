#!/bin/bash
echo "Offset?"
read offset

reNumber="^[1-9]([0-9])*"
if [[ $offset =~ $reNumber ]]
then
	echo "Writing all results greater $offset .."
	perl ../lib/getResults.pl $offset
else
	echo "Writing all results .."
	perl ../lib/getResults.pl
fi