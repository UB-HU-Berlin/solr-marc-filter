#!/bin/bash

coreDel=$1
length=${#coreDel}

if [ $length -le 0 ]
   then
      echo "Forgot name of core?" 
      echo "./removeCore.sh nameOfCoreToRemove"
      exit -1
fi

##DEFAULT PATHS
# needes awk installed
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
urlSolrDefault=$(awk -F "= " '/urlSolrDefault/ {print $2}' $DIR/../etc/config.ini)
pathToSolrCoresDefault=$(awk -F "= " '/pathToSolrCoresDefault/ {print $2}' $DIR/../etc/config.ini)
pathToSolrMarcDefault=$(awk -F "= " '/pathToSolrMarcDefault/ {print $2}' $DIR/../etc/config.ini)

pathToFachkatalogGlobal="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"

# check if core exists!
if [ ! -d "../data/$coreDel" ];
	then
		echo "Core $coreDel does not exists!"
		exit -1
fi

echo "Give parent path to the solr core you want to delete. Just type if it differs from $pathToSolrCoresDefault"
read pathToSolrCores
if [ "$pathToSolrCores" == "" ]
then
	pathToSolrCores=$pathToSolrCoresDefault
fi

echo "CAUTION! INDEXED DATA, FILES AND UPDATES WILL BE REMOVED PERMANENTLY - UNDO IMPOSSIBLE!"
echo "If you really want to continue, type YES"
read continue

if [ "$continue" == "YES" ]
	then
		echo "Core with all data, index and updates will be removed now!"
		echo "$urlSolrDefault$coreDel/update?commit=true -H \"Content-Type: text/xml\" --data-binary '<delete><query>*:*</query></delete>'"	#&commit=true
		curl "$urlSolrDefault$coreDel/update?commit=true -H \"Content-Type: text/xml\" --data-binary '<delete><query>*:*</query></delete>'"	#&commit=true
		echo "${urlSolrDefault}admin/cores?action=UNLOAD&core=$coreDel"
		curl "${urlSolrDefault}admin/cores?action=UNLOAD&core=$coreDel"
		rm -r ../data/$coreDel
		rm -r $pathToSolrCores$coreDel
		# update the config.ini
		perl ../lib/removeCoreFromIni.pl $coreDel
	else
		echo "Process aborted!"
		exit -1
fi
