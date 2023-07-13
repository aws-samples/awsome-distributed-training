#!/bin/bash

aws cloudformation create-stack --stack-name create-large-scale-vpc-stack --template-body file://./.env/Large-Scale-VPC.yaml --parameters ParameterKey=SubnetsAZ,ParameterValue=us-west-2a --capabilities CAPABILITY_IAM
