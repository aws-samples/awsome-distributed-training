#!/usr/bin/env python3

import os
import argparse
import logging
import requests
import random
import subprocess
from datetime import datetime
import random

try:
    from simple_slurm import Slurm
except Exception as e:
    os.system("sudo pip3 install simple-slurm")
    print("Please re-run")
    raise e

class State():
    pass

state = State()
artifact_home = "/home/ubuntu/jonghyl/aws_nvidia_gpu_distributed_training/scripts/artifacts"
mount_home = "/workspace/mount_dir"

ec2_topo_enabled = True
ec2_topo_regen = False

# Dictionary for each config
docker_config = {
    "EFA_INSTALLER_VERSION":        "1.34.0-dev",
    "AWS_OFI_NCCL_VERSION":         "v1.9.2-aws",
    "NCCL_TESTS_VERSION":           "v2.13.9",
    "NCCL_VERSION":                 "2.22.3",
    "CUDA_VER":                     "12.2",
    "DOCKER_IMAGE_TAG":             "",
}

slurm_config = {
    "NUM_NODE":                     "160",
    "TEST_ITERATION":               "5",
    "NUM_PROCESS_PER_NODE":         "8",
}

env_config = {
    "NCCL_DEBUG":                   "INFO",
    # "NCCL_DEBUG_SUBSYS":          "TUNING",
    "FI_PROVIDER":                  "efa",
    "FI_EFA_USE_DEVICE_RDMA":       "1",
    "FI_EFA_FORK_SAFE":             "1",
    "NCCL_TESTS_SPLIT_MASK":        "0x0",
    "NCCL_BUFFSIZE":                "8388608",
    "NCCL_P2P_NET_CHUNKSIZE":       "524288",
    # "NCCL_ALGO":                  "Ring", #"Ring,Tree,NVLSTree",
    # "NCCL_TUNER_PLUGIN":          "/opt/aws-ofi-nccl/install/lib/libnccl-ofi-tuner.so",
}

nccl_config = {
    "MIN_BYTE":                     "512K",
    "MAX_BYTE":                     "32G",
    "STEP_FACTOR":                  "2",
    "NUM_GPU_PER_THREAD":           "1",
    "CHECK_ITERATION_COUNT":        "0",
    "NUMBER_OF_ITERATION":          "100",
}

test_cases = [
    "all_reduce_perf",
    # "all_gather_perf",
    # "reduce_scatter_perf",
    # "sendrecv_perf",
    # "alltoall_perf",
]

def parse_args():
    argparser = argparse.ArgumentParser(epilog="AWS EC2 nccl test runner")
    argparser.add_argument("-w", "--nodelist", dest='nodelist')
    argparser.add_argument("-r", "--ranktopo", dest='ranktopo', action='store_true')
    argparser.add_argument("-m", "--machinefile", dest='machinefile')
    argparser.add_argument("-b", "--buffersize", dest='buffersize')
    argparser.add_argument("-c", "--chunksize", dest='chunksize')
    argparser.add_argument("-s", "--sanity", dest='sanity', action='store_true')
    return argparser.parse_args()

def logger_init():
    logging.basicConfig(filename="{}/nccl-test-{}.log".format(state.log_folder, state.dt_str),
                        level=logging.INFO,
                        format='%(asctime)s %(levelname)-8s %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S')

    logging.info("-------------------------")
    logging.info("Starting nccl test runner")

def init():
    state.log_folder = "./logs"
    state.test_file_base = "/opt/nccl-tests/build"
    state.dt_str = datetime.now().strftime("%Y%m%dT%HZ")
    dt_str_detail = datetime.now().strftime("%m%dT%H%M%SZ")
    state.ranktopo_file = ""

    if state.args.ranktopo and state.args.machinefile:
        print("-r and -m cannot be used simutaneously")
        exit(1)

    if state.args.sanity == True:
        state.dt_str_detail = "{}-{}".format(dt_str_detail, state.start_node)
    else:
        state.dt_str_detail = "{}-{}".format(dt_str_detail, state.test)

    state.artifact_folder = "./artifacts/run-{}".format(state.dt_str_detail)

    if not os.path.exists(state.artifact_folder):
        os.makedirs(state.artifact_folder)

    if not os.path.exists(state.log_folder):
        os.makedirs(state.log_folder)

    state.docker_image_tag = "{}-{}-{}-{}".format(
        docker_config["EFA_INSTALLER_VERSION"],
        docker_config["AWS_OFI_NCCL_VERSION"],
        docker_config["NCCL_TESTS_VERSION"],
        docker_config["NCCL_VERSION"],
    )
    state.docker_image_file = "/fsx/nccl-{}.sqsh".format(state.docker_image_tag)
    docker_config["DOCKER_IMAGE_TAG"] = state.docker_image_tag
    state.run_id = "nccl-test-{}-{}".format(state.docker_image_tag, state.dt_str_detail)
    print("Run id: run-{}".format(state.dt_str_detail))

    logger_init()
    state.region = get_imds("meta-data/placement/region")
    os.environ["AWS_DEFAULT_REGION"] = state.region

    return state

def print_all_values(input):
    if isinstance(input, dict):
        for key, value in input.items():
            print_all_values(value)
    elif isinstance(input, list):
        for value in input:
            print_all_values(value)
    else:
        print(input)

def generate_config_file(state):
    logging.info("Generating config file")

    if state.args.buffersize:
        print("Overwrite NCCL_BUFFSIZE with {}".format(state.args.buffersize))
        env_config["NCCL_BUFFSIZE"] = state.args.buffersize

    if state.args.chunksize:
        print("Overwrite NCCL_P2P_NET_CHUNKSIZE with {}".format(state.args.chunksize))
        env_config["NCCL_P2P_NET_CHUNKSIZE"] = state.args.chunksize

    # env_config["NCCL_DEBUG_FILE"] = "{}/run-{}/nccl-debug-%h-%p.out".format(mount_home, state.dt_str_detail)
    env_config["NCCL_TOPO_DUMP_FILE"] = "{}/run-{}/nccl-topo-dump.xml".format(mount_home, state.dt_str_detail)
    env_config["NCCL_GRAPH_DUMP_FILE"] = "{}/run-{}/nccl-graph-dump.xml".format(mount_home, state.dt_str_detail)

    if ec2_topo_regen == True:
        rc = os.system("./gen_ec2_topo.sh")
        if rc != 0:
            print("Failed to generate EC2 Topo")
            exit(1)

    wfp = open("{}/{}.config".format(state.artifact_folder, state.run_id), "w")
    wfp.write("----- Docker config -----\n")
    for key in docker_config.keys():
        wfp.write("{}={}\n".format(key, docker_config[key]))

    wfp.write("----- Slurm config -----\n")
    for key in slurm_config.keys():
        wfp.write("{}={}\n".format(key, slurm_config[key]))

    wfp.write("----- Environment variable -----\n")
    for key in env_config.keys():
        wfp.write("{}={}\n".format(key, env_config[key]))

    wfp.write("----- nccl-test config -----\n")
    for key in nccl_config.keys():
        wfp.write("{}={}\n".format(key, nccl_config[key]))

    wfp.write("----- OS env -----\n")
    with open("/etc/os-release", "r") as rfp:
        for line in rfp.readlines():
            wfp.write(line)

    wfp.write("----- Topology -----\n")
    if ec2_topo_enabled == True:
        proc = subprocess.Popen("cat /home/ubuntu/jonghyl/topology.conf", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = proc.communicate()
        wfp.write(stdout.decode())
        wfp.write(stderr.decode())
    else:
        wfp.write("EC2 Topo optimization is not enabled\n")

    wfp.write("----- node list -----\n")
    if state.args.nodelist:
        with open(state.args.nodelist, "r") as rfp:
            for line in rfp.readlines():
                wfp.write(line)

    wfp.write("----- Rank Topology -----\n")
    if state.args.ranktopo:
        with open(state.ranktopo_file, "r") as rfp:
            for line in rfp.readlines():
                wfp.write(line)
    elif state.args.machinefile:
        with open(state.args.machinefile, "r") as rfp:
            for line in rfp.readlines():
                wfp.write(line)
    else:
        wfp.write("nodelist for rank topology was not provided\n")

    wfp.close()
    logging.info("Generated config file")

def generate_docker_image(state):
    if os.path.isfile(state.docker_image_file):
        logging.info("Docker image exist already.")
        return

    logging.info("Generating docker image")
    new_docker_file = "{}/docker-{}.Dockerfile".format(state.artifact_folder, state.docker_image_tag)

    rfp = open("template.Dockerfile", "r")
    wfp = open(new_docker_file, "w")

    # Read template file and replace placeholder with new config values
    for line in rfp.readlines():
        if "PLACEHOLDER_REPLACE" in line:
            key_to_replace = None
            for key in docker_config.keys():
                if key in line:
                    key_to_replace = key
                    break

            if key_to_replace:
                new_line = line.replace("PLACEHOLDER_REPLACE", docker_config[key_to_replace])
                wfp.write(new_line)
        else:
            wfp.write(line)

    wfp.close()
    rfp.close()

    rc = os.system("sudo docker build -t nccl-tests:{} -f {} .".format(state.docker_image_tag, new_docker_file))
    if rc != 0:
        logging.error("Failed to generate docker image")
        exit(rc)

    rc = os.system("sudo enroot import -o {} dockerd://nccl-tests:{}".format(state.docker_image_file, state.docker_image_tag))
    if rc != 0:
        logging.error("Failed to enroot docker image")
        exit(rc)

    logging.info("Generated docker image")

def generate_command_line(state):
    logging.info("Generating command line")
    state.cmdlines = {}

    params = "-b {} -e {} -f {} -g {} -c {} -n {}".format(
        nccl_config["MIN_BYTE"],
        nccl_config["MAX_BYTE"],
        nccl_config["STEP_FACTOR"],
        nccl_config["NUM_GPU_PER_THREAD"],
        nccl_config["CHECK_ITERATION_COUNT"],
        nccl_config["NUMBER_OF_ITERATION"],
    )

    fp = open("{}/{}.config".format(state.artifact_folder, state.run_id), "a")
    fp.write("----- Command lines -----\n")
    test = state.test
    # for test in test_cases:
    nccl_cmdline = "{}/{} {}".format(state.test_file_base, test, params)
    timestamp = "| awk '{ print strftime(\"[\%Y-\%m-\%d \%H:\%M:\%S]\"), $0 }'"
    srun_cmdline_single = "srun -l --container-mounts={}:{} --container-image {} --mpi=pmix {} {}".format(artifact_home, mount_home, state.docker_image_file, nccl_cmdline, timestamp)
    srun_cmdline_loop = "for i in $(seq {}); do sleep 10; {}; done".format(slurm_config["TEST_ITERATION"], srun_cmdline_single)
    state.cmdlines[test] = srun_cmdline_loop
    fp.write("{}\n".format(srun_cmdline_loop))

    fp.close()
    logging.info("Generated command line")

def schedule_sbatch(state):
    logging.info("Executing nccl test")

    for key in state.cmdlines.keys():
        test = key
        cmdline = state.cmdlines[key]

        slurm = Slurm(
            job_name='compute-gpu',
            nodes=int(slurm_config["NUM_NODE"]),
            ntasks_per_node=int(slurm_config["NUM_PROCESS_PER_NODE"]),
            gres="gpu:{}".format(slurm_config["NUM_PROCESS_PER_NODE"]),
            output="{}/{}-{}.out".format(state.artifact_folder, state.run_id, test),
            error="{}/{}-{}.err".format(state.artifact_folder, state.run_id, test),
            # reservation="ubuntu_1",
        )

        # Set env variables
        slurm.add_cmd("export AWS_DEFAULT_REGION={}".format(state.region))
        for key in env_config.keys():
            slurm.add_cmd("export {}={}".format(key, env_config[key]))

        # Set node list
        if state.args.nodelist:
            # Example) nodelist="compute-gpu-st-p5-1,compute-gpu-st-p5-3"
            # Example) nodelist="/home/ec2-user/nodelist.txt"
            slurm.add_arguments(nodelist=state.args.nodelist)

        # Record host: instance-id mapping
        # Example) compute-gpu-st-p5-1: i-02b1736eb38043ed9c
        slurm.add_cmd('echo "Host mapping"')

        mpirun_command = "mpirun -N 1 -n {} bash -c 'echo $(hostname): $(cat /sys/devices/virtual/dmi/id/board_asset_tag)'".format(slurm_config["NUM_NODE"])
        if state.ranktopo_file:
            mpirun_command += " -machinefile {}".format(state.ranktopo_file)
        elif state.args.machinefile:
            mpirun_command += " -machinefile {}".format(state.args.machinefile)

        slurm.add_cmd(mpirun_command)
        slurm.add_cmd('echo "Test start time: $(date)"')

        logging.info("Dumping slurm configuration for {}".format(test))
        logging.info(slurm)
        logging.info(cmdline)
        logging.info(mpirun_command)

        fp = open("{}/{}.config".format(state.artifact_folder, state.run_id), "a")
        fp.write("----- Slurm bash -----\n")
        fp.write("{}\n".format(slurm))
        fp.close()

        slurm.sbatch(cmdline)

    logging.info("Executed nccl test")

def get_imds(path):
    response = requests.put("http://169.254.169.254/latest/api/token", headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"})
    response = requests.get("http://169.254.169.254/latest/{}".format(path), headers={"X-aws-ec2-metadata-token": response.text})
    return response.text

def generate_rank_topo_list(state):
    # Create node list for rank topology
    if state.args.ranktopo:
        nodelist_file_input = state.args.nodelist
        nodelist_file_output = "{}/nccl-test-nodelist-{}-rank-topology".format(state.artifact_folder, state.run_id)
        os.system("cat {}".format(nodelist_file_input))
        # Example) compute-gpu-st-p5-1 compute-gpu-st-p5-2 compute-gpu-st-p5-3 compute-gpu-st-p5-4
        os.system('export AWS_DEFAULT_REGION=$(TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` && curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/placement/region)')
        os.system("python3 hostfile-topologify --input {} --output {}".format(nodelist_file_input, nodelist_file_output))
        print("Generated {}".format(nodelist_file_output))
        os.system("cat {}".format(nodelist_file_output))
        state.ranktopo_file = nodelist_file_output

if __name__ == '__main__':
    state.args = parse_args()

    if state.args.sanity == True:
        state.test = "all_reduce_perf"
        group_size = 4
        num_of_node = 292

        ins_list = [*range(1, num_of_node+1)]

        shuffle = False
        if shuffle == True:
            random.shuffle(ins_list)

        idx = 1
        while idx <= len(ins_list):
            slurm_config["NUM_NODE"] = group_size
            slurm_config["TEST_ITERATION"] = "1"
            nccl_config["MIN_BYTE"] = "16G"
            nccl_config["MAX_BYTE"] = "16G"
            state.args.nodelist = "./sanity_node"
            compute_node_prefix = "gpu-dy-p5"
            state.start_node = "{}-{}".format(group_size, idx)

            with open(state.args.nodelist, "w") as wfp:
                for i in range(group_size):
                    wfp.write("{}-{}\n".format(compute_node_prefix, ins_list[idx-1]))
                    idx = idx + 1
                    if idx > len(ins_list):
                        print("Exceed cluster size. Stop right here")
                        break

            state = init()

            # Generate configuration provided from command line
            generate_config_file(state)

            # Generate rank topology optimized nodelist
            generate_rank_topo_list(state)

            # Generate docker image
            generate_docker_image(state)

            # Generate command line to execute
            generate_command_line(state)

            # Schedule batch
            schedule_sbatch(state)
    else:
        for test in test_cases:
            state.test = test

            if test == "alltoall_perf":
                # Do not run alltoall when split mask is set
                if env_config["NCCL_TESTS_SPLIT_MASK"] != "0x0":
                    continue

            state = init()

            # Generate rank topology optimized nodelist
            generate_rank_topo_list(state)

            # Generate configuration provided from command line
            generate_config_file(state)

            # Generate docker image
            generate_docker_image(state)

            # Generate command line to execute
            generate_command_line(state)

            # Schedule batch
            schedule_sbatch(state)


