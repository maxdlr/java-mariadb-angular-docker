MAKEFLAGS += --no-print-directory
include .env
export $(shell sed 's/=.*//' .env)
default: help

define applicationProperties
server.port=$(APP_PORT)
spring.datasource.url=jdbc:mysql://localhost:$(DB_PORT)/$(DB_NAME)?allowPublicKeyRetrieval=true
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver
spring.datasource.username=$(DB_USERNAME)
spring.datasource.password=$(DB_PASSWORD)
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MariaDBDialect
spring.jpa.hibernate.naming.physical-strategy=org.hibernate.boot.model.naming.PhysicalNamingStrategyStandardImpl
#spring.jpa.hibernate.ddl-auto=create-drop
#spring.jpa.properties.jakarta.persistence.schema-generation.scripts.action=create
#spring.jpa.properties.jakarta.persistence.schema-generation.scripts.create-target=create.sql
#spring.jpa.properties.jakarta.persistence.schema-generation.scripts.create-source=metadata
spring.jpa.show-sql=true
oc.app.jwtSecret=$(JWT_SECRET)
oc.app.jwtExpirationMs=86400000
logging.level.org.springframework.web=DEBUG
logging.level.org.hibernate=DEBUG
logging.level.org.springframework.boot.web=DEBUG
logging.level.org.springframework=DEBUG
logging.level.com.openclassrooms=DEBUG
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
HOME_CONTROLLER_PATH=$(BACKEND_WORKDIR)/src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/controller

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
SECURITY_CONFIG_PATH=$(BACKEND_WORKDIR)/src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/config

define ensureDockerState
    @if $(MAKE) -s backend-is-running; then \
        echo "Backend is running."; \
    else \
        echo "Backend is not running, starting it..."; \
        $(MAKE) -s backend-start-docker; \
    fi; \
    $(1)
endef

define runDockerCommand
    @$(DOCKER_UP) $(DOCKER) exec -w $(DOCKER_WORKDIR) $(CONTAINER_NAME) /bin/sh -c "$(1)";
endef

# Command shortcuts
RUN = $(call runDockerCommand, $(1))
ENSURE_DOCKER = $(call ensureDockerState, $(1))

# Global variables
DOCKER = docker
CONTAINER_NAME=jma-$(APP_NAME)
TIMESTAMP := $(shell date '+%Y-%m-%d_%H-%M-%S')

backend-start-docker: ## Start the backend Docker container
	$(DOCKER) compose up -d --build --force-recreate --remove-orphans; \

backend-deploy-boilerplate: ## Deploy the backend boilerplate
	@$(ENSURE_DOCKER) if [ -d $(BACKEND_WORKDIR) ]; then \
		exit 0; \
	else \
	  	echo "Backend directory doesn't exist. Creating..."; \
		$(RUN) unzip ./.docker/boilerplate.zip || { echo "Failed to unzip boilerplate."; exit 1; }; \
		$(RUN) mv demo $(BACKEND_WORKDIR); \
		$(MAKE) backend-setup-env; \
	  	echo "Backend directory created successfully."; \
	fi; \

backend-run: backend-deploy-boilerplate ## Run the backend project
	@$(RUN) cd $(BACKEND_WORKDIR) && mvn clean spring-boot:run || { echo "Failed to start $(BACKEND_WORKDIR)."; exit 1; }
	echo "Application started successfully on http://localhost:$(APP_PORT)"

backend-setup-env: ## Configure application properties
	$(RUN) echo "Writing application.properties..."
	@mkdir -p $(BACKEND_WORKDIR)/src/main/resources; \
	echo "application.properties written successfully."
	make backend-rename-app
	echo "$$applicationProperties" >> $(BACKEND_WORKDIR)/src/main/resources/application.properties
	make backend-starter-url

backend-starter-url: ## Creates a HomeController and simple "permitAll" SecurityConfig
	@mkdir -p $(HOME_CONTROLLER_PATH); \
	touch $(HOME_CONTROLLER_PATH)/HomeController.java; \
	echo "$$homeController" >> $(HOME_CONTROLLER_PATH)/HomeController.java; \

	@mkdir -p $(SECURITY_CONFIG_PATH); \
	touch $(SECURITY_CONFIG_PATH)/SecurityConfig.java; \
	echo "$$securityConfig" >> $(SECURITY_CONFIG_PATH)/SecurityConfig.java; \

	@echo "Starter pack url created."


backend-prune: ## Create a backup and remove the backend
	@make -s backend-directory-backup backend-directory-delete backend-prune-container

backend-prune-container: ## Delete current java container
	@if ! $(MAKE) -s backend-is-running; then \
		echo "No $(CONTAINER_NAME) containers found."; \
		exit 1; \
  	fi; \

	@read -p "Are you sure you want to delete the current $(CONTAINER_NAME) container? (yes/[no]):" response; \
		if [ "$$response" = "yes" ]; then \
			echo "Deleting $(CONTAINER_NAME) containers..."; \
			$(DOCKER) stop $(CONTAINER_NAME); \
			$(DOCKER) rm $(CONTAINER_NAME); \
			echo "'$(CONTAINER_NAME)' docker container deleted successfully."; \
		else \
			echo "Container deletion cancelled."; \
			exit 0; \
		fi; \


backend-directory-backup: ## Backup backend directory
	@if [ ! -d $(BACKEND_WORKDIR) ]; then \
    	echo "'./$(BACKEND_WORKDIR)' directory not found"; \
		exit 1; \
    fi; \

	@echo "'./$(BACKEND_WORKDIR)' directory found."; \
	read -p "Do you want to back it up before deletion? ([yes]/no):" response; \
	if [ "$$response" != "yes" ] && [ "$$response" != "" ]; then \
		echo "Backup cancelled."; \
		exit 0; \
	else \
		mkdir -p .$(BACKEND_WORKDIR)-archives; \
		$(RUN) zip -9r ./.$(BACKEND_WORKDIR)-archives/$(BACKEND_WORKDIR)-backup-$(TIMESTAMP).zip $(BACKEND_WORKDIR) || { echo "Failed to create backup."; exit 1; }; \
		echo "'./$(BACKEND_WORKDIR)' backed up successfully to ./.$(BACKEND_WORKDIR)-archives/$(BACKEND_WORKDIR)-backup-$(TIMESTAMP).zip."; \
	fi; \

backend-directory-delete: ## Delete backend directory
	@if [ ! -d $(BACKEND_WORKDIR) ]; then \
    	echo "'./$(BACKEND_WORKDIR)' directory not found"; \
		exit 1; \
    fi; \

	@echo "'./$(BACKEND_WORKDIR)' directory found."; \
	read -p "Are you sure you want to delete this './$(BACKEND_WORKDIR)'? (yes/[no]):" response; \
	if [ "$$response" = "yes" ]; then \
		echo "Deleting './$(BACKEND_WORKDIR)'..."; \
		rm -rf $(BACKEND_WORKDIR); \
		echo "'./$(BACKEND_WORKDIR)' has been deleted successfully."; \
		exit 0; \
	else \
		echo "'./$(BACKEND_WORKDIR)' deletion cancelled."; \
		exit 0; \
	fi; \

backend-is-running: ## Check if the backend is running
	@if $(DOCKER) ps --quiet --filter name=^$(CONTAINER_NAME) | grep -q .; then \
		exit 0; \
	else \
  		echo "Backend is not running."; \
  		exit 1; \
  	fi

APP_NAME_PASCAL := $(shell echo "$(APP_NAME)" | sed -r 's/(^|-)([a-z])/\U\2/g')
APP_ORG_LOWER := $(shell echo "$(APP_ORG)" | tr '[:upper:]' '[:lower:]')

backend-rename-app:
	@mkdir -p .$(BACKEND_WORKDIR)-archives; \
	zip -9r ./.$(BACKEND_WORKDIR)-archives/$(BACKEND_WORKDIR)-backup-$(TIMESTAMP).zip $(BACKEND_WORKDIR) || { echo "Failed to create backup."; exit 1; }; \
	echo "Renaming app with given name..."
	@cd $(BACKEND_WORKDIR) && \
	if [ ! -d "src/main/java/com/example" ]; then \
		echo "Source directory not found. Checking alternative location..."; \
		if [ ! -d "demo/src/main/java/com/example" ]; then \
			echo "ERROR: Could not find source directory structure"; \
			exit 1; \
		fi; \
		mv demo/* .; \
		rmdir demo; \
	fi && \
	find . -type f -name "*.java" -exec sed -i "s/com\.example\.demo/com.$(APP_ORG_LOWER).$(APP_NAME)/g" {} + && \
	find . -type f -name "*.java" -exec sed -i "s/com\.example/com.$(APP_ORG_LOWER)/g" {} + && \
	find . -type f -name "*.java" -exec sed -i "s/example/$(APP_ORG_LOWER)/g" {} + && \
	if [ -f src/main/resources/application.properties ]; then \
		sed -i "s/spring.application.name=.*/spring.application.name=$(APP_NAME)/g" src/main/resources/application.properties; \
	fi && \
	if [ -d src/main/java/com/example ]; then \
		mkdir -p src/main/java/com/$(APP_ORG_LOWER) && \
		cp -r src/main/java/com/example/* src/main/java/com/$(APP_ORG_LOWER)/ && \
		rm -rf src/main/java/com/example; \
	fi && \
	if [ -f src/main/java/com/$(APP_ORG_LOWER)/demo/DemoApplication.java ]; then \
		mkdir -p src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME) && \
		mv src/main/java/com/$(APP_ORG_LOWER)/demo/DemoApplication.java src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/$(APP_NAME_PASCAL)Application.java && \
		rm -rf src/main/java/com/$(APP_ORG_LOWER)/demo && \
		sed -i "s/DemoApplication/$(APP_NAME_PASCAL)Application/g" src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/$(APP_NAME_PASCAL)Application.java && \
		sed -i "s/package com.$(APP_ORG_LOWER).demo/package com.$(APP_ORG_LOWER).$(APP_NAME)/g" src/main/java/com/$(APP_ORG_LOWER)/$(APP_NAME)/$(APP_NAME_PASCAL)Application.java; \
	fi && \
	if [ -f pom.xml ]; then \
		sed -i "s/<artifactId>demo<\/artifactId>/<artifactId>$(APP_NAME)<\/artifactId>/g" pom.xml && \
		sed -i "s/<groupId>com\.example<\/groupId>/<groupId>com.$(APP_ORG_LOWER)<\/groupId>/g" pom.xml; \
	fi && \
	echo "Application renamed successfully."

# Help target to display available commands
help:
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-30s %s\n", $$1, $$2}'
