#!/bin/bash
echo "Which Core should be indizised?"

pathToFachkatalogGlobal="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"
pathToData="$pathToFachkatalogGlobal/data"
cd $pathToData
echo $pathToData

j=0
echo "[$j] ABORT"
array[$j]="ABORT";
j=1
echo "[$j] ALL"
array[$j]="ALL";

# show all existing cores and let the user select one
for i in $( ls -d */ );
do
	let "j+=1";
	echo "[$j]" ${i%%/};
	array[$j]=${i%%/};
done

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

indexAll=0

if [[ $core == "ALL" ]]
then
	echo "Are you shure to index the ALL Cores?. Check every index.properties file to make shure everything you want will be indicated."
	indexAll=1
else
	echo "Are you shure to index the Core $core?. Check index.properties file to make shure everything you want will be indicated."
fi
#subarray array[1:]
#echo ${array[@]:1:${#array[@]}}

echo "Type YES to continue .."
read continue

if [ "$continue" == "YES" ]
then
	echo "Will index Core(s) now!"
	if [ $indexAll == 1 ]
	then
		for coreName in ${array[@]:2:${#array[@]}} ;
		do
			core+=$coreName
			core+=" "
		done
		core=${core:0:-1}
	fi
	perl ../lib/buildInitialIndexThreading.pl $core
	echo ../lib/buildInitialIndexThreading.pl $core
else
	echo "Aborted!"
fi
