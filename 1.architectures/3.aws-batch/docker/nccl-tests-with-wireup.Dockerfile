# Dockerfile: build nccl-tests image with openssh and merged bootstrap
# - installs openssh server/client and utilities
# - generates sshd host keys (ssh-keygen -A)
# - does NOT bake cluster keypair; keys should be stored in Secrets Manager and fetched at container startup
# - copies the merged bootstrap script into the image and uses it as the ENTRYPOINT
#
# IMPORTANT: For production, protect private keys; consider using build-time secrets or an external secret rotation mechanism.
FROM public.ecr.aws/hpc-cloud/nccl-tests:latest

USER root

# Install required packages: openssh-server/clients, python3, curl, jq
RUN yum -y update && \
    yum -y install -y openssh-server openssh-clients python3 curl jq && \
    yum clean all || true

# Ensure sshd config allows root login with keys and disallows password auth
RUN sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

# Generate sshd host keys so container will have them at runtime
RUN ssh-keygen -A

# Copy the merged bootstrap script into the image (bootstrap contains the wireup logic)
COPY scripts/bootstrap.sh /opt/bootstrap.sh
RUN chmod +x /opt/bootstrap.sh

# Entrypoint: run the merged bootstrap directly (bootstrap will fetch SSH keys from Secrets Manager at runtime)
ENTRYPOINT [ "/opt/bootstrap.sh" ]
