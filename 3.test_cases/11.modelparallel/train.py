"""
Internal Train.py.

Duplicate of train_external.py with the dummy SageMaker environment enabled.
"""
# Set dummy SageMaker env var if not set to pass guardrail
# for Rubik and Herring cluster scripts.
from sm_env_utils import enable_dummy_sm_env
enable_dummy_sm_env()  # needs to be called before torch sagemaker is imported
import train_lib
from arguments import parse_args


def main():
    """Main function to train GPT."""
    args, _ = parse_args()
    train_lib.main(args)


if __name__ == "__main__":
    main()
