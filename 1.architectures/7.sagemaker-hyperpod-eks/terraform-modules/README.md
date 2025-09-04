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

#### Using a `custom.tfvars` File 
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

#### Using an Existing EKS Cluster with HyperPod

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
Run `terraform apply` to execute the proposed changes outlined in the Terraform plan, creating, updating, or deleting infrastructure resources according to your configuration, and updating the state to reflect the new infrastructure setup.

```bash 
terraform apply 
```
If you created a `custom.tfvars` file, apply using the `-var-file` flag: 
```bash
terraform apply  -var-file=custom.tfvars
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

Once you've validated the changes, you can proceed to destroy the resources: 
```bash 
terraform destroy
```
If you created a `custom.tfvars` file, destroy using the `-var-file` flag: 
```bash
terraform destroy -var-file=custom.tfvars
```