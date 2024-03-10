# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import os
from tools.datasets.corpora import maybe_download_gpt2_tokenizer_data, DataDownloader
import argparse

class C4(DataDownloader):
    name = "c4"
    urls = [
        f"https://data.together.xyz/redpajama-data-1T/v1.0.0/c4/c4-train.{i:05}-of-01024.jsonl"
        for i in range(1024)
    ]

class C4Subset(DataDownloader):
    name = "c4_openwebtext"
    urls = [
        f"https://data.together.xyz/redpajama-data-1T/v1.0.0/c4/c4-train.{i:05}-of-01024.jsonl"
        for i in range(4)
    ]


DATA_DOWNLOADERS = {
    "c4": C4,
    "c4_subset": C4Subset,
}

def prepare_dataset(
    dataset_name: str,
    tokenizer_type: str = None,
    data_dir: str = None,
    vocab_file: str = None,
    merge_file: str = None,
    force_redownload: bool = None,
    num_workers: int = None,
):
    """
    Downloads + tokenizes a dataset in the registry (dataset_name) and saves output .npy files to data_dir.
    Adapted from https://github.com/EleutherAI/gpt-neox/blob/main/tools/datasets/corpora.py#L330
    """
    if data_dir is None:
        data_dir = os.environ.get("DATA_DIR", "./data")
    os.makedirs(data_dir, exist_ok=True)
    maybe_download_gpt2_tokenizer_data(tokenizer_type, data_dir)
    DownloaderClass = DATA_DOWNLOADERS.get(dataset_name.lower(), None)
    if DownloaderClass is None:
        raise NotImplementedError(
            f'Dataset "{dataset_name}" not recognized - please choose from {list(DATA_DOWNLOADERS.keys())}'
        )
    elif DownloaderClass == "pass":
        # pass on building dataset (for unit tests)
        pass
    else:
        num_workers = 1 if dataset_name == "enwik8" else num_workers
        d = DownloaderClass(
            tokenizer_type=tokenizer_type,
            vocab_file=vocab_file,
            merge_file=merge_file,
            data_dir=data_dir,
            force_redownload=force_redownload,
            num_workers=num_workers,
        )
        d.prepare()

"""
Code below is adapted from 
https://github.com/EleutherAI/gpt-neox/blob/main/prepare_data.py
"""

TOKENIZER_CHOICES = [
    "HFGPT2Tokenizer",
    "HFTokenizer",
    "GPT2BPETokenizer",
    "CharLevelTokenizer",
    "TiktokenTokenizer",
    "SPMTokenizer",
]
DATASET_CHOICES = [i for i in DATA_DOWNLOADERS.keys() if i != "pass"]


def get_args():
    parser = argparse.ArgumentParser(description="Download & preprocess neox datasets")
    parser.add_argument(
        "dataset",
        nargs="?",
        default="enwik8",
        help="name of dataset to download.",
        choices=DATASET_CHOICES,
    )
    parser.add_argument(
        "-t",
        "--tokenizer",
        default="GPT2BPETokenizer",
        choices=TOKENIZER_CHOICES,
        help=f'Type of tokenizer to use - choose from {", ".join(TOKENIZER_CHOICES)}',
    )
    parser.add_argument(
        "-d",
        "--data-dir",
        default=None,
        help=f"Directory to which to download datasets / tokenizer "
        f"files - defaults to ./data",
    )
    parser.add_argument(
        "-v", "--vocab-file", default=None, help=f"Tokenizer vocab file (if required)"
    )
    parser.add_argument(
        "-m", "--merge-file", default=None, help=f"Tokenizer merge file (if required)"
    )
    parser.add_argument(
        "-f",
        "--force-redownload",
        dest="force_redownload",
        default=False,
        action="store_true",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = get_args()
    prepare_dataset(
        dataset_name=args.dataset,
        tokenizer_type=args.tokenizer,
        data_dir=args.data_dir,
        vocab_file=args.vocab_file,
        merge_file=args.merge_file,
        force_redownload=args.force_redownload,
    )