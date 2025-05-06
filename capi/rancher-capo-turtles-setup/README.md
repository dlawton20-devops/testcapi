# Rancher CAPO Turtles Setup

This project provides scripts and manifests to:
- Connect to an admin Rancher cluster
- Use Cluster API (CAPI) and Cluster API Provider OpenStack (CAPO) to create a downstream Kubernetes cluster
- Install the Turtles workload/operator on the downstream cluster

## Prerequisites

- Access to an admin Rancher cluster (API URL, token)
- OpenStack credentials with permissions to create resources
- `kubectl`, `clusterctl`, and `rancher` CLI installed
- jq, curl, and yq installed

## Setup

### 1. Configure Credentials

- Edit `config/rancher-api-credentials.env` with your Rancher API URL and token.
- Edit `config/openstack-clouds.yaml` with your OpenStack cloud config.

### 2. Login to Rancher

```sh
./scripts/01-login-admin-rancher.sh
```

### 3. Install CAPO on Management Cluster

```sh
./scripts/03-install-capo.sh
```

### 4. Create Downstream Cluster via CAPO

- Edit `manifests/capo-cluster-template.yaml` as needed.
- Apply the manifest:

```sh
kubectl apply -f manifests/capo-cluster-template.yaml
```

Or use the script:

```sh
./scripts/04-create-capo-cluster.sh
```

### 5. Install Turtles on Downstream Cluster

- Update kubeconfig to point to the new downstream cluster.
- Install Turtles:

```sh
./scripts/05-install-turtles.sh
```

---

# Full Manual Installation Instructions

This section provides a step-by-step guide to manually set up a downstream Kubernetes cluster on OpenStack using Rancher, Cluster API, and CAPO, and then install the Turtles workload.

---

## 1. Prerequisites

- **Tools installed:**
  - `kubectl`
  - `clusterctl`
  - `rancher` CLI
  - `jq`, `curl`, `yq` (for scripting convenience)
- **Access to:**
  - A running Rancher management cluster (admin cluster)
  - OpenStack credentials with permissions to create resources
- **Configuration files:**
  - `config/rancher-api-credentials.env` (Rancher URL and token)
  - `config/openstack-clouds.yaml` (OpenStack cloud config)

---

## 2. Authenticate with Rancher

1. **Export your Rancher credentials:**

   Edit `config/rancher-api-credentials.env`:
   ```env
   RANCHER_URL=https://your-rancher.example.com
   RANCHER_TOKEN=token-xxxx:yyyyyyyyyyyyyyyyyyyyyyyyyyyy
   ```

2. **Login to Rancher:**
   ```sh
   rancher login "$RANCHER_URL" --token "$RANCHER_TOKEN"
   ```

---

## 3. Prepare OpenStack Credentials

1. **Edit your OpenStack clouds.yaml:**

   Edit `config/openstack-clouds.yaml`:
   ```yaml
   clouds:
     default:
       auth:
         auth_url: https://openstack.example.com:5000/v3
         username: your-username
         password: your-password
         project_name: your-project
         user_domain_name: Default
         project_domain_name: Default
       region_name: RegionOne
       interface: public
       identity_api_version: 3
   ```

2. **Export environment variables:**
   ```sh
   export OS_CLOUD=default
   export CLOUDS_YAML=$(pwd)/config/openstack-clouds.yaml
   ```

---

## 4. Install Cluster API Provider OpenStack (CAPO) in the Management Cluster

1. **Set your kubeconfig to the management cluster:**
   ```sh
   export KUBECONFIG=~/.kube/config  # or your Rancher management cluster kubeconfig
   ```

2. **Initialize Cluster API with the OpenStack provider:**
   ```sh
   clusterctl init --infrastructure openstack
   ```

   This installs the necessary CRDs and controllers for CAPI and CAPO.

---

## 5. Register the OpenStack Provider in Rancher (Optional but recommended)

1. **In the Rancher UI:**
   - Go to **Cluster Management > Drivers**.
   - Ensure the OpenStack (Cluster API) provider is enabled.
   - If not, add/enable it so Rancher can manage OpenStack clusters via CAPI.

---

## 6. Create the Downstream Cluster

1. **Edit the cluster manifest:**

   Edit `manifests/capo-cluster-template.yaml` to match your OpenStack environment and desired cluster configuration.

2. **Apply the manifest:**
   ```sh
   kubectl apply -f manifests/capo-cluster-template.yaml
   ```

3. **Monitor cluster creation:**
   ```sh
   kubectl get clusters
   kubectl get machines
   kubectl get kubeadmcontrolplanes
   kubectl get openstackmachines
   ```

   Wait until the cluster and its control plane are ready.

---

## 7. Retrieve the Downstream Cluster Kubeconfig

1. **Get the kubeconfig secret:**
   ```sh
   kubectl get secret <cluster-name>-kubeconfig -o jsonpath='{.data.value}' | base64 --decode > turtles-downstream.kubeconfig
   ```

   Replace `<cluster-name>` with the name you set in your cluster manifest (e.g., `turtles-downstream`).

2. **Set your kubeconfig to the downstream cluster:**
   ```sh
   export KUBECONFIG=$PWD/turtles-downstream.kubeconfig
   ```

---

## 8. Install the Turtles Workload

1. **Edit the Turtles manifest:**

   Edit `manifests/turtles-install.yaml` as needed for your workload.

2. **Apply the manifest:**
   ```sh
   kubectl apply -f manifests/turtles-install.yaml
   ```

---

## 9. Verify the Installation

1. **Check the Turtles deployment:**
   ```sh
   kubectl get pods -n turtles
   kubectl get deployments -n turtles
   ```

2. **Check cluster health:**
   ```sh
   kubectl get nodes
   kubectl get pods -A
   ```

---

## 10. Troubleshooting

- **Check logs for failed pods or controllers:**
  ```sh
  kubectl describe pod <pod-name> -n <namespace>
  kubectl logs <pod-name> -n <namespace>
  ```
- **Check CAPI/CAPO controllers:**
  ```sh
  kubectl get pods -n capi-system
  kubectl get pods -n capo-system
  ```
- **Ensure your OpenStack and Rancher credentials are correct.**

---

## Summary Table

| Step                        | Command/Action                                      |
|-----------------------------|-----------------------------------------------------|
| Rancher login               | `rancher login ...`                                 |
| Export OpenStack vars       | `export OS_CLOUD=default` ...                       |
| Install CAPO                | `clusterctl init --infrastructure openstack`        |
| Register provider in Rancher| Rancher UI (optional)                               |
| Apply cluster manifest      | `kubectl apply -f .../capo-cluster-template.yaml`   |
| Get kubeconfig              | `kubectl get secret ...-kubeconfig ...`             |
| Install Turtles             | `kubectl apply -f .../turtles-install.yaml`         |

---

**You can run each step manually, or use the provided scripts for automation.** 