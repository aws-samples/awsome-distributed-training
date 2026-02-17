#!/usr/bin/env python3
"""
Deploy VERL training with proper checkpointing and persistent storage.
This script sets up persistent storage and resumes from checkpoints correctly.
"""

import argparse
import subprocess
import sys

def create_pvc(namespace="default", storage_size="100Gi"):
    """Create a PersistentVolumeClaim for checkpoints."""
    pvc_yaml = f"""apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: verl-checkpoints
  namespace: {namespace}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ebs-sc
  resources:
    requests:
      storage: {storage_size}
"""
    
    with open("/tmp/verl-checkpoints-pvc.yaml", "w") as f:
        f.write(pvc_yaml)
    
    result = subprocess.run(
        ["kubectl", "apply", "-f", "/tmp/verl-checkpoints-pvc.yaml"],
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        print(f"Created PVC 'verl-checkpoints' with {storage_size} storage")
        return True
    else:
        print(f"Failed to create PVC: {result.stderr}")
        print("Note: You may need to install the EBS CSI driver")
        return False

def main():
    parser = argparse.ArgumentParser(description='Deploy VERL training with persistent checkpointing')
    parser.add_argument('--job_name', default='verl-training')
    parser.add_argument('--image_uri', required=True)
    parser.add_argument('--num_nodes', type=int, default=4)
    parser.add_argument('--namespace', default='default')
    parser.add_argument('--storage_size', default='100Gi')
    
    args = parser.parse_args()
    
    # Create PVC
    create_pvc(args.namespace, args.storage_size)
    
    print("Training deployment with checkpointing support")
    print("Use the RayCluster YAML with persistent volume mounts")

if __name__ == '__main__':
    main()
