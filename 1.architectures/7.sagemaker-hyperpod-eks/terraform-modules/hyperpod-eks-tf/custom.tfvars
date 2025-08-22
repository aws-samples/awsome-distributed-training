kubernetes_version = "1.32"
eks_cluster_name = "tf-eks-cluster"
hyperpod_cluster_name = "tf-hp-cluster"
resource_name_prefix = "tf-eks-test"
aws_region = "us-west-2"
availability_zone_id  = "usw2-az2"
instance_groups = {
    accelerated-instance-group-1 = {
        instance_type = "ml.c5.2xlarge",
        instance_count = 1,
        ebs_volume_size = 100,
        threads_per_core = 1,
        enable_stress_check = false,
        enable_connectivity_check = false,
        lifecycle_script = "on_create.sh"
    }
}
