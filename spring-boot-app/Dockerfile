# You can change this base image to anything else
# But make sure to use the correct version of Java
FROM docker.io/eclipse-temurin:11-jre-alpine
WORKDIR /app
COPY target/spring-boot-web.jar app.jar
EXPOSE 8081
ENTRYPOINT ["java","-jar","app.jar","--server.port=8081"]
