#!/bin/bash

python -m venv .testenv

source .testenv/bin/activate

# Install test dependencies
pip install -r test_requirements.txt

# Run the tests
pytest