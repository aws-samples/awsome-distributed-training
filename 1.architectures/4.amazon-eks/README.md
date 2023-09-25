
# Amazon EKS distributed training architecture

This project provides several reference architectures to run distributed training on Amazon EKS for different use cases using `p4d.24xlarge` instances (you can replace them by `p5` or `trn1`. These examples use [eksctl](eksctl.io) and a cluster manifest to create your specified Amazon EKS cluster.

## Prerequisites

To deploy the architectures you must install the dependencies below. You are advised to go through the fist two steps of the [Getting started with Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html) guide from the AWS Documentation.

1. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) is the AWS command line interface.
2. [eksctl](https://eksctl.io) command line tool to manage EKS clusters.
3. [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) command line for Kubernetes.

## Architecture

The following digram shows a common architecture that can be used for distributed model training on EKS.

<img align="center" src="../../0.docs/eks-model-training-single-az.png" width="60%" />

The EKS cluster has two nodegroups. A `system` nodegroup is used to run pods like kube-dns, kubeflow training operator, etc. which provide internal cluster-scope services and can run on CPU. A worker nodegroup built with an accelerated instance type is used to run the distributed training workload. 

## Cluster configuration

The cluster configuration is specified via a yaml manifest file. If a cluster version is not specified in the manifest, then the default EKS API version will be used. For our examples we set the version to 1.27. This setting may be adjusted before creating clusters as needed.
The following example cluster configurations for distributed training are provided:

* [**`eks-g4dn-vpc.yaml`**](./eks-g4dn-vpc.yaml): A cluster using an existing VPC with a nodegroup of 2 * `g4dn.metal` instances. This instance type supports Elastic Fabric Adapter (EFA), usually does not require a capacity reservation, and is a good starting point when developing distributed training architectures. To use this manifest, edit the vpc id and subnets, and specify the desired private subnet for the nodes.
* [**`eks-g4dn.yaml`**](./eks-g4dn.yaml): Cluster with a nodegroup of 2 * `g4dn.metal` instances, created in a new VPC. This example shows that when a VPC is not specified, one is created for the cluster. The manifest can work without any modifications, however if you wish to change the cluster name, API version, region, availability zones, etc. you can modify the file before using it to create the cluster.
* [**`eks-p4de-odcr-vpc.yaml`**](./eks-p4de-odcr-vpc.yaml): It is a cluster using an existing VPC with a nodegroup of 2 * `p4de.24xlarge` instances from an existing on-demand capacity reservation (ODCR). This is the most common configuration for distributed training workloads.Edit the file to specify vpc id, subnets, and capacityReservationID. Please note that the subnet of the nodeGroup should match the one of the capacity reservation.
* [**`eks-p4de-odcr.yaml`**](./eks-p4de-odcr.yaml): A cluster with 2 * `p4de.24xlarge` instances from an existing ODCR, that will be created in a new VPC. This cluster configuration is useful for distributed training when no VPC is already available. Note that you would have to match the AZ of your ODCR in the nodegroup section of the manifest.


You will need to replace



## Cluster creation


### Edit the cluster configuration

To configure your desired cluster, edit the cluster manifest file that most closely matches your desired configuration or copy the file and customize it, following the [cluster manifest schema](https://eksctl.io/usage/schema/). Any of the values in the manifests can be changed and more node groups can be added to the same cluster. The minimal set of values to specify for each file are described above.

### Create a cluster

1. Let's assume that your desired cluster configuration is stored in file `cluster.yaml`. Then to create the cluster, execute the following command:
    ```bash
    eksctl create cluster -f ./cluster.yaml
    ```
    Example output:
    ```console
    YYYY-MM-DD HH:mm:SS [ℹ] eksctl version x.yyy.z
    YYYY-MM-DD HH:mm:SS [ℹ] using region <region_name>
    ...
    YYYY-MM-DD HH:mm:SS [✔] EKS cluster "<cluster_name>" in "<region_name>" region is ready
    ```
    Cluster creation may take between 15 and 30 minutes. Upon successful creation your local `~/.kube/config` file gets updated with connection information to your cluster.
2. Execute the following command line in order to verify that the cluster is accessible:
    ```bash
    kubectl get nodes
    ```

You should see a list of three nodes. One would be a system node instance of type c5.2xlarge, and the others will belong to the nodegroup of instances with your desired instance type for distributed training.

## Cleanup

When it is time to decommission your cluster, execute the following command:

```bash
kubectl delete cluster -f ./cluster.yaml
```

Example output:
```console
YYYY-MM-DD HH:mm:SS [ℹ] deleting EKS cluster "<cluster_name>"
...
YYYY-MM-DD HH:mm:SS [ℹ] waiting for CloudFormation stack "<stack_name>"
```

## References

For further information regarding EKS cluster infrastructure see the [aws-do-eks](https://github.com/aws-samples/aws-do-eks) project. More cluster configurations are available [here](https://github.com/aws-samples/aws-do-eks/tree/main/wd/conf/eksctl/yaml). 

Related resources for further reading can be found at the links below:
* [AWS CLI](https://aws.amazon.com/cli)
* [Amazon EKS](https://aws.amazon.com/eks)
* [eksctl](https://eksctl.io)
* [kubectl](https://kubernetes.io/docs/reference/kubectl)
* [do-framework](https://bit.ly/do-framework)

