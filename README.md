# Drone CI with TLS on Google Kubernetes Engine

## Prerequisites: 
- GCP account
- gcloud downloaded and initialized
- Cloudflare account
- You must possess a domain or subdomain you wish to use. I used Namecheap. I hear good things about Cloudflare and Google.
- Github account
- Github OAuth application ID and secret
- Helm installed

You can do this with any DNS provider with support for cert-manager, and certainly using any registrar.

### Steps
1. Register your domain and point the DNS servers to Cloudflare (out of scope for this tutorial. I'll add it if anyone needs it).
2. Get your Cloudflare API Key
   - Log in to the Cloudflare dashboard.
   - Click the icon at the very top right of the screen. 
   - Click `My Profile`
   - Scroll to the bottom.
   - Next to `Global API Key`, click `View`
   - Copy this value down for later.
3. Open up `create-cluster.sh`. Customize `${YOUR_KEY}` with your Cloudflare API key.
4. Open up `issuer.yml`. Replace `${YOUR_EMAIL}` with your email. If you'd like to test out this tutorial using the staging provider for Let's Encrypt, change the `metadata.name`, `spec.acme.server`, `spec.acme.privateKeySecretRef.name` fields to be unique for staging/prod.
5. Open up `drone.yml`. Customize `${YOUR_DOMAIN_NAME}`, `${YOUR_CLIENT_ID}`, `${YOUR_CLIENT_SECRET}` to appropriate values.
6. Execute `bash create-cluster.sh`

If all goes well, several things should happen:
1. GCP will create a new VPC, `drone`, for the project,
2. GCP will reserve a static IP, `drone-ip`, for ingress into the cluster.
3. GKE will build a cluster with autoscaling from 1 to 5 nodes (n1-standard-1 by default), autoupgrade, autorepair, stackdriver, and monitoring.
4. `gcloud` will download the credentials from GKE.
5. `kubectl` applies rbac necessary to use `helm`: a `serviceaccount` named `tiller` and a `clusterrolebinding` for helm to `cluster-admin` (you may choose to restrict helm's capabilities in your cluster).
6. `helm` initializes `tiller` on the cluster using the previously mentioned account; we sleep until `tiller` is ready.
7. `kubectl` creates a secret on our cluster representing our Cloudflare API key. `cert-manager` needs this to use ACME to acquire certs.
8. `helm` installs `cert-manager` into the `kube-system` namespace. We apply some values to allow for automatic certificate creation using our Cloudflare account, the DNS01 challenge type, and a yet-to-be-created `ClusterIssuer`.
9. `kubectl` creates the default `ClusterIssuer` we previously specified. This `ClusterIssuer` makes requests on our behalf for certificates, and makes DNS modifications with Cloudflare to prove ownership of the domain.
10. `helm` installs `nginx-ingress`, set to listen on the static IP we previously reserved.
11. `helm` installs drone using the customized values in `drone.yml`

If you didn't get any errors after running the script, in less than 2 minutes you should be able to navigate to `https://${YOUR_DOMAIN}` and find yourself greeted by a GitHub login and then the Drone homepage.
