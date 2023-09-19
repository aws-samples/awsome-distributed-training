
# Amazon EKS distributed training architecture
This project module uses [eksctl](eksctl.io) and a cluster manifest to create your specified Amazon EKS cluster.

## Prerequisites

To deploy the architectures you must install the dependencies below. You are advised to go through the fist two steps of the [Getting started with Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html) guide from the AWS Documentation.

1. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) is the AWS command line interface.
2. [eksctl](https://eksctl.io) command line tool to manage EKS clusters.
3. [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) command line for Kubernetes.

## Cluster configuration

The following example cluster configurations are provided:

* [eks-g4dn-vpc.yaml](./eks-g4dn-vpc.yaml) - a cluster using an existing VPC with a nodegroup of two g4dn.metal instances
* [eks-g4dn.yaml](./eks-g4dn.yaml) - a cluster with a nodegroup of two g4dn.metal instances, created in a new VPC
* [eks-p4de-odcr-vpc.yaml](./eks-p4de-odcr-vpc.yaml) - a cluster using an existing VPC with a nodegroup of two p4de.24xlarge instances from an existing on-demand capacity reservation (ODCR)
* [eks-p4de-odcr.yaml](./eks-p4de-odcr.yaml) - a cluster with two p4de.24xlarge instances from an existing ODCR, that will be created in a new VPC

To configure your desired cluster, edit the cluster manifest file that most closely matches your desired configuration or copy the file and customize it, following the [cluster manifest schema](https://eksctl.io/usage/schema/)

## Cluster creation

Let's assume that your desired cluster configuration is stored in file `cluster.yaml`. Then to create the cluster, execute the following command:

```
$ eksctl create cluster -f ./cluster.yaml
```

Cluster creation may take between 15 and 30 minutes. Upon successful creation your local `~/.kube/config` file gets updated with connection information to your cluster. Execute the following command line in order to verify that the cluster is accessible:

```
$ kubectl get nodes
```

You should see a list of three nodes. One would be a system node instance of type c5.2xlarge, and the others will belong to the nodegroup of instances with your desired instanct type.w

## Delete cluster

When it is time to decommission your cluster, execute the following command:

```
$ kubectl delete cluster -f ./cluster.yaml
```

## References
* [AWS CLI](https://aws.amazon.com/cli)
* [Amazon EKS](https://aws.amazon.com/eks)
* [eksctl](https://eksctl.io)
* [kubectl](https://kubernetes.io/docs/reference/kubectl)

