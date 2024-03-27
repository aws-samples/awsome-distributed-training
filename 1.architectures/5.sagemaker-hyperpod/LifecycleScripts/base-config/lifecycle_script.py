#!/usr/bin/env python

import argparse
from enum import Enum
import json
import os
import socket
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple


SLURM_CONF = os.getenv("SLURM_CONF", "/opt/slurm/etc/slurm.conf")

class SlurmNodeType(str, Enum):
    HEAD_NODE = "controller"
    LOGIN_NODE = "login"
    COMPUTE_NODE = "compute"


class ExecuteBashScript:
    def __init__(self, script_name: str):
        self.script_name = script_name

    def run(self, *args):
        print(f"Execute script: {self.script_name} {' '.join([str(x) for x in args])}")
        result = subprocess.run(["sudo", "bash", self.script_name, *args])
        result.check_returncode()
        print(f"Script {self.script_name} executed successully")


class ResourceConfig:
    INSTANCE_GROUP_NAME = "Name"
    INSTANCE_NAME = "InstanceName"
    CUSTOMER_IP_ADDRESS = "CustomerIpAddress"

    def __init__(self, path: str):
        with open(path, "r") as f:
            self._config = json.load(f)

    def find_instance_by_address(self, address) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
        for group in self._config["InstanceGroups"]:
            for instance in group["Instances"]:
                if instance.get(ResourceConfig.CUSTOMER_IP_ADDRESS) == address:
                    return group, instance
        return None, None

    def get_list_of_addresses(self, group_name) -> List[str]:
        for group in self._config["InstanceGroups"]:
            if group.get(ResourceConfig.INSTANCE_GROUP_NAME) != group_name:
                continue
            return [i.get(ResourceConfig.CUSTOMER_IP_ADDRESS) for i in group["Instances"]]
        return []


class ProvisioningParameters:
    WORKLOAD_MANAGER_KEY: str = "workload_manager"
    FSX_DNS_NAME: str = "fsx_dns_name"
    FSX_MOUNT_NAME: str = "fsx_mountname"

    def __init__(self, path: str):
        with open(path, "r") as f:
            self._params = json.load(f)

    @property
    def workload_manager(self) -> Optional[str]:
        return self._params.get(ProvisioningParameters.WORKLOAD_MANAGER_KEY)

    @property
    def fsx_settings(self) -> Tuple[str, str]:
        return self._params.get(ProvisioningParameters.FSX_DNS_NAME), self._params.get(ProvisioningParameters.FSX_MOUNT_NAME)

    @property
    def controller_group(self) -> Optional[str]:
        return self._params.get("controller_group")

    @property
    def login_group(self) -> Optional[str]:
        return self._params.get("login_group")

def get_ip_address():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # doesn't even have to be reachable
        s.connect(('10.254.254.254', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    return IP


def wait_for_slurm_conf(controllers: List[str]) -> bool:
    """
    SageMaker agents do a slurm configuration. Wait for a signal that slurm is ready to start.
    This means that we can start controller, or do additional setup
    Function return True if walid slurm configuration found
    """
    sleep = 5 # sec
    timeout = 60  # sec
    for i in range(timeout // sleep):
        if not os.path.exists(SLURM_CONF):
            print("slurm.conf is not present. It is fine for login/compute nodes")
            return True
        with open(SLURM_CONF, "rt") as f:
            data = f.read()
            # check if controller information is present
            for ip in controllers:
                if ip in data:
                    print("slurm.conf found. It contains at least one controller address")
                    return True
        time.sleep(sleep)
    return False


def main(args):
    params = ProvisioningParameters(args.provisioning_parameters)
    resource_config = ResourceConfig(args.resource_config)

    fsx_dns_name, fsx_mountname = params.fsx_settings
    if fsx_dns_name and fsx_mountname:
        print(f"Mount fsx: {fsx_dns_name}. Mount point: {fsx_mountname}")
        ExecuteBashScript("./mount_fsx.sh").run(fsx_dns_name, fsx_mountname)

    ExecuteBashScript("./add_users.sh").run()

    if params.workload_manager == "slurm":
        # Wait until slurm will be configured
        controllers = resource_config.get_list_of_addresses(params.controller_group)
        wait_for_slurm_conf(controllers)

        print("This is a slurm cluster. Do additional slurm setup")
        self_ip = get_ip_address()
        print(f"This node ip address is {self_ip}")

        group, instance = resource_config.find_instance_by_address(self_ip)
        if instance is None:
            raise ValueError("This instance not found in resource config. Can't process")
        print(group)

        node_type = SlurmNodeType.COMPUTE_NODE
        if group.get("Name") == params.controller_group:
            node_type = SlurmNodeType.HEAD_NODE
        elif group.get("Name") == params.login_group:
            node_type = SlurmNodeType.LOGIN_NODE

        if node_type == SlurmNodeType.HEAD_NODE:
            ExecuteBashScript("./setup_mariadb_accounting.sh").run()

        ExecuteBashScript("./utils/motd.sh").run(node_type)
        ExecuteBashScript("./utils/setup_timesync.sh").run()
        ExecuteBashScript("./utils/fsx_ubuntu.sh").run()

        ExecuteBashScript("./start_slurm.sh").run(node_type, ",".join(controllers))

        ## Note: Uncomment the below lines to install docker and enroot.
        ExecuteBashScript("./utils/install_docker.sh").run()
        ExecuteBashScript("./utils/install_enroot_pyxis.sh").run(node_type)

        # # Note: Uncomment the below lines to install DCGM Exporter and EFA Node Exporter and Cluster Nodes. (Docker must also be installed above)
        # if node_type == SlurmNodeType.COMPUTE_NODE:
        #     ExecuteBashScript("./utils/install_dcgm_exporter.sh").run()
        #     ExecuteBashScript("./utils/install_efa_node_exporter.sh").run()

        # # Note: Uncomment the below lines to install Slurm Exporter and Prometheus on the Controller Node.
        # if node_type == SlurmNodeType.HEAD_NODE:
        #     ExecuteBashScript("./utils/install_slurm_exporter.sh").run()
        #     ExecuteBashScript("./utils/install_prometheus.sh").run()

    print("[INFO]: Success: All provisioning scripts completed")


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("-rc", "--resource_config", help="Resource config JSON file containing Ip_address of head, login and compute nodes")
    parser.add_argument("-pp", "--provisioning_parameters", help="Provisioning Parameters containing the head, login and compute ID/names")
    args=parser.parse_args()

    main(args)
