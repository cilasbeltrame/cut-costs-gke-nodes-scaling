#!/usr/bin/env bash
set -e

check_inputs() {
  if [[ $# -ne 4 ]]; then
    echo "Please check the necessary inputs to run the nodes scaling."
    exit 0
  fi
}

get_gcp_project() {
  if [[ "$PRODUCT_ID" == "some-id" && "$ENVIRONMENT" == "dev" ]]; then
    GCP_PROJECT="my-project-dev"
  elif [[ "$PRODUCT_ID" == "some-id" && "$ENVIRONMENT" == "stg" ]]; then
    GCP_PROJECT="my-project-stage"
  elif [[ "$PRODUCT_ID" == "some-id" && "$ENVIRONMENT" == "prod" ]]; then
    GCP_PROJECT="some-project-prod"
  elif [[ "$PRODUCT_ID" == "another-project" ]]; then
    GCP_PROJECT="some-project-qa"
  else
    GCP_PROJECT="some-project-$PRODUCT_ID"
  fi

  export CLOUDSDK_CORE_PROJECT="$GCP_PROJECT"
}

set_k8s_nodes_scaling_stage() {
  K8S_NODES_SCALING_STAGE="${K8S_NODES_SCALING_STAGE:=plan}"
  export K8S_NODES_SCALING_STAGE
}

plan_scale_nodes() {
  echo "Plan:"
  echo
  scale_nodes "plan"
}

apply_scale_nodes() {
  echo "Apply:"
  echo
  scale_nodes "apply"
}

scale_nodes() {
  local stage=$1

  if [[ "$CLUSTER_TYPE" == "all" ]]; then
    CLUSTERS=$(gcloud container clusters list --format='value(NAME)' | grep -o "\S*$ENVIRONMENT$")
  elif [[ "$CLUSTER_TYPE" == "clusterType1" ]]; then
    CLUSTERS=$(gcloud container clusters list --format='value(NAME)' | grep -o "\S*$ENVIRONMENT$" | grep -o '\S*clusterType1\S*' )
  elif [[ "$CLUSTER_TYPE" == "clusterType2" ]]; then
    CLUSTERS=$(gcloud container clusters list --format='value(NAME)' | grep -o "\S*$ENVIRONMENT$" | grep -o '\S*clusterType2\S*')
  else
    echo "Please check your inputs."
    exit 1
  fi

  echo -e "The clusters that will be scaled for $ENVIRONMENT.$PRODUCT_ID:\n$CLUSTERS"
  echo "-----------------"

  set +e

  echo "More details:"
  echo

  for cluster in $CLUSTERS; do
    REGION="$(gcloud container clusters list --format="value(location)" --filter="name=$cluster")"

    if [[ $K8S_NODES_SCALING_STAGE == "apply" && $NUMBER_NODES -eq 0 ]]; then
      gcloud container clusters get-credentials "$cluster" --region "$REGION"
      CONTEXT_NAME="gke_${GCP_PROJECT}_${REGION}_${cluster}"
      kubectl config set-context "$CONTEXT_NAME"
      echo "Checking for PDBs..."
      PDB=$(kubectl get pdb -A --no-headers)
      while IFS= read -r pdb; do
        PDB_NAME=$(echo "$pdb" | awk '{print $2}')
        PDB_NAMESPACE=$(echo "$pdb" | awk '{print $1}')
        kubectl delete pdb "$PDB_NAME" -n "$PDB_NAMESPACE"
      done <<<"$PDB"
    fi

    NODE_POOLS=$(gcloud container node-pools list --cluster="$cluster" --region "$REGION" --format='value(NAME)')

    for node_pool in $NODE_POOLS; do
      echo "Node pool $node_pool for cluster $cluster will have $NUMBER_NODES node(s) per region..."
      echo "-----------------"
      NODE_POOLS_SERVICES=$(echo "$node_pool" | grep -o "\S*services\S*")
      if [[ "$stage" == "apply" && -n $NODE_POOLS_SERVICES ]]; then
        for my_custom_node_pool in $NODE_POOLS_SERVICES; do
          if [[ "$NUMBER_NODES" -eq 0 ]]; then
            gcloud container clusters update "$cluster" --node-pool "$my_custom_node_pool" --no-enable-autoscaling --region "$REGION"
            
          else
            gcloud container clusters update "$cluster" --enable-autoscaling --min-nodes=1 --max-nodes=10 --node-pool="$my_custom_node_pool" --region "$REGION"
          fi
          gcloud container clusters resize "$cluster" --region "$REGION" --node-pool "$node_pool" --num-nodes="$NUMBER_NODES" --quiet
          sleep 30
          while true; do
            nodes_count=$(kubectl get nodes --no-headers | grep -i ready | grep ser | wc -l | tr -d " ")
            if [ "$nodes_count" -eq 0 ]; then
              echo "Kubernetes nodes for node pool $my_custom_node_pool are 0. Exiting loop."
              break
            fi
            echo "Waiting from Kubernetes nodes for node pool $my_custom_node_pool to be 0. Current node count: $nodes_count"
            sleep 10
            gcloud container clusters resize "$cluster" --region "$REGION" --node-pool "$node_pool" --num-nodes="$NUMBER_NODES" --quiet
          done
        done
      elif [[ "$stage" == "apply" ]]; then
        gcloud container clusters resize "$cluster" --region "$REGION" --node-pool "$node_pool" --num-nodes="$NUMBER_NODES" --quiet
        echo
      fi
    done
  done
}

main() {
  check_inputs "$@"
  PRODUCT_ID="$1"
  ENVIRONMENT="$2"
  CLUSTER_TYPE="$3"
  NUMBER_NODES="$4"
  get_gcp_project
  set_k8s_nodes_scaling_stage

  if [[ $K8S_NODES_SCALING_STAGE == "apply" ]]; then
    apply_scale_nodes
  else
    plan_scale_nodes
  fi
}

main "$@"
