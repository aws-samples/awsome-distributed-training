#!/bin/bash

is_supported_instance() {
    local instance_type="$1"
    local supported_types=(
        "hpc6a.48xlarge" "hpc6id.32xlarge" "hpc7a.12xlarge" "hpc7a.24xlarge" 
        "hpc7a.48xlarge" "hpc7a.96xlarge" "hpc7g.4xlarge" "hpc7g.8xlarge" 
        "hpc7g.16xlarge" "p3dn.24xlarge" "p4d.24xlarge" "p4de.24xlarge" 
        "p5.48xlarge" "p5e.48xlarge" "p5en.48xlarge" "p6e-gb200.36xlarge"
        "trn1.2xlarge" "trn1.32xlarge" "trn1n.32xlarge" "trn2.48xlarge" 
        "trn2u.48xlarge" "p6-b200.48xlarge"
    )
    
    for supported in "${supported_types[@]}"; do
        if [ "$instance_type" = "$supported" ]; then
            return 0
        fi
    done
    return 1
}

validate_instances() {
    local has_unsupported=false
    
    echo "Validating instance types..."
    while IFS= read -r node; do
        instance_type=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}')
        if ! is_supported_instance "$instance_type"; then
            echo "Error: Node $node has unsupported instance type: $instance_type"
            has_unsupported=true
        fi
    done < <(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name)

    if [ "$has_unsupported" = true ]; then
        echo "This script only works with instances that support node topology information."
        exit 1
    fi
    echo "Instance type validation passed."
}

get_unique_values() {
    local layer=$1
    kubectl get nodes --no-headers -L "topology.k8s.aws/network-node-layer-$layer" | awk "{print \$NF}" | sort | uniq
}

validate_instances

echo "Getting layer information..."
layer1=($(get_unique_values 1))
layer2=($(get_unique_values 2))
layer3=($(get_unique_values 3))

echo "flowchart TD"
echo "    A[\"Cluster Topology\"]"

# Layer 1
for l1 in "${layer1[@]}"; do
    l1_id=$(echo "$l1" | sed 's/[^a-zA-Z0-9]/_/g')
    echo "    A --> L1_${l1_id}[\"Layer 1: ${l1}\"]"
done

# Layer 2
for l2 in "${layer2[@]}"; do
    l2_id=$(echo "$l2" | sed 's/[^a-zA-Z0-9]/_/g')
    parent=$(kubectl get nodes --no-headers -L topology.k8s.aws/network-node-layer-1,topology.k8s.aws/network-node-layer-2 | 
             awk -v l2="$l2" '$NF == l2 {print $(NF-1)}' | head -n1)
    parent_id=$(echo "$parent" | sed 's/[^a-zA-Z0-9]/_/g')
    echo "    L1_${parent_id} --> L2_${l2_id}[\"Layer 2: ${l2}\"]"
done

# Layer 3
for l3 in "${layer3[@]}"; do
    l3_id=$(echo "$l3" | sed 's/[^a-zA-Z0-9]/_/g')
    parent=$(kubectl get nodes --no-headers -L topology.k8s.aws/network-node-layer-2,topology.k8s.aws/network-node-layer-3 | 
             awk -v l3="$l3" '$NF == l3 {print $(NF-1)}' | head -n1)
    parent_id=$(echo "$parent" | sed 's/[^a-zA-Z0-9]/_/g')
    echo "    L2_${parent_id} --> L3_${l3_id}[\"Layer 3: ${l3}\"]"
done

kubectl get nodes --no-headers | while read -r node rest; do
    node_id=$(echo "$node" | sed 's/[^a-zA-Z0-9]/_/g')
    l3_parent=$(kubectl get nodes "$node" -o jsonpath='{.metadata.labels.topology\.k8s\.aws/network-node-layer-3}')
    l3_parent_id=$(echo "$l3_parent" | sed 's/[^a-zA-Z0-9]/_/g')
    echo "    L3_${l3_parent_id} --> N_${node_id}[\"${node}\"]"
done

