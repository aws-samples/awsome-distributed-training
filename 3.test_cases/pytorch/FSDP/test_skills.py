#!/usr/bin/env python3
"""
Comprehensive test suite for opencode skills.
Tests all modules, skills, and commands.
"""

import sys
import os
import unittest
from unittest.mock import Mock, patch, MagicMock
import json

# Add paths
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'opencode', 'skills', 'shared'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'opencode', 'skills', 'eks-cluster-manager', 'src'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'opencode', 'skills', 'training-job-deployer', 'src'))

class TestLogger(unittest.TestCase):
    """Test logger module."""
    
    def test_import(self):
        """Test logger imports."""
        from logger import create_logger, SkillLogger, StatusReporter
        self.assertTrue(True)
    
    def test_create_logger(self):
        """Test logger creation."""
        from logger import create_logger
        logger = create_logger('test', verbose=False)
        self.assertIsNotNone(logger)
    
    def test_status_reporter(self):
        """Test status reporter."""
        from logger import create_logger, StatusReporter
        logger = create_logger('test', verbose=False)
        reporter = StatusReporter(logger)
        
        reporter.add_step('Test Step', 'Test description')
        reporter.start_step('Test Step')
        reporter.complete_step('Test Step', success=True)
        
        self.assertEqual(len(reporter.steps), 1)
        self.assertEqual(reporter.steps[0]['status'], 'completed')


class TestFailureAnalyzer(unittest.TestCase):
    """Test failure analyzer module."""
    
    def setUp(self):
        from failure_analyzer import FailureAnalyzer
        self.analyzer = FailureAnalyzer()
    
    def test_oom_detection(self):
        """Test OOM error detection."""
        logs = "CUDA out of memory. Tried to allocate 2.00 GiB"
        failures = self.analyzer.analyze_logs(logs)
        
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0]['name'], 'OOM_ERROR')
        self.assertTrue(failures[0]['auto_fixable'])
    
    def test_image_pull_error_detection(self):
        """Test image pull error detection."""
        logs = "Failed to pull image: ImagePullBackOff"
        failures = self.analyzer.analyze_logs(logs)
        
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0]['name'], 'IMAGE_PULL_ERROR')
    
    def test_no_failures(self):
        """Test when no failures present."""
        logs = "Training completed successfully!"
        failures = self.analyzer.analyze_logs(logs)
        
        self.assertEqual(len(failures), 0)
    
    def test_suggest_fix_oom(self):
        """Test fix suggestion for OOM."""
        failure = {
            'name': 'OOM_ERROR',
            'severity': 'high',
            'auto_fixable': True,
            'fix_action': 'reduce_batch_size',
            'fix_description': 'Reduce batch size by 50%'
        }
        job_config = {'train_batch_size': 4}
        
        fix = self.analyzer.suggest_fix(failure, job_config)
        
        self.assertEqual(fix['action'], 'reduce_batch_size')
        self.assertIn('train_batch_size', fix['config_changes'])
        self.assertEqual(fix['config_changes']['train_batch_size'], 2)
    
    def test_apply_fix(self):
        """Test applying fix to config."""
        failure = {
            'fix_action': 'reduce_batch_size',
            'fix_description': 'Reduce batch size'
        }
        job_config = {'train_batch_size': 4, 'other_param': 'value'}
        
        fix = self.analyzer.suggest_fix(failure, job_config)
        new_config = self.analyzer.apply_fix(fix, job_config)
        
        self.assertEqual(new_config['train_batch_size'], 2)
        self.assertEqual(new_config['other_param'], 'value')


class TestK8sUtils(unittest.TestCase):
    """Test k8s_utils module."""
    
    def test_import(self):
        """Test k8s_utils imports."""
        from k8s_utils import EKSClient, K8sClient, ClusterValidator
        self.assertTrue(True)
    
    @patch('k8s_utils.boto3.Session')
    def test_eks_client_init(self, mock_session):
        """Test EKSClient initialization."""
        from k8s_utils import EKSClient
        
        mock_client = Mock()
        mock_session.return_value.client.return_value = mock_client
        
        client = EKSClient(region='us-west-2')
        self.assertIsNotNone(client)
    
    def test_cluster_validator_init(self):
        """Test ClusterValidator initialization."""
        from k8s_utils import ClusterValidator, K8sClient
        
        mock_k8s = Mock(spec=K8sClient)
        validator = ClusterValidator(mock_k8s)
        
        self.assertIsNotNone(validator)


class TestClusterManager(unittest.TestCase):
    """Test cluster_manager module."""
    
    @patch('cluster_manager.EKSClient')
    @patch('cluster_manager.create_logger')
    def test_init(self, mock_logger, mock_eks):
        """Test ClusterManager initialization."""
        from cluster_manager import ClusterManager
        
        manager = ClusterManager(region='us-west-2', verbose=False)
        self.assertIsNotNone(manager)
    
    @patch('cluster_manager.EKSClient')
    @patch('cluster_manager.create_logger')
    def test_interactive_select_single_cluster(self, mock_logger, mock_eks):
        """Test interactive selection with one cluster."""
        from cluster_manager import ClusterManager
        
        manager = ClusterManager(region='us-west-2', verbose=False)
        
        clusters = [{'name': 'test-cluster', 'status': 'ACTIVE'}]
        
        with patch('builtins.input', return_value='y'):
            result = manager.interactive_select(clusters)
            self.assertEqual(result, 'test-cluster')


class TestJobDeployer(unittest.TestCase):
    """Test job_deployer module."""
    
    @patch('job_deployer.K8sClient')
    @patch('job_deployer.create_logger')
    def test_init(self, mock_logger, mock_k8s):
        """Test JobDeployer initialization."""
        from job_deployer import JobDeployer
        
        deployer = JobDeployer(cluster_name='test-cluster', verbose=False)
        self.assertIsNotNone(deployer)
    
    def test_generate_manifest_kubectl(self):
        """Test manifest generation for kubectl."""
        from job_deployer import JobDeployer
        
        deployer = JobDeployer(cluster_name='test-cluster', verbose=False)
        
        config = {
            'job_name': 'test-job',
            'image_uri': 'test-image:latest',
            'num_nodes': 4,
            'instance_type': 'ml.g5.xlarge'
        }
        
        manifest = deployer.generate_manifest(config, format='kubectl')
        
        self.assertIn('PyTorchJob', manifest)
        self.assertIn('test-job', manifest)
        self.assertIn('test-image:latest', manifest)


class TestSkillsIntegration(unittest.TestCase):
    """Test integration between skills."""
    
    def test_failure_analyzer_with_job_deployer(self):
        """Test failure analyzer integration with job deployer."""
        from failure_analyzer import FailureAnalyzer
        from job_deployer import JobDeployer
        
        analyzer = FailureAnalyzer()
        
        # Simulate job failure logs
        logs = "CUDA out of memory"
        failures = analyzer.analyze_logs(logs)
        
        self.assertEqual(len(failures), 1)
        
        # Test fix application
        job_config = {
            'job_name': 'test',
            'train_batch_size': 4,
            'num_nodes': 8
        }
        
        fix = analyzer.suggest_fix(failures[0], job_config)
        new_config = analyzer.apply_fix(fix, job_config)
        
        self.assertEqual(new_config['train_batch_size'], 2)
        self.assertEqual(new_config['num_nodes'], 8)  # Unchanged


class TestClaudeCommands(unittest.TestCase):
    """Test Claude Code commands."""
    
    def test_build_image_import(self):
        """Test build_image command imports."""
        try:
            sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'claude-commands'))
            from build_image import build_docker_image
            self.assertTrue(True)
        except ImportError as e:
            self.fail(f"Import failed: {e}")
    
    def test_manage_eks_cluster_import(self):
        """Test manage_eks_cluster command imports."""
        try:
            sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'claude-commands'))
            from manage_eks_cluster import manage_eks_cluster
            self.assertTrue(True)
        except ImportError as e:
            self.fail(f"Import failed: {e}")
    
    def test_deploy_training_job_import(self):
        """Test deploy_training_job command imports."""
        try:
            sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'claude-commands'))
            from deploy_training_job import deploy_training_job
            self.assertTrue(True)
        except ImportError as e:
            self.fail(f"Import failed: {e}")


class TestOpencodeSkills(unittest.TestCase):
    """Test opencode skills."""
    
    def test_eks_cluster_manager_import(self):
        """Test eks-cluster-manager skill imports."""
        try:
            from manage_cluster import main
            self.assertTrue(True)
        except ImportError as e:
            self.fail(f"Import failed: {e}")
    
    def test_training_job_deployer_import(self):
        """Test training-job-deployer skill imports."""
        try:
            from deploy_job import main
            self.assertTrue(True)
        except ImportError as e:
            self.fail(f"Import failed: {e}")


def run_tests():
    """Run all tests and return results."""
    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add all test classes
    suite.addTests(loader.loadTestsFromTestCase(TestLogger))
    suite.addTests(loader.loadTestsFromTestCase(TestFailureAnalyzer))
    suite.addTests(loader.loadTestsFromTestCase(TestK8sUtils))
    suite.addTests(loader.loadTestsFromTestCase(TestClusterManager))
    suite.addTests(loader.loadTestsFromTestCase(TestJobDeployer))
    suite.addTests(loader.loadTestsFromTestCase(TestSkillsIntegration))
    suite.addTests(loader.loadTestsFromTestCase(TestClaudeCommands))
    suite.addTests(loader.loadTestsFromTestCase(TestOpencodeSkills))
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return result


if __name__ == '__main__':
    print("="*80)
    print("RUNNING COMPREHENSIVE SKILL TESTS")
    print("="*80)
    print()
    
    result = run_tests()
    
    print()
    print("="*80)
    print("TEST SUMMARY")
    print("="*80)
    print(f"Tests run: {result.testsRun}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")
    print(f"Skipped: {len(result.skipped)}")
    
    if result.wasSuccessful():
        print("\n✅ ALL TESTS PASSED!")
        sys.exit(0)
    else:
        print("\n❌ SOME TESTS FAILED")
        sys.exit(1)
