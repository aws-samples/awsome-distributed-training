#!/bin/bash

# BUG
# Slurm configless bug workaround for pyxis SPANK plugin reference in etc/plugstack.conf # CF internal ticket D148893639 and V1514329557 # schedMD ticket 20903
# known limitation of configless, where included files must be adjacent to their parent file.
# slurmctld is attempting to read '*' wildcard as a file, marking it not responsive
# The slurmctld not responsive issue was fixed in 23.11.5, but the wildcard limitation still exists.
# WORKAROUND
# This script changes the Slurm configuration file /opt/slurm/etc/plugstack.conf expanding wildcard to include directly config files absolute path
# like /opt/slurm/etc/plugstack.conf.d/pyxis.conf instead of using the generic /opt/slurm/etc/plugstack.conf.d/*
# Avoids slurmctld restart hanging for minutes
# Avoids "slurmctld[]: slurmctld: error: s_p_parse_file: cannot stat file /opt/slurm/etc/plugstack.conf.d/*: No such file or directory, retry"


slurm_dir="/opt/slurm"
plugstack_conf="${slurm_dir}/etc/plugstack.conf"
plugstack_dir="${slurm_dir}/etc/plugstack.conf.d"
pyxis_conf="${plugstack_dir}/pyxis.conf"

smhp_conf="/opt/ml/config/resource_config.json"

# pretty echo
pecho(){
    echo
    echo "### $@"
}

# checking if user is root, exit if not
check_root(){
    if [ "$EUID" -ne 0 ] ; then
        echo "Please run as root"
        exit -1
    fi
}

# swap the generic include in ${plugstack_conf} from ${plugstack_dir}/* to direct ${pyxis_conf}
# WARNING it is not generic anymore, only pyxis plugin will be loaded
slurm_fix_plugstack(){
    pecho "start ${FUNCNAME}:"
    
    pecho "Fixing ${plugstack_conf}"
    cat "${plugstack_conf}"
    
    # expand all wildcard path
    while read -r line; do
        for f in $(ls $line) ;do
            echo "include $f" >> "${plugstack_conf}"
        done
    done < <(cat "${plugstack_conf}" | grep -v "^#" | grep "^include" | awk '{print $2}')

    # sed -i "${plugstack_conf}" -e "s#^include[ ][ ]*.*${plugstack_dir}/\*.*#include ${pyxis_conf}#g" # WARNING this only swap pyxis, it is not generic anymore, only pyxis plugin will be loaded
    sed -i "${plugstack_conf}" -e "s#^\(include[ ][ ]*.*${plugstack_dir}/\*.*\)#\#\1#g" # comment the whole wildcard line

    cat "${plugstack_conf}"
    pecho "leave ${FUNCNAME}."
}

# main
main(){
    pecho "start ${FUNCNAME}:"

    check_root
    slurm_fix_plugstack # need to run on all instances (controller-machine and work-group-1, etc.)

    pecho "leave ${FUNCNAME}."
}

# main exec
main $@

exit

