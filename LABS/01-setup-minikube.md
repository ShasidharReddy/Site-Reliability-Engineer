Lab 01 — Setup local Kubernetes (minikube)

Prereqs: kubectl, minikube or kind, docker, helm

Using minikube:
1. Install minikube per docs: https://minikube.sigs.k8s.io/docs/start/
2. Start cluster with sufficient resources:
   minikube start --cpus=4 --memory=8192 --driver=docker
3. Enable metrics-server (used by kubectl top):
   minikube addons enable metrics-server
4. Validate cluster:
   kubectl get nodes
   kubectl top nodes

Using kind (alternative):
- Create cluster: kind create cluster --name sre-lab
- Configure kubectl: export KUBECONFIG="$(kind get kubeconfig-path --name=sre-lab)"
