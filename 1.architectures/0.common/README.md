# Common templates and tools

## S3 Bucket

This template creates a S3 Bucket with all public access disabled. To deploy it, click the link below:

[<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https://awsome-distributed-training.s3.amazonaws.com/templates/0.private-bucket.yaml&stackName=ML-S3)


## HyperPod cluster status change / node health event notifications

This template deploys a stack to receive human-readable email notifications for HyperPod cluster status changes and node health events. See the [workshop page](https://catalog.workshops.aws/sagemaker-hyperpod/en-US/07-tips-and-tricks/26-event-bridge) for more details.

[<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https://ws-assets-prod-iad-r-iad-ed304a55c2ca1aee.s3.us-east-1.amazonaws.com/e3752eec-63b5-4033-9720-fa68d35164e9/hyperpod-event-bridge-email.yaml&stackName=hyperpod-event-bridge-email)

## Create a scheduler to scale up and down the number of nodes in an instance group

This template deploys an AWS Lambda lamdba function which is triggered by an Amazon EventBridge Rule to scale up and down the number of nodes based on a cron expression. 

[<kbd> <br> 1-Click Deploy 🚀 <br> </kdb>](https://ws-assets-prod-iad-r-iad-ed304a55c2ca1aee.s3.us-east-1.amazonaws.com/2433d39e-ccfe-4c00-9d3d-9917b729258e/update-instance-group-instance-count.yaml)