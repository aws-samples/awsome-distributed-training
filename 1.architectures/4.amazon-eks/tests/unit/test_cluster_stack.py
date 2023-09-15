import aws_cdk as core
import aws_cdk.assertions as assertions

from cluster.cluster_stack import ClusterStack

# example tests. To run these tests, uncomment this file along with the example
# resource in cluster/cluster_stack.py
def test_cluster_created():
    app = core.App()
    stack = ClusterStack(app, "cluster")
    template = assertions.Template.from_stack(stack)
