# Create separate VPC and subnet for GKE
gcloud compute networks create drone

# Create an IP address for ingress
STATIC_IP=gcloud compute addresses create drone-ingress --region us-west1 --format="value(address)"

# Build the cluster
# auto-repair + auto-upgrade
# stackdriver kubernetes + cloud-monitoring
# auto-scaling 1 to 5 nodes
# Stackdriver-Kubernetes requires `gcloud beta`
gcloud beta container clusters create drone-gke \
 --zone us-west1-a --enable-stackdriver-kubernetes \
 --enable-cloud-monitoring --enable-autoupgrade \
 --enable-autorepair --cluster-version 1.11.2 --num-nodes 3 \
 --enable-autoscaling --min-nodes 1 --max-nodes 5 \
 --subnetwork drone --network drone

# Fetch kubeconfig for cluster
# This can fail if, for example, there is an difference between expected and actual encoding in existing kubeconfig. Delete existing kubeconfig and retry.
gcloud container clusters get-credentials drone-gke

# END GCP OPERATIONS
# START KUBERNETES OPERATIONS

kubectl apply -f helm-rbac.yml
helm init --service-account tiller # wait after this until tiller is ready
sleep 10s

# Cert-manager config. Describes a cluster issuer with CloudFlare DNS01 challenge to use automatically to acquire certificates.
helm install --name cert-manager stable/cert-manager --namespace kube-system -f cert-manager.yml
kubectl apply -f issuer.yml

# Nginx ingress, using earlier defined static IP.
# If you leave out the static IP, you can promote it to static later in GCE.
helm install --name nginx stable/nginx-ingress --set controller.service.loadBalancerIP=${STATIC_IP}

# Remember to fill in your values! If you forget, you can run `helm upgrade --install drone stable/drone -f drone.yml`
# If things get really hairy, go for `helm del --purge drone` and then re-run the command below.
helm install --name drone stable/drone -f drone.yml