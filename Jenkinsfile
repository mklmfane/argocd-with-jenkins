pipeline {
  agent { label 'static-k8s-agent' }

  options {
    overrideIndexTriggers(true)
  }

  triggers {
    pollSCM('H/2 * * * *')
  }

  environment {
    APP_NAME         = 'spring-boot-app'
    APP_NAMESPACE    = 'default'
    CONTAINER_PORT   = '8081'
    HARBOR_REGISTRY  = 'harbor.harbor.svc.cluster.local'
    HARBOR_PROJECT   = 'library'
    MAVEN_POM        = 'spring-boot-app/pom.xml'
    DOCKERFILE_PATH  = 'spring-boot-app/Dockerfile'
    BUILD_CONTEXT    = 'spring-boot-app'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Diagnostics') {
      steps {
        sh '''
          set -eux
          java -version
          mvn -version
          git --version
          buildah version
          kubectl version --client=true
          pwd
          ls -la
          find . -maxdepth 3 \\( -name pom.xml -o -name Dockerfile -o -name deployment.yml \\) | sort
        '''
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
          sh '''
            set -euo pipefail

            IMAGE="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${APP_NAME}"
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

    stage('Deploy to Kubernetes') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'harbor-creds',
          usernameVariable: 'HARBOR_USER',
          passwordVariable: 'HARBOR_PASS'
        )]) {
          sh '''
            set -euo pipefail

            IMAGE="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${APP_NAME}"

            kubectl create namespace "${APP_NAMESPACE}" \
              --dry-run=client -o yaml | kubectl apply -f -

            kubectl create secret docker-registry harbor-registry \
              --namespace "${APP_NAMESPACE}" \
              --docker-server="${HARBOR_REGISTRY}" \
              --docker-username="${HARBOR_USER}" \
              --docker-password="${HARBOR_PASS}" \
              --dry-run=client -o yaml | kubectl apply -f -

            cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      imagePullSecrets:
        - name: harbor-registry
      containers:
        - name: ${APP_NAME}
          image: ${IMAGE}:${BUILD_NUMBER}
          imagePullPolicy: Always
          ports:
            - containerPort: ${CONTAINER_PORT}
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAMESPACE}
spec:
  selector:
    app: ${APP_NAME}
  ports:
    - port: 80
      targetPort: ${CONTAINER_PORT}
  type: ClusterIP
EOF

            kubectl rollout status deployment/${APP_NAME} -n "${APP_NAMESPACE}" --timeout=180s
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'rm -f "$WORKSPACE/auth.json" || true'
    }
  }
}