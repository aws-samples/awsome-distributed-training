#!/usr/bin/env bash
. config.env

set_options
run aws cloudformation create-stack --stack-name s3-${NAME} \
    --template-body file://../../1.architectures/0.s3/0.private-bucket.yaml \
    --parameters ParameterKey=S3BucketName,ParameterValue=${S3_BUCKET_NAME} \
    --region ${REGION} --capabilities=CAPABILITY_IAM