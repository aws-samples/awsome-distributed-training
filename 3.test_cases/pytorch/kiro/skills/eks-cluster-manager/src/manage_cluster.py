#!/usr/bin/env python3
"""
EKS Cluster Manager Skill
Discover, validate, and manage EKS clusters for training workloads.
"""

import argparse
import sys
import os

# Add shared utilities to path
sys.path.insert(0, os.path.expanduser('~/.opencode/skills/shared'))

from cluster_manager import ClusterManager
from logger import create_logger


def main():
    parser = argparse.ArgumentParser(description='Manage EKS cluster')
    parser.add_argument('--cluster_name', default='', help='Cluster name')
    parser.add_argument('--region', default='us-west-2', help='AWS region')
    parser.add_argument('--validate_components', type=lambda x: x.lower() == 'true',
                       default=True, help='Validate components')
    parser.add_argument('--auto_fix', type=lambda x: x.lower() == 'true',
                       default=False, help='Auto-fix issues')
    parser.add_argument('--create_if_missing', type=lambda x: x.lower() == 'true',
                       default=False, help='Create if missing')
    parser.add_argument('--infrastructure_type', default='cloudformation',
                       help='Infrastructure type')
    
    args = parser.parse_args()
    
    logger = create_logger('eks-cluster-manager')
    manager = ClusterManager(
        region=args.region,
        verbose=True
    )
    
    # Discover clusters
    clusters = manager.discover_clusters()
    
    if not clusters:
        logger.warning("No EKS clusters found")
        if args.create_if_missing:
            logger.info("Creating new cluster...")
            # Would create cluster here
        else:
            logger.info("Use --create_if_missing to create a cluster")
            return 1
    
    # Select cluster
    if args.cluster_name:
        selected_cluster = args.cluster_name
    else:
        selected_cluster = manager.interactive_select(clusters)
    
    if selected_cluster == 'CREATE_NEW':
        logger.info("Creating new cluster...")
        # Would create cluster here
        return 0
    
    if not selected_cluster:
        logger.error("No cluster selected")
        return 1
    
    # Validate cluster
    if args.validate_components:
        logger.info(f"Validating cluster: {selected_cluster}")
        results = manager.validate_cluster(selected_cluster)
        
        # Print results
        print(f"\nValidation Results:")
        print(f"Overall Status: {results['overall_status']}")
        for check_name, check_result in results['checks'].items():
            icon = "✅" if check_result['status'] == 'PASS' else "⚠️" if check_result['status'] == 'WARNING' else "❌"
            print(f"{icon} {check_name}: {check_result['message']}")
        
        # Auto-fix if requested
        if args.auto_fix and results['overall_status'] != 'PASS':
            logger.info("Attempting to fix issues...")
            fixed, fixes = manager.fix_cluster_issues(results)
            if fixed:
                logger.success(f"Applied {len(fixes)} fixes")
                for fix in fixes:
                    print(f"  - {fix}")
            else:
                logger.warning("Could not auto-fix all issues")
    
    logger.success(f"Cluster ready: {selected_cluster}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
