
# Basic configuration parameters
class Config:

    # Set true if you want to install Docker/Enroot/Pyxis.
    enable_docker_enroot_pyxis = True

    # Set true if you want to install 
    # DCGM Exporter and EFA Node Exporter are installed on compute nodes, 
    # Slurm Exporter and Prometheus are installed on controller node.
    enable_observability = False

    # Set true if you want to install SSSD for ActiveDirectory/LDAP integration.
    # You need to configure parameters in SssdConfig as well.
    enable_sssd = False


# Configuration parameters for ActiveDirectory/LDAP/SSSD
class SssdConfig:

    # Name of domain. Can be default if you are not sure.
    domain = "default"

    # Comma separated list of LDAP server URIs
    ldap_uri = "ldaps://nlb-ds-xyzxyz.elb.us-west-2.amazonaws.com"

    # The default base DN to use for performing LDAP user operations
    ldap_search_base = "dc=hyperpod,dc=abc123,dc=com"

    # The default bind DN to use for performing LDAP operations
    ldap_default_bind_dn = "CN=ReadOnly,OU=Users,OU=hyperpod,DC=hyperpod,DC=abc123,DC=com"
    
    # "password" or "obfuscated_password". Obfuscated password is recommended.
    ldap_default_authtok_type = "obfuscated_password"

    # You need to modify this parameter with the obfuscated password, not plain text password
    ldap_default_authtok = "placeholder"

    # SSH authentication method - "password" or "publickey"
    ssh_auth_method = "publickey"

    # Home directory. You can change it to "/home/%u" if your cluster doesn't use FSx volume.
    override_homedir = "/fsx/%u"

    # Group names to accept SSH login
    ssh_allow_groups = {
        "controller" : ["ClusterAdmin", "ubuntu"],
        "compute" : ["ClusterAdmin", "ClusterDev", "ubuntu"],
        "login" : ["ClusterAdmin", "ClusterDev", "ubuntu"],
    }

    # Group names for sudoers
    sudoers_groups = {
        "controller" : ["ClusterAdmin", "ClusterDev"],
        "compute" : ["ClusterAdmin", "ClusterDev"],
        "login" : ["ClusterAdmin", "ClusterDev"],
    }
