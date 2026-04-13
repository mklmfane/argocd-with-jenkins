pipeline {
  agent {
    kubernetes {
      defaultContainer 'tools'
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: spring-boot-ci
spec:
  serviceAccountName: jenkins-agent
  containers:
    - name: tools
      image: alpine:3.20
      imagePullPolicy: IfNotPresent
      securityContext:
        runAsUser: 0
      command:
        - sh
        - -c
        - sleep 99d
      tty: true
    - name: buildah
      image: quay.io/buildah/stable:latest
      imagePullPolicy: IfNotPresent
      securityContext:
        privileged: true
        runAsUser: 0
      command:
        - sh
        - -c
        - sleep 99d
      tty: true
"""
    }
  }

  options {
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    overrideIndexTriggers(true)
    skipDefaultCheckout(true)
  }

  environment {
    APP_NAME        = 'spring-boot-app'
    APP_NAMESPACE   = 'spring-boot-dev'
    CONTAINER_PORT  = '8081'

    HARBOR_REGISTRY = 'harbor.harbor.svc.cluster.local:8085'
    HARBOR_PROJECT  = 'library'

    MAVEN_POM       = 'spring-boot-app/pom.xml'
    DOCKERFILE_PATH = 'spring-boot-app/Dockerfile'
    BUILD_CONTEXT   = 'spring-boot-app'

    MANIFEST_FILE   = 'spring-boot-app-manifests/deployment.yml'
    GITOPS_BRANCH   = 'main'
    REPO_URL        = 'https://github.com/mklmfane/argocd-with-jenkins.git'
    GIT_CREDENTIALS = 'github-creds'

    KUBECONFIG      = "${WORKSPACE}/kubeconfig"
    LOCAL_BIN       = "${WORKSPACE}/bin"
    PATH            = "${WORKSPACE}/bin:${PATH}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Install kubectl') {
      steps {
        sh '''
          set -eux

          mkdir -p "${LOCAL_BIN}"

          apk add --no-cache \
            bash \
            ca-certificates \
            curl \
            git \
            maven \
            openjdk17-jdk

          if [ ! -x "${LOCAL_BIN}/kubectl" ]; then
            KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
            curl -fsSL -o "${LOCAL_BIN}/kubectl" \
              "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
            chmod +x "${LOCAL_BIN}/kubectl"
          fi

          "${LOCAL_BIN}/kubectl" version --client=true
        '''
      }
    }

    stage('Create in-cluster kubeconfig') {
      steps {
        sh '''
          set -eux

          TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
          CA_CERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
          API_SERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS}"

          cat > "${KUBECONFIG}" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: in-cluster
  cluster:
    certificate-authority: ${CA_CERT}
    server: ${API_SERVER}
contexts:
- name: in-cluster
  context:
    cluster: in-cluster
    namespace: ${APP_NAMESPACE}
    user: jenkins-sa
current-context: in-cluster
users:
- name: jenkins-sa
  user:
    token: ${TOKEN}
EOF

          kubectl version --client=true
          kubectl get ns
          kubectl create namespace "${APP_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
        '''
      }
    }

    stage('Check RBAC') {
      steps {
        sh '''
          set -eux
          kubectl auth can-i create configmap -n "${APP_NAMESPACE}"
          kubectl auth can-i create deployment -n "${APP_NAMESPACE}"
          kubectl auth can-i create service -n "${APP_NAMESPACE}"
          kubectl auth can-i create pod -n "${APP_NAMESPACE}"
          kubectl auth can-i patch serviceaccount -n "${APP_NAMESPACE}"
        '''
      }
    }

    stage('Diagnostics') {
      steps {
        sh '''
          set -eux
          java -version
          mvn -version
          git --version
          kubectl version --client=true
          pwd
          ls -la
          find . -maxdepth 3 \\( -name pom.xml -o -name Dockerfile -o -name deployment.yml -o -name service.yml \\) | sort
        '''
        container('buildah') {
          sh '''
            set -eux
            buildah version
          '''
        }
      }
    }

    stage('Build and Test') {
      steps {
        retry(2) {
          sh '''
            set -eux
            mvn -B -U -ntp -f "${MAVEN_POM}" clean package
          '''
        }
      }
    }

    stage('Verify Artifact') {
      steps {
        sh '''
          set -eux
          ls -lah spring-boot-app/target
          test -f spring-boot-app/target/spring-petclinic-4.0.0-SNAPSHOT.jar
        '''
      }
    }

    stage('Build and Push Image to Harbor') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'harbor-creds',
          usernameVariable: 'HARBOR_USER',
          passwordVariable: 'HARBOR_PASS'
        )]) {
          container('buildah') {
            sh '''
              set -euo pipefail

              IMAGE="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${APP_NAME}"
              export STORAGE_DRIVER=vfs
              export REGISTRY_AUTH_FILE="$WORKSPACE/auth.json"

              printf '%s' "$HARBOR_PASS" | \
                buildah login \
                  --tls-verify=false \
                  --authfile "$REGISTRY_AUTH_FILE" \
                  --username "$HARBOR_USER" \
                  --password-stdin \
                  "$HARBOR_REGISTRY"

              buildah bud \
                --storage-driver vfs \
                --isolation chroot \
                --build-arg JAR_FILE=target/spring-petclinic-4.0.0-SNAPSHOT.jar \
                -t "${IMAGE}:${BUILD_NUMBER}" \
                -t "${IMAGE}:latest" \
                -f "${DOCKERFILE_PATH}" \
                "${BUILD_CONTEXT}"

              buildah push \
                --tls-verify=false \
                --authfile "$REGISTRY_AUTH_FILE" \
                "${IMAGE}:${BUILD_NUMBER}" \
                "docker://${IMAGE}:${BUILD_NUMBER}"

              buildah push \
                --tls-verify=false \
                --authfile "$REGISTRY_AUTH_FILE" \
                "${IMAGE}:latest" \
                "docker://${IMAGE}:latest"
            '''
          }
        }
      }
    }

    stage('Deploy to Kubernetes') {
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'harbor-creds',
            usernameVariable: 'HARBOR_USER',
            passwordVariable: 'HARBOR_PASS'
          ),
          usernamePassword(
            credentialsId: "${GIT_CREDENTIALS}",
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_PAT'
          )
        ]) {
          sh '''
            set -euo pipefail

            IMAGE="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${APP_NAME}"
            FULL_IMAGE="${IMAGE}:${BUILD_NUMBER}"

            kubectl create namespace "${APP_NAMESPACE}" \
              --dry-run=client -o yaml | kubectl apply -f -

            kubectl create secret docker-registry harbor-registry \
              --namespace "${APP_NAMESPACE}" \
              --docker-server="${HARBOR_REGISTRY}" \
              --docker-username="${HARBOR_USER}" \
              --docker-password="${HARBOR_PASS}" \
              --dry-run=client -o yaml | kubectl apply -f -

            kubectl patch serviceaccount default \
              -n "${APP_NAMESPACE}" \
              --type merge \
              -p '{"imagePullSecrets":[{"name":"harbor-registry"}]}'

            git config user.name "jenkins"
            git config user.email "jenkins@local"

            git remote set-url origin "${REPO_URL}"
            git fetch origin "${GITOPS_BRANCH}"
            git checkout -B "${GITOPS_BRANCH}" "origin/${GITOPS_BRANCH}"

            sed -i -E "s#(^[[:space:]]*image:[[:space:]]*).+#\\1${FULL_IMAGE}#" "${MANIFEST_FILE}"

            echo "Updated manifest:"
            grep -n "image:" "${MANIFEST_FILE}"

            git add "${MANIFEST_FILE}"

            if git diff --cached --quiet; then
              echo "No manifest change detected."
            else
              AUTH="$(printf '%s:%s' "${GIT_USER}" "${GIT_PAT}" | base64 | tr -d '\\n')"
              git commit -m "ci: update ${APP_NAME} image to ${BUILD_NUMBER}"
              git -c http.extraHeader="Authorization: Basic ${AUTH}" push origin HEAD:${GITOPS_BRANCH}
            fi

            for i in $(seq 1 60); do
              CURRENT_IMAGE="$(kubectl get deployment "${APP_NAME}" -n "${APP_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
              echo "Current image: ${CURRENT_IMAGE}"

              if [ "${CURRENT_IMAGE}" = "${FULL_IMAGE}" ]; then
                kubectl rollout status deployment/${APP_NAME} -n "${APP_NAMESPACE}" --timeout=180s
                kubectl get pods -n "${APP_NAMESPACE}" -l app="${APP_NAME}" -o wide
                kubectl get svc -n "${APP_NAMESPACE}" -o wide
                exit 0
              fi

              sleep 10
            done

            echo "Argo CD did not reconcile deployment ${APP_NAME} to ${FULL_IMAGE} in time."
            kubectl get deployment "${APP_NAME}" -n "${APP_NAMESPACE}" -o wide || true
            exit 1
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'rm -f "$WORKSPACE/auth.json" "$KUBECONFIG" || true'
    }
  }
}