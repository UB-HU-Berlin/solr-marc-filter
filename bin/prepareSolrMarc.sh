#!/bin/bash

#TODO: dirty way - SolrMarc.jar location and content of some files have to be changed for that..

echo "This script will download and configure solrMarc for you. This script should only be run once!"
echo "Type YES to continue .."
read continue

if [ "$continue" == "YES" ]
then
	echo "Will download and configure SolrMarc now"
else
	echo "Aborted!"
fi

## DEFAULT PATHS
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
urlSolrDefault=$(awk -F "= " '/urlSolrDefault/ {print $2}' $DIR/../etc/config.ini)
pathToFachkatalogGlobal="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"

pathToSolrMarcDefault=$pathToFachkatalogGlobal"/../solrmarc/"

mkdir $pathToSolrMarcDefault
cd $pathToSolrMarcDefault

#URL_SolrMarc="https://solrmarc.googlecode.com/files/SolrMarc_Generic_Source-2.6.tar.gz"
#wget $URL_SolrMarc
#tar zxvf *.tar.gz

svn checkout http://solrmarc.googlecode.com/svn/trunk/ $pathToSolrMarcDefault
ant init

cp local_build/lib/SolrMarc.jar local_build

sed -i 's/@MEM_ARGS@/-Xmx256m/' local_build/script_templates/indexfile

chmod u+x local_build/script_templates/*

cp -r $pathToFachkatalogGlobal/lib/templates/solrMarc/*.bsh local_build/index_scripts/

echo exit
