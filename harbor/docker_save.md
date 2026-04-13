kubectl port-forward -n harbor --address 0.0.0.0 svc/harbor 8085:8085

docker save saragoza68/spring-boot-app:10 -o spring-boot-app-10.tar

docker run --rm `
  -v "${PWD}:/work" `
  quay.io/skopeo/stable:latest `
  login `
  --tls-verify=false `
  --authfile /work/auth.json `
  -u admin `
  -p Harbor12345 `
  host.docker.internal:30080

docker run --rm `
  -v "${PWD}:/work" `
  quay.io/skopeo/stable:latest `
  copy `
  --dest-tls-verify=false `
  --dest-authfile /work/auth.json `
  docker-archive:/work/spring-boot-app-10.tar `
  docker://host.docker.internal:30080/library/spring-boot-app:10


docker save saragoza68/spring-boot-app:10 -o spring-boot-app-10.tar

docker run --rm `
  -v "${PWD}:/work" `
  quay.io/skopeo/stable:latest `
  login `
  --tls-verify=false `
  --authfile /work/auth.json `
  -u admin `
  -p Harbor12345 `
  host.docker.internal:30080

docker run --rm `
  -v "${PWD}:/work" `
  apache/kafka:4.0.2 `
  login `
  --tls-verify=false `
  --authfile /work/auth.json `
  -u admin `
  -p Harbor12345 `
  host.docker.internal:30080

docker run --rm `
  -v "${PWD}:/work" `
  quay.io/skopeo/stable:latest `
  copy `
  --dest-tls-verify=false `
  --dest-authfile /work/auth.json `
  docker-archive:/work/spring-boot-app-10.tar `
  docker://host.docker.internal:30080/library/spring-boot-app:10


  $images = @(
  @{ src = "sha256:3fa7c2194bc73081ac509d373727a647091c2c0450ff8fede30cc0013b6a9f5c"; repo = "local/spring-boot-app:10"; tar = "spring-boot-app-10.tar" },
  @{ src = "saragoza68/jenkins-inbound-agent-buildah:1.0"; repo = "local/jenkins-inbound-agent-buildah:1.0"; tar = "jenkins-agent-1.0.tar" }
)

foreach ($img in $images) {
  docker save $img.src -o $img.tar
  docker run --rm `
    -v "${PWD}:/work" `
    quay.io/skopeo/stable:latest `
    copy `
    --dest-tls-verify=false `
    --dest-creds admin:Harbor12345 `
    docker-archive:/work/$($img.tar) `
    docker://host.docker.internal:30080/$($img.repo)
}

docker run --rm `
  -v "${PWD}:/work" `
  quay.io/skopeo/stable:latest `
  copy `
  --dest-tls-verify=false `
  --dest-creds admin:Harbor12345 `
  docker-archive:/work/spring-boot-app-10.tar `
  docker://host.docker.internal:30080/library/spring-boot-app:10

docker run --rm `
  -v "${PWD}:/work" `
  quay.io/skopeo/stable:latest `
  login `
  --tls-verify=false `
  --authfile /work/auth.json `
  -u admin `
  -p Harbor12345 `
  host.docker.internal:30080

docker save apache/kafka:4.0.2 -o apache-kafka-4.0.2.tar

docker run --rm `
  -v "${PWD}:/work" `
  quay.io/skopeo/stable:latest `
  copy `
  --dest-tls-verify=false `
  --dest-authfile /work/auth.json `
  docker-archive:/work/apache-kafka-4.0.2.tar `
  docker://host.docker.internal:30080/library/apache-kafka:4.0.2