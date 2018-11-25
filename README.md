# Drone CI with TLS on Google Kubernetes Engine

## Prerequisites:
- GCP account
- gcloud downloaded and initialized
- Cloudflare account
- You must possess a domain or subdomain you wish to use. I used Namecheap. I hear good things about Cloudflare and Google.
- Github account
- Github OAuth application ID and secret
- Helm installed

The focus of this tutorial is on working with GCP and Kubernetes. The above prerequisites are out of scope. If the prerequisites become a blocking issue for completing the tutorial, open an issue and I can add directions.

These steps will work with any DNS provider with support for cert-manager, and certainly using any registrar. If you change DNS providers you should follow the cert-manager reference documentation to modify `issuer.yml` for your provider. This mostly pertains to authentication.

## Steps
### Cloudflare
1. Register your domain and point the DNS servers to Cloudflare.
2. Get your Cloudflare API Key
   - Log in to the Cloudflare dashboard.
   - Click the icon at the very top right of the screen.
   - Click `My Profile`
   - Scroll to the bottom.
   - Next to `Global API Key`, click `View`
   - Copy this value down for later.

### GCP 
1. Create a VPC to contain the project.
   ```
   gcloud compute networks create drone
   ```
2. Reserve a static IP address for use with the ingress controller.
   ```
   STATIC_IP=gcloud compute addresses create drone-ingress --region us-west1 --format="value(address)"
   ```
3. Create the cluster. I included autoupgrade, autorepair, monitoring, stackdriver logging, and autoscaling from 1 to 5 nodes.
   ```
   gcloud beta container clusters create drone-gke \
    --zone us-west1-a --enable-stackdriver-kubernetes \
    --enable-cloud-monitoring --enable-autoupgrade \
    --enable-autorepair --cluster-version 1.11.2 --num-nodes 3 \
    --enable-autoscaling --min-nodes 1 --max-nodes 5 \
    --subnetwork drone --network drone
   ```

### Kubernetes 
1. Create a service account for `helm/tiller` in the cluster.
   ```
   kubectl create serviceaccount tiller -n kube-system
   ```
2. Bind that service account to a role with permissions appropriate for your `helm` deployment. In this scenario, I'm using `cluster-admin`. You may choose to restrict this.
   ```
   kubectl create clusterrolebinding tiller-admin --clusterrole cluster-admin --serviceaccount tiller
   ```
3. Initialize `helm` with the service account created previously. Wait a few seconds after until a `tiller` pod is ready on the cluster.
   ```
   helm init --service-account tiller
   sleep 10s
   ```
4. Create a Kubernetes secret to hold the Cloudflare API key for the ClusterIssuer
   ```
   kubectl create secret generic cf-key -n kube-system --from-literal=cloudflare-api-key=${YOUR_KEY}
   ```
### cert-manager
#### Install
Install `cert-manager` in the cluster. Here's a manifest, following the naming schemes in this tutorial.
```
cat > cert-manager.yml <<EOF
ingressShim:
defaultIssuerName: letsencrypt-prod
defaultIssuerKind: ClusterIssuer
defaultACMEChallengeType: dns01
defaultACMEDNS01ChallengeProvider: cf-dns
EOF

helm install --name cert-manager stable/cert-manager --namespace kube-system -f cert-manager.yml
```
#### ClusterIssuer
In the previous step we told cert-manager the defaults to use for acquiring certificates automatically. However, the issuer and challenge provider we specified don't exist yet.  Let's create them.

    In the remainder of the tutorial we use the `letsencrypt-prod` ClusterIssuer. The Let's Encrypt production endpoint imposes rate limiting on requests which may cause issues for testing scenarios. If you would like to test the configuration first, you may use the staging endpoint.

Both manifests are below for your convenience. To follow the tutorial, customize and apply the `letsencrypt-prod` manifest.

#### Using the staging endpoint
If you would like to use the staging endpoint, you should update the `defaultIssuerName` from when we deployed `cert-manager`:
```
cat > cert-manager.yml <<EOF
ingressShim:
   defaultIssuerName: letsencrypt-staging
   defaultIssuerKind: ClusterIssuer
   defaultACMEChallengeType: dns01
   defaultACMEDNS01ChallengeProvider: cf-dns
EOF
```
```
helm upgrade --install cert-manager stable/cert-manager -f cert-manager.yml
```
Here is the manifest to create the `letsencrypt-staging` ClusterIssuer:

```
cat > issuer.yml <<EOF
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
   name: letsencrypt-staging
spec:
   acme:
     server: https://acme-staging-v02.api.letsencrypt.org/directory
     email: ${YOUR_EMAIL}
     privateKeySecretRef:
       name: letsencrypt-staging
     dns01:
       providers:
         - name: cf-dns
           cloudflare:
             email: ${YOUR_EMAIL}
             apiKeySecretRef:
               name: cf-key
               key: cloudflare-api-key
EOF
```

 #### Using the production endpoint
 Here is the manifest to create the `letsencrypt-prod` ClusterIssuer:
 ```
 cat > issuer.yml <<EOF
 apiVersion: certmanager.k8s.io/v1alpha1
 kind: ClusterIssuer
 metadata:
   name: letsencrypt-prod
 spec:
   acme:
     server: https://acme-v02.api.letsencrypt.org/directory
     email: ${YOUR_EMAIL}
     privateKeySecretRef:
       name: letsencrypt-prod
     dns01:
       providers:
         - name: cf-dns
           cloudflare:
             email: ${YOUR_EMAIL}
             apiKeySecretRef:
               name: cf-key
               key: cloudflare-api-key
 EOF
 ```
 Finally:
 ```
 kubectl apply -f issuer.yml
 ```
### Ingress
Install the `nginx-ingress` Helm chart to manage ingress, using the static IP we previously acquired.
```
helm install --name nginx stable/nginx-ingress --set controller.service.loadBalancerIP=${STATIC_IP}
```

### Drone
Install `drone` via `helm`. Customize the following values to deploy using your personal GitHub account as an admin.
```
cat > drone.yml <<EOF
ingress:
   enabled: true

   ## Drone Ingress annotations for cert-manager and nginx
   annotations:
     kubernetes.io/ingress.class: nginx
     kubernetes.io/tls-acme: "true"

   ## Drone hostnames must be provided if Ingress is enabled
   hosts:
     - ${YOUR_DOMAIN_NAME}

   tls:
     - secretName: drone-tls
       hosts:
         - ${YOUR_DOMAIN_NAME}

server:
   env:
     DRONE_HOST: https://${YOUR_DOMAIN_NAME}
     DRONE_PROVIDER: github
     DRONE_OPEN: false
     DRONE_GITHUB: true
     DRONE_ADMIN: ${YOUR_GITHUB_USERNAME}
     DRONE_GITHUB_CLIENT: ${YOUR_CLIENT_ID}
     DRONE_GITHUB_SECRET: ${YOUR_CLIENT_SECRET}
EOF
```
Deploy.
```
helm install --name drone stable/drone -f drone.yml
```

If you didn't get any errors after running these steps, in less than 2 minutes you should be able to navigate to `https://${YOUR_DOMAIN}` and find yourself greeted by a GitHub login followed by the Drone homepage.
