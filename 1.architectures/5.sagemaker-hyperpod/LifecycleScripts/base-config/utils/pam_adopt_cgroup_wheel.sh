#!/bin/bash
# https://slurm.schedmd.com/pam_slurm_adopt.html
# https://github.com/SchedMD/slurm/blob/master/contribs/pam_slurm_adopt/pam_slurm_adopt.c
# https://slurm.schedmd.com/slurm.conf.html
# root needed
# tested on Ubuntu 20.04

install_dir="/tmp"
shared_mount="/fsx"
admin_dir="${shared_mount}/admin"

admin_user="ubuntu"
access_conf="/etc/security/access.conf"

# admin_group="" # to deactivate this option
admin_group="admin"
# wheel_list="" # to deactivate this option
wheel_list="${admin_dir}/${admin_group}.lst"

slurm_gitversion="$(sinfo --version | tr ". " "-")-1"
# slurm_gitversion="slurm-23-11-3-1"
slurm_giturl="SchedMD/slurm"
slurm_gitdir="$(basename ${slurm_giturl})"
slurm_dir="/opt/slurm"
slurm_adopt_apt="libpam-slurm-adopt"
slurm_cgroup_conf="${slurm_dir}/etc/cgroup.conf"
slurm_conf="${slurm_dir}/etc/slurm.conf"
slurm_conf_accounting="${slurm_dir}/etc/accounting.conf"
pam_conf="/etc/pam.d/sshd"
sshd_conf="/etc/ssh/sshd_config"
plugstack_conf="${slurm_dir}/etc/plugstack.conf"
plugstack_dir="${slurm_dir}/etc/plugstack.conf.d"
pyxis_conf="${plugstack_dir}/pyxis.conf"

smhp_conf="/opt/ml/config/resource_config.json"
# apt_opts='-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"'
export DEBIAN_FRONTEND=noninteractive

pecho(){
    #pretty echo
    echo
    echo "### $@"
}

check_root(){
    if [ "$EUID" -ne 0 ] ; then
        echo "Please run as root"
        exit -1
    fi
}

get_node_type(){
    headnode_ip="$(cat "${smhp_conf}" | jq -r '.InstanceGroups[] | select(.Name == "controller-machine") | .Instances[0].CustomerIpAddress')"
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
    apt -y remove libpam-slurm-adopt libpam-slurm
    
    path_orig="$(pwd)"
    rm -rf ${slurm_gitdir}
    git clone -b ${slurm_gitversion} https://github.com/${slurm_giturl}.git
    cd ${slurm_gitdir}
    ./configure --prefix=/opt/slurm > /dev/null
    cd contribs/pam_slurm_adopt/
    make -j > /dev/null
    make install 2>&1 | tail -n20
    cd ${path_orig}
    rm -rf ${slurm_gitdir}
    
    pecho "check /lib/security/ content:"
    ls -lh /lib/security/ 
    ls -lh /lib/x86_64-linux-gnu/security/pam_listfile.so
    
    if [[ -n "${admin_group}" ]] && [[ -n "${wheel_list}" ]] ;then
        pecho "WARNING: using both PAM options - pam_access.so using ${access_conf} AND pam_listfile.so using ${wheel_list}"
    fi
    
    if [[ -n "${wheel_list}" ]] ;then
        mkdir -p "$(dirname "${wheel_list}" )"
        touch "${wheel_list}"
        chmod 0600 "${wheel_list}"
    fi
    
    if [[ -n "${admin_group}" ]] ;then
        getent group ${admin_group}
        if ! [[ $? ]] ;then
            groupadd ${admin_group}
        fi
        if [[ $(cat ${access_conf} | grep -v '^#' | grep -c ${admin_group} ) -eq 0 ]] ;then
            echo "+:(${admin_group}):ALL" >> "${access_conf}"
        fi
    fi
    for u in ${admin_user} ;do
        [[ -n "${admin_group}" ]] && usermod -a -G "${admin_group}" "${u}"
        [[ -n "${wheel_list}" ]] && echo "${u}" >> "${wheel_list}"
    done
    
    if [[ -n "${wheel_list}" ]] ;then
        cat "${wheel_list}" | sort -u | tee "${wheel_list}"
    fi
    
    if [[ $(cat ${pam_conf} | grep -v '^#' | grep -c pam_slurm_adopt.so) -eq 0 ]] ;then
        pecho "Adding pam_slurm_adopt.so at the bottom of ${pam_conf}"
        [[ -n "${admin_group}" ]] && echo "-account    sufficient    pam_access.so" | tee -a ${pam_conf}
        [[ -n "${wheel_list}" ]] && echo "-account    sufficient    pam_listfile.so item=user sense=allow onerr=fail file=${wheel_list}" | tee -a ${pam_conf}
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
    c=$(grep -ic "^${p}=" "${f}")
    case $c in
        1)
            pecho "${p} present in ${f}:"
            echo "from: $(grep "^${p}=" "${f}")"
            sed -i "${f}" -e "s#^${p}=.*#${p}=${v}#g"
            echo "to:   $(grep "^${p}=" "${f}")"
        ;;
        0)
            pecho "${p} not present in ${f}, adding ${p}=${v} at the end of ${f}:"
            echo "${p}=${v}" >> "${f}"
            grep "^${p}=" "${f}"
        ;;
        *)
            pecho "Warning ${p} present multiple times, swapping all occurences..."
            sed -i "${f}" -e "s#^${p}=.*#${p}=${v}#g"
            grep "^${p}=" "${f}"
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
    slurm_swap_opt JobAcctGatherType=jobacct_gather/cgroup "${slurm_conf_accounting}"
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
    
    cd ${install_dir}
    check_root
    get_node_type
    
    if [[ $node_type == "controller-machine" ]] ;then
        slurm_cgroups
        # scontrol reconfigure
        systemctl --no-pager restart slurmctld
        systemctl --no-pager status slurmctld
    else # compute nodes
        slurm_pam_adopt
        systemctl --no-pager restart slurmd
        systemctl --no-pager status slurmd
    fi
    
    pecho "scontrol show config | grep -i cgroup:"
    scontrol show config | grep -i cgroup
    sinfo
    
    pecho "leave ${FUNCNAME}."
}

main $@

exit


# test
node="ip-10-1-64-87"
squeue
ssh $node uname
# Access denied by pam_slurm_adopt: you have no active jobs on this node
# Connection closed by 10.1.64.87 port 22
sbatch --wrap "sleep 600" -w $node -N 1
ssh $node uname
scancel -u ubuntu
squeue

# ssh ip-10-1-64-87 uname -a ; -u ubuntu ssh ip-10-1-64-87 uname 
#  log_level=debug5 
 
# systemctl stop systemd-logind
# systemctl mask systemd-logind

# grep -i pam_systemd /etc/pam.d/*
# for f in /etc/pam.d/* ;do
#     pecho "${f}"
#     sed -i "${f}" -e "s/^\(.*pam_systemd.so.*\)/# \1/g"
# done
# grep -i pam_systemd /etc/pam.d/*





