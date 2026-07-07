FROM alpine:3.21

RUN apk add --no-cache \
      openssh-server \
      bash \
      docker-cli \
      git \
      curl \
      python3 \
 && ssh-keygen -A \
 && mkdir -p /root/.ssh \
 && chmod 700 /root/.ssh \
 && sed -i \
      -e 's/^#*PermitRootLogin.*/PermitRootLogin yes/' \
      -e 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
      -e 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' \
      -e 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
      /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
