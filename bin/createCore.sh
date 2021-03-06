#!/bin/bash
newCore=$1
length=${#newCore}

if [ $length -le 0 ]
   then
      echo "Forgot name of core?" 
      echo "./createCore.sh nameOfNewCore"
      exit -1
fi

##DEFAULT PATHS
# needes awk installed
# TODO: Slashes and Whitespaces! 
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
urlSolrDefault=$(awk -F "= " '/urlSolrDefault/ {print $2}' $DIR/../etc/config.ini)
pathToSolrCoresDefault=$(awk -F "= " '/pathToSolrCoresDefault/ {print $2}' $DIR/../etc/config.ini)
pathToSolrMarcDefault=$(awk -F "= " '/pathToSolrMarcDefault/ {print $2}' $DIR/../etc/config.ini)

# check if newCore already exists ..
while [ -d "../data/$newCore" ];
do
   echo "Core $newCore already exists! Choose different name: "
   read newCore
done

pathToFachkatalogGlobal="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"
echo "Give path to SOLR CORES if it differs from $pathToSolrCoresDefault"
read pathToSolrCores
if [ "$pathToSolrCores" == "" ]
then
	pathToSolrCores=$pathToSolrCoresDefault
	#sed -i "s/^pathToSolrMarcDefault(\s)?=(\s)?/pathToSolrMarcDefault = $pathToSolrCoresDefault/g" $DIR/../etc/config.ini
	#TODO .. change default value!
fi

echo "Give path to SOLR MARC if it differs from $pathToSolrMarcDefault"
read pathToSolrMarc
if [ "$pathToSolrMarc" == "" ]
then
	pathToSolrMarc=$pathToSolrMarcDefault
	#TODO .. change default value!
fi

echo "Give the format of which the initial data is (xml|mrc):"
read initialDataFormat
while [ "$initialDataFormat" != "xml" ] && [ "$initialDataFormat" != "mrc" ]
do
   echo "Only xml or mrc as initial data is supported! Type xml|mrc"
   read initialDataFormat
done

echo "Choose update type (oai|ssh|http): "
read updateType

while [ "$updateType" != "oai" ] && [ "$updateType" != "ssh" ] && [ "$updateType" != "http" ]
do
   echo "Choose update type (oai|ssh|http): "
   read updateType
done

if [ "$updateType" == "ssh" ]
then
	./startSshAgent.sh
fi

echo "Choose update intervals in days: "
read updateIntervalInDays

re="^[0-9]+$"
while ! [[ $updateIntervalInDays =~ $re ]];
do
   echo "Choose update intervals in days:"
   read updateIntervalInDays
done

coreSpecificString=""
NEWLINE=$'\n'
case "$updateType" in
"oai")	
	echo "Choose OAI specific: oldest possible update for this interface, format: yyyy-mm-dd"
	read oaiOldestUpdate
	
	reDate="^[1-2][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]"
	d="[[:digit:]]"
	while ! [[ $oaiOldestUpdate =~ $reDate ]]
    do
    	echo "Format: yyyy-mm-dd"
        read oaiOldestUpdate
	done
	oaiOldestUpdate=$oaiOldestUpdate"T00:00:00Z"
	coreSpecificString="oaiOldestUpdate = $oaiOldestUpdate"

	echo "Choose OAI specific: url"
	read oaiUrl
	coreSpecificString="$coreSpecificString${NEWLINE}oaiUrl = $oaiUrl"
	
	echo "Choose OAI specific: oaiMaxRecordsPerUpdatefile (default 10000)"
	read oaiMaxRecordsPerUpdatefile
	
	if [ "$oaiMaxRecordsPerUpdatefile" == "" ]
	then 
		oaiMaxRecordsPerUpdatefile=10000
	fi
	
	while ! [[ $oaiMaxRecordsPerUpdatefile =~ $re ]];
	do
	   echo "Choose OAI specific: oaiMaxRecordsPerUpdatefile"
	   read oaiMaxRecordsPerUpdatefile
	done
	
	if [ oaiMaxRecordsPerUpdatefile == 0 ]
	then
		oaiMaxRecordsPerUpdatefile=10000
	fi
	
	coreSpecificString="$coreSpecificString${NEWLINE}oaiMaxRecordsPerUpdatefile = $oaiMaxRecordsPerUpdatefile"	
	oaiMaxDaysPerUpdatefile=0
	coreSpecificString="$coreSpecificString${NEWLINE}oaiMaxDaysPerUpdatefile = $oaiMaxDaysPerUpdatefile"
	;;

"ssh")
	echo "Choose SSH specific: ssh host"	
	read sshHost
	coreSpecificString="$coreSpecificString${NEWLINE}sshHost = $sshHost"
	
	echo "Choose SSH specific: ssh user"	
	read sshUser
	coreSpecificString="$coreSpecificString${NEWLINE}sshUser = $sshUser"
		
	echo "Choose SSH specific: ssh path to data"    
	read sshDataPath
	coreSpecificString="$coreSpecificString${NEWLINE}sshDataPath = $sshDataPath"
	;;

"http")
	echo "Choose HTTP parameter: url to update data"
    read httpUrl
    http='^http://.+'
	while [ "$httpUrl" == "" ] || ! [[ $httpUrl =~ $http ]]
	do
		echo "Choose HTTP parameter: url to update data (non empty and beginning with http://)"
		read httpUrl
	done
    coreSpecificString="httpUrl = $httpUrl"
		
    echo "Choose HTTP parameter: url to deletion data (skip this if there is just one url for updates and deletions you typed before)"
    read httpUrlDeletions
	if [ "$httpUrlDeletions" == "" ]
	then
		httpUrlDeletions=$httpUrl
	fi
	
	while ! [[ $httpUrlDeletions =~ $http ]]
	do
		echo "Choose HTTP parameter: url to update data (url must begin with http://)"
		read httpUrlDeletions
		
	    if [ "$httpUrlDeletions" == "" ]
		then
			httpUrlDeletions=$httpUrl
		fi
	done
        
    coreSpecificString="$coreSpecificString${NEWLINE}httpUrlDeletions = $httpUrlDeletions"
	;;

*)	;;

esac

FILE="../etc/config.ini"
/bin/cat <<EOF >>$FILE


[$newCore]
updateType = $updateType
$coreSpecificString
indexPropertiesFile = data/$newCore/conf/index.properties
configPropertiesFile = data/$newCore/conf/config.properties
updateIntervalInDays = $updateIntervalInDays 
updates = data/$newCore/updates/
updateFormat = $initialDataFormat
updateIsRunning = 0
check = 1
lastUpdate = 2014-01-01T12:00:00Z
urlSolrCore = $urlSolrDefault/#/$newCore
initial = data/$newCore/initialData/
initialDataFormat = $initialDataFormat
EOF

# create data directory structure in solr-marc-filter
mkdir ../data/$newCore
mkdir ../data/$newCore/conf
touch ../data/$newCore/conf/config.properties
cp 	  ../lib/templates/solrMarc/index.properties.plain ../data/$newCore/conf/index.properties
mkdir ../data/$newCore/initialData
mkdir ../data/$newCore/updates
mkdir ../data/$newCore/updates/applied
touch ../data/$newCore/updates/lastUpdates.txt

# create directories in solr and copy all solr template files
mkdir $pathToSolrCores$newCore
mkdir $pathToSolrCores$newCore"/conf/"
mkdir $pathToSolrCores$newCore"/data/"
cp -r $pathToFachkatalogGlobal"/lib/templates/solr/." $pathToSolrCores$newCore"/conf/"

#TODO: vllt probleme mit Slash /
echo "curl \"${urlSolrDefault}admin/cores?action=CREATE&name=$newCore&instanceDir=$pathToSolrCores$newCore\""
curl "${urlSolrDefault}admin/cores?action=CREATE&name=$newCore&instanceDir=$pathToSolrCores$newCore"

customJarPath=$pathToSolrMarc"/lib/solr_remote_only"

# fill the config.properties file with data
FILE="../data/$newCore/conf/config.properties"
/bin/cat <<EOF >>$FILE

# Properties for the Solrmarc program
# solrmarc.solr.war.path - must point to either a war file for the version of Solr that
# you want to use, or to a directory of jar files extracted from a Solr war files.  If
# this is not provided, SolrMarc can only work by communicating with a running Solr server.
solrmarc.solr.war.path=$pathToSolrCores../solr-webapp/webapp/WEB-INF/lib

# solrmarc.custom.jar.path - Jar containing custom java code to use in indexing. 
# If solr.indexer below is defined (other than the default of org.solrmarc.index.SolrIndexer)
# you MUST define this value to be the Jar containing the class listed there. 
solrmarc.custom.jar.path=$pathToSolrMarc|$customJarPath

# Path to your solr instance
solr.path = REMOTE

# - solr.indexer - full name of java class with custom indexing functions. This 
#   class must extend SolrIndexer; Defaults to SolrIndexer.
solr.indexer = org.solrmarc.index.SolrIndexer

# - solr.indexer.properties -indicates how to populate Solr index fields from
#   marc data.  This is the core configuration file for solrmarc.
solr.indexer.properties = index.properties

# URL of running solr search engine to cause updates to be recognized.
#TODO vllt probleme mit Slash /
solr.hosturl = $urlSolrDefault$newCore								

solr.data.dir = $pathToSolrCores$newCore/data
solr.core.name = $newCore

# Settings to control how the records are handled as they are read in.

# - marc.to_utf_8 - if true, this will convert records in our import file from 
#   MARC8 encoding into UTF-8 encoding on output to index
marc.to_utf_8 = false

# - marc_permissive - if true, try to recover from errors, including records
#  with errors, when possible
marc.permissive = true

# - marc.default_encoding - possible values are MARC8, UTF-8, UNIMARC, BESTGUESS
marc.default_encoding = MARC8

# - marc.include_erros - when error in marc record, dump description of error 
#   to field in solr index an alternative way to trap the indexing error 
#   messages that are logged during index time.  Nice for staff b/c they can 
#   search for errors and see ckey and record fields in discovery portal.  This 
#   field is NOT used for other queries.  Solr schema.xml must have field 
#   marc_error.
marc.include_errors = false

EOF
