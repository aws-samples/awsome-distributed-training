# Train Evolutionary Scale Models (ESM) with BioNemo

[NVIDIA BioNeMo](https://docs.nvidia.com/bionemo-framework/latest/) is a domain-specific machine learning framework for training and using foundation models for biology. This includes models for analyzing proteins, small molecules, and other biological molecules. NVIDIA first announced it in [September 2022](https://nvidianews.nvidia.com/news/nvidia-launches-large-language-model-cloud-services-to-advance-ai-and-digital-biology) and released a more comprehensive version on DGX cloud at [GTC 2023](https://nvidianews.nvidia.com/news/nvidia-unveils-large-language-models-and-generative-ai-services-to-advance-life-sciences-r-d). The GTC 2023 release included two main capabilities:
1. A NeMo-based training framework to enable ML teams to create training and inference jobs via Python scripts. submitted via DGX-hosted notebooks
2. A web application that enabled scientists to create inference jobs and visualize output data.

|Num|                                    BioNeMo Model Support                                     |
|:-:|:--------------------------------------------------------------------------------------------:|
| 1 |      [ESM-1nv](https://docs.nvidia.com/bionemo-framework/latest/models/esm1-nv.html)         |
| 2 |      [ESM-2nv](https://docs.nvidia.com/bionemo-framework/latest/models/esm2-nv.html)         |
| 3 |      [MegaMolBART](https://docs.nvidia.com/bionemo-framework/latest/models/megamolbart.html) |
| 4 |      [DiffDock](https://docs.nvidia.com/bionemo-framework/latest/models/diffdock.html)       |
| 5 |      [EquiDock](https://docs.nvidia.com/bionemo-framework/latest/models/equidock.html)       |
| 6 |      [ProtT5nv](https://docs.nvidia.com/bionemo-framework/latest/models/prott5nv.html)       |


This project provides a guide to run [Nvidia's BioNemo](https://docs.nvidia.com/bionemo-framework/latest/index.html) and pretrain the popular [ESM models](https://github.com/facebookresearch/esm) specifically the [ESM1nv](https://docs.nvidia.com/bionemo-framework/latest/notebooks/model_training_esm1nv.html) model. We provide guides for Slurm (Kubernetes guide is coming soon!). For detailed instructions, proceed to the [slurm](slurm) or [kubernetes](kubernetes) subdirectory.


## Prerequisites

You must have access to the bionemo container. To get the access to BioNeMo, visit the [information website](https://www.nvidia.com/en-us/clara/bionemo/).

## Build container


```bash
docker build -t bionemo:latest -f bionemo.Dockerfile .
```