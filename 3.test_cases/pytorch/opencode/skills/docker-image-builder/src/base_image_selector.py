#!/usr/bin/env python3
"""
Intelligent base image selector for PyTorch/CUDA compatibility.
"""

from typing import Optional, List, Dict
from dataclasses import dataclass


@dataclass
class BaseImage:
    """Represents a Docker base image."""
    image: str
    pytorch_version: str
    cuda_version: str
    python_version: str
    size_mb: int
    features: List[str]


class BaseImageSelector:
    """Selects optimal base images based on requirements."""
    
    # Curated list of stable PyTorch base images
    AVAILABLE_IMAGES = [
        BaseImage(
            image="pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime",
            pytorch_version="2.5.1",
            cuda_version="12.4",
            python_version="3.11",
            size_mb=8500,
            features=["cuda", "cudnn", "runtime"]
        ),
        BaseImage(
            image="pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime",
            pytorch_version="2.4.1",
            cuda_version="12.1",
            python_version="3.11",
            size_mb=8200,
            features=["cuda", "cudnn", "runtime"]
        ),
        BaseImage(
            image="pytorch/pytorch:2.3.1-cuda12.1-cudnn8-runtime",
            pytorch_version="2.3.1",
            cuda_version="12.1",
            python_version="3.11",
            size_mb=8000,
            features=["cuda", "cudnn", "runtime"]
        ),
        BaseImage(
            image="pytorch/pytorch:2.2.2-cuda12.1-cudnn8-runtime",
            pytorch_version="2.2.2",
            cuda_version="12.1",
            python_version="3.11",
            size_mb=7800,
            features=["cuda", "cudnn", "runtime"]
        ),
        BaseImage(
            image="pytorch/pytorch:2.1.2-cuda12.1-cudnn8-runtime",
            pytorch_version="2.1.2",
            cuda_version="12.1",
            python_version="3.10",
            size_mb=7500,
            features=["cuda", "cudnn", "runtime"]
        ),
    ]
    
    def __init__(self):
        self.images = self.AVAILABLE_IMAGES
    
    def select(
        self,
        pytorch_version: Optional[str] = None,
        cuda_version: Optional[str] = None,
        python_version: Optional[str] = None,
        minimize_size: bool = False,
        require_features: Optional[List[str]] = None
    ) -> Optional[BaseImage]:
        """Select best matching base image."""
        
        candidates = self.images.copy()
        
        # Filter by PyTorch version
        if pytorch_version:
            candidates = [
                img for img in candidates
                if img.pytorch_version.startswith(pytorch_version)
            ]
        
        # Filter by CUDA version
        if cuda_version:
            candidates = [
                img for img in candidates
                if img.cuda_version == cuda_version
            ]
        
        # Filter by Python version
        if python_version:
            candidates = [
                img for img in candidates
                if img.python_version.startswith(python_version)
            ]
        
        # Filter by required features
        if require_features:
            candidates = [
                img for img in candidates
                if all(f in img.features for f in require_features)
            ]
        
        if not candidates:
            return None
        
        # Sort by preference
        if minimize_size:
            candidates.sort(key=lambda x: x.size_mb)
        else:
            # Prefer newer PyTorch versions
            candidates.sort(
                key=lambda x: [int(n) for n in x.pytorch_version.split('.')],
                reverse=True
            )
        
        return candidates[0]
    
    def get_compatible_images(
        self,
        pytorch_version: str
    ) -> List[BaseImage]:
        """Get all images compatible with a PyTorch version."""
        major_minor = '.'.join(pytorch_version.split('.')[:2])
        
        return [
            img for img in self.images
            if img.pytorch_version.startswith(major_minor)
        ]
    
    def get_recommendation(
        self,
        requirements: Dict[str, str]
    ) -> Optional[str]:
        """Get recommended base image from requirements."""
        
        # Extract torch version from requirements
        torch_ver = requirements.get('torch', '')
        
        if torch_ver:
            # Find compatible image
            image = self.select(pytorch_version=torch_ver)
            if image:
                return image.image
        
        # Default to latest stable
        return self.images[0].image


def main():
    """CLI for testing base image selector."""
    import sys
    
    selector = BaseImageSelector()
    
    if len(sys.argv) > 1:
        pytorch_ver = sys.argv[1]
        image = selector.select(pytorch_version=pytorch_ver)
        
        if image:
            print(f"Recommended: {image.image}")
            print(f"  PyTorch: {image.pytorch_version}")
            print(f"  CUDA: {image.cuda_version}")
            print(f"  Python: {image.python_version}")
            print(f"  Size: ~{image.size_mb} MB")
        else:
            print(f"No compatible image found for PyTorch {pytorch_ver}")
    else:
        print("Available base images:")
        for img in selector.images:
            print(f"  {img.image}")


if __name__ == '__main__':
    main()
