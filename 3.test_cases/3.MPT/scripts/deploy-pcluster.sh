#!/usr/bin/env bash
. config.env

export PRIVATE_SUBNET_ID=$(aws cloudformation describe-stacks --stack-name vpc-${NAME} --region ${REGION} \
    | jq -r '.Stacks[] | .Outputs[] | select(.OutputKey == "PrivateSubnet") | .OutputValue')
export PUBLIC_SUBNET_ID=$(aws cloudformation describe-stacks --stack-name vpc-${NAME} --region ${REGION} \
    | jq -r '.Stacks[] | .Outputs[] | select(.OutputKey == "PublicSubnet") | .OutputValue')
TMPFILE=$(mktemp)
echo ${TMPFILE}
cat ../../1.architectures/2.aws-parallelcluster/distributed-training-clususter-with-container.yaml | envsubst > ${TMPFILE}
set_options
run cat ${TMPFILE}
run pcluster create-cluster --cluster-configuration ${TMPFILE} --cluster-name pcluster-${NAME} --region ${REGION}