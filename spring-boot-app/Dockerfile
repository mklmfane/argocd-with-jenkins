FROM docker.io/eclipse-temurin:11-jre

WORKDIR /app

# Create a non-root user
RUN useradd -r -u 1001 -g root appuser

# Copy the jar and set ownership
COPY --chown=1001:0 target/spring-boot-web.jar /app/app.jar

# Use non-root user
USER 1001

EXPOSE 8081
ENTRYPOINT ["java","-XX:+UseContainerSupport","-Djava.security.egd=file:/dev/./urandom","-jar","/app/app.jar","--server.port=8081"]