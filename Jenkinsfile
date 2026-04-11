pipeline {
  agent { label 'static-k8s-agent' }

  triggers {
    pollSCM('H/1 * * * *')
  }

  environment {
    REGISTRY_IMAGE = 'docker.io/saragoza68/spring-boot-app'
    GIT_REPO       = 'https://github.com/mklmfane/argocd-with-jenkins.git'
  }

  stages {
    stage('Checkout') {
      steps {
        git branch: 'main', poll: true, url: "${GIT_REPO}"
      }
    }

    stage('Skip self-generated commit') {
      steps {
        script {
          def commitMsg = sh(
            script: "git log -1 --pretty=%B",
            returnStdout: true
          ).trim()

          echo "Last commit message: ${commitMsg}"

          if (commitMsg.contains('[skip jenkins]')) {
            currentBuild.result = 'NOT_BUILT'
            error('Skipping self-generated manifest commit')
          }
        }
      }
    }

    stage('Diagnostics') {
      steps {
        sh '''
          java -version
          mvn -version
          git --version
          buildah version
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
          mvn -B -U -ntp -f spring-boot-app/pom.xml clean package
        '''
      }
    }
    }

    stage('Maven Network Diagnostics') {
      steps {
        sh '''
          env | grep -i proxy || true
          curl -I https://repo.maven.apache.org/maven2/ || true
        curl -I https://repo.maven.apache.org/maven2/org/graalvm/buildtools/utils/0.11.4/utils-0.11.4.jar || true
        '''
      }
    }

    stage('Build and Push Image with Buildah') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub',
          usernameVariable: 'DOCKER_USER',
          passwordVariable: 'DOCKER_PASS'
        )]) {
          sh '''
            set -euo pipefail

            export REGISTRY_AUTH_FILE="$WORKSPACE/auth.json"

            printf '%s' "$DOCKER_PASS" | \
              buildah login \
                --authfile "$REGISTRY_AUTH_FILE" \
                --username "$DOCKER_USER" \
                --password-stdin \
                docker.io

            buildah bud \
              --storage-driver vfs \
              --isolation chroot \
              -t "${REGISTRY_IMAGE}:${BUILD_NUMBER}" \
              -t "${REGISTRY_IMAGE}:v1.0" \
              -f spring-boot-app/Dockerfile \
              spring-boot-app

            buildah push \
              --authfile "$REGISTRY_AUTH_FILE" \
              "${REGISTRY_IMAGE}:${BUILD_NUMBER}" \
              "docker://${REGISTRY_IMAGE}:${BUILD_NUMBER}"

            buildah push \
              --authfile "$REGISTRY_AUTH_FILE" \
              "${REGISTRY_IMAGE}:v1.0" \
              "docker://${REGISTRY_IMAGE}:v1.0"
          '''
        }
      }
    }

    stage('Update Deployment Manifest') {
        steps {
            withCredentials([usernamePassword(
            credentialsId: 'github-creds',
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_TOKEN'
        )]) {
        sh '''
        set +x
        git config user.email "mircea_constantin58@yahoo.com"
        git config user.name "mklmfane"

        sed -i "s|image: .*|image: saragoza68/spring-boot-app:${BUILD_NUMBER}|g" spring-boot-app-manifests/deployment.yml

        echo "Changed files before commit:"
        git status --short

        git add -A

        if git diff --cached --quiet; then
          echo "No changes to commit"
        else
          git commit -m "[skip jenkins] Update files for build ${BUILD_NUMBER}"
          git push https://${GIT_USER}:${GIT_TOKEN}@github.com/mklmfane/argocd-with-jenkins.git HEAD:main
        fi
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