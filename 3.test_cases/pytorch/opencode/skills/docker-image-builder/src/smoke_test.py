#!/usr/bin/env python3
"""
Smoke tests for Docker images.
Quick validation that built images work correctly.
"""

import subprocess
import json
from typing import Tuple, List, Dict
from dataclasses import dataclass


@dataclass
class TestResult:
    """Result of a smoke test."""
    name: str
    passed: bool
    message: str
    duration_ms: int


class SmokeTester:
    """Runs smoke tests on Docker images."""
    
    def __init__(self, image_name: str, use_sudo: bool = False):
        self.image_name = image_name
        self.use_sudo = use_sudo
        self.results = []
    
    def _run_in_container(self, command: List[str]) -> Tuple[int, str, str]:
        """Run command in container."""
        docker_cmd = ['sudo'] if self.use_sudo else []
        docker_cmd.extend(['docker', 'run', '--rm', self.image_name])
        docker_cmd.extend(command)
        
        result = subprocess.run(
            docker_cmd,
            capture_output=True,
            text=True,
            timeout=60
        )
        
        return result.returncode, result.stdout, result.stderr
    
    def test_python_imports(self) -> TestResult:
        """Test basic Python imports."""
        test_code = """
import sys
errors = []

try:
    import torch
    print(f"torch:{torch.__version__}")
except Exception as e:
    errors.append(f"torch: {e}")

try:
    import transformers
    print(f"transformers:{transformers.__version__}")
except Exception as e:
    errors.append(f"transformers: {e}")

try:
    import datasets
    print(f"datasets:{datasets.__version__}")
except Exception as e:
    errors.append(f"datasets: {e}")

if errors:
    print("ERRORS:" + "|".join(errors))
    sys.exit(1)
print("SUCCESS")
"""
        
        returncode, stdout, stderr = self._run_in_container(
            ['python', '-c', test_code]
        )
        
        output = stdout + stderr
        
        if returncode == 0 and "SUCCESS" in output:
            return TestResult(
                name="python_imports",
                passed=True,
                message="All imports successful",
                duration_ms=0
            )
        else:
            error_msg = "Import failed"
            if "ERRORS:" in output:
                error_msg = output.split("ERRORS:")[1].split("|")[0]
            
            return TestResult(
                name="python_imports",
                passed=False,
                message=error_msg,
                duration_ms=0
            )
    
    def test_cuda_available(self) -> TestResult:
        """Test CUDA availability."""
        test_code = """
import torch
if torch.cuda.is_available():
    print(f"CUDA:{torch.version.cuda}")
    print(f"GPUs:{torch.cuda.device_count()}")
    print("SUCCESS")
else:
    print("CUDA not available (CPU-only)")
    print("SUCCESS")
"""
        
        returncode, stdout, stderr = self._run_in_container(
            ['python', '-c', test_code]
        )
        
        if returncode == 0 and "SUCCESS" in stdout:
            return TestResult(
                name="cuda_available",
                passed=True,
                message="CUDA check passed",
                duration_ms=0
            )
        else:
            return TestResult(
                name="cuda_available",
                passed=False,
                message="CUDA check failed",
                duration_ms=0
            )
    
    def test_model_utils_import(self) -> TestResult:
        """Test FSDP model utils import."""
        test_code = """
import sys
sys.path.insert(0, '/fsdp')

try:
    from model_utils.arguments import parse_args
    from model_utils.train_utils import get_model_config
    print("SUCCESS")
except Exception as e:
    print(f"FAILED: {e}")
    sys.exit(1)
"""
        
        returncode, stdout, stderr = self._run_in_container(
            ['python', '-c', test_code]
        )
        
        if returncode == 0 and "SUCCESS" in stdout:
            return TestResult(
                name="model_utils_import",
                passed=True,
                message="Model utils import successful",
                duration_ms=0
            )
        else:
            return TestResult(
                name="model_utils_import",
                passed=False,
                message="Model utils import failed",
                duration_ms=0
            )
    
    def run_all_tests(self) -> List[TestResult]:
        """Run all smoke tests."""
        self.results = []
        
        self.results.append(self.test_python_imports())
        self.results.append(self.test_cuda_available())
        self.results.append(self.test_model_utils_import())
        
        return self.results
    
    def all_passed(self) -> bool:
        """Check if all tests passed."""
        return all(r.passed for r in self.results)
    
    def generate_report(self) -> Dict:
        """Generate test report."""
        return {
            'image': self.image_name,
            'total_tests': len(self.results),
            'passed': sum(1 for r in self.results if r.passed),
            'failed': sum(1 for r in self.results if not r.passed),
            'results': [
                {
                    'name': r.name,
                    'passed': r.passed,
                    'message': r.message
                }
                for r in self.results
            ]
        }


def main():
    """CLI for testing smoke tester."""
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: smoke_test.py <image_name>")
        sys.exit(1)
    
    image_name = sys.argv[1]
    tester = SmokeTester(image_name)
    
    print(f"Running smoke tests on {image_name}...")
    results = tester.run_all_tests()
    
    for result in results:
        icon = "✅" if result.passed else "❌"
        print(f"{icon} {result.name}: {result.message}")
    
    report = tester.generate_report()
    print(f"\nSummary: {report['passed']}/{report['total_tests']} passed")
    
    sys.exit(0 if tester.all_passed() else 1)


if __name__ == '__main__':
    main()
