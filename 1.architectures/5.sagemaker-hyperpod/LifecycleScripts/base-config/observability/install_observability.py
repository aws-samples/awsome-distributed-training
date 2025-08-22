import os
import shutil
import argparse
import subprocess


def install_observability(node_type, advanced=False):

    if node_type=="controller":

        os.makedirs("/etc/otel", exist_ok=True)
        shutil.copy("./otel_config/config-head.yaml", "/etc/otel/config.yaml")

        subprocess.run( ["bash", "./install_node_exporter.sh"] )
        subprocess.run( ["bash", "./install_slurm_exporter.sh"] )
        subprocess.run( ["bash", "./install_otel_collector.sh"] )

    elif node_type=="compute":

        os.makedirs("/etc/otel", exist_ok=True)
        shutil.copy("./otel_config/config-compute.yaml", "/etc/otel/config.yaml")

        os.makedirs("/etc/dcgm-exporter", exist_ok=True)
        if advanced:
            shutil.copy("./dcgm_metrics_config/dcgm-metrics-advanced.csv", "/etc/dcgm-exporter/dcgm-metrics.csv")
        else:
            shutil.copy("./dcgm_metrics_config/dcgm-metrics-basic.csv", "/etc/dcgm-exporter/dcgm-metrics.csv")

        subprocess.run( ["bash", "./install_node_exporter.sh"] )
        subprocess.run( ["bash", "./install_dcgm_exporter.sh"] )
        subprocess.run( ["bash", "./install_efa_exporter.sh"] )
        subprocess.run( ["bash", "./install_otel_collector.sh"] )

    elif node_type=="login":
        pass


if __name__ == "__main__":

    argparser = argparse.ArgumentParser(description="Script to install HyperPod observability")
    argparser.add_argument('--node-type', action="store", required=True, help='Node type (controller, login, compute)')
    argparser.add_argument('--advanced', action="store_true", default=False, help='Advanced setup (default: False)')
    args = argparser.parse_args()

    assert args.node_type in ["controller", "login", "compute"]

    print("Starting observability installation")

    install_observability(args.node_type, args.advanced)

    print("---")
    print("Finished observability installation")
