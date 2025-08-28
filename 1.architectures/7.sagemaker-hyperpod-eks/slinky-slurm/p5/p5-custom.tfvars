kubernetes_version = "1.32"
eks_cluster_name = "slinky-eks-cluster"
hyperpod_cluster_name = "slinky-hp-cluster"
resource_name_prefix = "slinky-hp-eks"
availability_zone_id  = "usw2-az2"
instance_groups = {
    accelerated-instance-group-1 = {
        instance_type = "ml.p5.48xlarge",
        instance_count = 2,
        ebs_volume_size_in_gb = 500,
        threads_per_core = 2,
        enable_stress_check = true,
        enable_connectivity_check = true,
        lifecycle_script = "on_create.sh"
    },
    general-instance-group-2 = {
        instance_type = "ml.m5.2xlarge",
        instance_count = 2,
        ebs_volume_size_in_gb = 500,
        threads_per_core = 1,
        lifecycle_script = "on_create.sh"
    }
}