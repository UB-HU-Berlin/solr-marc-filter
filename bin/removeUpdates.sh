#!/bin/bash

pathToFachkatalogGlobal="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"
pathToLib="$pathToFachkatalogGlobal/lib"

perl ../lib/removeUpdates.pl