This project aims to create a development environment deployer and manager.

First time setup:
```bash
make back-run
```
and
```bash
make front-run
```


# Roadmap
## Backend
- [x] Create a Docker Java container
- [x] Create and run a Java/SpringBoot web project from a provided Spring Boot initializer demo.zip file.
- [x] Set project up with ``.env`` file variables.
  - [x] Set application.properties to connect to database
  - [x] Export Backend port of choice
  - [x] Name Backend directory with given string

## Database
- [x] Create a Docker Mariadb container
- [x] Create a Mariadb database with given name
- [ ] Execute given ``.sql`` script if given any.

## Frontend
- [ ] Create a Docker NodeJs container
- [ ] Create and run an Angular project
- [ ] Set Project with default librairies
  - [ ] Prettier
  - [ ] Esling
  - [ ] Angular Material
  -
