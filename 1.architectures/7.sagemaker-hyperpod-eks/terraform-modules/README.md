# Deploy HyperPod Infrastructure using Terraform

The diagram below depicts the Terraform modules that have been bundled into a single project to enable you to deploy a full HyperPod cluster environment all at once. 

<img src="./smhp_tf_modules.png" width="75%"/>

---

## Get the Modules
Clone the AWSome Distributed Training repository and navigate to the terraform-modules directory:
```bash
git clone https://github.com/aws-samples/awsome-distributed-training.git
cd awsome-distributed-training/1.architectures/7.sagemaker-hyperpod-eks/terraform-modules/hyperpod-eks-tf
```

---

## Customize Deployment Configuration
Start by reviewing the default configurations in the `terraform.tfvars` file and make modifications to customize your deployment as needed.

If you wish to reuse any cloud resources rather than creating new ones, set the associated `create_*_module` variable to `false` and provide the id for the corresponding resource as the value of the `existing_*` variable. 

For example, if you want to reuse an existing VPC, set `create_vpc_module ` to `false`, then set `existing_vpc_id` to your VPC ID, like `vpc-1234567890abcdef0`. 

---

### Using a `custom.tfvars` File 
To modify your deployment details without having to open and edit the `terraform.tfvars` file directly, create a `custom.tfvars` file with your parameter overrides. 

For example, the following `custom.tfvars` file would enable the creation of all new resources including a new EKS Cluster and a HyperPod instance group of 5 `ml.p5en.48xlarge` instances in `us-west-2`:

```bash
cat > custom.tfvars << EOL 
kubernetes_version = "1.32"
eks_cluster_name = "my-eks-cluster"
hyperpod_cluster_name = "my-hp-cluster"
resource_name_prefix = "hp-eks-test"
aws_region = "us-west-2"
availability_zone_id  = "usw2-az2"
instance_groups = {
    accelerated-instance-group-1 = {
        instance_type = "ml.p5en.48xlarge",
        instance_count = 5,
        ebs_volume_size_in_gb = 100,
        threads_per_core = 2,
        enable_stress_check = true,
        enable_connectivity_check = true,
        lifecycle_script = "on_create.sh"
    }
}
EOL
```
---

### Using an Existing EKS Cluster with HyperPod

The following `custom.tfvars` file uses an existing EKS Cluster (referenced by name) along with an existing Security Group, VPC, and NAT Gateway (referenced by ID):
```bash
cat > custom.tfvars << EOL 
create_eks_module = false
existing_eks_cluster_name = "my-eks-cluster"
existing_security_group_id = "sg-1234567890abcdef0"
create_vpc_module = false
existing_vpc_id = "vpc-1234567890abcdef0"
existing_nat_gateway_id = "nat-1234567890abcdef0"
hyperpod_cluster_name = "my-hp-cluster"
resource_name_prefix = "hp-eks-test"
aws_region = "us-west-2"
availability_zone_id  = "usw2-az2"
instance_groups = {
    accelerated-instance-group-1 = {
        instance_type = "ml.p5en.48xlarge",
        instance_count = 5,
        ebs_volume_size_in_gb = 100,
        threads_per_core = 2,
        enable_stress_check = true,
        enable_connectivity_check = true,
        lifecycle_script = "on_create.sh"
  }
}
EOL
```
---
### Enabling Optional Addons 
Set the following parameters to `true` in your `custom.tfvars` file to enable optional addons for your HyperPod cluster (e.g. `create_task_governance_module = true`):
| Parameter | Usage |
|-----------|-------|
| `create_task_governance_module`    | Installs the [HyperPod task governance addon](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-eks-operate-console-ui-governance.html) for  job queuing, prioritization, and scheduling on multi-team compute clusters |
| `create_hyperpod_training_operator_module`   | Installs the [HyperPod training operator addon](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-eks-operator.html) for intelligent fault recovery, hang job detection, and process-level management capabilities (required for [Checkpointless](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-eks-checkpointless.html) and [Elastic](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-eks-elastic-training.html) training)|
| `create_hyperpod_inference_operator_module`  | Installs the [HyperPod inference operator addon](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-model-deployment-setup.html) for deployment and management of machine learning inference endpoints |
| `create_observability_module` | Installs the [HyperPod Observability addon](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod-observability-addon-setup.html) to publish key metrics to Amazon Managed Service for Prometheus and displays them in Amazon Managed Grafana dashboards | 

---
### Advanced Observability Metrics Configuration
In addition to enabling the [HyperPod Observability addon](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod-observability-addon-setup.html) by setting `create_observability_module = true`, you can also configure the following metrics that you wish to collect on your cluster: 
| Parameter | Default | Options | Usage |
|-----------|---------|---------|-------|
| `training_metric_level` | `BASIC` | `BASIC, ADVANCED` | Task duration, type, fault data (Advanced: Event-based task performance), [Learn More Here](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod-observability-cluster-metrics.html#hyperpod-observability-training-metrics)
| `task_governance_metric_level` | `DISABLED` | `DISABLED, ADVANCED` | Team-level resource allocation, [Learn More Here](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod-observability-cluster-metrics.html#hyperpod-observability-task-governance-metrics)
| `scaling_metric_level` | `DISABLED` | `DISABLED, ADVANCED` | KEDA auto-scaling metrics, [Learn More Here](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod-observability-cluster-metrics.html#hyperpod-observability-scaling-metrics)
| `cluster_metric_level` | `BASIC` | `BASIC, ADVANCED` | Cluster health, instance count (Advanced: Detailed Kube-state cluster metrics), [Learn More Here](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod-observability-cluster-metrics.html#hyperpod-observability-cluster-health-metrics)
| `node_metric_level` | `BASIC` | `BASIC, ADVANCED` | CPU, disk, OS-level usage (Advanced: Full node exporter suite), [Learn More Here](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod-observability-cluster-metrics.html#hyperpod-observability-instance-metrics)
| `network_metric_level` | `DISABLED` | `DISABLED, ADVANCED` | Elastic Fabric Adapter metrics, [Learn More Here](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod-observability-cluster-metrics.html#hyperpod-observability-network-metrics)
| `accelerated_compute_metric_level` | `BASIC` | `BASIC, ADVANCED` | GPU utilization, temperature (Advanced: All NVIDIA GPU DCGM, Neuron metrics), [Learn More Here](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod-observability-cluster-metrics.html#hyperpod-observability-accelerated-compute-metrics)
| `logging_enabled` | `false` | `true, false` | When enabled, this will automatically create the required log groups in Amazon CloudWatch and start recording all container and pod logs as log streams
---
### FSx for Lustre Module

By default, the FSx for Lustre module installs the Amazon FSx for Lustre Container Storage Interface (CSI) Driver, but does not dynamically provision a new filesystem. For existing filesystems, you can follow [these steps in the AI on SageMaker HyperPod Workshop](https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/getting-started/orchestrated-by-eks/Set%20up%20your%20shared%20file%20system#option-3-bring-your-own-fsx-static-provisioning) for static provisioning. If you wish to create a new filesystem using Terraform, set the `create_new_fsx_filesystem` parameter to `true` in your `custom.tfvars` file, and review the `fsx_storage_capacity` (default 1200 GiB) and `fsx_throughput` (default 250 MBps/TiB) parameters to ensure they are set according to your requirements. 

---
### Creating a Restricted Instance Group (RIG) for Nova Model Customization

As a prerequisite, you will need to identify or create input and output S3 buckets to reference in your deployment (represented as `my-tf-rig-test-input-bucket` and `my-tf-rig-test-output-bucket` in the following examples). 

To create new S3 buckets, you can execute commands like the following example using the AWS CLI: 
```bash
aws s3 mb s3://my-tf-rig-test-input-bucket --region us-east-1 # adjust region as needed

aws s3 mb s3://my-tf-rig-test-output-bucket --region us-east-1 # adjust region as needed
```
S3 bucket names must be globally unique. 

You will also need to have [yq](https://pypi.org/project/yq/) installed so that a bash script that modifies CoreDNS and VPC CNI deployments can execute properly. 

For Nova model customization using Restricted Instance Groups (RIG), you can use the example configuration in [`rig_custom.tfvars`](./hyperpod-eks-tf/rig_custom.tfvars). This file demonstrates how to configure restricted instance groups with the necessary S3 buckets and instance specifications.

If you wish to create a new `rig_custom.tfvars` file, you execute a command like the following example with your specific configuration: 

```bash 
cat > rig_custom.tfvars << EOL 
kubernetes_version = "1.32"
eks_cluster_name = "tf-eks-cluster-rig"
hyperpod_cluster_name = "tf-hp-cluster-rig"
resource_name_prefix = "tf-eks-test-rig"
aws_region = "us-east-1"
availability_zone_id  = "use1-az6"
rig_input_s3_bucket = "my-tf-rig-test-input-bucket"
rig_output_s3_bucket = "my-tf-rig-test-output-bucket"
restricted_instance_groups = {
   rig-1 = {
        instance_type = "ml.p5.48xlarge",
        instance_count = 2, 
        ebs_volume_size_in_gb = 850,
        threads_per_core = 2, 
        enable_stress_check = false,
        enable_connectivity_check = false,
        fsxl_per_unit_storage_throughput = 250,
        fsxl_size_in_gi_b = 4800
   }
}
EOL
```
RIG mode (`local.rig_mode = true` set in [main.tf](./hyperpod-eks-tf/main.tf)) is automatic when `restricted_instance_groups` are defined, enabling Nova model customization with the following changes: 
- **VPC Endpoints**: Lambda and SQS interface endpoints are added for reinforcement fine-tuning (RFT) with integrations for your custom reward service hosted outside of the RIG. These endpoints are enabled in RIG mode by default so that you can easily transition from continuous pre-training (CPT) or supervised fine-tuning (SFT) to RFT without making infrastructure changes, but they can be disabled by setting `rig_rft_lambda_access` and `rig_rft_sqs_access` to false. 
- **IAM Execution Role Permissions**: The execution role associated with the HyperPod nodes is expanded to include read permission to your input S3 bucket and write permissions to your output S3 bucket. Access to SQS and Lambda resources with ARN patterns `arn:aws:lambda:*:*:function:*SageMaker*` and `arn:aws:sqs:*:*:*SageMaker*` are also conditionally added if `rig_rft_lambda_access` and `rig_rft_sqs_access` are true (default). 
- **Helm Charts**: A specific Helm revision is checked out and used for RIG support. After Helm chart instillation, a bash script is used to modify CoreDNS and VPC NCI deployments (be sure to have [yq](https://pypi.org/project/yq/) installed for this). 
- **HyperPod Cluster**: Continuous provisioning mode and Karpenter autoscaling are disabled automatically for RIG compatibility. Deploying a HyperPod cluster with a combination of standard instance groups and RIGs is also not currently supported, so `instance_groups` definitions are ignored when `restricted_instance_groups` are defined.
- **FSx for Lustre**: For RIGs a service managed FSx for Lustre filesystem is created based on the specifications you provide in `fsxl_per_unit_storage_throughput` and `fsxl_size_in_gi_b`. 
    - Valid values for `fsxl_per_unit_storage_throughput` are 125, 250, 500, or 1000 MBps/TiB. 
    - Valid values for `fsxl_size_in_gi_b` start at 1200 GiB and go up in increments of 2400 GiB. 
- **S3 Lifecycle Scripts**: Because RIGs do not leverage lifecycle scripts, the `s3_bucket` and `lifecycle_script` modules are also disabled in RIG mode. 

Please note that the following addons are NOT currently supported on HyperPod with RIGs: 
- HyperPod Task Governance 
- HyperPod Observability
- HyperPod Training Operator
- HyperPod Inference Operator

Do not attempt to install these addons later using the console. 

Once you have your `rig_custom.tfvars` file is created, you can proceed to deployment. 

---

## Deployment 
First, clone the [HyperPod Helm charts GitHub repository](https://github.com/aws/sagemaker-hyperpod-cli/tree/main/helm_chart) to locally stage the dependencies Helm chart.  
```bash
git clone https://github.com/aws/sagemaker-hyperpod-cli.git /tmp/helm-repo
```
Run `terraform init` to initialize the Terraform working directory, install necessary provider plugins, download modules, set up state storage, and configure the backend for managing infrastructure state: 

```bash 
terraform init
```
Run `terraform plan` to generate and display an execution plan that outlines the changes Terraform will make to your infrastructure, allowing you to review and validate the proposed updates before applying them.

```bash 
terraform plan
```
If you created a `custom.tfvars` file, plan using the `-var-file` flag: 
```bash 
terraform plan -var-file=custom.tfvars
```
Or for RIG deployments:
```bash
terraform plan -var-file=rig_custom.tfvars
```
Run `terraform apply` to execute the proposed changes outlined in the Terraform plan, creating, updating, or deleting infrastructure resources according to your configuration, and updating the state to reflect the new infrastructure setup.

```bash 
terraform apply 
```
If you created a `custom.tfvars` file, apply using the `-var-file` flag: 
```bash
terraform apply  -var-file=custom.tfvars
```
Or for RIG deployments: 
```bash
terraform apply -var-file=rig_custom.tfvars
```
When prompted to confirm, type `yes` and press enter.

You can also run `terraform apply` with the `-auto-approve` flag to avoid being prompted for confirmation, but use with caution to avoid unintended changes to your infrastructure. 

---

## Environment Variables
Run the `terraform_outputs.sh` script, which populates the `env_vars.sh` script with your environment variables for future reference: 
```bash 
cd ..
chmod +x terraform_outputs.sh
./terraform_outputs.sh
cat env_vars.sh 
```
Source the `env_vars.sh` script to set your environment variables: 
```bash 
source env_vars.sh
```
Verify that your environment variables are set: 
```bash
echo $EKS_CLUSTER_NAME
echo $PRIVATE_SUBNET_ID
echo $SECURITY_GROUP_ID
```

---

## Clean Up

Before cleaning up, validate the changes by running a speculative destroy plan: 

```bash
cd hyperpod-eks-tf
terraform plan -destroy
```

If you created a `custom.tfvars` file, plan using the `-var-file` flag: 
```bash
terraform plan -destroy -var-file=custom.tfvars
```
Or for RIG deployments:
```bash
terraform plan -destroy -var-file=rig_custom.tfvars
```
Once you've validated the changes, you can proceed to destroy the resources: 
```bash 
terraform destroy
```
If you created a `custom.tfvars` file, destroy using the `-var-file` flag: 
```bash
terraform destroy -var-file=custom.tfvars
```
Or for RIG deployments: 
```bash
terraform destroy -var-file=rig_custom.tfvars
```