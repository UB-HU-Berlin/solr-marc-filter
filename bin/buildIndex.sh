#!/bin/bash
echo "Which Core should be indizised?"

pathToFachkatalogGlobal="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"
pathToData="$pathToFachkatalogGlobal/data"
cd $pathToData
echo $pathToData

j=0
echo "[$j] ABORT"
array[$j]="ABORT";

for i in $( ls -d */ );
do
	let "j+=1";
	echo "[$j]" ${i%%/};
	array[$j]=${i%%/};
done
#echo $j
#echo ${array[@]}

read number
reNumber="^[0-$j]"
while ! [[ $number =~ $reNumber ]]
do
   echo "Not a valid number!"
   read number
done

if [[ $number -eq "0" ]] ;
then
	echo "Aborted!"
	exit -1
fi

core=${array[$number]}

echo "Are you shure to index the Core >$core<? Type YES to continue"
read continue

#TODO index all ..
if [ "$continue" == "YES" ]
then
	echo "Will index Core(s) now!"
	perl ../lib/buildInitialIndexThreading.pl $core
else
	echo "Aborted!"
fi