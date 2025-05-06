apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: default
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: ${CLUSTER_NAME}-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: OpenStackCluster
    name: ${CLUSTER_NAME}

---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: OpenStackCluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: default
spec:
  cloudName: ${OPENSTACK_CLOUD}
  network:
    id: ${OPENSTACK_NETWORK_ID}

---
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

---
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
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
  kubeadmConfigSpec:
    clusterConfiguration:
      apiServer:
        extraArgs:
          cloud-provider: external
      controllerManager:
        extraArgs:
          cloud-provider: external
    initConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: external
    joinConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: external

---
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

---
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