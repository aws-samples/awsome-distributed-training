"""SageMaker environment utils."""
import os

SM_ENV_KEY = "TRAINING_JOB_ARN"


def enable_dummy_sm_env():
    """
    Sets up dummy environment variable
    to handle SageMaker platform guardrail.

    Necessary for both Rubik and Herring.
    """
    if os.environ.get(SM_ENV_KEY, None) is None:
        # Set the SageMaker environment variable to a dummy value
        # if not set.
        os.environ[SM_ENV_KEY] = "0"
