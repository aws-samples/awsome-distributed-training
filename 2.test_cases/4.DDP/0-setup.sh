#!/bin/bash

aws configure

# Create a New Role
aws iam create-role --role-name EC2Role --assume-role-policy-document file://./.env/EC2Role-Trust-Policy.json

# Attach S3 policy
aws iam attach-role-policy --role-name EC2Role --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Create New Instance Profile
aws iam create-instance-profile --instance-profile-name Workshop-Instance-Profile
aws iam add-role-to-instance-profile --role-name EC2Role --instance-profile-name Workshop-Instance-Profile

instance_id=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
echo $instance_id
# Associate new instance profile to EC2 instance
aws ec2 associate-iam-instance-profile --instance-id $instance_id --iam-instance-profile Name=Workshop-Instance-Profile

# Verify
#aws ec2 describe-iam-instance-profile-associations

# Create Virtual env
python3 -m pip install --upgrade pip
python3 -m pip install --user --upgrade virtualenv

python3 -m virtualenv ~/apc-ve
# ACTIVATE ENV BEFORE STEP 2
source ~/apc-ve/bin/activate
