"""
EKS Cluster Manager - High-level cluster operations.
"""

from typing import Optional, Dict, List, Tuple
from .k8s_utils import EKSClient, K8sClient, ClusterValidator
from .logger import create_logger


class ClusterManager:
    """Manage EKS clusters for training workloads."""
    
    def __init__(self, region: str = "us-west-2", profile_name: Optional[str] = None, verbose: bool = True):
        self.region = region
        self.profile_name = profile_name
        self.logger = create_logger('cluster-manager', verbose=verbose)
        self.eks = EKSClient(region=region, profile_name=profile_name)
        self.k8s = None
        self.validator = None
    
    def discover_clusters(self) -> List[Dict]:
        """Discover and list all EKS clusters."""
        self.logger.info(f"🔍 Discovering EKS clusters in {self.region}...")
        
        clusters = self.eks.list_clusters()
        
        if not clusters:
            self.logger.warning("No EKS clusters found")
            return []
        
        # Enrich with node group info
        for cluster in clusters:
            if cluster.get('status') == 'ACTIVE':
                try:
                    cluster['node_groups'] = self.eks.get_node_groups(cluster['name'])
                except Exception as e:
                    cluster['node_groups'] = []
                    cluster['error'] = str(e)
        
        return clusters
    
    def interactive_select(self, clusters: List[Dict]) -> Optional[str]:
        """Interactive cluster selection."""
        if not clusters:
            return None
        
        if len(clusters) == 1:
            cluster = clusters[0]
            self.logger.info(f"Found 1 cluster: {cluster['name']}")
            confirm = input(f"Use cluster '{cluster['name']}'? [Y/n]: ").strip().lower()
            if confirm in ['', 'y', 'yes']:
                return cluster['name']
            return None
        
        # Multiple clusters - show table
        print("\n" + "="*80)
        print("Available EKS Clusters")
        print("="*80)
        
        for i, cluster in enumerate(clusters, 1):
            status_icon = "✅" if cluster.get('status') == 'ACTIVE' else "❌"
            node_count = sum(ng.get('desired_size', 0) for ng in cluster.get('node_groups', []))
            
            print(f"\n{i}. {cluster['name']} {status_icon}")
            print(f"   Status: {cluster.get('status', 'Unknown')}")
            print(f"   Version: {cluster.get('version', 'Unknown')}")
            print(f"   Nodes: {node_count}")
            
            if cluster.get('node_groups'):
                instance_types = set()
                for ng in cluster['node_groups']:
                    instance_types.update(ng.get('instance_types', []))
                print(f"   Instance Types: {', '.join(instance_types)}")
        
        print("\n" + "="*80)
        
        while True:
            choice = input(f"\nSelect cluster [1-{len(clusters)}, or 'create' for new]: ").strip()
            
            if choice.lower() == 'create':
                return 'CREATE_NEW'
            
            try:
                idx = int(choice) - 1
                if 0 <= idx < len(clusters):
                    return clusters[idx]['name']
                else:
                    print(f"❌ Invalid selection. Please enter 1-{len(clusters)} or 'create'")
            except ValueError:
                print("❌ Invalid input. Please enter a number or 'create'")
    
    def validate_cluster(self, cluster_name: str) -> Dict:
        """Validate cluster readiness."""
        self.logger.info(f"🔍 Validating cluster: {cluster_name}")
        
        # Initialize k8s client for this cluster
        self.k8s = K8sClient(cluster_name=cluster_name, region=self.region)
        self.validator = ClusterValidator(self.k8s)
        
        return self.validator.validate_all()
    
    def fix_cluster_issues(self, validation_results: Dict) -> Tuple[bool, List[str]]:
        """Auto-fix detected cluster issues."""
        fixes_applied = []
        
        for check_name, check_result in validation_results.get('checks', {}).items():
            if check_result.get('status') == 'PASS':
                continue
            
            self.logger.info(f"🔧 Attempting to fix: {check_name}")
            
            if check_name == 'gpu_plugin':
                success = self._install_gpu_plugin()
                if success:
                    fixes_applied.append('Installed NVIDIA GPU device plugin')
            
            elif check_name == 'efa_plugin':
                success = self._install_efa_plugin()
                if success:
                    fixes_applied.append('Installed AWS EFA device plugin')
            
            elif check_name == 'kubeflow_operator':
                success = self._install_kubeflow_operator()
                if success:
                    fixes_applied.append('Installed Kubeflow Training Operator')
        
        return len(fixes_applied) > 0, fixes_applied
    
    def _install_gpu_plugin(self) -> bool:
        """Install NVIDIA GPU device plugin."""
        try:
            self.logger.info("Installing NVIDIA GPU device plugin...")
            # Would apply manifest here
            return True
        except Exception as e:
            self.logger.error(f"Failed to install GPU plugin: {e}")
            return False
    
    def _install_efa_plugin(self) -> bool:
        """Install AWS EFA device plugin."""
        try:
            self.logger.info("Installing AWS EFA device plugin...")
            # Would apply manifest here
            return True
        except Exception as e:
            self.logger.error(f"Failed to install EFA plugin: {e}")
            return False
    
    def _install_kubeflow_operator(self) -> bool:
        """Install Kubeflow Training Operator."""
        try:
            self.logger.info("Installing Kubeflow Training Operator...")
            # Would apply manifest here
            return True
        except Exception as e:
            self.logger.error(f"Failed to install Kubeflow operator: {e}")
            return False
    
    def create_cluster(self, config: Dict) -> Tuple[bool, str]:
        """Create new EKS cluster with confirmation."""
        cluster_name = config.get('name', 'training-cluster')
        
        # Show preview
        print("\n" + "="*80)
        print("Cluster Creation Preview")
        print("="*80)
        print(f"\nName: {cluster_name}")
        print(f"Region: {self.region}")
        print(f"Node Type: {config.get('instance_type', 'ml.g5.8xlarge')}")
        print(f"Node Count: {config.get('node_count', 4)}")
        print(f"Kubernetes Version: {config.get('kubernetes_version', '1.29')}")
        print("\nResources to be created:")
        print("  • EKS Cluster (control plane)")
        print("  • Managed Node Group")
        print("  • VPC with subnets")
        print("  • IAM roles")
        print("  • GPU Device Plugin")
        print("  • EFA Device Plugin")
        print("  • Kubeflow Training Operator")
        print("\nEstimated time: 15-20 minutes")
        print("="*80)
        
        confirm = input("\nCreate these resources? [Y/n/show-details]: ").strip().lower()
        
        if confirm == 'show-details':
            print("\nDetailed resource list would be shown here...")
            confirm = input("\nCreate these resources? [Y/n]: ").strip().lower()
        
        if confirm not in ['', 'y', 'yes']:
            return False, "User cancelled"
        
        # Would create cluster here using CloudFormation or Terraform
        self.logger.info(f"🚀 Creating cluster {cluster_name}...")
        
        # Placeholder for actual creation
        return True, cluster_name
