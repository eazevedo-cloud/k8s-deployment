#!/bin/bash

# show download progress bar (works sometimes)
show_progress() {
  local -r pid="$1"
  local -r delay=0.1
  local spinstr='|/-\'

  while ps a | awk '{print $1}' | grep -q "$pid"; do
    local temp="${spinstr#?}"
    printf " [%c]  " "$spinstr"
    spinstr="$temp${spinstr%"$temp"}"
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# install minikube and addons
install_minikube() {
  # Determine OS and Architecture
  OS=$(uname -s)
  ARCH=$(uname -m)

  # Install minikube based on OS and Architecture
  if [[ "$OS" == "Linux" ]]; then
    echo "Linux OS detected. Downloading..."
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 &
    show_progress $!
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
  elif [[ "$OS" == "Darwin" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
      echo "OSX (ARM64) detected. Downloading..."
      curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-arm64 &
      show_progress $!
      sudo install minikube-darwin-arm64 /usr/local/bin/minikube
    else
      echo "OSX (x86_64) detected. Downloading..."
      curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-amd64 &
      show_progress $!
      sudo install minikube-darwin-amd64 /usr/local/bin/minikube
    fi
  else
    echo "Unsupported OS: $OS"
    exit 1
  fi

  # Ask for Kubernetes version (be sure what you are doing!)
  read -p "Enter Kubernetes version (blank for latest): " k8s_version

  # Number of worker nodes
  read -p "Enter number of worker nodes: " num_nodes

  # Starting minikube 4 CPUs (Istio requires 4!)
  minikube start --driver=docker --nodes "$num_nodes" --cpus 4 ${k8s_version:+--kubernetes-version="$k8s_version"}

  # Enabling addons
  minikube addons enable storage-provisioner-gluster
  minikube addons enable ingress-dns
  minikube addons enable ingress
  minikube addons enable istio-provisioner
  minikube addons enable istio
}

# uninstall minikube and addons
uninstall_minikube() {
  # Disable addons
  minikube addons disable istio
  minikube addons disable istio-provisioner
  minikube addons disable ingress
  minikube addons disable ingress-dns
  minikube addons disable storage-provisioner-gluster

  # Stop and delete minikube cluster
  minikube delete

  # Remove minikube binary (optional)
  # sudo rm /usr/local/bin/minikube
}

# stop minikube cluster
stop_minikube() {
  minikube stop
}

# start minikube cluster
start_minikube() {
  minikube start
}

# Parse command line arguments
if [[ "$1" == "install" ]]; then
  install_minikube
elif [[ "$1" == "uninstall" ]]; then
  uninstall_minikube
elif [[ "$1" == "stop" ]]; then
  stop_minikube
elif [[ "$1" == "start" ]]; then
  start_minikube
else
  echo "Usage: $0 {install|uninstall|stop|start}"
  exit 1
fi
