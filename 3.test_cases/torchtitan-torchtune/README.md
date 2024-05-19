# End-to-End LLM Model Development with Torchtitan and Torchtune <!-- omit in toc -->

This guide demonstrates the comprehensive process of developing a Large Language Model (LLM) from start to finish using [Torchtitan](https://github.com/pytorch/torchtitan) and [Torchtune](https://github.com/pytorch/torchtune). The journey of creating an LLM encompasses five pivotal steps:

![LLMOps](docs/LLMOps.png)

1. **Data Preparation**: The journey begins with the collection and preparation of data for training. This step is crucial as it involves exploring the data's characteristics, performing necessary cleaning, and applying preprocessing techniques to ensure the data is in the right shape for model training.

2. **Pretraining the Language Model**: Next, the language model undergoes pretraining on a vast corpus of text data. This step can be bypassed if starting with an already pretrained model. Pretraining is essential for the model to learn the general patterns and structures of language.

3. **Fine-Tuning**: The pretrained model is then fine-tuned to cater to specific tasks by updating its parameters with a new dataset. This process involves partially retraining the model with samples that exemplify the desired behavior, thus refining the model weights for the particular application.

4. **Evaluation**: Evaluating the LLM's performance is a critical step. It involves using various metrics to assess the model's accuracy and effectiveness. This step is vital for validating new techniques and objectively comparing different model releases.

5. **Deployment**: Upon achieving the desired performance, the model is deployed as an API. This deployment enables the model's integration into applications, making it accessible to users and other systems.

Following these steps allows for the iterative development and refinement of a Large Language Model to meet specific needs and ensure its successful deployment. This guide specifically addresses all steps except the initial data preparation. The pretraining phase is facilitated by Torchtitan, while Torchtune manages the fine-tuning and evaluation phases.


**Torchtitan** is a pioneering library for large-scale LLM training utilizing native PyTorch. It highlights PyTorch's latest distributed training features through a clean, minimalistic codebase.

Characteristics of Torchtitan include:

* User-friendly design, making it easy to understand, use, and extend for various training purposes.
* Minimal modifications required to the model code for applying 1D, 2D, or upcoming 3D parallelism.
* A modular approach over a monolithic codebase, facilitating quick start-ups.

**Torchtune** emerges as a PyTorch-native library dedicated to the easy authoring, fine-tuning, and experimentation with LLMs, proudly announcing its alpha release.

Features of Torchtune encompass:

* Native-PyTorch implementations of renowned LLMs using composable and modular building blocks.
* Straightforward and adaptable training recipes for popular fine-tuning techniques such as LoRA and QLoRA, emphasizing a PyTorch-centric approach without the need for trainers or frameworks.
* YAML configurations for simplifying the setup of training, evaluation, quantization, or inference recipes.
* Comprehensive support for numerous popular dataset formats and prompt templates, ensuring a smooth start to training endeavors.

This directory houses `0.torchtitan-torchtune.dockerfile` alongside this `README.md`. This case study provides examples for two schedulers, Slurm and Kubernetes, with detailed instructions available in the `slurm` or `kubernetes` subdirectories.


