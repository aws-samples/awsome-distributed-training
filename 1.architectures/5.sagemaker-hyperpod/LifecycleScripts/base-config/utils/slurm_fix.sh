#!/bin/bash
# https://slurm.schedmd.com/pam_slurm_adopt.html
# https://github.com/SchedMD/slurm/blob/master/contribs/pam_slurm_adopt/pam_slurm_adopt.c
# https://slurm.schedmd.com/slurm.conf.html
# root needed
# tested on Ubuntu 20.04


plugstack_conf="${slurm_dir}/etc/plugstack.conf"
plugstack_dir="${slurm_dir}/etc/plugstack.conf.d"
pyxis_conf="${plugstack_dir}/pyxis.conf"

smhp_conf="/opt/ml/config/resource_config.json"

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

slurm_fix(){
    pecho "start ${FUNCNAME}:"
    
    pecho "Fixing ${plugstack_conf}"
    sed -i "${plugstack_conf}" -e "s#^include[ ][ ]*.*${plugstack_dir}/\*.*#include ${pyxis_conf}#g"
    
    cat "${plugstack_conf}"
    
    pecho "leave ${FUNCNAME}."
}


main(){
    pecho "start ${FUNCNAME}:"

    check_root
    get_node_type

    if [[ $node_type == "controller-machine" ]] ;then
        slurm_fix
        # scontrol reconfigure
        systemctl restart slurmctld
        systemctl status slurmctld
        sinfo
    fi

    pecho "leave ${FUNCNAME}."
}

main $@

exit

