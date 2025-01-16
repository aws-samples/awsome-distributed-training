# Slurm job template to probe EC2 informations

Usage: review and customize [job-template.sbatch](job-template.sbatch) to your need.

Below shows the sample output (trimmed) of customizing the template to run Megatron-LM, i.e.,
replace the `srun -l /usr/bin/hostname` with the relevant parts from the [Megatron-LM
example](../../3.test_cases/1.megatron-lm/)).

```text
...
+ validate_ec2_same_spine
++ lstopo_ec2
++ INSTANCE_IDS=($(srun cat /sys/devices/virtual/dmi/id/board_asset_tag))
+++ srun cat /sys/devices/virtual/dmi/id/board_asset_tag
++ local INSTANCE_IDS
++ aws ec2 describe-instance-topology --instance-ids i-1111111111example i-0000000000example
+ local 'TOPO_JSON={
    "Instances": [
        {
            "InstanceId": "i-0000000000example",
            "InstanceType": "p4de.24xlarge",
            "NetworkNodes": [
                "nn-1111111111example",
                "nn-2222222222example",
                "nn-3333333333example"
            ],
            "AvailabilityZone": "us-west-2b",
            "ZoneId": "usw2-az2"
        },
        {
            "InstanceId": "i-1111111111example",
            "InstanceType": "p4de.24xlarge",
            "NetworkNodes": [
                "nn-1111111111example",
                "nn-2222222222example",
                "nn-3333333333example"
            ],
            "AvailabilityZone": "us-west-2b",
            "ZoneId": "usw2-az2"
        }
    ]
}'
+ echo '{
    "Instances": [
        {
            "InstanceId": "i-0000000000example",
            "InstanceType": "p4de.24xlarge",
            "NetworkNodes": [
                "nn-1111111111example",
                "nn-2222222222example",
                "nn-3333333333example"
            ],
            "AvailabilityZone": "us-west-2b",
            "ZoneId": "usw2-az2"
        },
        {
            "InstanceId": "i-1111111111example",
            "InstanceType": "p4de.24xlarge",
            "NetworkNodes": [
                "nn-1111111111example",
                "nn-2222222222example",
                "nn-3333333333example"
            ],
            "AvailabilityZone": "us-west-2b",
            "ZoneId": "usw2-az2"
        }
    ]
}'
{
    "Instances": [
        {
            "InstanceId": "i-0000000000example",
            "InstanceType": "p4de.24xlarge",
            "NetworkNodes": [
                "nn-1111111111example",
                "nn-2222222222example",
                "nn-3333333333example"
            ],
            "AvailabilityZone": "us-west-2b",
            "ZoneId": "usw2-az2"
        },
        {
            "InstanceId": "i-1111111111example",
            "InstanceType": "p4de.24xlarge",
            "NetworkNodes": [
                "nn-1111111111example",
                "nn-2222222222example",
                "nn-3333333333example"
            ],
            "AvailabilityZone": "us-west-2b",
            "ZoneId": "usw2-az2"
        }
    ]
}
++ echo '{
    "Instances": [
        {
            "InstanceId": "i-0000000000example",
            "InstanceType": "p4de.24xlarge",
            "NetworkNodes": [
                "nn-1111111111example",
                "nn-2222222222example",
                "nn-3333333333example"
            ],
            "AvailabilityZone": "us-west-2b",
            "ZoneId": "usw2-az2"
        },
        {
            "InstanceId": "i-1111111111example",
            "InstanceType": "p4de.24xlarge",
            "NetworkNodes": [
                "nn-1111111111example",
                "nn-2222222222example",
                "nn-3333333333example"
            ],
            "AvailabilityZone": "us-west-2b",
            "ZoneId": "usw2-az2"
        }
    ]
}'
++ grep '^  *"nn\-.................\"'
++ sort -n
++ uniq -c
++ wc -l
+ local UNIQ_NN=3
+ echo Expected 3 nn ids, got 3 nn ids
Expected 3 nn ids, got 3 nn ids
+ [[ 3 -eq 3 ]]
...
+ srun -l bash -c 'echo "hostname <=> instance_id mapping: $(hostname) <=> $(cat /sys/devices/virtual/dmi/id/board_asset_tag)"'
1: hostname <=> instance_id mapping: p4de-st-p4de-2 <=> i-0000000000example
0: hostname <=> instance_id mapping: p4de-st-p4de-1 <=> i-1111111111example
+ srun -l bash -c 'echo BEFORE: $(hostname) $(sudo lctl get_param llite.*.stats | grep write_bytes)'
0: BEFORE: p4de-st-p4de-1 write_bytes 10361 samples [bytes] 1 2147479552 401369912220
1: BEFORE: p4de-st-p4de-2
...
++ date
+ BEGIN_TRAINING='Mon Apr  8 08:33:01 UTC 2024'
+ SECONDS=0
+ srun -l --container-image ... --container-mounts ... python -m torch.distributed.run ... /workspace/Megatron-LM/pretrain_gpt.py ...
...
++ date
+ END_TRAINING='Mon Apr  8 09:02:25 UTC 2024'
+ echo 'BEGIN_TRAINING: Mon Apr  8 08:33:01 UTC 2024'
BEGIN_TRAINING: Mon Apr  8 08:33:01 UTC 2024
+ echo 'END_TRAINING  : Mon Apr  8 09:02:25 UTC 2024'
END_TRAINING  : Mon Apr  8 09:02:25 UTC 2024
+ echo 'Elapsed: 29min 24sec'
Elapsed: 29min 24sec
+ srun -l bash -c 'echo AFTER: $(hostname) $(sudo lctl get_param llite.*.stats | grep write_bytes)'
srun: Step created for StepId=191.4
1: AFTER: p4de-st-p4de-2
0: AFTER: p4de-st-p4de-1 write_bytes 11553 samples [bytes] 1 2147479552 775980517197
```
