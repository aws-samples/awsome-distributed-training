"""
Kubernetes and EKS utilities for managing clusters and training jobs.
"""

import boto3
import subprocess
import json
import time
from typing import Optional, Dict, List, Tuple, Any
from datetime import datetime
from botocore.exceptions import ClientError


class EKSClient:
    """AWS EKS client wrapper."""
    
    def __init__(self, region: str = "us-west-2", profile_name: Optional[str] = None):
        self.region = region
        self.profile_name = profile_name
        self.session = boto3.Session(profile_name=profile_name, region_name=region)
        self.eks = self.session.client('eks')
        self.ec2 = self.session.client('ec2')
    
    def list_clusters(self) -> List[Dict]:
        """List all EKS clusters with details."""
        clusters = []
        try:
            response = self.eks.list_clusters()
            for cluster_name in response.get('clusters', []):
                try:
                    cluster_info = self.describe_cluster(cluster_name)
                    clusters.append(cluster_info)
                except Exception as e:
                    clusters.append({
                        'name': cluster_name,
                        'status': 'ERROR',
                        'error': str(e)
                    })
        except ClientError as e:
            print(f"❌ Error listing clusters: {e}")
        return clusters
    
    def describe_cluster(self, cluster_name: str) -> Dict:
        """Get detailed cluster information."""
        try:
            response = self.eks.describe_cluster(name=cluster_name)
            cluster = response['cluster']
            
            return {
                'name': cluster['name'],
                'arn': cluster['arn'],
                'status': cluster['status'],
                'version': cluster['version'],
                'endpoint': cluster.get('endpoint'),
                'role_arn': cluster.get('roleArn'),
                'vpc_id': cluster.get('resourcesVpcConfig', {}).get('vpcId'),
                'subnets': cluster.get('resourcesVpcConfig', {}).get('subnetIds', []),
                'security_groups': cluster.get('resourcesVpcConfig', {}).get('securityGroupIds', []),
                'created_at': cluster.get('createdAt'),
                'tags': cluster.get('tags', {})
            }
        except ClientError as e:
            raise Exception(f"Failed to describe cluster {cluster_name}: {e}")
    
    def get_node_groups(self, cluster_name: str) -> List[Dict]:
        """Get managed node groups for cluster."""
        try:
            response = self.eks.list_nodegroups(clusterName=cluster_name)
            node_groups = []
            
            for ng_name in response.get('nodegroups', []):
                try:
                    ng_response = self.eks.describe_nodegroup(
                        clusterName=cluster_name,
                        nodegroupName=ng_name
                    )
                    ng = ng_response['nodegroup']
                    
                    node_groups.append({
                        'name': ng['nodegroupName'],
                        'status': ng['status'],
                        'instance_types': ng.get('instanceTypes', []),
                        'desired_size': ng.get('scalingConfig', {}).get('desiredSize', 0),
                        'min_size': ng.get('scalingConfig', {}).get('minSize', 0),
                        'max_size': ng.get('scalingConfig', {}).get('maxSize', 0),
                        'disk_size': ng.get('diskSize'),
                        'ami_type': ng.get('amiType'),
                        'capacity_type': ng.get('capacityType')
                    })
                except Exception as e:
                    node_groups.append({
                        'name': ng_name,
                        'status': 'ERROR',
                        'error': str(e)
                    })
            
            return node_groups
        except ClientError as e:
            print(f"❌ Error getting node groups: {e}")
            return []
    
    def wait_for_cluster_active(self, cluster_name: str, timeout: int = 900) -> bool:
        """Wait for cluster to become active."""
        print(f"⏳ Waiting for cluster {cluster_name} to become active...")
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                cluster = self.describe_cluster(cluster_name)
                status = cluster['status']
                
                if status == 'ACTIVE':
                    print(f"✅ Cluster {cluster_name} is active")
                    return True
                elif status == 'FAILED':
                    print(f"❌ Cluster {cluster_name} creation failed")
                    return False
                
                print(f"   Status: {status}...")
                time.sleep(30)
                
            except Exception as e:
                print(f"   Waiting... ({e})")
                time.sleep(30)
        
        print(f"⏱️  Timeout waiting for cluster")
        return False


class K8sClient:
    """Kubernetes client using kubectl."""
    
    def __init__(self, cluster_name: Optional[str] = None, region: str = "us-west-2"):
        self.cluster_name = cluster_name
        self.region = region
        
        if cluster_name:
            self._update_kubeconfig()
    
    def _update_kubeconfig(self):
        """Update kubeconfig for cluster access."""
        try:
            cmd = ['aws', 'eks', 'update-kubeconfig',
                   '--region', self.region,
                   '--name', self.cluster_name]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"⚠️  Warning: Could not update kubeconfig: {result.stderr}")
        except Exception as e:
            print(f"⚠️  Warning: Could not update kubeconfig: {e}")
    
    def _kubectl(self, args: List[str]) -> Tuple[int, str, str]:
        """Run kubectl command."""
        cmd = ['kubectl'] + args
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return result.returncode, result.stdout, result.stderr
    
    def get_nodes(self) -> List[Dict]:
        """Get all nodes with details."""
        returncode, stdout, stderr = self._kubectl(['get', 'nodes', '-o', 'json'])
        
        if returncode != 0:
            print(f"❌ Error getting nodes: {stderr}")
            return []
        
        try:
            data = json.loads(stdout)
            nodes = []
            
            for node in data.get('items', []):
                metadata = node.get('metadata', {})
                status = node.get('status', {})
                labels = metadata.get('labels', {})
                allocatable = status.get('allocatable', {})
                
                # Get conditions
                conditions = status.get('conditions', [])
                ready_status = 'Unknown'
                for condition in conditions:
                    if condition.get('type') == 'Ready':
                        ready_status = condition.get('status', 'Unknown')
                
                nodes.append({
                    'name': metadata.get('name'),
                    'instance_type': labels.get('node.kubernetes.io/instance-type', 'unknown'),
                    'gpu_count': int(allocatable.get('nvidia.com/gpu', 0)),
                    'efa_count': int(allocatable.get('vpc.amazonaws.com/efa', 0)),
                    'cpu': allocatable.get('cpu'),
                    'memory': allocatable.get('memory'),
                    'status': ready_status,
                    'labels': labels
                })
            
            return nodes
        except json.JSONDecodeError:
            print("❌ Error parsing node data")
            return []
    
    def get_pods(self, namespace: str = 'kubeflow', label_selector: Optional[str] = None) -> List[Dict]:
        """Get pods in namespace."""
        cmd = ['get', 'pods', '-n', namespace, '-o', 'json']
        if label_selector:
            cmd.extend(['-l', label_selector])
        
        returncode, stdout, stderr = self._kubectl(cmd)
        
        if returncode != 0:
            return []
        
        try:
            data = json.loads(stdout)
            pods = []
            
            for pod in data.get('items', []):
                metadata = pod.get('metadata', {})
                status = pod.get('status', {})
                spec = pod.get('spec', {})
                
                container_statuses = status.get('containerStatuses', [])
                containers_ready = sum(1 for c in container_statuses if c.get('ready'))
                
                pods.append({
                    'name': metadata.get('name'),
                    'namespace': metadata.get('namespace'),
                    'status': status.get('phase'),
                    'ready': f"{containers_ready}/{len(container_statuses)}",
                    'restarts': sum(c.get('restartCount', 0) for c in container_statuses),
                    'age': metadata.get('creationTimestamp'),
                    'node': spec.get('nodeName')
                })
            
            return pods
        except json.JSONDecodeError:
            return []
    
    def get_daemonsets(self, namespace: str = 'kube-system') -> List[Dict]:
        """Get daemonsets (for checking plugins)."""
        returncode, stdout, stderr = self._kubectl([
            'get', 'daemonsets', '-n', namespace, '-o', 'json'
        ])
        
        if returncode != 0:
            return []
        
        try:
            data = json.loads(stdout)
            daemonsets = []
            
            for ds in data.get('items', []):
                metadata = ds.get('metadata', {})
                status = ds.get('status', {})
                
                daemonsets.append({
                    'name': metadata.get('name'),
                    'namespace': metadata.get('namespace'),
                    'desired': status.get('desiredNumberScheduled', 0),
                    'current': status.get('currentNumberScheduled', 0),
                    'ready': status.get('numberReady', 0),
                    'available': status.get('numberAvailable', 0)
                })
            
            return daemonsets
        except json.JSONDecodeError:
            return []
    
    def check_daemonset_status(self, name: str, namespace: str = 'kube-system') -> Optional[Dict]:
        """Check specific daemonset status."""
        daemonsets = self.get_daemonsets(namespace)
        for ds in daemonsets:
            if ds['name'] == name:
                return ds
        return None
    
    def get_pytorchjobs(self, namespace: str = 'kubeflow') -> List[Dict]:
        """Get PyTorchJob CRDs."""
        returncode, stdout, stderr = self._kubectl([
            'get', 'pytorchjobs', '-n', namespace, '-o', 'json'
        ])
        
        if returncode != 0:
            return []
        
        try:
            data = json.loads(stdout)
            jobs = []
            
            for job in data.get('items', []):
                metadata = job.get('metadata', {})
                status = job.get('status', {})
                spec = job.get('spec', {})
                
                replica_status = status.get('replicaStatuses', {}).get('Worker', {})
                
                # Get state from conditions
                conditions = status.get('conditions', [])
                state = 'Unknown'
                if conditions:
                    state = conditions[-1].get('type', 'Unknown')
                
                jobs.append({
                    'name': metadata.get('name'),
                    'namespace': metadata.get('namespace'),
                    'created': metadata.get('creationTimestamp'),
                    'state': state,
                    'replicas': spec.get('pytorchReplicaSpecs', {}).get('Worker', {}).get('replicas', 0),
                    'active': replica_status.get('active', 0),
                    'succeeded': replica_status.get('succeeded', 0),
                    'failed': replica_status.get('failed', 0)
                })
            
            return jobs
        except json.JSONDecodeError:
            return []
    
    def apply_manifest(self, manifest_path: str) -> Tuple[bool, str]:
        """Apply Kubernetes manifest."""
        returncode, stdout, stderr = self._kubectl(['apply', '-f', manifest_path])
        return returncode == 0, stdout if returncode == 0 else stderr
    
    def delete_manifest(self, manifest_path: str) -> Tuple[bool, str]:
        """Delete Kubernetes manifest."""
        returncode, stdout, stderr = self._kubectl(['delete', '-f', manifest_path])
        return returncode == 0, stdout if returncode == 0 else stderr
    
    def get_pod_logs(self, pod_name: str, namespace: str = 'kubeflow',
                    tail: int = 100) -> Tuple[bool, str]:
        """Get pod logs."""
        returncode, stdout, stderr = self._kubectl([
            'logs', pod_name, '-n', namespace, f'--tail={tail}'
        ])
        return returncode == 0, stdout if returncode == 0 else stderr
    
    def stream_pod_logs(self, pod_name: str, namespace: str = 'kubeflow'):
        """Stream pod logs in real-time."""
        cmd = ['kubectl', 'logs', pod_name, '-n', namespace, '-f']
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        
        try:
            for line in process.stdout:
                yield line.strip()
        finally:
            process.terminate()
    
    def delete_pytorchjob(self, job_name: str, namespace: str = 'kubeflow') -> Tuple[bool, str]:
        """Delete a PyTorchJob."""
        returncode, stdout, stderr = self._kubectl([
            'delete', 'pytorchjob', job_name, '-n', namespace
        ])
        return returncode == 0, stdout if returncode == 0 else stderr


class ClusterValidator:
    """Validate EKS cluster readiness for training."""
    
    def __init__(self, k8s_client: K8sClient):
        self.k8s = k8s_client
    
    def validate_all(self) -> Dict:
        """Run all validation checks."""
        results = {
            'timestamp': datetime.now().isoformat(),
            'overall_status': 'UNKNOWN',
            'checks': {}
        }
        
        results['checks']['gpu_plugin'] = self.check_gpu_plugin()
        results['checks']['efa_plugin'] = self.check_efa_plugin()
        results['checks']['kubeflow_operator'] = self.check_kubeflow_operator()
        results['checks']['nodes'] = self.check_nodes()
        
        # Determine overall status
        statuses = [c.get('status') for c in results['checks'].values()]
        if all(s == 'PASS' for s in statuses):
            results['overall_status'] = 'PASS'
        elif any(s == 'FAIL' for s in statuses):
            results['overall_status'] = 'FAIL'
        else:
            results['overall_status'] = 'WARNING'
        
        return results
    
    def check_gpu_plugin(self) -> Dict:
        """Check NVIDIA GPU device plugin."""
        ds = self.k8s.check_daemonset_status('nvidia-device-plugin-daemonset')
        
        if ds is None:
            return {
                'status': 'FAIL',
                'message': 'NVIDIA GPU device plugin not found',
                'suggestion': 'Install: kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/main/nvidia-device-plugin.yml'
            }
        
        if ds['desired'] == ds['ready'] and ds['ready'] > 0:
            return {
                'status': 'PASS',
                'message': f'GPU plugin running on {ds["ready"]} nodes',
                'details': ds
            }
        else:
            return {
                'status': 'WARNING',
                'message': f'GPU plugin: {ds["ready"]}/{ds["desired"]} nodes ready',
                'details': ds
            }
    
    def check_efa_plugin(self) -> Dict:
        """Check AWS EFA device plugin."""
        ds = self.k8s.check_daemonset_status('aws-efa-k8s-device-plugin-daemonset')
        
        if ds is None:
            return {
                'status': 'FAIL',
                'message': 'AWS EFA device plugin not found',
                'suggestion': 'Install from https://github.com/aws/aws-efa-k8s-device-plugin'
            }
        
        if ds['desired'] == ds['ready'] and ds['ready'] > 0:
            return {
                'status': 'PASS',
                'message': f'EFA plugin running on {ds["ready"]} nodes',
                'details': ds
            }
        else:
            return {
                'status': 'WARNING',
                'message': f'EFA plugin: {ds["ready"]}/{ds["desired"]} nodes ready',
                'details': ds
            }
    
    def check_kubeflow_operator(self) -> Dict:
        """Check Kubeflow Training Operator."""
        returncode, stdout, stderr = self.k8s._kubectl(['get', 'crd', 'pytorchjobs.kubeflow.org'])
        
        if returncode != 0:
            return {
                'status': 'FAIL',
                'message': 'Kubeflow Training Operator not installed',
                'suggestion': 'Install: kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.7.0"'
            }
        
        pods = self.k8s.get_pods(namespace='kubeflow', label_selector='app=training-operator')
        running_pods = [p for p in pods if p['status'] == 'Running']
        
        if running_pods:
            return {
                'status': 'PASS',
                'message': f'Kubeflow Training Operator running ({len(running_pods)} pods)',
                'details': {'pods': len(running_pods)}
            }
        else:
            return {
                'status': 'WARNING',
                'message': 'Kubeflow operator pods not running',
                'suggestion': 'Check training-operator deployment'
            }
    
    def check_nodes(self) -> Dict:
        """Check node status and resources."""
        nodes = self.k8s.get_nodes()
        
        if not nodes:
            return {
                'status': 'FAIL',
                'message': 'No nodes found in cluster',
                'suggestion': 'Check node group configuration'
            }
        
        total_gpus = sum(n.get('gpu_count', 0) for n in nodes)
        total_efas = sum(n.get('efa_count', 0) for n in nodes)
        ready_nodes = sum(1 for n in nodes if n.get('status') == 'True')
        
        result = {
            'status': 'PASS',
            'message': f'{ready_nodes}/{len(nodes)} nodes ready, {total_gpus} GPUs, {total_efas} EFAs',
            'details': {
                'total_nodes': len(nodes),
                'ready_nodes': ready_nodes,
                'total_gpus': total_gpus,
                'total_efas': total_efas,
                'node_types': list(set(n.get('instance_type', 'unknown') for n in nodes))
            }
        }
        
        if total_gpus == 0:
            result['status'] = 'WARNING'
            result['message'] += ' (No GPUs detected)'
            result['suggestion'] = 'Add GPU node group to cluster'
        
        return result


class ConfigMapManager:
    """Manage job configurations in ConfigMaps."""
    
    def __init__(self, k8s_client: K8sClient, namespace: str = 'kubeflow'):
        self.k8s = k8s_client
        self.namespace = namespace
    
    def save_config(self, name: str, config: Dict) -> bool:
        """Save configuration to ConfigMap."""
        import yaml
        
        config_yaml = yaml.dump(config)
        
        # Create ConfigMap manifest
        manifest = {
            'apiVersion': 'v1',
            'kind': 'ConfigMap',
            'metadata': {
                'name': f'job-config-{name}',
                'namespace': self.namespace
            },
            'data': {
                'config.yaml': config_yaml
            }
        }
        
        # Write to temp file and apply
        import tempfile
        import json
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            json.dump(manifest, f)
            temp_path = f.name
        
        success, output = self.k8s.apply_manifest(temp_path)
        
        import os
        os.unlink(temp_path)
        
        return success
    
    def load_config(self, name: str) -> Optional[Dict]:
        """Load configuration from ConfigMap."""
        returncode, stdout, stderr = self.k8s._kubectl([
            'get', 'configmap', f'job-config-{name}', 
            '-n', self.namespace,
            '-o', 'jsonpath={.data.config\\.yaml}'
        ])
        
        if returncode != 0:
            return None
        
        try:
            import yaml
            return yaml.safe_load(stdout)
        except Exception:
            return None
    
    def list_configs(self) -> List[str]:
        """List all saved configurations."""
        returncode, stdout, stderr = self.k8s._kubectl([
            'get', 'configmaps', '-n', self.namespace,
            '-l', 'app=training-job-config',
            '-o', 'jsonpath={.items[*].metadata.name}'
        ])
        
        if returncode != 0:
            return []
        
        return stdout.split()
    
    def delete_config(self, name: str) -> bool:
        """Delete configuration ConfigMap."""
        returncode, stdout, stderr = self.k8s._kubectl([
            'delete', 'configmap', f'job-config-{name}',
            '-n', self.namespace
        ])
        
        return returncode == 0
