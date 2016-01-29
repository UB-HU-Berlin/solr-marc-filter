#!/bin/bash
echo "Save results? [Y]es/[n]o"
read saveResults
reYesNo="^[ynYN]"
while ! [[ $saveResults =~ $reYesNo ]]
do
   echo "y/n?"
   read saveResults
done

echo "Offset?"
read offset

reNumber="^[1-9]([0-9])*"
if [[ $offset =~ $reNumber ]]
then
	echo "Writing all results greater $offset .."
	perl ../lib/getResults.pl $offset $saveResults
else
	echo "Writing all results .."
	perl ../lib/getResults.pl 0 $saveResults
fi