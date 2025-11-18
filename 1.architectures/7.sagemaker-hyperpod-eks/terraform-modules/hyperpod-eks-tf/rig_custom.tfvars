kubernetes_version = "1.32"
eks_cluster_name = "tf-eks-cluster-rig"
hyperpod_cluster_name = "tf-hp-cluster-rig"
resource_name_prefix = "tf-eks-test-rig"
aws_region = "us-east-1"
availability_zone_id  = "use1-az2"
rig_input_s3_bucket = "natharno-tf-rig-test-input-bucket"
rig_output_s3_bucket = "natharno-tf-rig-test-output-bucket"
continuous_provisioning_mode = false
instance_groups = {}
restricted_instance_groups = {
   rig-1 = {
        instance_type = "ml.g5.8xlarge",
        instance_count = 2, 
        ebs_volume_size_in_gb = 100,
        threads_per_core = 1, 
        enable_stress_check = false,
        enable_connectivity_check = false,
        fsxl_per_unit_storage_throughput = 250,
        fsxl_size_in_gi_b = 4800
   }
}
