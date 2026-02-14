#!/usr/bin/env python3
"""
Claude Code Command: Manage EKS Cluster
Discover, validate, and manage EKS clusters for training workloads.
"""

from typing import Optional
import sys
import os

# Add shared utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'opencode', 'skills', 'shared'))

try:
    from cluster_manager import ClusterManager
    from logger import create_logger
except ImportError:
    sys.path.insert(0, os.path.expanduser('~/.opencode/skills/shared'))
    from cluster_manager import ClusterManager
    from logger import create_logger


def manage_eks_cluster(
    cluster_name: Optional[str] = None,
    region: str = "us-west-2",
    validate_components: bool = True,
    auto_fix: bool = False,
    create_if_missing: bool = False,
    infrastructure_type: str = "cloudformation"
) -> str:
    """
    Manage EKS cluster for training workloads.
    
    Discovers available clusters, validates components (GPU plugin, EFA,
    Kubeflow), and optionally creates new clusters using EKS Blueprints.
    Supports both CloudFormation and Terraform.
    
    Args:
        cluster_name: Cluster name (None for interactive selection)
        region: AWS region (default: "us-west-2")
        validate_components: Validate GPU/EFA/Kubeflow (default: True)
        auto_fix: Auto-fix detected issues (default: False)
        create_if_missing: Create cluster if none exist (default: False)
        infrastructure_type: "cloudformation" or "terraform" (default: "cloudformation")
    
    Returns:
        str: Cluster status and validation results
    
    Examples:
        "Setup EKS cluster"
        "Validate my-cluster and fix issues"
        "Create new training cluster"
        "Show me available clusters"
    """
    
    logger = create_logger('eks-cluster-manager')
    manager = ClusterManager(region=region, verbose=True)
    
    try:
        # Discover clusters
        clusters = manager.discover_clusters()
        
        if not clusters:
            if create_if_missing:
                return "Would create new cluster (implementation pending)"
            else:
                return "❌ No EKS clusters found. Use create_if_missing=True to create one."
        
        # Select cluster
        if cluster_name:
            selected = cluster_name
            # Verify it exists
            if not any(c['name'] == cluster_name for c in clusters):
                return f"❌ Cluster '{cluster_name}' not found"
        else:
            selected = manager.interactive_select(clusters)
        
        if selected == 'CREATE_NEW':
            return "Would create new cluster (implementation pending)"
        
        if not selected:
            return "❌ No cluster selected"
        
        # Validate
        if validate_components:
            results = manager.validate_cluster(selected)
            
            message = f"\n✅ Selected cluster: {selected}\n\n"
            message += f"Overall Status: {results['overall_status']}\n\n"
            
            for check_name, check_result in results['checks'].items():
                icon = "✅" if check_result['status'] == 'PASS' else "⚠️" if check_result['status'] == 'WARNING' else "❌"
                message += f"{icon} {check_name}: {check_result['message']}\n"
                
                if 'suggestion' in check_result:
                    message += f"   💡 {check_result['suggestion']}\n"
            
            # Auto-fix
            if auto_fix and results['overall_status'] != 'PASS':
                fixed, fixes = manager.fix_cluster_issues(results)
                if fixed:
                    message += f"\n🔧 Applied {len(fixes)} fixes:\n"
                    for fix in fixes:
                        message += f"  - {fix}\n"
            
            return message
        
        return f"✅ Cluster selected: {selected}"
    
    except Exception as e:
        return f"❌ Error: {str(e)}"


try:
    from claude.tools import tool
    
    @tool
    def manage_eks_cluster_tool(
        cluster_name: Optional[str] = None,
        region: str = "us-west-2",
        validate_components: bool = True,
        auto_fix: bool = False
    ) -> str:
        """Manage EKS cluster"""
        return manage_eks_cluster(cluster_name, region, validate_components, auto_fix)
        
except ImportError:
    pass


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--cluster_name', default=None)
    parser.add_argument('--region', default='us-west-2')
    parser.add_argument('--validate_components', type=lambda x: x.lower() == 'true', default=True)
    parser.add_argument('--auto_fix', type=lambda x: x.lower() == 'true', default=False)
    args = parser.parse_args()
    
    print(manage_eks_cluster(**vars(args)))
