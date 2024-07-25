#!/bin/bash
# https://slurm.schedmd.com/pam_slurm_adopt.html
# https://github.com/SchedMD/slurm/blob/master/contribs/pam_slurm_adopt/pam_slurm_adopt.c
# https://slurm.schedmd.com/slurm.conf.html
# root needed
# tested on Ubuntu 20.04

shared_mount="/fsx"
admin_dir="${shared_mount}/admin"
ssh_dir="${HOME}/.ssh"
key_priv="id_rsa"
key_pub="${key_priv}.pub"
key_auth="authorized_keys"
slurm_adopt_apt="libpam-slurm-adopt"
slurm_cgroup_conf="/opt/slurm/etc/cgroup.conf"
slurm_conf="/opt/slurm/etc/slurm.conf"
slurm_conf_accounting="/opt/slurm/etc/accounting.conf"
smhp_conf="/opt/ml/config/resource_config.json"
pam_conf="/etc/pam.d/sshd"
sshd_conf="/etc/ssh/sshd_config"

pecho(){
    #pretty echo
    echo
    echo "### $@"
}

check_root(){
    if [ "$EUID" -ne 0 ] ; then
        pecho "Please run as root"
        exit -1
    fi
}

get_node_type(){
    headnode_ip="$(cat /opt/ml/config/resource_config.json | jq -r '.InstanceGroups[] | select(.Name == "controller-machine") | .Instances[0].CustomerIpAddress')"
    if [[ $(hostname -I | grep -c $headnode_ip ) -ge 1 ]]; then
        node_type="controller-machine"
    else
        node_type="login-or-compute"
    fi
    # we could revert the search --> no
    # for hip in $(hostname -I) ;do
    #     node_type="$(cat "${smhp_conf}" | jq -r ".InstanceGroups[] | select(.Instances[0].CustomerIpAddress == \"${hip}\") | .Name")"
    #     [[ -n $node_type ]] && break
    # done
    pecho "node_type=${node_type}" # controller-machine, worker-group-1
}

# Not working...
ssh_keys(){
    pecho "start ${FUNCNAME}:"
    
    if ! [[ -f "${ssh_dir}/${key_priv}" ]] ;then
        rm -f "${ssh_dir}/${key_pub}"
        # rm -f "${ssh_dir}/${key_auth}"
        pecho ssh-keygen -b 2048 -t rsa -f "${ssh_dir}/${key_priv}" -q -N ""
        ssh-keygen -b 2048 -t rsa -f "${ssh_dir}/${key_priv}" -q -N ""
    fi
    cat "${ssh_dir}/${key_pub}" >> "${ssh_dir}/${key_auth}"
    if [[ $node_type == "controller-machine" ]] ;then
        pecho mkdir -p "${admin_dir}"
        mkdir -p "${admin_dir}"
        chown root:root "${admin_dir}"
        chmod 0600 "${admin_dir}"
        pecho cp "${ssh_dir}/${key_pub}" "${admin_dir}/${key_pub}"
        cp "${ssh_dir}/${key_pub}" "${admin_dir}/${key_pub}"
    else # compute
        pecho "cat ${admin_dir}/${key_pub} >> ${ssh_dir}/${key_auth}"
        cat "${admin_dir}/${key_pub}" >> "${ssh_dir}/${key_auth}"
    fi
    pecho "Testing SSH local loopback:"
    ssh -o 'StrictHostKeychecking=no' -- root@localhost uname -a
    # ls /usr/lib/systemd/system/ssh.service.d/ec2-instance-connect.conf
    # apt remove ec2-instance-connect
    
    pecho "leave ${FUNCNAME}."
}

slurm_pam_adopt(){
    pecho "start ${FUNCNAME}:"
    # follow https://github.com/SchedMD/slurm/blob/master/contribs/pam_slurm_adopt/pam_slurm_adopt.c
    # https://slurm.schedmd.com/pam_slurm_adopt.html
    pecho "Adding UsePAM to ${sshd_conf}:"
    grep -Hn "^UsePAM " ${sshd_conf} 
    sed -i ${sshd_conf} -e "s/^UsePAM .*/UsePAM yes/g"
    grep -Hn "^UsePAM " ${sshd_conf} 

    # apt update
    # # -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    # DEBIAN_FRONTEND=noninteractive apt -y install ${slurm_adopt_apt}
    pecho "Remove OS slurm-pam packages:"
    DEBIAN_FRONTEND=noninteractive apt -y remove libpam-slurm-adopt libpam-slurm
    
    slurm_version="$(sinfo --version | tr ". " "-")-1"
    # slurm_version="slurm-23-11-3-1"
    git clone -b ${slurm_version} https://github.com/SchedMD/slurm.git
    cd slurm/
    ./configure --prefix=/opt/slurm > /dev/null
    cd contribs/pam_slurm_adopt/
    make > /dev/null
    make install
    cd
    
    pecho "check /lib/security/ content:"
    ls -lh /lib/security/ 
    
    if [[ $(cat ${pam_conf} | grep -v '^#' | grep -c pam_slurm_adopt.so) -eq 0 ]] ;then
        pecho "Adding pam_slurm_adopt.so at the bottom of ${pam_conf}"
        echo "-account    required      pam_slurm_adopt.so" | tee -a ${pam_conf}
    else
        pecho "pam_slurm_adopt.so already in ${pam_conf}"
    fi
    
    pecho "leave ${FUNCNAME}."
}

slurm_swap_opt(){
    pecho "start ${FUNCNAME}:"
    
    p="$(echo "$1" | cut -d'=' -f1)" # parameter
    v="$(echo "$1" | cut -d'=' -f2)" # value
    f="${2:-${slurm_conf}}" # slurm config file
    
    # pecho "Checking if ${p} is present in ${slurm_conf}:"
    c=$(grep -c "^${p}=" "${slurm_conf}")
    case $c in
        1)
            pecho "${p} present in ${slurm_conf}:"
            pecho "from: $(grep "^${p}=" "${slurm_conf}")"
            sed -i "${slurm_conf}" -e "s#^${p}=.*#${p}=${v}#g"
            pecho "to:   $(grep "^${p}=" "${slurm_conf}")"
        ;;
        0)
            pecho "${p} not present, adding ${p}=${v} at the end of ${slurm_conf}:"
            echo "${p}=${v}" >> "${slurm_conf}"
            grep "^${p}=" "${slurm_conf}"
        ;;
        *)
            pecho "Warning ${p} present multiple times, swapping all occurences..."
            sed -i "${slurm_conf}" -e "s#^${p}=.*#${p}=${v}#g"
            grep "^${p}=" "${slurm_conf}"
        ;;
    esac
    
    pecho "leave ${FUNCNAME}."
}

slurm_cgroups(){
    pecho "start ${FUNCNAME}:"
    # Cgroup settings
    slurm_swap_opt ProctrackType=proctrack/cgroup
    slurm_swap_opt TaskPlugin=task/cgroup,task/affinity # even if TaskPlugin=task/none is "Required for auto-resume feature."
    slurm_swap_opt PrologFlags=Contain
    slurm_swap_opt SelectTypeParameters=CR_Core_Memory
    slurm_swap_opt JobacctGatherType=jobacct_gather/cgroup "${slurm_conf_accounting}"
    slurm_swap_opt LaunchParameters=enable_nss_slurm,ulimit_pam_adopt
    
    
    cat << EOF > ${slurm_cgroup_conf}
CgroupPlugin=autodetect
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
SignalChildrenProcesses=yes
MaxRAMPercent=99

EOF
    pecho "leave ${FUNCNAME}."
}


main(){
    pecho "start ${FUNCNAME}:"
    
    check_root
    get_node_type
    
    ssh_keys
    
    if [[ $node_type == "controller-machine" ]] ;then
        slurm_cgroups
        # scontrol reconfigure
        systemctl restart slurmctld # wait
        sleep 5
        systemctl status slurmctld
        sinfo
    else # compute nodes
        slurm_pam_adopt
        systemctl restart ssh # PAM
        systemctl restart slurmd
        systemctl status slurmd
    fi
    # scontrol reconfigure
    # systemctl daemon-reload
    pecho "scontrol show config | grep -i cgroup:"
    scontrol show config | grep -i cgroup
    
    pecho "leave ${FUNCNAME}."
}

main $@

exit


# test
node="ip-10-1-64-87"
squeue
ssh $node uname
sbatch --wrap "sleep 6000" -w $node -N 1
ssh $node uname
scancel -u ubuntu
squeue

ssh ip-10-1-64-87 uname -a ; sudo -u ubuntu ssh ip-10-1-64-87 uname 
 log_level=debug5 
 
systemctl stop systemd-logind
systemctl mask systemd-logind

grep -i pam_systemd /etc/pam.d/*
for f in /etc/pam.d/* ;do
    pecho "${f}"
    sed -i "${f}" -e "s/^\(.*pam_systemd.so.*\)/# \1/g"
done
grep -i pam_systemd /etc/pam.d/*


Access denied by pam_slurm_adopt: you have no active jobs on this node
Connection closed by 10.1.64.87 port 22


