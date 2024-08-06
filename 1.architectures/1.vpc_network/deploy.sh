aws cloudformation create-stack --stack-name vpc-stack-ml\
                                --template-body file://2.vpc-one-az.yaml \
                                --parameters ParameterKey=SubnetsAZ,ParameterValue=us-west-2a \
                                             ParameterKey=VPCName,ParameterValue="ML HPC VPC" \
                                --capabilities CAPABILITY_IAM

