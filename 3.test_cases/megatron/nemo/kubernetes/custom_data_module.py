import json
import shutil
import numpy as np
from pathlib import Path
from typing import TYPE_CHECKING, Any, Dict, List, Optional
from datasets import load_dataset
from nemo.utils import logging
from nemo.lightning.io.mixin import IOMixin
from nemo.collections.llm.gpt.data.fine_tuning import FineTuningDataModule
from nemo.collections.llm.gpt.data.core import get_dataset_root

if TYPE_CHECKING:
    from nemo.collections.common.tokenizers import TokenizerSpec
    from nemo.collections.llm.gpt.data.packed_sequence import PackedSequenceSpecs


class CustomDataModule(FineTuningDataModule, IOMixin):
    """A data module for fine-tuning on custom dataset.

    This class inherits from the `FineTuningDataModule` class and is specifically designed for fine-tuning models on custom 
    dataset. we'll use "databricks/databricks-dolly-15k" as an example. It handles data download, preprocessing, splitting, and preparing the data
    in a format suitable for training, validation, and testing.

    Args:
        force_redownload (bool, optional): Whether to force re-download the dataset even if it exists locally. Defaults to False.
        delete_raw (bool, optional): Whether to delete the raw downloaded dataset after preprocessing. Defaults to True.
        See FineTuningDataModule for the other args
    """

    def __init__(
        self,
        seq_length: int = 2048,
        tokenizer: Optional["TokenizerSpec"] = None,
        micro_batch_size: int = 4,
        global_batch_size: int = 8,
        rampup_batch_size: Optional[List[int]] = None,
        dataset_name: str = None,
        dataset_dir_name: str = None,
        force_redownload: bool = False,
        delete_raw: bool = True,
        seed: int = 1234,
        memmap_workers: int = 1,
        num_workers: int = 8,
        pin_memory: bool = True,
        persistent_workers: bool = False,
        packed_sequence_specs: Optional["PackedSequenceSpecs"] = None,
        dataset_kwargs: Optional[Dict[str, Any]] = None,
    ):
        self.dataset_name = dataset_name
        self.dataset_dir_name = dataset_dir_name
        self.force_redownload = force_redownload
        self.delete_raw = delete_raw

        super().__init__(
            dataset_root=get_dataset_root(self.dataset_dir_name),
            seq_length=seq_length,
            tokenizer=tokenizer,
            micro_batch_size=micro_batch_size,
            global_batch_size=global_batch_size,
            rampup_batch_size=rampup_batch_size,
            seed=seed,
            memmap_workers=memmap_workers,
            num_workers=num_workers,
            pin_memory=pin_memory,
            persistent_workers=persistent_workers,
            packed_sequence_specs=packed_sequence_specs,
            dataset_kwargs=dataset_kwargs,
        )
    
    def prepare_data(self) -> None:
        # if train file is specified, no need to do anything
        if not self.train_path.exists() or self.force_redownload:
            dset = self._download_data()
            self._preprocess_and_split_data(dset)
        super().prepare_data()

    def _download_data(self):
        logging.info(f"Downloading {self.__class__.__name__}...")
        return load_dataset(
            self.dataset_name,
            cache_dir=str(self.dataset_root),
            download_mode="force_redownload" if self.force_redownload else None,
        )

    def _preprocess_and_split_data(self, dset, train_ratio: float = 0.80, val_ratio: float = 0.15):
        logging.info(f"Preprocessing {self.__class__.__name__} to jsonl format and splitting...")

        test_ratio = 1 - train_ratio - val_ratio
        save_splits = {}
        dataset = dset.get('train')
        split_dataset = dataset.train_test_split(test_size=val_ratio + test_ratio, seed=self.seed)
        split_dataset2 = split_dataset['test'].train_test_split(
            test_size=test_ratio / (val_ratio + test_ratio), seed=self.seed
        )
        save_splits['training'] = split_dataset['train']
        save_splits['validation'] = split_dataset2['train']
        save_splits['test'] = split_dataset2['test']

        for split_name, dataset in save_splits.items():
            output_file = self.dataset_root / f"{split_name}.jsonl"
            with output_file.open("w", encoding="utf-8") as f:
                for example in dataset:
                    context = example["context"].strip()
                    if context != "":
                        # Randomize context and instruction order.
                        context_first = np.random.randint(0, 2) == 0
                        if context_first:
                            instruction = example["instruction"].strip()
                            assert instruction != ""
                            _input = f"{context}\n\n{instruction}"
                            _output = example["response"]
                        else:
                            instruction = example["instruction"].strip()
                            assert instruction != ""
                            _input = f"{instruction}\n\n{context}"
                            _output = example["response"]
                    else:
                        _input = example["instruction"]
                        _output = example["response"]

                    f.write(json.dumps({"input": _input, "output": _output, "category": example["category"]}) + "\n")

            logging.info(f"{split_name} split saved to {output_file}")

        if self.delete_raw:
            for p in self.dataset_root.iterdir():
                if p.is_dir():
                    shutil.rmtree(p)
                elif '.jsonl' not in str(p.name):
                    p.unlink() 