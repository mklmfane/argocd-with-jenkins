FROM docker.io/eclipse-temurin:17-jre

WORKDIR /app

RUN useradd -r -u 1001 -g root appuser

ARG JAR_FILE=target/spring-petclinic-4.0.0-SNAPSHOT.jar
COPY --chown=1001:0 ${JAR_FILE} /app/app.jar

EXPOSE 8081

USER 1001

ENTRYPOINT ["java","-jar","/app/app.jar","--server.port=8081"]