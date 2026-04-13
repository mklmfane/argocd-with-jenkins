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

    SKIP_PIPELINE   = 'false'
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
          git --version
        '''
      }
    }

    stage('Preflight') {
        steps {
            sh '''
                set -eux
                git config --global --add safe.directory "${WORKSPACE}"
            '''
        script {
            def skip = sh(
                script: """
                    set -eu

                    COMMIT_MSG="\$(git -C "${WORKSPACE}" log -1 --pretty=%s)"
                    CHANGED_FILES="\$(git -C "${WORKSPACE}" diff-tree --no-commit-id --name-only -r HEAD | tr '\\n' ' ' | sed 's/[[:space:]]*\$//')"

                    echo "Last commit message: \$COMMIT_MSG"
                    echo "Changed files: \$CHANGED_FILES"

                    if echo "\$COMMIT_MSG" | grep -Eq '^ci: update ${APP_NAME} image to '; then
                        if [ "\$CHANGED_FILES" = "${MANIFEST_FILE}" ]; then
                            echo true
                        else
                            echo false
                        fi
                    else
                    echo false
                    fi
                """,
                returnStdout: true
            ).trim()

            env.SKIP_PIPELINE = skip

            if (env.SKIP_PIPELINE == 'true') {
                currentBuild.description = 'Skipped self-triggered manifest-only commit'
                echo 'Skipping pipeline because this commit was created by Jenkins only to update the GitOps manifest.'
            }
            }
        }
    }

    stage('Create in-cluster kubeconfig') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
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
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
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
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
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
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
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
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        sh '''
          set -eux
          ls -lah spring-boot-app/target
          test -f spring-boot-app/target/spring-petclinic-4.0.0-SNAPSHOT.jar
        '''
      }
    }

    stage('Build and Push Image to Harbor') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
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
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'harbor-creds',
            usernameVariable: 'HARBOR_USER',
            passwordVariable: 'HARBOR_PASS'
          ),
          usernamePassword(
            credentialsId: 'github-creds',
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

            test -d "${WORKSPACE}/.git"

            git config --global --add safe.directory "${WORKSPACE}"
            git -C "${WORKSPACE}" config user.name "jenkins"
            git -C "${WORKSPACE}" config user.email "jenkins@local"    

            git -C "${WORKSPACE}" remote set-url origin "${REPO_URL}"
            git -C "${WORKSPACE}" fetch origin "${GITOPS_BRANCH}"
            git -C "${WORKSPACE}" checkout -B "${GITOPS_BRANCH}" "origin/${GITOPS_BRANCH}"

            sed -i -E "s#(^[[:space:]]*image:[[:space:]]*).+#\\1${FULL_IMAGE}#" "${WORKSPACE}/${MANIFEST_FILE}"

            echo "Updated manifest:"
            grep -n "image:" "${WORKSPACE}/${MANIFEST_FILE}"

            git -C "${WORKSPACE}" add "${MANIFEST_FILE}"

            if git -C "${WORKSPACE}" diff --cached --quiet; then
              echo "No manifest change detected."
            else
              AUTH="$(printf '%s:%s' "${GIT_USER}" "${GIT_PAT}" | base64 | tr -d '\\n')"
              git -C "${WORKSPACE}" commit -m "ci: update ${APP_NAME} image to ${BUILD_NUMBER}"
              git -C "${WORKSPACE}" -c http.extraHeader="Authorization: Basic ${AUTH}" push origin HEAD:${GITOPS_BRANCH}
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