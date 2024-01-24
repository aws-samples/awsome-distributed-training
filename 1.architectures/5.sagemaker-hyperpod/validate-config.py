#!/usr/bin/env python3

import json
import argparse
import boto3

# This function checks that all instance group names match
# between the cluster config and provisioning parameters.
def validate_instance_groups(cluster_config, provisioning_parameters):
    for group in provisioning_parameters.get('worker_groups'):
        instance_group_name = group.get('instance_group_name')
        if not [instance_group for instance_group in cluster_config.get('InstanceGroups') if instance_group.get('InstanceGroupName') == instance_group_name]:
            print(f"❌ Invalid instance group name in file provisioning_parameters.json: {instance_group_name}")
            return False
        else:
            print(f"✔️  Validated instance group name {instance_group_name} is correct ...")
    return True

# Check if Subnet is private
def validate_subnet(ec2_client, cluster_config):
    if cluster_config.get('VpcConfig'):
        subnet_id = cluster_config.get('VpcConfig').get('Subnets')[0]
        response = ec2_client.describe_subnets(SubnetIds=[subnet_id])
        if 'Subnets' in response and response.get('Subnets')[0].get('MapPublicIpOnLaunch'):
            print(f"❌ Subnet {subnet_id} is public which will fail cluster creation ...")
            return False
        else:
            print(f"✔️  Validated subnet {subnet_id} ...")
    else:
        print("⭕️ No subnet found in cluster_config.json ... skipping check")
    return True

# Check if Security Group supports EFA.
# See https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html#efa-start-security
def validate_sg(ec2_client, cluster_config):
    if cluster_config.get('VpcConfig'):
        security_group = cluster_config.get('VpcConfig').get('SecurityGroupIds')[0]
        ec2_client = boto3.client('ec2')
        response = ec2_client.describe_security_groups(GroupIds=[security_group])

        ingress = response.get('SecurityGroups')[0].get('IpPermissions')
        egress = response.get('SecurityGroups')[0].get('IpPermissionsEgress')
        
        for rule in ingress:
            if rule.get('IpProtocol') == '-1':
                user_id_group_pairs = rule.get('UserIdGroupPairs')
                if not user_id_group_pairs:
                    print(f"❌ No EFA egress rule found in security group {security_group} ...")
                    return False
                else:
                    if not ('GroupId' in user_id_group_pairs[0] or security_group == user_id_group_pairs[0].get('GroupId')):
                        print(f"❌ No EFA egress rule found in security group {security_group} ...")
                        return False
                    else:
                        print(f"✔️  Validated security group {security_group} ingress rules ...")

        for rule in egress:
            if rule.get('IpProtocol') == '-1':
                user_id_group_pairs = rule.get('UserIdGroupPairs')
                if not user_id_group_pairs:
                    print(f"❌ No EFA egress rule found in security group {security_group} ...")
                    return False
                else:
                    if not ('GroupId' in user_id_group_pairs[0] or security_group == user_id_group_pairs[0].get('GroupId')):
                        print(f"❌ No EFA egress rule found in security group {security_group} ...")
                        return False
                    else:
                        print(f"✔️  Validated security group {security_group} egress rules ...")
    else:
        print("⭕️ No security group found in cluster_config.json ... skipping check.")
    
    return True


def main():
    parser = argparse.ArgumentParser(description="Validate cluster config.")
    parser.add_argument("--cluster-config", help="Path to the cluster config JSON file")
    parser.add_argument("--provisioning-parameters", help="Path to the provisioning parameters JSON file")
    args = parser.parse_args()

    with open(args.cluster_config, "r") as cluster_config_file:
        cluster_config = json.load(cluster_config_file)

    with open(args.provisioning_parameters, "r") as provisioning_parameters_file:
        provisioning_parameters = json.load(provisioning_parameters_file)

    ec2_client = boto3.client('ec2')

    # check instance group name
    valid = validate_instance_groups(cluster_config, provisioning_parameters)

    # Validate Subnet
    valid = validate_subnet(ec2_client, cluster_config) and valid

    # Validate Security Group
    valid = validate_sg(ec2_client, cluster_config) and valid

    if valid:
        # All good!
        print(f"✅ Cluster Validation succeeded")
    else:
        print(f"❌ Cluster Validation failed")

if __name__ == "__main__":
    main()
