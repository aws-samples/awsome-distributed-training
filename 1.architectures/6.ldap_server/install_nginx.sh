sudo apt install -y amazon-ec2-utils
sudo apt install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev unzip libldap2-dev 
# Install NGINX 
# https://nginx.org/en/linux_packages.html

# Add NGINX Server
git clone https://github.com/kvspb/nginx-auth-ldap.git   /etc/nginx-auth-ldap
wget  http://nginx.org/download/nginx-1.24.0.tar.gz
tar -zxvf nginx-1.24.0.tar.gz
cd nginx-1.24.0
./configure --prefix=/var/www/html \
            --sbin-path=/usr/sbin/nginx \
            --conf-path=/etc/nginx/nginx.conf \
            --http-log-path=/var/log/nginx/access.log \
            --error-log-path=/var/log/nginx/error.log \
            --with-pcre  \
            --lock-path=/var/lock/nginx.lock \
            --pid-path=/var/run/nginx.pid \
            --with-http_ssl_module \
            --add-module=/etc/nginx-auth-ldap \
            --modules-path=/etc/nginx/modules \
            --with-http_v2_module \
            --with-stream=dynamic \
            --with-http_addition_module 
make install
nginx_dir="/home/ubuntu/nginx"
nginx_ssl_dir="/home/ubuntu/nginx/ssl"
mkdir -p /home/ubuntu/nginx/ssl 
echo -e "\nDNS.1=$(ec2-metadata -p | awk '{print $2}')" >> "/home/ubuntu/nginx/ssl/openssl.cnf"
openssl req -new -x509 -nodes -newkey rsa:4096 -days 3650 -keyout "/home/ubuntu/nginx/ssl/nginx.key" -out "/home/ubuntu/nginx/ssl/nginx.crt" -config "/home/ubuntu/nginx/ssl/openssl.cnf"
#give $cfn_cluster_user ownership
#cfn_cluster_user=ubuntu
#chown -R $cfn_cluster_user:$cfn_cluster_user "~/nginx/ssl/nginx.key"
#chown -R $cfn_cluster_user:$cfn_cluster_user "~/nginx/ssl/nginx.crt"


cat << EOF > /etc/nginx/nginx.conf
http {
    ldap_server ldap {
        url ldap://localhost:1389/dc=example,dc=com?uid?sub?(objectClass=person);
        group_attribute uniqueMember;
        group_attribute_is_dn on;
        require group cn=Sales,ou=Groups,dc=example,dc=com;
    }
    server {
        listen 80;
        server_name localhost;
        location / {
            auth_ldap "test1"
            auth_ldap_servers ldap;
        }
    }
}
EOF