#!/usr/bin/env bash
. config.env

set_options
run	aws cloudformation create-stack --stack-name vpc-${NAME} \
    --template-body file://../../1.architectures/1.vpc_network/2.vpc-one-az.yaml \
	--parameters ParameterKey=VPCName,ParameterValue=${VPC_NAME} ParameterKey=SubnetsAZ,ParameterValue=${AZ} \
	--region ${REGION} --capabilities=CAPABILITY_IAM
