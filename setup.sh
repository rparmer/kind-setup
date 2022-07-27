#!/bin/bash -e

export KIND_CLUSTER_NAME="${@}"

if [[ -z "$KIND_CLUSTER_NAME" ]]; then
	echo "Please provide the kind cluster name"
	exit 1
fi

export GITHUB_REPO="${GITHUB_REPO:-$KIND_CLUSTER_NAME}"
export INSTALL_INGRESS="${INSTALL_INGRESS:-1}"
export INSTALL_FLUX="${INSTALL_FLUX:-1}"
export INSTALL_CAPI="${INSTALL_CAPI:-0}"
export INSTALL_METALLB="${INSTALL_METALLB:-1}"
export METALLB_ADDRESS_RANGE="${METALLB_ADDRESS_RANGE:-172.18.255.0/24}"

kind delete cluster --name "$KIND_CLUSTER_NAME"

if [[ "$INSTALL_INGRESS" == "1" ]]; then
	kind create cluster --name "$KIND_CLUSTER_NAME" --config kind-config-ingress.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
else
	kind create cluster --name "$KIND_CLUSTER_NAME" --config kind-config.yaml
fi

if [[ "$INSTALL_FLUX" == "1" ]]; then
	flux bootstrap github \
		--owner="$GITHUB_USER" \
		--repository="$GITHUB_REPO" \
		--branch=main \
		--path=./clusters/kind \
		--components-extra=image-reflector-controller,image-automation-controller \
		--personal
fi

if [[ "$INSTALL_CAPI" == "1" ]]; then
	EXP_CLUSTER_RESOURCE_SET=true clusterctl init \
		--infrastructure docker
fi

if [[ "$INSTALL_METALLB" == "1" ]]; then
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/main/config/manifests/metallb-native.yaml
	envsubst <<-EOF | kubectl apply -f -
	apiVersion: v1
	kind: ConfigMap
	metadata:
	  name: config
	  namespace: metallb-system
	data:
	  config: |
	    address-pools:
	    - name: default
	      protocol: layer2
	      addresses:
	      - $METALLB_ADDRESS_RANGE
	EOF
fi
