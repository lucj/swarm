#!/bin/bash

# By default, 1 manager and 2 additional workers
NODES=3

# IP of manager node
MANAGER_IP=

function usage(){
  echo Usage: swk.sh [-n node_number]  
  exit 0
}

# Get options
while getopts ":n:" opt; do
  case $opt in
    n)
      NODES=$OPTARG
      ;;
    \?)
      usage
      ;;
  esac
done

# Get number of workers
WORKERS=$((NODES-1))

echo "-> swarm will start with 1 manager and $WORKERS workers"

# Create Docker host for manager
function create_manager {
  echo "-> creating Docker host for manager (please wait)"
  docker-machine create --driver virtualbox swarm0 1>/dev/null
  MANAGER_IP=$(docker-machine ip swarm0)
}

# Create Docker host for workers
function create_workers {
  for i in $(seq 1 $WORKERS); do
    echo "-> creating Docker host for worker $i (please wait)"
    docker-machine create --driver virtualbox swarm$i 1>/dev/null
  done
}

# Compile swarmkit binaries on the manager
function compile_binaries {
  echo "-> compiling swarmkit binaries on manager"
  docker-machine ssh swarm0 <<EOF
  git clone https://github.com/docker/swarmkit.git 1>/dev/null
  docker run -i -v /home/docker/swarmkit:/go/src/github.com/docker/swarmkit golang:1.6 /bin/bash -s <<END
  cd /go/src/github.com/docker/swarmkit/
  make binaries
END
EOF
}

# Run manager
function run_manager {
  echo "-> running manager in background"
  docker-machine ssh swarm0 <<EOF
  nohup /home/docker/swarmkit/bin/swarmd -d /tmp/node-mgmt-01 --listen-control-api /tmp/mgmt-01/swarm.sock --hostname mgmt-01 > output.log 2>error.log &
EOF
}

# Run workers
function run_workers {
  for i in $(seq 1 $WORKERS);do

    # Copy binaries
    echo "-> copying binaries from manager to worker $i"
    docker-machine scp swarm0:/home/docker/swarmkit/bin/swarmd swarm$i:/home/docker/
    docker-machine scp swarm0:/home/docker/swarmkit/bin/swarmctl swarm$i:/home/docker/

    # Run worker
    echo "-> running worker $i in background"
    nohup docker-machine ssh swarm$i "/home/docker/swarmd -d /tmp/node --hostname work-$i --join-addr $MANAGER_IP:4242" > output.log 2>error.log &
  done
}

# Check status of swarm
function get_status {
  echo "-> current swarm status:" 
  docker-machine ssh swarm0 'export SWARM_SOCKET=/tmp/mgmt-01/swarm.sock && /home/docker/swarmkit/bin/swarmctl node ls'
}

# Wait a little bit
function wait {
  echo $1
  sleep $2
}

function main {
  create_manager
  create_workers
  compile_binaries
  run_manager
  run_workers
  wait "waiting for the cluster to be up" 10
  get_status
}

main
