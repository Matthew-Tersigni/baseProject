#!/bin/bash

CURRENT_DIR="`dirname \"$0\"`"

set -e                                                                                                

declare -r VERSION='1.0'                                                                            

function showHelp()
{
         cat << EOF
usage: ${0} [options]
Options:
  -h Show help options

  -v Print version info

  -i install and initialize minikube and pods (ledger will be public by default)

  -d destroy the minikube and the pods

  -s Skip creation of a type of pod
	
	EXAMPLE USAGE: -s PG -s RMQ would not install postgres and RMQ or bring up those pods
	Options separated by a single dash
	Options include:
		RDB    - Relational DB (PostgreSQL, or MariaDB Galera Cluster) 
		RMQ    - RabbitMQ
		MONGO  - MongoDB
		LEDGER - Custom public ledger

  -p Do a full database import using a database dump file
	-p <PATH_TO_DB_DUMP>

  -o database option 
	one of 'mysql' or 'postgresql'

  -l Set the ledger to private (only trusted nodes can post blocks)

  -x Deploy on the bare metal - this will not deploy in a VM

Example (initializes vm without mongo, but with mariaDB mysql):
  ./${0} -i -s=MONGO -omysql
EOF
}

function parseCommandLineOptions()                            
{                
	while getopts "hvids:p:l:o:" opt	
	do
	# Parse command line options                          
        case $opt in                         
                h)                                         
                        showHelp                              
                        exit 0;;                                    
                v)  
			echo "Version ${VERSION}"                 
                        exit 0;;                                    
                i)  
			init_flag=1;;                                    
                d)
			destroy_flag=1;;  
		s)
			multi_skip+=("$OPTARG");; 
		p)
			dump_path=("$OPTARG");;
		l)
			private_ledger=1;;
		o)
			db_option=("$OPTARG");;
		x)
			bare_metal=1;;
		*)
			showHelp
			exit 0;;
                esac                                          
        done                                                  
        
        for val in "${multi_skip[@]}"; do
		if [ $val == "RDB" ]; then 
			echo "Skipping Relational Database"
			skip_db=1
		elif [ $val == "MONGO" ]; then 
			echo "Skipping MONGO"
			skip_mongo=1
		elif [ $val == "RMQ" ]; then 
			echo "Skipping RMQ"
			skip_rmq=1
		elif [ $val == "LEDGER" ]; then 
			echo "Skipping LEDGER"
			skip_ledger=1
		else
			echo "Invalid option - $val - Exiting."
			exit 0
		fi
	done
}       


function installKubernetes()
{
	echo "----------------------------------------------------------------------------"
	echo "Installing Kubernetes"
	echo "----------------------------------------------------------------------------"
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -                                 
        sudo touch /etc/apt/sources.list.d/kubernetes.list                                                                 
        echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list  
        sudo apt-get update                                                                                                
        sudo apt-get install -y kubectl                                                                                    
}

function installMinukube()
{
	echo "----------------------------------------------------------------------------"
	echo "---------------------------Installing Minikube------------------------------"
	echo "----------------------------------------------------------------------------"
	curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
	sudo chmod +x minikube
	sudo mv -v minikube /usr/local/bin
}

function installHelm()
{
	echo "----------------------------------------------------------------------------"
	echo "-----------------------------Installing Helm--------------------------------"
	echo "----------------------------------------------------------------------------"
	curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > get_helm.sh
	chmod 700 get_helm.sh
	./get_helm.sh
	helm repo update
}

function installPreRequisits()
{
	echo "----------------------------------------------------------------------------"
	echo "----VT-x or AMD-v virtualization must be enabled in your computer’s BIOS----"
	echo "----------------------------------------------------------------------------"
	sleep 10;
	sudo apt-get install virtualbox -y 
	sudo apt-get update && sudo apt-get install -y apt-transport-https
	sudo apt-get install jq -y
	installKubernetes
	installMinukube
	installHelm
}

function startKubeMaster()
{
	echo "----------------------------------------------------------------------------"
	echo "----------------------------Starting Kubemaster-----------------------------"
	echo "----------------------------------------------------------------------------"
	minikube start
	helm init
	helm init --upgrade
	helm plugin install https://github.com/astronomerio/helm-delete-all-plugin --version 0.0.2
}

function getCharts()
{

	
	echo "----------------------------------------------------------------------------"
	echo "-------------------------Setting up Relational DB---------------------------"
	echo "----------------------------------------------------------------------------"
	#set up RDB
	if [ "$db_option" = "postgresql" ]; then

		#get configuration options
		base_pg_config="/kubeConfig/postgres.conf"
		local_pg_config="/kubeConfig/local.postgres.conf"

		if [ ! -f $CURRENT_DIR$local_pg_config ]; then
			postgres_conf_path=$CURRENT_DIR$base_pg_config
		else
			postgres_conf_path=$CURRENT_DIR$local_pg_config
		fi

		pg_options_pre=`jq -r '. | keys_unsorted[] as $k | "\($k)=\(.[$k]|.val),"' $postgres_conf_path`
		pg_options=${pg_options_pre::-1}

		#install with options
		helm install --name pgsql-cluster stable/postgresql

	elif [ "$db_option" = "mysql" ]; then
		helm install --name stable/mariadb
	else 
		echo "Not setting up a database instance at this time. Invalid option - $db_option"
	fi


	
	echo "----------------------------------------------------------------------------"
	echo "---------------------Setting up Container Monitoring------------------------"
	echo "----------------------------------------------------------------------------"
	helm install --name kong stable/kong
	helm install --name ops-view stable/kube-ops-view

	
	
	echo "----------------------------------------------------------------------------"
	echo "------------------------Setting up Reporting Tool---------------------------"
	echo "----------------------------------------------------------------------------"
	helm install --name metabase stable/metabase

	
	echo "----------------------------------------------------------------------------"
	echo "---------------------------Setting up Mongo DB------------------------------"
	echo "----------------------------------------------------------------------------"
	helm install --name mongo stable/mongodb

	
	echo "----------------------------------------------------------------------------"
	echo "-------------------------Setting up Flask Server----------------------------"
	echo "----------------------------------------------------------------------------"
#	helm install --name python-backend charts/flask.yaml
	
	echo "----------------------------------------------------------------------------"
	echo "----------------------------Setting up Rabbit-------------------------------"
	echo "----------------------------------------------------------------------------"
	helm install --name rmq stable/rabbitmq-ha
	
	echo "----------------------------------------------------------------------------"
	echo "----------------------------Setting up Redis--------------------------------"
	echo "----------------------------------------------------------------------------"
	helm install --name redis stable/redis-ha


}

function cleanUp()
{
	rm get_helm.sh
}
#parseCommandLineOptions "${@}"
#installPreRequisits
#startKubeMaster
#cleanUp

getCharts
