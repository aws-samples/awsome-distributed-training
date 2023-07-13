# Usage
Run `make ami_gpu` or `make ami_cpu` to build AMI for GPU with EFA and CPU supporting [pyxies](https://github.com/NVIDIA/pyxis) (see [here](https://github.com/NVIDIA/enroot/blob/9c6e979059699e93cfc1cce0967b78e54ad0e263/doc/cmd/import.md) to configure [AWS ECR](https://aws.amazon.com/ecr/) authentication out of the box ), while `make docker` builds container to use with GPUs and EFA. Run `make deploy` to deploy test cluster in `./test/cluster.yaml` assuming you have credentials in config file with default profile (`${HOME}/.aws`) and different parameters (AMI, subnets, ssh keys) are updated.
## Notes
* Review `packer-ami.pkr.hcl` for all available variables.
* We are using shared filesystem (`/fsx`) for container cache, set this accordingly to your cluster in `roles/nvidia_enroot_pyxis/templates/enroot.conf` variable `ENROOT_CACHE_PATH`.
* Review variables (dependency versions) in `./roles/*/defaults/main.yml` according to [Ansible directory structure](https://docs.ansible.com/ansible/latest/tips_tricks/sample_setup.html).


# Preflight
Code is in `./preflight` directory. It consists of sanity checks for:
* Nvidia GPUs
* EFA and Nvidia NCCL
* PyTorch
## Notes
* `torch.cuda.nccl.version()` in `preflight/preflight.sh` will return built in version, while searching for `NCCL version` if `NCCL_DEBUG=info` is exported will get preloaded version.


# using Deep Learning AMI
[DLAMI](https://docs.aws.amazon.com/dlami/latest/devguide/what-is-dlami.html) contains common DL dependencies, it can be used with parallel cluster.
We can use following configuration:
```
Build:
  InstanceType: p2.xlarge
  ParentImage: ami-123
```
where `ami-123` is ID of DLAMI of your choice. Run [pcluster build-image](https://docs.aws.amazon.com/parallelcluster/latest/ug/pcluster-v3.html) to add all pcluster dependencies.
