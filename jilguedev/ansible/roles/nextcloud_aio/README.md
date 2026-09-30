sudo podman exec -it aio-functional-test bash
su - aiotest
docker exec nextcloud-aio-mastercontainer grep password /mnt/docker-aio-config/data/configuration.json
