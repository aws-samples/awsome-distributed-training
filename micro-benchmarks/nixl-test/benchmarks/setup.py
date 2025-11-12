from setuptools import setup, find_packages

setup(
    name="dynamo-benchmarks",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        "torch",
        "numpy",
        "pytest",
    ],
    entry_points={
        'console_scripts': [
            'dynamo-bench=benchmarks.cli:main',
        ],
    },
)
