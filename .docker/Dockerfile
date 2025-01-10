# Use bitnami Java image as base
FROM bitnami/java:latest

# Build arguments
ARG DOCKER_WORKDIR

# Configure noninteractive installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && \
    apt-get install -y curl maven unzip zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install SDKMAN and Spring Boot CLI
ENV SDKMAN_DIR="/root/.sdkman"
RUN set -e && \
    curl -s "https://get.sdkman.io" | bash && \
    bash -c "source $SDKMAN_DIR/bin/sdkman-init.sh && \
    yes | sdk install springboot 3.2.1"

# Add Spring Boot to PATH
ENV PATH="$SDKMAN_DIR/candidates/springboot/current/bin:${PATH}"

# Set working directory
WORKDIR ${DOCKER_WORKDIR}

# Copy your application files
COPY . ${DOCKER_WORKDIR}

# Verify Spring Boot CLI installation
RUN spring --version

# The command to create a new Spring Boot project
# CMD ["mvn", "clean", "spring-boot:run"]
CMD ["tail", "-f", "/dev/null"]
