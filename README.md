# villajilguero-oci-services


docker run \
  --init \
  --sig-proxy=false \
  --name nextcloud-aio-mastercontainer \
  --restart always \
  --publish 80:80 \
  --publish 8080:8080 \
  --publish 8443:8443 \
  --volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
  --volume /run/user/1000/podman/podman.sock:/var/run/docker.sock:ro \
  ghcr.io/nextcloud-releases/all-in-one:latest


338e36ccf007:~/docker-aio# grep password /mnt/docker-aio-config/data/configuration.json

journalctl --user -u docker-compose-nextcloud
systemctl status --user docker-compose-nextcloud


mocker purgatory scam crisply perfectly polymer reimburse drown
backup: a4ede93715731cca809b5e5d20d1c33a124d1ace4f53bdff
