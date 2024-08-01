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
        chmod 0611 "${admin_dir}"
        pecho cp "${ssh_dir}/${key_pub}" "${admin_dir}/${key_pub}"
        cp "${ssh_dir}/${key_pub}" "${admin_dir}/${key_pub}"
    else # compute
        pecho "cat ${admin_dir}/${key_pub} >> ${ssh_dir}/${key_auth}"
        cat "${admin_dir}/${key_pub}" >> "${ssh_dir}/${key_auth}"
    fi
    pecho "Testing SSH local loopback:"
    ssh -o 'StrictHostKeychecking=no' -- root@localhost uname -a
    
    pecho "leave ${FUNCNAME}."
}


main(){
    pecho "start ${FUNCNAME}:"
    
    cd ${install_dir}
    check_root
    get_node_type

    ssh_keys

    pecho "leave ${FUNCNAME}."
}

main $@

exit
