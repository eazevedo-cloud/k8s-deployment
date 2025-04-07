#!/bin/bash

# Variables
CLUSTER_NAME="zalpy-kind"
NETWORK_NAME="${CLUSTER_NAME}-net"
NETWORK_SUBNET="172.23.0.0/24"
CONFIG_FILE="${CLUSTER_NAME}-config.yaml"
KUBERNETES_VERSION="v1.29.2"  # Kind uses node images tagged with Kubernetes versions
NUM_WORKERS=2  # Number of worker nodes

KIND_PORT=6443  # Default Kubernetes API port
MAX_RETRIES=10
RETRY_DELAY=15

# Function to display help
show_help() {
  echo "Usage: $0 [OPTION]"
  echo "Manage a Kind (Kubernetes in Docker) cluster"
  echo ""
  echo "Options:"
  echo "  --create    Create a new Kind cluster"
  echo "  --delete    Delete all cluster resources"
  echo "  --addons [name]  Install addons (minio, metallb, metrics-server)"
  echo "                   If no addon name is specified, installs all"
  echo "  --help      Display this help message"
  echo ""
  echo "Examples:"
  echo "  $0 --create          # Create a new cluster"
  echo "  $0 --delete          # Delete the cluster"
  echo "  $0 --addons minio    # Install MinIO addon"
  echo "  $0 --addons          # Install all addons"
  exit 0
}


# Function to create cluster
create_cluster() {
  echo "Creating Kind cluster '${CLUSTER_NAME}' with 1 control-plane and $NUM_WORKERS workers..."

  # Create Docker network with a specific subnet if it doesn't exist
  if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    echo "Creating Docker network '${NETWORK_NAME}' with subnet $NETWORK_SUBNET..."
    docker network create --subnet="$NETWORK_SUBNET" "$NETWORK_NAME"
  else
    echo "Docker network '${NETWORK_NAME}' already exists."
  fi


  # Generate Kind configuration file
  cat <<EOF > "$CONFIG_FILE"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "0.0.0.0"
  apiServerPort: $KIND_PORT
nodes:
- role: control-plane
EOF
  for i in $(seq 1 $NUM_WORKERS); do
    cat <<EOF >> "$CONFIG_FILE"
- role: worker
EOF
  done

  # Start Kind cluster
  echo "Starting Kind cluster..."
  kind create cluster \
    --name "$CLUSTER_NAME" \
    --config "$CONFIG_FILE" \
    --image "kindest/node:$KUBERNETES_VERSION"

  echo "Waiting for cluster to initialize..."
  sleep 30


  # Verify cluster status with retry
  echo "Verifying cluster status..."
  for attempt in $(seq 1 $MAX_RETRIES); do
    if kubectl cluster-info --context "kind-$CLUSTER_NAME" &>/dev/null; then
      echo "Kind cluster is running."
      break
    fi
    echo "Retrying cluster status check ($attempt/$MAX_RETRIES)..."
    sleep $RETRY_DELAY
  done

  if ! kubectl cluster-info --context "kind-$CLUSTER_NAME" &>/dev/null; then
    echo "Error: Kind cluster failed to start after $MAX_RETRIES attempts."
    kind --name "$CLUSTER_NAME" export logs
    exit 1
  fi

  # Export kubeconfig
  echo "Configuring kubeconfig..."
  mkdir -p ~/.kube
  kind get kubeconfig --name "$CLUSTER_NAME" > ~/.kube/kind-$CLUSTER_NAME.yaml
  export KUBECONFIG=~/.kube/kind-$CLUSTER_NAME.yaml
  kubectl config use-context "kind-$CLUSTER_NAME"

  # Verify cluster nodes
  echo "Verifying cluster nodes..."
  kubectl get nodes

  echo "Kind cluster setup completed successfully!"
}

# Function to delete all resources
delete_resources() {
  echo "Cleaning up all resources for cluster '${CLUSTER_NAME}'..."
  if kind get clusters | grep -q "$CLUSTER_NAME"; then
    echo "Deleting Kind cluster '${CLUSTER_NAME}'..."
    kind delete cluster --name "$CLUSTER_NAME"
  fi
  if docker network inspect "$NETWORK_NAME" &>/dev/null; then
    echo "Removing Docker network '${NETWORK_NAME}'..."
    docker network rm "$NETWORK_NAME"
  fi
  echo "Removing kubeconfig and config files..."
  rm -f ~/.kube/kind-$CLUSTER_NAME.yaml
  rm -f "$CONFIG_FILE"
  echo "Cleanup completed!"
  exit 0
}

# Function to install addons
install_addon() {
  local addon_name=$1
  case $addon_name in
    minio)
      echo "Installing MinIO..."
      kubectl apply -k "github.com/minio/operator?ref=v7.0.1"
      ;;
    metallb)
      echo "Installing MetalLB..."
      kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
      cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-address-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.23.0.100-172.23.0.200
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec: {}
EOF
      ;;
    metrics-server)
      echo "Installing Metrics Server..."
      kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
      kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
      ;;
    *)
      echo "Error: Unknown addon '$addon_name'."
      exit 1
      ;;
  esac
}

# Parameter handling
case "$1" in
  "")
    show_help
    ;;
  "--help")
    show_help
    ;;
  "--create")
    create_cluster
    ;;
  "--delete")
    delete_resources
    ;;
  "--addons")
    if [ -z "$2" ]; then
      echo "Installing all addons..."
      install_addon minio
      install_addon metallb
      install_addon metrics-server
      exit 0
    else
      echo "Installing selected addon: $2"
      install_addon "$2"
      exit 0
    fi
    ;;
  *)
    echo "Error: Unknown parameter '$1'"
    show_help
    ;;
esac
