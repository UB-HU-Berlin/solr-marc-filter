#!/bin/bash

# TODO: wann werden diese envs ungültig?
# TODO: was ist mit ssh-agnet beim logout des benutzers - z.b. wäre es sinnvoll unter nobody agent zu starten sodass agent nicht schließt?

## set paths
pathToFachkatalogGlobal="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"
pathToEtc="$pathToFachkatalogGlobal/etc"
FILE="$pathToEtc/env"


## check another key path
echo 'Enter GLOBAL PATH of ssh private key if differs from ~/.ssh/id_rsa'
read pathToPrivateKey

## while path isnt empty and doesnt exist
## 	-z checks if string is empty
## 	-a checks if FILE exists
while [[ ! -z "$pathToPrivateKey" ]] && [[ ! -a "$pathToPrivateKey" ]];
do
   echo "PrivateKey Location does not exist ($pathToPrivateKey) (used global path?), enter correct path or just leave it out:"
   read pathToPrivateKey
done


## function to start the ssh-agent and ask for pass if needed
function startAgent(){
	eval $(ssh-agent); ssh-add $pathToPrivateKey
}


## Check if File with env vars is empty
if [ ! -s $FILE ]
then
	## start ssh agent and enter password
	echo "$FILE is empty - creating new in $FILE"
	echo agent0
	startAgent
	
	## write env-vars into FILE
	echo "SSH_AGENT_PID=$SSH_AGENT_PID" > $FILE
	echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" >> $FILE
	exit
fi


## 	check if $SSH_AUTH_SOCK and $SSH_AGENT_PID are used and if $SSH_AGENT_PID is running as process
## 	info: <&3 to enable reading from command line for password while reading a file
## 	info: -r and -n flags: to enable reading for files not escaped with newline
while read -r line <&3 || [[ -n "$line" ]]; do

	if [[ $line == "SSH_AGENT_PID="* ]]
	then
		## parse SSH_AGENT_PID from $line
		index=$(echo "SSH_AGENT_PID=" | wc -c)
		SSH_AGENT_PID_READ=$(echo $line | cut -c $index-)
				
		## check if pid exists
		pids=$(ps -efww | grep $SSH_AGENT_PID_READ | wc -l)
		
		if [[ $pids == 2 ]]
		then
			echo "necessary ssh env vars exists in $FILE"
			## Notice: exporting SSH env vars take only effect within this script
			export SSH_AGENT_PID=$SSH_AGENT_PID_READ
		else
			## start ssh agent and enter password
			echo "necessary ssh env vars doesnt exist - create new in $FILE"
			echo agent1
			startAgent
			
			## write env-vars into FILE
			echo "SSH_AGENT_PID=$SSH_AGENT_PID" > $FILE
			echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" >> $FILE
			break
		fi
	
	elif [[ $line == "SSH_AUTH_SOCK="* ]]
	then
		export $line
	
	else
		## start ssh agent and enter password
		echo "necessary ssh env vars doesnt exist - create new in $FILE"
		echo agent2
		startAgent
		
		## write env-vars into FILE
		echo "SSH_AGENT_PID=$SSH_AGENT_PID" > $FILE
		echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" >> $FILE
		break
	fi

done 3<$FILE;

echo "SSH_AGENT_PID=$SSH_AGENT_PID"
echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
echo "Done"
