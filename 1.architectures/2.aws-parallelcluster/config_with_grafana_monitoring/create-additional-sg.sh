#!/bin/bash

read -p "Please enter the vpc id of your cluster: " vpc_id
echo -e "creating a security group with $vpc_id..."
security_group=$(aws ec2 create-security-group --group-name grafana-sg --description "Open HTTP/HTTPS ports" --vpc-id ${vpc_id} --output text)
aws ec2 authorize-security-group-ingress --group-id ${security_group} --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id ${security_group} --protocol tcp --port 80 —-cidr 0.0.0.0/0
