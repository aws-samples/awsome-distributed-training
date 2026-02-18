#!/usr/bin/env python3
"""
Docker Image Tester Skill
Comprehensive testing with fix recommendations.
"""

import argparse
import sys
import os
import json
import subprocess
import tempfile
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass, asdict

# Add shared utilities to path
sys.path.insert(0, os.path.expanduser('~/.opencode/skills/shared'))

from logger import create_logger, StatusReporter
from docker_utils import DockerClient


@dataclass
class TestCase:
    """Represents a single test case."""
    name: str
    category: str
    description: str
    passed: bool = False
    message: str = ""
    duration_ms: int = 0
    error_details: Optional[str] = None


@dataclass
class FixRecommendation:
    """Represents a fix recommendation."""
    issue: str
    severity: str  # critical, high, medium, low
    recommendation: str
    code_example: Optional[str] = None
    documentation_link: Optional[str] = None


class TestSuite:
    """Collection of tests for Docker images."""
    
    def __init__(self, image_name: str, docker_client: DockerClient, logger):
        self.image_name = image_name
        self.docker = docker_client
        self.logger = logger
        self.tests: List[TestCase] = []
        self.recommendations: List[FixRecommendation] = []
    
    def _run_in_container(self, code: str, timeout: int = 120) -> Tuple[bool, str, str]:
        """Run Python code in container."""
        cmd = ['python', '-c', code]
        success, output = self.docker.run(self.image_name, command=cmd)
        return success, output, ""
    
    def test_imports_basic(self) -> TestCase:
        """Test basic Python imports."""
        test = TestCase(
            name="basic_imports",
            category="imports",
            description="Test basic package imports"
        )
        
        code = """
import sys
errors = []

packages = [
    ('torch', 'PyTorch'),
    ('transformers', 'Transformers'),
    ('datasets', 'Datasets'),
    ('numpy', 'NumPy'),
]

for module, name in packages:
    try:
        __import__(module)
        print(f"✓ {name}")
    except ImportError as e:
        errors.append(f"{name}: {e}")
        print(f"✗ {name}: {e}")

if errors:
    sys.exit(1)
print("SUCCESS")
"""
        
        success, stdout, stderr = self._run_in_container(code)
        test.passed = success and "SUCCESS" in stdout
        test.message = "All basic imports successful" if test.passed else "Some imports failed"
        
        if not test.passed:
            test.error_details = stdout + stderr
            self.recommendations.append(FixRecommendation(
                issue="Import failures detected",
                severity="critical",
                recommendation="Check requirements.txt for missing or incompatible packages",
                code_example="pip install torch transformers datasets"
            ))
        
        return test
    
    def test_imports_versions(self) -> TestCase:
        """Test import with version checking."""
        test = TestCase(
            name="version_check",
            category="imports",
            description="Verify package versions"
        )
        
        code = """
import torch
import transformers
import datasets

print(f"torch:{torch.__version__}")
print(f"transformers:{transformers.__version__}")
print(f"datasets:{datasets.__version__}")
print("SUCCESS")
"""
        
        success, stdout, stderr = self._run_in_container(code)
        test.passed = success and "SUCCESS" in stdout
        
        if test.passed:
            # Extract versions from output
            versions = {}
            for line in stdout.split('\n'):
                if ':' in line and not line.startswith('SUCCESS'):
                    pkg, ver = line.split(':', 1)
                    versions[pkg] = ver
            test.message = f"Versions: {versions}"
        else:
            test.message = "Version check failed"
            test.error_details = stdout + stderr
        
        return test
    
    def test_cuda_availability(self) -> TestCase:
        """Test CUDA availability."""
        test = TestCase(
            name="cuda_available",
            category="hardware",
            description="Check if CUDA is available"
        )
        
        code = """
import torch

if torch.cuda.is_available():
    print(f"CUDA available: {torch.version.cuda}")
    print(f"GPU count: {torch.cuda.device_count()}")
    print("SUCCESS")
else:
    print("CUDA not available (CPU-only mode)")
    print("SUCCESS")
"""
        
        success, stdout, stderr = self._run_in_container(code)
        test.passed = success and "SUCCESS" in stdout
        test.message = "CUDA check passed" if test.passed else "CUDA check failed"
        
        if "CUDA not available" in stdout:
            self.recommendations.append(FixRecommendation(
                issue="CUDA not available",
                severity="medium",
                recommendation="Image is CPU-only. For GPU training, use CUDA-enabled base image",
                code_example="FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime"
            ))
        
        return test
    
    def test_model_utils_import(self) -> TestCase:
        """Test FSDP model utils import."""
        test = TestCase(
            name="model_utils_import",
            category="fsdp",
            description="Import FSDP model utilities"
        )
        
        code = """
import sys
sys.path.insert(0, '/fsdp')

try:
    from model_utils.arguments import parse_args
    from model_utils.train_utils import get_model_config, compute_num_params
    from model_utils.checkpoint import save_checkpoint, load_checkpoint
    print("SUCCESS")
except Exception as e:
    print(f"FAILED: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
"""
        
        success, stdout, stderr = self._run_in_container(code)
        test.passed = success and "SUCCESS" in stdout
        test.message = "Model utils imported successfully" if test.passed else "Model utils import failed"
        
        if not test.passed:
            test.error_details = stdout + stderr
            self.recommendations.append(FixRecommendation(
                issue="FSDP model utils import failed",
                severity="high",
                recommendation="Ensure src/ directory is copied to /fsdp in Dockerfile",
                code_example="COPY src/ /fsdp/"
            ))
        
        return test
    
    def test_model_config_creation(self) -> TestCase:
        """Test model configuration creation."""
        test = TestCase(
            name="model_config",
            category="model",
            description="Create model configuration"
        )
        
        code = """
import sys
sys.path.insert(0, '/fsdp')

from model_utils.train_utils import get_model_config

class TestArgs:
    model_type = 'llama_v3'
    max_context_width = 128
    num_key_value_heads = 2
    intermediate_size = 8192
    hidden_width = 512
    num_layers = 2
    num_heads = 8
    vocab_size = 32000
    initializer_range = 0.02
    resid_pdrop = 0.1
    embd_pdrop = 0.1
    attn_pdrop = 0.1
    summary_first_pdrop = 0.1
    rotary_pct = 0.25
    rotary_emb_base = 10000

args = TestArgs()
config = get_model_config(args)

print(f"Config created: hidden={config.hidden_size}, layers={config.num_hidden_layers}")
print("SUCCESS")
"""
        
        success, stdout, stderr = self._run_in_container(code)
        test.passed = success and "SUCCESS" in stdout
        test.message = "Model config created" if test.passed else "Model config creation failed"
        
        if not test.passed:
            test.error_details = stdout + stderr
        
        return test
    
    def test_model_instantiation(self) -> TestCase:
        """Test model instantiation."""
        test = TestCase(
            name="model_instantiation",
            category="model",
            description="Instantiate model from config"
        )
        
        code = """
import sys
sys.path.insert(0, '/fsdp')

import torch
from transformers import AutoModelForCausalLM
from model_utils.train_utils import get_model_config, compute_num_params

class TestArgs:
    model_type = 'llama_v3'
    max_context_width = 128
    num_key_value_heads = 2
    intermediate_size = 8192
    hidden_width = 512
    num_layers = 2
    num_heads = 8
    vocab_size = 32000
    initializer_range = 0.02
    resid_pdrop = 0.1
    embd_pdrop = 0.1
    attn_pdrop = 0.1
    summary_first_pdrop = 0.1
    rotary_pct = 0.25
    rotary_emb_base = 10000

args = TestArgs()
config = get_model_config(args)
model = AutoModelForCausalLM.from_config(config)
num_params = compute_num_params(model)

print(f"Model created: {num_params:,} parameters ({num_params*1e-6:.1f}M)")
print("SUCCESS")
"""
        
        success, stdout, stderr = self._run_in_container(code)
        test.passed = success and "SUCCESS" in stdout
        
        if test.passed:
            # Extract parameter count
            for line in stdout.split('\n'):
                if 'parameters' in line:
                    test.message = line.strip()
                    break
        else:
            test.message = "Model instantiation failed"
            test.error_details = stdout + stderr
            self.recommendations.append(FixRecommendation(
                issue="Model instantiation failed",
                severity="high",
                recommendation="Check model configuration and available memory",
                documentation_link="https://huggingface.co/docs/transformers"
            ))
        
        return test
    
    def test_forward_pass(self) -> TestCase:
        """Test model forward pass."""
        test = TestCase(
            name="forward_pass",
            category="model",
            description="Execute forward pass"
        )
        
        code = """
import sys
sys.path.insert(0, '/fsdp')

import torch
from transformers import AutoModelForCausalLM
from model_utils.train_utils import get_model_config

class TestArgs:
    model_type = 'llama_v3'
    max_context_width = 128
    num_key_value_heads = 2
    intermediate_size = 8192
    hidden_width = 512
    num_layers = 2
    num_heads = 8
    vocab_size = 32000
    initializer_range = 0.02
    resid_pdrop = 0.1
    embd_pdrop = 0.1
    attn_pdrop = 0.1
    summary_first_pdrop = 0.1
    rotary_pct = 0.25
    rotary_emb_base = 10000

args = TestArgs()
config = get_model_config(args)
model = AutoModelForCausalLM.from_config(config)

# Test forward pass
dummy_input = torch.randint(0, args.vocab_size, (1, 10))
with torch.no_grad():
    output = model(input_ids=dummy_input, labels=dummy_input)

loss = output.loss.item()
print(f"Forward pass successful: loss={loss:.4f}")
print("SUCCESS")
"""
        
        success, stdout, stderr = self._run_in_container(code)
        test.passed = success and "SUCCESS" in stdout
        test.message = "Forward pass executed" if test.passed else "Forward pass failed"
        
        if not test.passed:
            test.error_details = stdout + stderr
        
        return test
    
    def run_tests(self, level: str = "standard") -> List[TestCase]:
        """Run test suite based on level."""
        self.logger.section(f"Running Tests (Level: {level})")
        
        # Always run basic tests
        self.tests.append(self.test_imports_basic())
        
        if level in ["standard", "full"]:
            self.tests.append(self.test_imports_versions())
            self.tests.append(self.test_cuda_availability())
            self.tests.append(self.test_model_utils_import())
            self.tests.append(self.test_model_config_creation())
            self.tests.append(self.test_model_instantiation())
        
        if level == "full":
            self.tests.append(self.test_forward_pass())
        
        return self.tests
    
    def get_summary(self) -> Dict:
        """Get test summary."""
        passed = sum(1 for t in self.tests if t.passed)
        failed = sum(1 for t in self.tests if not t.passed)
        
        return {
            'total': len(self.tests),
            'passed': passed,
            'failed': failed,
            'success_rate': (passed / len(self.tests) * 100) if self.tests else 0,
            'recommendations_count': len(self.recommendations)
        }
    
    def generate_report(self) -> Dict:
        """Generate complete test report."""
        return {
            'image': self.image_name,
            'timestamp': datetime.now().isoformat(),
            'summary': self.get_summary(),
            'tests': [asdict(t) for t in self.tests],
            'recommendations': [asdict(r) for r in self.recommendations]
        }


class ImageTester:
    """Main image tester."""
    
    def __init__(self, args):
        self.args = args
        self.logger = create_logger('docker-image-tester', verbose=args.verbose)
        self.docker = DockerClient(use_sudo=args.use_sudo)
    
    def get_image_to_test(self) -> str:
        """Determine which image to test."""
        if self.args.image:
            return self.args.image
        
        # Try to find recently built image
        # This would check for the most recent local image
        self.logger.info("No image specified, looking for recent builds...")
        return "pytorch-fsdp:latest"  # Default fallback
    
    def run(self) -> Dict:
        """Run test workflow."""
        self.logger.section("Docker Image Tester")
        
        image_name = self.get_image_to_test()
        self.logger.info(f"Testing image: {image_name}")
        self.logger.info(f"Test level: {self.args.level}")
        
        # Create test suite
        suite = TestSuite(image_name, self.docker, self.logger)
        
        # Run tests
        suite.run_tests(self.args.level)
        
        # Print results
        self.logger.section("Test Results")
        for test in suite.tests:
            icon = "✅" if test.passed else "❌"
            self.logger.info(f"{icon} {test.name}: {test.message}")
        
        # Print recommendations
        if suite.recommendations:
            self.logger.section("Fix Recommendations")
            for rec in suite.recommendations:
                icon = {"critical": "🚨", "high": "❌", "medium": "⚠️", "low": "ℹ️"}.get(rec.severity, "•")
                self.logger.info(f"{icon} [{rec.severity.upper()}] {rec.issue}")
                self.logger.info(f"   Recommendation: {rec.recommendation}")
                if rec.code_example:
                    self.logger.info(f"   Example: {rec.code_example}")
        
        # Generate report
        report = suite.generate_report()
        summary = suite.get_summary()
        
        self.logger.section("Test Summary")
        self.logger.info(f"Total: {summary['total']}")
        self.logger.success(f"Passed: {summary['passed']}")
        if summary['failed'] > 0:
            self.logger.error(f"Failed: {summary['failed']}")
        self.logger.info(f"Success rate: {summary['success_rate']:.1f}%")
        
        # Save report
        if self.args.generate_report:
            os.makedirs(self.args.output_dir, exist_ok=True)
            report_path = os.path.join(
                self.args.output_dir,
                f"test-report-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
            )
            with open(report_path, 'w') as f:
                json.dump(report, f, indent=2)
            self.logger.success(f"Report saved: {report_path}")
            report['report_path'] = report_path
        
        return report


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Test Docker image')
    parser.add_argument('--image', default='', help='Image name to test')
    parser.add_argument('--level', default='standard', choices=['quick', 'standard', 'full'],
                       help='Test level')
    parser.add_argument('--generate_report', type=lambda x: x.lower() == 'true',
                       default=True, help='Generate test report')
    parser.add_argument('--output_dir', default='./test-reports', help='Output directory')
    parser.add_argument('--verbose', type=lambda x: x.lower() == 'true',
                       default=True, help='Verbose output')
    parser.add_argument('--use_sudo', type=lambda x: x.lower() == 'true',
                       default=False, help='Use sudo')
    
    args = parser.parse_args()
    
    tester = ImageTester(args)
    result = tester.run()
    
    # Output result
    print(f"\nRESULT_JSON:{json.dumps(result)}")
    
    # Exit code based on success
    summary = result.get('summary', {})
    sys.exit(0 if summary.get('failed', 0) == 0 else 1)


if __name__ == '__main__':
    main()
