#!/usr/bin/env bash
set -e
if [[ $# -ne 4 ]]; then
  echo "Please check the necessary inputs to run the nodes scaling."
  exit 0
fi

PRODUCT_ID="$1"
ENVIRONMENT="$2"
CLUSTER_TYPE="$3"
NUMBER_NODES="$4"
K8S_NODES_SCALING_STAGE="${K8S_NODES_SCALING_STAGE:=plan}"
STDOUT_OUTPUT_SEPARATOR="-----------------"

if [[ "$PRODUCT_ID" == "some-id" && "$ENVIRONMENT" == "dev" ]];
then
   GCP_PROJECT="my-project-dev"
elif [[ "$PRODUCT_ID" == "some-id" && "$ENVIRONMENT" == "stg" ]];
then
   GCP_PROJECT="my-project-stage"
elif [[ "$PRODUCT_ID" == "some-id" && "$ENVIRONMENT" == "qa" ]];
then
   GCP_PROJECT="some-other-project-qa"
elif [[ "$PRODUCT_ID" == "sandbox" ]];
then
   GCP_PROJECT="my-custom-sandbox"   
else
  GCP_PROJECT="some-other-project-$PRODUCT_ID"    
fi

export CLOUDSDK_CORE_PROJECT="$GCP_PROJECT"
export K8S_NODES_SCALING_STAGE

if [[ "$CLUSTER_TYPE" == "all" ]]; then
  CLUSTERS=$(gcloud container clusters list --format='value(NAME)' | grep -o "\S*$ENVIRONMENT$")
elif [[ "$CLUSTER_TYPE" == "clustertype1" ]]; then
  CLUSTERS=$(gcloud container clusters list --format='value(NAME)' | grep -o "\S*$ENVIRONMENT$" | grep -o '\S*clustertype1\S*' )
elif [[ "$CLUSTER_TYPE" == "clustertype2" ]]; then
  CLUSTERS=$(gcloud container clusters list --format='value(NAME)' | grep -o "\S*$ENVIRONMENT$" | grep -o '\S*clustertype2\S*'  )
else
  echo "Please check your inputs."
  exit 1
fi

  if [[ $K8S_NODES_SCALING_STAGE == "apply" ]]; then
    echo "Apply:"
    echo
  else
    echo "Plan:"
    echo
  fi
echo -e "The clusters that will be scaled for $ENVIRONMENT.$PRODUCT_ID:\n$CLUSTERS"
echo $STDOUT_OUTPUT_SEPARATOR

set +e

echo "More details:"
echo
for cluster in $CLUSTERS; do
  REGION="$(gcloud container clusters list --format="value(location)" --filter="name=$cluster")"
  NODE_POOLS=$(gcloud container node-pools list --cluster="$cluster" --region "$REGION" --format='value(NAME)')
  for node in $NODE_POOLS; do
    echo "Node pool $node for cluster $cluster will have $NUMBER_NODES node(s) per region..."
    echo $STDOUT_OUTPUT_SEPARATOR
    if [[ "$K8S_NODES_SCALING_STAGE" == "apply" ]]; then
      gcloud container clusters resize "$cluster" --region "$REGION" --node-pool "$node" --num-nodes="$NUMBER_NODES" --quiet
      echo
    fi
  done
done
