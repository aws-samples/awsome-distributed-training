import argparse

from checkpoint_converter import CheckpointConverterBase


class CheckpointConverterLlama(CheckpointConverterBase):
    pass


if __name__ == "__main__":
    checkpoint_converter = CheckpointConverterLlama()
    parser = checkpoint_converter.get_arg_parser()
    args, _ = parser.parse_known_args()
    checkpoint_converter.run(args)
