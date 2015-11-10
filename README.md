# solr-marc-filter

Indizierung von MARC21-Daten und anschließende Filterung nach Kriterium zur Generierung eines Extractes - kurzum - ein Sieb zum Erstellen von bspw. Fachausschnitten

Dies ist ein Projekt der Universitätsbibliothek der Humboldt-Universität zu Berlin, welches im Rahmen der Fachinfomationsdienste (FID)gestarter wurde. Hiermit sollen möglichst alle deutschen Verbunddaten indizier- und damit durchsuchbar gemacht werden, um darüber spezifische Fachausschnitte für ein jeweiliges FID zu generieren.

## Dokumentation
[fachkatalog-dokumentation.pdf](https://github.com/UB-HU-Berlin/solr-marc-filter/blob/master/docu/fachkatalog-dokumentation.pdf) enthält die Dokumentation mit detaillierten Beispielen und Informationen, sowie ein Workaround zum Einrichten des Projekts.

## Abhängigkeiten

Diese Projekt benötigt bzw. ist abhängig von folgenden Komponenten (getestet)

- [Apache Solr](http://lucene.apache.org/solr/) v4.8.1 
- [SolrMarc](https://code.google.com/p/solrmarc/source/checkout) SVN-Revision r1803
- Perl v5.8.9 mit folgenden Modulen
    - Apache::Solr
    - Archive::Extract
    - Config::INI
    - Data::Dumper
    - **Date::Simple**
    - HTTP::OAI
    - (JSON::Parse)
    - LWP::Simple
    - LWP::UserAgent
    - MARC::Batch
    - MARC::Field
    - MARC::File
    - ~~Net::SCP~~
    - ~~Net::SSH~~
    - **Net::OpenSSH**
    - Sys::Info
    - Text::Unidecode
    - Time::Piece
    - Try::Tiny
    - XML::Simple

## Struktur

- __./bin/__ 
    - enthält auführbare Bash-Skripte, die von Kommandozeile gerufen werden können
- __./data/__ 
    - enthält alle Cores (Verbünde), die in der Solr Instanz angezeigt, verwaltet und geupdatet werden
- __./docu/__
    - enthält die Dokumentation des Projekts als pdf mit detaillierten Erklärungen und den entsprechenden LaTex Resourcen
- __./etc/__ 
    - enthält wichtige Dateien wie die Konfigurationen der jeweiligen Cores und eine Datei mit der die jeweiligen Filter geschrieben werden können
- __./lib/__
    - enthält die jeweiligen Perl Skripte, die über die Bash-Skripte aufgerufen werden
- __./log/__ 
    - enthält eine globale log.txt in denen alle Änderungen/Updates/ usw. verzeichnet werden
    - enthält außerdem die jeweiligen Core-spezifischen Log-Dokumente, die angelegt werden, wenn die Core Daten initial in den Solr Index initialisiert werden
- __./results/__ 
    - enhält die Ergebnisse der Suche für die speziellen Filter sortiert nach Name des Filters bzw. Abfragezeitpunkt

    
-----------

Copyright 2015 University Library of Humboldt-Universität zu Berlin

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
