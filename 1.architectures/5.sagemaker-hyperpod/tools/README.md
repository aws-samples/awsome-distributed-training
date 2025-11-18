# SMHP Tools <!-- omit from toc -->

The “tools” directory contains utility scripts for common tasks to help debug and troubleshoot issues.
Here are the details of each script, along with its usage and the expected output.

### [`dump_cluster_nodes_info.py`](./dump_cluster_nodes_info.py) 

Utility to dump details of all nodes in a cluster, into a csv file. 

**Usage:** `python dump_cluster_nodes_info.py –cluster-name <name-of-cluster-whose-node-details-are-needed>`

**Output:** “nodes.csv” file in the current directory, containing details of all nodes in the cluster 

## Create a scheduler to scale up and down the number of nodes in an instance group

This template deploys an AWS Lambda lamdba function which is triggered by an Amazon EventBridge Rule to scale up and down the number of nodes based on a cron expression. 

[<kbd> <br> 1-Click Deploy 🚀 <br> </kdb>](https://ws-assets-prod-iad-r-iad-ed304a55c2ca1aee.s3.us-east-1.amazonaws.com/2433d39e-ccfe-4c00-9d3d-9917b729258e/update-instance-group-instance-count.yaml)