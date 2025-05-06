# Cluster definition with Rancher Turtles auto-import label for downstream clusters
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: default
  labels:
    cluster-api.cattle.io/rancher-auto-import: "true"  # Label to auto-import the cluster into Rancher as a downstream cluster
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
  controlPlaneRef:
    apiVersion: controlplane.rke2.cattle.io/v1
    kind: RKE2ControlPlane
    name: ${CLUSTER_NAME}-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: OpenStackCluster
    name: ${CLUSTER_NAME}
---
# OpenStackCluster resource for provisioning infrastructure
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: OpenStackCluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: default
spec:
  cloudName: ${OPENSTACK_CLOUD}
  dnsNameservers: ["8.8.8.8"]
  externalNetworkId: ${OPENSTACK_EXTERNAL_NETWORK_ID}
  network:
    id: ${OPENSTACK_NETWORK_ID}
  subnets:
    - uuid: ${OPENSTACK_SUBNET_ID}
  managedSecurityGroups: true
---
# RKE2ControlPlane for the control plane
apiVersion: controlplane.rke2.cattle.io/v1
kind: RKE2ControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
  namespace: default
spec:
  replicas: 1
  version: ${K8S_VERSION}
  machineTemplate:
    infrastructureRef:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: OpenStackMachineTemplate
      name: ${CLUSTER_NAME}-control-plane
  etcd:
    external:
      endpoints:
        - ${ETCD_ENDPOINTS}
      caCertData: ${ETCD_CA_CERT}
      certData: ${ETCD_CERT}
      keyData: ${ETCD_KEY}
---
# OpenStackMachineTemplate for the control plane
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: OpenStackMachineTemplate
metadata:
  name: ${CLUSTER_NAME}-control-plane
  namespace: default
spec:
  template:
    spec:
      flavor: ${CONTROL_PLANE_FLAVOR}
      image: ${IMAGE_NAME}
      sshKeyName: ${SSH_KEY}
      networks:
        - uuid: ${OPENSTACK_NETWORK_ID}
      availabilityZone: ${OPENSTACK_AZ}
---
# OpenStackMachineTemplate for worker nodes
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: OpenStackMachineTemplate
metadata:
  name: ${CLUSTER_NAME}-worker
  namespace: default
spec:
  template:
    spec:
      flavor: ${WORKER_FLAVOR}
      image: ${IMAGE_NAME}
      sshKeyName: ${SSH_KEY}
      networks:
        - uuid: ${OPENSTACK_NETWORK_ID}
      availabilityZone: ${OPENSTACK_AZ}
---
# MachineDeployment for worker nodes
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: ${CLUSTER_NAME}-worker
  namespace: default
spec:
  clusterName: ${CLUSTER_NAME}
  replicas: 1
  selector:
    matchLabels:
      cluster.x-k8s.io/deployment-name: ${CLUSTER_NAME}-worker
  template:
    metadata:
      labels:
        cluster.x-k8s.io/deployment-name: ${CLUSTER_NAME}-worker
    spec:
      version: ${K8S_VERSION}
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: KubeadmConfigTemplate
          name: ${CLUSTER_NAME}-worker
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: OpenStackMachineTemplate
        name: ${CLUSTER_NAME}-worker
---
# KubeadmConfigTemplate for worker nodes
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: ${CLUSTER_NAME}-worker
  namespace: default
spec:
  template:
    spec:
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
            cloud-provider: external
