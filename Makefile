#debug flags:
#a for all debugging (same as make -d and make --debug).
#b for basic debugging.
#v for slightly more verbose basic debugging.
#i for implicit rules.
#j for invocation information.
#m for information during makefile remakes.
MAKEFLAGS += --no-print-directory
#MAKEFLAGS += --debug=v
MAKEFLAGS += -s
include .env
export $(shell sed 's/=.*//' .env)
#default: help
.DEFAULT_GOAL := help
#.PHONY: all

PRIMARY_COLOR=\033[1;35m
WARNING_COLOR=\033[1;33m
SUCCESS_COLOR=\033[1;32m
ERROR_COLOR=\033[0;31m
END_COLOR=\033[0m
TIMESTAMP := $(shell date '+%Y-%m-%d_%H-%M-%S')

# Global variables
DOCKER = docker
DOCKER_BACKEND_CONTAINER_NAME=jma-backend-${APP_NAME}
DOCKER_FRONTEND_CONTAINER_NAME=jma-frontend-${APP_NAME}
DOCKER_DATABASE_CONTAINER_NAME=jma-database-${APP_NAME}
BACKEND_WORKDIR=${APP_NAME}-backend
FRONTEND_WORKDIR=${APP_NAME}-frontend

DOCKER_APP_CONTAINER_IDS=$(shell docker container ps -a --filter "name=${APP_NAME}" --format "{{.ID}}")
DOCKER_APP_VOLUMES=$(shell docker inspect ${DOCKER_BACKEND_CONTAINER_NAME} --format '{{range .Mounts}}{{.Name}}{{"\n"}}{{end}}' > /dev/null 2>&1 && docker inspect ${DOCKER_DATABASE_CONTAINER_NAME} --format '{{range .Mounts}}{{.Name}}{{"\n"}}{{end}}' > /dev/null 2>&1)
DOCKER_APP_UNUSED_NETWORKS=$(shell docker network ls --filter "dangling=true" --format "{{.ID}}")
DOCKER_APP_DANGLING_IMAGES=$(shell docker images -f "dangling=true" -q)

BACKEND_HOME_CONTROLLER_PATH=src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/controller
BACKEND_SECURITY_CONFIG_PATH=src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/config

JAVA_VERSION=$(shell docker exec -w /app jma-backend-p8 /bin/sh -c "java --version | awk '/openjdk/ {print \$$2}' | cut -d'.' -f1")

# Command shortcuts
ENSURE_BACKEND_DOCKER = $(call ensureBackendDockerState, $(1))
ENSURE_FRONTEND_DOCKER = $(call ensureFrontendDockerState, $(1))
ENSURE_DATABASE_DOCKER = $(call ensureDatabaseDockerState, $(1))

APP_NAME_PASCAL := $(shell echo "$(APP_NAME)" | sed -r 's/(^|-)([a-z])/\U\2/g')
APP_ORG_LOWER := $(shell echo "$(APP_ORG)" | tr '[:upper:]' '[:lower:]')

define applicationProperties
# Application Server Configuration
server.port=9292

# Database Configuration
spring.datasource.url=jdbc:mariadb://${DOCKER_DATABASE_CONTAINER_NAME}:3306/${DB_NAME}
spring.datasource.driver-class-name=org.mariadb.jdbc.Driver
spring.datasource.username=${DB_USERNAME}
spring.datasource.password=${DB_PASSWORD}

# Hibernate and JPA Configuration
spring.jpa.hibernate.ddl-auto=update
#spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MariaDBDialect
spring.jpa.hibernate.naming.physical-strategy=org.hibernate.boot.model.naming.PhysicalNamingStrategyStandardImpl
spring.jpa.show-sql=true

# Connection Pool Configuration
spring.datasource.hikari.pool-name=HikariPool
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.connection-timeout=60000
spring.datasource.hikari.idle-timeout=60000
spring.datasource.hikari.max-lifetime=1800000

# JWT Configuration
oc.app.jwtSecret=${JWT_SECRET}
oc.app.jwtExpirationMs=86400000

# Logging Configuration
logging.level.root=ERROR
logging.level.org.springframework.web=INFO
logging.level.org.hibernate=ERROR
logging.level.org.springframework=ERROR
logging.level.com.${APP_ORG}=INFO
logging.level.com.zaxxer.hikari=ERROR
logging.level.org.springframework.jdbc.datasource=ERROR
endef
export applicationProperties

define homeController
package com.$(APP_ORG_LOWER).$(APP_NAME).controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/")
public class HomeController {

    @GetMapping
    public ResponseEntity<String> home() {
        return ResponseEntity.ok("Success, enjoy this free controller");
    }
}
endef
export homeController

define securityConfig
package com.$(APP_ORG_LOWER).$(APP_NAME).config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfigurationSource;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, CorsConfigurationSource corsConfigurationSource) throws Exception {
        return http
                .cors(AbstractHttpConfigurer::disable)
                .csrf(AbstractHttpConfigurer::disable)
                .authorizeHttpRequests(
                        auth -> auth
                                .anyRequest().permitAll()).build();
    }
}
endef
export securityConfig

define ensureBackendDockerState
    if $(MAKE) back-is-running; then \
    	$(MAKE) success-msg msg="Backend container is up."; \
    else \
    	$(MAKE) command-intro-msg msg="Backend is not running, starting it"; \
        $(MAKE) app-start-docker; \
    fi; \
    $(1)
endef

define ensureFrontendDockerState
    if $(MAKE) front-is-running; then \
    	$(MAKE) success-msg msg="Frontend container is up."; \
    else \
    	$(MAKE) command-intro-msg msg="Frontend is not running, starting it"; \
        $(MAKE) app-start-docker; \
    fi; \
    $(1)
endef

define ensureDatabaseDockerState
    if $(MAKE) -s db-test-run; then \
    	$(MAKE) success-msg msg="Database container is up."; \
    else \
    	$(MAKE) command-intro-msg msg="Database is not running, starting it"; \
        $(MAKE) -s app-start-docker; \
    fi; \
    $(1)
endef

define runBackCmd
    $(DOCKER) exec -w /app $(DOCKER_BACKEND_CONTAINER_NAME) /bin/sh -c "$(1)"
endef

define runFrontCmd
    $(DOCKER) exec -w /app $(DOCKER_FRONTEND_CONTAINER_NAME) /bin/sh -c "$(1)"
endef

define runBackCmdWD
    $(DOCKER) exec -w /app $(DOCKER_BACKEND_CONTAINER_NAME) /bin/sh -c "cd $(BACKEND_WORKDIR) &&$(1)"
endef

define runFrontCmdWD
    $(DOCKER) exec -w /app $(DOCKER_FRONTEND_CONTAINER_NAME) /bin/sh -c "cd ${FRONTEND_WORKDIR} &&$(1)"
endef

define runDbCmd
    $(DOCKER) exec -w / $(DOCKER_DATABASE_CONTAINER_NAME) mariadb -u $(DB_USERNAME) -p"$(DB_PASSWORD)" --show-warnings -vvv -t $(1)
endef

#	$(call runBackCmdWD, mvn versions:use-releases)
#	$(call runBackCmdWD, mvn versions:use-next-releases)

START_SPRINGBOOT=$(call runBackCmdWD, mvn clean versions:use-latest-releases install -DskipTests spring-boot:run)
START_ANGULAR=$(call runFrontCmdWD, ng serve --host $(DOCKER_FRONTEND_CONTAINER_NAME))

run: ## Start project
	if make back-deploy-boilerplate; then \
		make success-msg msg="Database is up."; \
		make success-msg msg="Back is up."; \
	else \
	make front-deploy-boilerplate
	make success-msg msg="Front is up."
	$(START_SPRINGBOOT) & $(START_ANGULAR) & wait

app-start-docker: app-create-network ## Start the Docker containers
	$(DOCKER) compose up -d --build --force-recreate --remove-orphans

db-create-default: ## Create database
	$(call runDbCmd, -e "CREATE DATABASE IF NOT EXISTS $(DB_NAME); GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO 'root'@'%'; FLUSH PRIVILEGES;") > /dev/null 2>&1
	if [ $$? -eq 0 ]; then \
		make success-msg msg="Database $(DB_NAME) exists."; \
	else \
		make error-msg msg="Could not create database $(DB_NAME)."; \
		exit 1 > /dev/null 2>&1; \
	fi

app-create-network: ## Create the docker network shared by database, backend and frontend
	if docker network inspect ${APP_ORG}-${APP_NAME} > /dev/null 2>&1 ; then \
	    make warning-msg msg="Network '${APP_ORG}-${APP_NAME}' already exists."; \
	    exit 0; \
	else \
		if ! $(DOCKER) network create ${APP_ORG}-${APP_NAME}; then \
			make error-msg msg="Could not create '${APP_ORG}-${APP_NAME}' network"; \
			exit 1; \
		fi; \
		make success-msg msg="Network created."; \
	fi;

db-deploy-boilerplate: ##hidden Deploy the database boilerplate
	$(ENSURE_DATABASE_DOCKER)
	make db-create-default

back-deploy-boilerplate: ##hidden Deploy the backend boilerplate
	$(ENSURE_BACKEND_DOCKER) if [ -d $(BACKEND_WORKDIR) ]; then \
		make success-msg msg="Backend directory already exists."; \
		exit 0; \
	else \
	  	make recipe-intro-msg msg="Backend directory doesn't exist. Creating"; \
		if ! unzip ./.docker/boilerplate.zip > /dev/null 2>&1; then \
			make error-msg msg="Failed to unzip boilerplate."; \
			exit 1; \
		fi; \
		$(call runBackCmd, mv demo $(BACKEND_WORKDIR)); \
		make back-setup-env; \
		make success-msg msg="Backend directory created."; \
	fi

front-deploy-boilerplate: ##hidden Deploy the frontend boilerplate
	$(ENSURE_FRONTEND_DOCKER)
	if ! -f $(FRONTEND_WORKDIR)/package.json; then \
	    make warning-msg msg="Cannot start Angular, checking $(FRONTEND_WORKDIR)"; \
	    if ! $(call runFrontCmdWD, ng build); then \
	        make warning-msg msg="Cannot build project, doesn't seem to exist"; \
	        make front-create-new; \
	        exit 0; \
	    fi; \
	else \
	  	make recipe-intro-msg msg="Frontend project doesn't exist. Creating"; \
	fi

front-create-new:
	$(ENSURE_FRONTEND_DOCKER)
	make command-intro-msg msg="Creating frontend"
	make front-setup-env
	if ! $(call runFrontCmd, ng new ${APP_NAME} --directory ${FRONTEND_WORKDIR} --defaults --skip-git --skip-tests); then \
	    make error-msg msg="Could create new project."; \
	    exit 1; \
	else \
		make success-msg msg="Frontend angular app ${APP_NAME} created."; \
	fi

front-setup-env: ##hidden Create the frontend environment
	$(call runFrontCmd, mkdir -p ${FRONTEND_WORKDIR})

front-run: front-deploy-boilerplate ## Run the frontend project
	make recipe-intro-msg msg="Starting Angular"
	make front-start-server

back-run: back-deploy-boilerplate db-deploy-boilerplate ## Run the backend project
	make recipe-intro-msg msg="Starting Spring-Boot"
	make back-start-server

front-start-server: ##hidden Run the frontend server
	if ! $(START_ANGULAR); then \
  		make error-msg msg="Failed to start $(FRONTEND_WORKDIR)."; \
		exit 1; \
	fi

back-start-server: back-test-database-handshake ##hidden Run the backend server
	if ! $(START_SPRINGBOOT); then \
		make error-msg msg="Failed to start $(BACKEND_WORKDIR)."; \
		exit 1; \
	fi;

back-is-online: ## Verify that the backend is accepting requests
	if ! curl http://localhost:$(APP_BACKEND_PORT)/; then \
  		make error-msg msg="Backend not accepting requests"; \
  		exit 1; \
  	else \
  		make success-msg msg="Backend is accepting requests -> http://localhost:$(APP_BACKEND_PORT)/"; \
  	fi

front-is-online: ## Verify that the backend is accepting requests
	if ! curl http://localhost:$(APP_FRONTEND_PORT)/; then \
  		make error-msg msg="Frontend not accepting requests"; \
  		exit 1; \
  	else \
  		make success-msg msg="Frontend is accepting requests -> http://localhost:$(APP_FRONTEND_PORT)/"; \
  	fi

back-test-database-handshake: ## Verify that the backend can communicate with the database
	if ! $(call runBackCmd, nc -zv $(DOCKER_DATABASE_CONTAINER_NAME) 3306) > /dev/null 2>&1; then \
		make error-msg msg="Cannot connect to database."; \
		exit 1; \
	fi; \
	make success-msg msg="Connected to database."
	exit 0

back-setup-env: ## Configure application properties
	make command-intro-msg msg="Setting environment"
	make back-set-app-prop
	make back-rename-app
	make success-msg msg="Application renamed."
	make back-starter-code
	$(shell runBackCmd, sudo chown -R $$(whoami):$$(whoami) .)
	make success-msg msg="Environment is set"

a-set-gitignore: ##hidden Sets the parent folder .gitignore file
	make command-intro-msg msg="Creating .gitignore"
	$(call runBackCmd, touch .gitignore && echo ".idea" | tee .gitignore)
	make success-msg msg=".gitignore created."

back-set-app-prop: ##hidden Sets the starting set of application properties
	make command-intro-msg msg="Setting application.properties"
	$(call runBackCmdWD, echo '$$applicationProperties' | tee src/main/resources/application.properties) > /dev/null 2>&1
	make success-msg msg="application.properties written"

back-starter-code: ##hidden Creates a HomeController and simple "permitAll" SecurityConfig
	make command-intro-msg msg="Creating HomeController"
	$(call runBackCmdWD, mkdir -p $(BACKEND_HOME_CONTROLLER_PATH))
	$(call runBackCmdWD, touch $(BACKEND_HOME_CONTROLLER_PATH)/HomeController.java)
	$(call runBackCmdWD, echo '$$homeController' | tee $(BACKEND_HOME_CONTROLLER_PATH)/HomeController.java) > /dev/null 2>&1

	if -n $(call runBackCmdWD, cat $(BACKEND_HOME_CONTROLLER_PATH)/HomeController.java); then \
		make warning-msg msg="Could not create $(BACKEND_HOME_CONTROLLER_PATH)/HomeController.java"; \
	else \
		make success-msg msg="HomeController created."; \
	fi

	make command-intro-msg msg="Creating SecurityConfig"
	$(call runBackCmdWD, mkdir -p $(BACKEND_SECURITY_CONFIG_PATH))
	$(call runBackCmdWD, touch $(BACKEND_SECURITY_CONFIG_PATH)/SecurityConfig.java)
	$(call runBackCmdWD, echo '$$securityConfig' | tee $(BACKEND_SECURITY_CONFIG_PATH)/SecurityConfig.java) > /dev/null 2>&1

	if -n $(call runBackCmdWD, cat $(BACKEND_SECURITY_CONFIG_PATH)/SecurityConfig.java); then \
		make warning-msg msg="Could not create $(BACKEND_SECURITY_CONFIG_PATH)/SecurityConfig.java"; \
	else \
		make success-msg msg="SecurityConfig created."; \
  	fi

back-prune: ## Through prompts, create a backup, delete the backend directory and the container
	make recipe-intro-msg msg="Project deletion"
	make -s back-directory-backup back-directory-prune back-container-prune db-container-prune

db-container-prune: ##hidden Delete current mariadb container
	if ! make -s db-test-run; then \
      		make error-msg msg="No $(DOCKER_DATABASE_CONTAINER_NAME) containers found."; \
    		exit 1 > /dev/null 2>&1; \
	fi; \

	read -p "Are you sure you want to delete the current $(DOCKER_DATABASE_CONTAINER_NAME) container? (yes/[no]):" response; \
    		if [ "$$response" = "yes" ]; then \
    		  	make command-intro-msg msg="Deleting $(DOCKER_DATABASE_CONTAINER_NAME) containers"; \
    			$(DOCKER) stop $(DOCKER_DATABASE_CONTAINER_NAME); \
    			$(DOCKER) rm $(DOCKER_DATABASE_CONTAINER_NAME); \
    			make success-msg msg="'$(DOCKER_DATABASE_CONTAINER_NAME)' docker container deleted successfully."; \
    		else \
    		  	make success-msg msg="'$(DOCKER_DATABASE_CONTAINER_NAME)' Container deletion cancelled."; \
    			exit 0; \
    		fi

back-container-prune: ##hidden Delete current java container
	if ! make -s back-is-running; then \
  		make error-msg msg="No $(DOCKER_BACKEND_CONTAINER_NAME) containers found."; \
		exit 1 > /dev/null 2>&1; \
  	fi; \

	read -p "Are you sure you want to delete the current $(DOCKER_BACKEND_CONTAINER_NAME) container? (yes/[no]):" response; \
		if [ "$$response" = "yes" ]; then \
		  	make command-intro-msg msg="Deleting $(DOCKER_BACKEND_CONTAINER_NAME) containers"; \
			$(DOCKER) stop $(DOCKER_BACKEND_CONTAINER_NAME); \
			$(DOCKER) rm $(DOCKER_BACKEND_CONTAINER_NAME); \
			make success-msg msg="'$(DOCKER_BACKEND_CONTAINER_NAME)' docker container deleted successfully."; \
		else \
		  	make success-msg msg="'$(DOCKER_BACKEND_CONTAINER_NAME)' Container deletion cancelled."; \
			exit 0; \
		fi

back-directory-backup: ##hidden Backup backend directory
	if [ ! -d $(BACKEND_WORKDIR) ]; then \
		make error-msg msg="'./$(BACKEND_WORKDIR)' directory not found"; \
		exit 1 > /dev/null 2>&1; \
    fi; \

	make success-msg msg="'./$(BACKEND_WORKDIR)' directory found."; \
	read -p "Do you want to back it up before deletion? ([yes]/no):" response; \
	if [ "$$response" != "yes" ] && [ "$$response" != "" ]; then \
		make success-msg msg="Backup cancelled."; \
		exit 0; \
	else \
		$(call runBackCmdWD, mkdir -p .$(BACKEND_WORKDIR)-archives); \
		$(call runBackCmdWD, zip -9r ./.$(BACKEND_WORKDIR)-archives/$(BACKEND_WORKDIR)-backup-$(TIMESTAMP).zip $(BACKEND_WORKDIR)) || { make error-msg msg="Failed to create backup."; exit 1; }; \
		make success-msg msg="'./$(BACKEND_WORKDIR)' backed up successfully to ./.$(BACKEND_WORKDIR)-archives/$(BACKEND_WORKDIR)-backup-$(TIMESTAMP).zip."; \
	fi;

back-directory-prune: ##hidden Delete backend directory
	if [ ! -d $(BACKEND_WORKDIR) ]; then \
    	make error-msg msg="'./$(BACKEND_WORKDIR)' directory not found"; \
		exit 1; \
    fi; \

	make success-msg msg="'./$(BACKEND_WORKDIR)' directory found."; \
	read -p "Are you sure you want to delete this './$(BACKEND_WORKDIR)'? (yes/[no]):" response; \
	if [ "$$response" = "yes" ]; then \
		make command-intro-msg msg="Deleting './$(BACKEND_WORKDIR)'"; \
		$(call runBackCmd, rm -rf $(BACKEND_WORKDIR)); \
		make success-msg msg="'./$(BACKEND_WORKDIR)' has been deleted successfully."; \
		exit 0; \
	else \
		make success-msg msg="'./$(BACKEND_WORKDIR)' deletion cancelled."; \
		exit 0; \
	fi;

back-is-running: ## Check if the backend docker container is running
	if $(DOCKER) ps --quiet --filter name=^$(DOCKER_BACKEND_CONTAINER_NAME) | grep -q .; then \
		exit 0; \
	else \
  		make warning-msg msg="Backend is not running."; \
  		exit 1; \
  	fi

front-is-running: ## Check if the backend docker container is running
	if $(DOCKER) ps --quiet --filter name=^$(DOCKER_FRONTEND_CONTAINER_NAME) | grep -q .; then \
		exit 0; \
	else \
		make warning-msg msg="Frontend is not running."; \
		exit 1; \
	fi

db-test-run: ## Check if the database docker container is running
	if $(DOCKER) ps --quiet --filter name=^$(DOCKER_DATABASE_CONTAINER_NAME) | grep -q .; then \
		exit 0; \
	else \
		make error-msg msg="Database is not running."; \
		exit 1; \
	fi

back-rename-app: ##hidden Rename the app according to the .env variables
	if [ ! -d $(BACKEND_WORKDIR) ]; then \
		make error-msg msg="Cannot rename app, './$(BACKEND_WORKDIR)' directory not found"; \
		exit 1; \
	fi

	$(call runBackCmd, mkdir -p .$(BACKEND_WORKDIR)-archives)

	if ! $(call runBackCmd, pwd && ls -la && zip -9r ./.$(BACKEND_WORKDIR)-archives/$(BACKEND_WORKDIR)-backup-$(TIMESTAMP).zip $(BACKEND_WORKDIR)) > /dev/null 2>&1; then \
  		make error-msg msg="Failed to create backup."; \
		exit 1; \
	fi

	make command-intro-msg msg="Renaming app with given name"

	if [ ! -d "$(BACKEND_WORKDIR)/src/main/java/com/example" ]; then \
		make error-msg msg="Source directory not found. Checking alternative location"; \
		if [ ! -d "demo/src/main/java/com/example" ]; then \
			make error-msg msg="Could not find source directory structure"; \
			exit 1; \
		fi; \
		$(call runBackCmd, mv demo/* .); \
		$(call runBackCmd, rmdir demo); \
	fi

	$(call runBackCmd, find . -type f -name "*.java" -exec sed -i 's/com\.example\.demo/com.$(APP_ORG_LOWER).$(APP_NAME)/g' {} +)

	$(call runBackCmd, find . -type f -name "*.java" -exec sed -i 's/com\.example/com.$(APP_ORG_LOWER)/g' {} +)

	$(call runBackCmd, find . -type f -name "*.java" -exec sed -i 's/example/$(APP_ORG_LOWER)/g' {} +)

	if [ -f $(BACKEND_WORKDIR)/src/main/resources/application.properties ]; then \
		$(call runBackCmdWD, sed -i 's/spring.application.name=.*/spring.application.name=$(APP_NAME)/g' src/main/resources/application.properties); \
	fi

	if [ -d $(BACKEND_WORKDIR)/src/main/java/com/example ]; then \
		$(call runBackCmdWD, mkdir -p src/main/java/com/$(APP_ORG_LOWER)) && \
		$(call runBackCmdWD, cp -r src/main/java/com/example/* src/main/java/com/$(APP_ORG_LOWER)/) && \
		$(call runBackCmdWD, rm -rf src/main/java/com/example); \
	fi

	if [ -d $(BACKEND_WORKDIR)/src/test/java/com/example ]; then \
		$(call runBackCmdWD, mkdir -p src/test/java/com/$(APP_ORG_LOWER)) && \
		$(call runBackCmdWD, cp -r src/test/java/com/example/* src/test/java/com/$(APP_ORG_LOWER)/) && \
		$(call runBackCmdWD, rm -rf src/test/java/com/example); \
	fi

	if [ -f $(BACKEND_WORKDIR)/src/main/java/com/$(APP_ORG_LOWER)/demo/DemoApplication.java ]; then \
		$(call runBackCmdWD, mkdir -p src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)) && \
		$(call runBackCmdWD, mv src/main/java/com/$(APP_ORG_LOWER)/demo/DemoApplication.java src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/$(APP_NAME_PASCAL)Application.java) && \
		$(call runBackCmdWD, rm -rf src/main/java/com/$(APP_ORG_LOWER)/demo) && \
		$(call runBackCmdWD, sed -i 's/DemoApplication/$(APP_NAME_PASCAL)Application/g' src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/$(APP_NAME_PASCAL)Application.java) && \
		$(call runBackCmdWD, sed -i 's/package com.$(APP_ORG_LOWER).demo/package com.$(APP_ORG_LOWER).$(APP_NAME)/g' src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/$(APP_NAME_PASCAL)Application.java); \
	fi

	if [ -f $(BACKEND_WORKDIR)/src/test/java/com/$(APP_ORG_LOWER)/demo/DemoApplicationTests.java ]; then \
		$(call runBackCmdWD, mkdir -p src/test/java/com/$(APP_ORG_LOWER)/$(APP_NAME)) && \
		$(call runBackCmdWD, mv src/test/java/com/$(APP_ORG_LOWER)/demo/DemoApplicationTests.java src/test/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/$(APP_NAME_PASCAL)ApplicationTests.java) && \
		$(call runBackCmdWD, rm -rf src/test/java/com/$(APP_ORG_LOWER)/demo) && \
		$(call runBackCmdWD, sed -i 's/DemoApplication/$(APP_NAME_PASCAL)Application/g' src/test/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/$(APP_NAME_PASCAL)ApplicationTests.java) && \
		$(call runBackCmdWD, sed -i 's/package com.$(APP_ORG_LOWER).demo/package com.$(APP_ORG_LOWER).$(APP_NAME)/g' src/test/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/$(APP_NAME_PASCAL)ApplicationTests.java); \
	fi

	if [ -f $(BACKEND_WORKDIR)/pom.xml ]; then \
		$(call runBackCmdWD, sed -i 's/<artifactId>demo<\/artifactId>/<artifactId>$(APP_NAME)<\/artifactId>/g' pom.xml); \
		$(call runBackCmdWD, sed -i 's/<groupId>com\.example<\/groupId>/<groupId>com.$(APP_ORG_LOWER)<\/groupId>/g' pom.xml); \
		$(call runBackCmdWD, sed -i 's/<name>demo<\/name>/<name>$(APP_NAME)<\/name>/g' pom.xml); \
		$(call runBackCmdWD, sed -i 's/<description>Demo project for Spring Boot<\/description>/<description>$(APP_NAME) Project authored by $(APP_ORG) powered by the MaxdlrJMA app deployer.<\/description>/g' pom.xml); \
		$(call runBackCmdWD, sed -i 's/<java.version>.*<\/java.version>/<java.version>$(JAVA_VERSION)<\/java.version>/g' pom.xml); \
	fi

back-backups-prune-force: ## Delete all backup files
	if make -S back-is-running; then \
		$(call runBackCmd, rm -fr .backend-archives); \
	else \
	  	make warning-msg msg="Cannot delete .backend-archives directory through container: No such container."; \
	fi

back-directory-prune-force: ## Delete backend directory
	if make back-is-running; then \
	  	$(call runBackCmd, rm -rf $(BACKEND_WORKDIR)); \
	else \
		make warning-msg msg="Cannot delete backend directory through container: No such container."; \
	fi

front-directory-prune-force: ## Delete backend directory
	if make front-is-running; then \
	  	$(call runFrontCmd, rm -rf $(FRONTEND_WORKDIR)); \
	else \
		make warning-msg msg="Cannot delete frontend directory through container: No such container."; \
	fi

app-prune-force: ##hidden Force delete project files, do not backup and delete container
	make recipe-intro-msg msg="Deleting everything"; \
	make back-directory-prune-force; \
	make front-directory-prune-force; \
	make back-backups-prune-force; \
	make app-docker-entities-prune-all-force; \
	make success-msg msg="Everything has been deleted"; \

app-docker-entities-prune-all-force: ##hidden Force delete all volumes, networks, images
	if [ -n "$(DOCKER_APP_VOLUMES)" ]; then \
		make command-intro-msg msg="Removing volumes: $(DOCKER_APP_VOLUMES)"; \
		docker volume rm $(DOCKER_APP_VOLUMES) > /dev/null 2>&1; \
		make success-msg msg="Volumes removed."; \
	fi; \
	if [ -n "$(DOCKER_APP_CONTAINER_IDS)" ]; then \
		make command-intro-msg msg="Stopping and removing containers: $(DOCKER_APP_CONTAINER_IDS)"; \
		docker stop $(DOCKER_APP_CONTAINER_IDS) > /dev/null 2>&1; \
		docker rm $(DOCKER_APP_CONTAINER_IDS) > /dev/null 2>&1; \
		make success-msg msg="Containers removed."; \
	fi; \
	if [ -n "$(DOCKER_APP_UNUSED_NETWORKS)" ]; then \
		make command-intro-msg msg="Removing networks: $(DOCKER_APP_UNUSED_NETWORKS)"; \
		docker network rm $(DOCKER_APP_UNUSED_NETWORKS) > /dev/null 2>&1; \
		make success-msg msg="Networks removed."; \
	fi; \
	if [ -n "$(DOCKER_APP_DANGLING_IMAGES)" ]; then \
		make command-intro-msg msg="Removing dangling images: $(DOCKER_APP_DANGLING_IMAGES)"; \
		docker rmi $(DOCKER_APP_DANGLING_IMAGES) > /dev/null 2>&1; \
		make success-msg msg="Images deleted."; \
	fi


command-intro-msg: ##hidden Styles a command intro message
	echo "[$(PRIMARY_COLOR)$(APP_NAME)$(END_COLOR)] -------------$(SUCCESS_COLOR)|=>$(END_COLOR) $(PRIMARY_COLOR)$(msg)... $(END_COLOR)";
recipe-intro-msg: ##hidden Styles a recipe intro message
	echo "[$(PRIMARY_COLOR)$(APP_NAME)$(END_COLOR)] -- $(PRIMARY_COLOR)[ ------------- $(msg)... ------------- ]$(END_COLOR)";
success-msg: ##hidden Styles a success message
	echo "[$(PRIMARY_COLOR)$(APP_NAME)$(END_COLOR)] -- $(SUCCESS_COLOR)[OK]$(END_COLOR) -- $(SUCCESS_COLOR)$(msg)$(END_COLOR)";
error-msg: ##hidden Styles an error message
	echo "[$(PRIMARY_COLOR)$(APP_NAME)$(END_COLOR)] -- $(ERROR_COLOR)[ERROR]$(END_COLOR) -- $(ERROR_COLOR)$(msg)$(END_COLOR)";
warning-msg: ##hidden Styles an error message
	echo "[$(PRIMARY_COLOR)$(APP_NAME)$(END_COLOR)] -- $(WARNING_COLOR)[WARN]$(END_COLOR) -- $(WARNING_COLOR)$(msg)$(END_COLOR)";
a-loading: ##hidden Pause execution
	make command-intro-msg msg="Loading"
	count=$$(($(time))); \
	while [ $$count -ge 0 ]; do \
		echo $$count; \
		sleep 1; \
		count=$$((count - 1)); \
	done

help: ## This menu
	echo "Usage: make [target]"
	echo "If this is your first time, you are likely looking for: $(SUCCESS_COLOR)make back-run$(END_COLOR) here, and $(SUCCESS_COLOR)make front-run$(END_COLOR) in another terminal buffer."

	echo
	echo "Available targets:"
	echo
	echo "---------- $(PRIMARY_COLOR)App commands$(END_COLOR)"
	awk -F ':|##' '/^app-.*?:.*?##/ && !/##hidden/ {printf "$(SUCCESS_COLOR)%-30s$(END_COLOR) %s\n", $$1, $$NF}' $(MAKEFILE_LIST) | sort
	echo
	echo "---------- $(PRIMARY_COLOR)Backend commands$(END_COLOR)"
	awk -F ':|##' '/^back-.*?:.*?##/ && !/##hidden/ {printf "$(SUCCESS_COLOR)%-30s$(END_COLOR) %s\n", $$1, $$NF}' $(MAKEFILE_LIST) | sort
	echo
	echo "---------- $(PRIMARY_COLOR)Frontend commands$(END_COLOR)"
	awk -F ':|##' '/^front-.*?:.*?##/ && !/##hidden/ {printf "$(SUCCESS_COLOR)%-30s$(END_COLOR) %s\n", $$1, $$NF}' $(MAKEFILE_LIST) | sort
	echo
