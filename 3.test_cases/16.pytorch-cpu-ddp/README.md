# PyTorch DDP on CPU <!-- omit in toc -->

Isolated environments are crucial for reproducible machine learning because they encapsulate specific software versions and dependencies, ensuring models are consistently retrainable, shareable, and deployable without compatibility issues.

[Anaconda](https://www.anaconda.com/) leverages conda environments to create distinct spaces for projects, allowing different Python versions and libraries to coexist without conflicts by isolating updates to their respective environments. [Docker](https://www.docker.com/), a containerization platform, packages applications and their dependencies into containers, ensuring they run seamlessly across any Linux server by providing OS-level virtualization and encapsulating the entire runtime environment.

This example showcases CPU [PyTorch DDP](https://pytorch.org/tutorials/beginner/ddp_series_theory.html) environment setup utilizing these approaches for efficient environment management.

 We will provide guides for both Slurm and Kubernetes. However, please note that the Conda example is only compatible with Slurm. For detailed instructions, proceed to the `slurm` or `kubernetes` subdirectory. ```
