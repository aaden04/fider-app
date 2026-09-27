# Local Container Setup

## Purpose

Fider is an open-source web application that provides a central place for collecting and discussing feedback. Users can create accounts, submit suggestions, view posts, vote, comment and receive account related emails. Administrators and organisations can review submissions and engage with users through organised discussion threads.

Running Fider locally with containers makes it possible to understand and test its application dependencies, networking, data storage and email flow before deploying it to AWS. It also helps identify which services require public access and which should remain private in the production architecture.

## Application Components

### Fider

The Fider container runs the compiled Fider application and contains the runtime files required to serve the backend and frontend. It is created from the `fider-app-image:local` image and is available from the Windows host through the `3000:3000` port mapping.

### PostgreSQL

The PostgreSQL container runs PostgreSQL 17 and stores Fider’s users, suggestions, comments, votes and other structured data. Windows port `5555` maps to PostgreSQL’s internal port `5432`. Its database files are stored outside the container in the `pgdev-data` volume, which is mounted at `/var/lib/postgresql/data`.

### MailHog

The MailHog container provides a local email testing service. Fider sends messages to MailHog using SMTP on port `1025`, while captured messages can be viewed in a browser using HTTP on port `8025`. MailHog stores the messages locally and does not deliver them to real external inboxes.


## Multi-Stage Docker Build

The Fider image uses a three stage Docker build so the backend and frontend can be built separately before their outputs are combined into a smaller runtime image.

### Backend Builder

The backend stage uses a Debian-based Go image and `/build` as its working directory. It copies the files that list and verify Fider’s Go dependencies, downloads the required modules and then copies the application source code. The `build-server` Makefile target compiles the Go backend into a Linux executable named `fider`.

### Frontend Builder

The frontend stage uses a Debian-based Node.js image. It copies `package.json` and `package-lock.json`, then uses `npm ci` to install the exact JavaScript dependency versions. The Makefile build targets produce the browser assets in `dist/` and the server-side rendering file `ssr.js`.

### Runtime

The final stage uses a smaller Debian image and installs trusted CA certificates for secure HTTPS connections. It copies the compiled Fider executable, frontend assets, SSR file, migrations, views, localisation files and static files from the two builder stages.

Go, Node.js, npm, compilers and other build tools are not copied into the final stage because the application has already been built. This reduces the final image size and limits unnecessary software in the runtime environment.

## Local Networking

Docker Compose automatically created the fider-app_default network for PostgreSQL and MailHog. The Fider container was started separately and manually connected to the same network.

Each container has its own isolated network environment, so localhost inside Fider refers only to the Fider container. Fider reaches PostgreSQL through pgdev:5432 and MailHog through smtp:1025, using Docker’s internal DNS to resolve the service names.

The Fider container publishes port 3000 to the Windows host, allowing the application to be accessed through http://localhost:3000. PostgreSQL is published as localhost:5555, and MailHog’s browser interface is published as localhost:8025.

## Email Testing

Fider acts as an SMTP client and sends account related messages to MailHog, which acts as a local SMTP server. The containers communicate through Docker’s private network using smtp:1025.

MailHog captures messages rather than delivering them to real external inboxes. Captured messages can be viewed through its HTTP interface at http://localhost:8025. This allowed the account verification process to be tested safely with a non-existent email address.

## Request and Database Flow

Creating a suggestion demonstrated the path between the browser, Fider and PostgreSQL. The browser sent an HTTP POST request to /api/v1/posts. Fider processed the request and issued an INSERT INTO posts SQL statement to PostgreSQL.

PostgreSQL stored the suggestion and returned its identifier. Fider completed the request with HTTP status 200, after which the browser sent a GET request to load the newly created suggestion page.

This demonstrates two separate communication paths:

The browser communicates with Fider using HTTP.

Fider communicates with PostgreSQL using the PostgreSQL protocol and SQL queries.

## Production Replacements

The local setup is designed to reproduce the main application relationships before deployment to AWS.

The local Fider container will become a Fider pod running in Amazon EKS.

The PostgreSQL development container will be replaced by Amazon RDS for PostgreSQL.

The pgdev-data Docker volume will be replaced by managed RDS storage and backups.

MailHog will be replaced by Amazon SES for real email delivery.

Local environment variables will be replaced by Kubernetes configuration and secrets sourced from AWS Secrets Manager.

localhost:3000 will be replaced by a public HTTPS domain using Route 53, an Application Load Balancer and ACM.

Docker’s private network will be replaced by VPC and Kubernetes networking.

Only the public application entry point should accept user traffic. EKS worker nodes, RDS and other supporting services should remain private wherever possible.

## Troubleshooting Evidence


The container status showed Fider as running and healthy, with Windows port 3000 mapped to container port 3000. The startup logs confirmed that 95 database migrations were applied, the PostgreSQL and SMTP services were initialised and the HTTP server started on port 3000.

A request finishing with HTTP status 200 confirmed that the application returned a successful response. SQL SELECT statements showed Fider reading data from PostgreSQL, while INSERT INTO posts showed a new suggestion being stored.

The investigation also demonstrated the importance of filtering noisy logs. HTTP methods such as GET and POST describe communication between the browser and Fider, while SQL operations such as SELECT and INSERT describe communication between Fider and PostgreSQL.

## Docker Compose Workflow

Docker Compose manages the three services required for local development:

- Fider provides the web application and listens internally on port `3000`.
- PostgreSQL stores users, suggestions, comments and other application data.
- MailHog captures development emails sent by Fider.

Compose creates a private network where services can locate one another through Docker DNS. Fider connects to PostgreSQL using `postgres:5432` and sends email to MailHog using SMTP at `mailhog:1025`. The Fider application is available to the host at `http://localhost:3000`, while MailHog's HTTP interface is available at `http://localhost:8025`.

### Environment Configuration

Local configuration is provided through an ignored `.env` file. The committed `.env.example` documents the required variables without containing real secrets. Compose constructs Fider's database URL from the configured PostgreSQL username, password and database name.

### Startup Readiness

Starting a PostgreSQL container does not immediately prove that the database can accept connections. During initialisation, PostgreSQL prepares its files and creates the configured user and database.

The PostgreSQL health check uses `pg_isready` to confirm that it can accept connections. Fider waits for this successful result before its container starts. Its startup command then runs outstanding database migrations before starting the web server.

This prevents Fider from attempting migrations while PostgreSQL is still initialising.

### Persistent Storage

PostgreSQL stores its files in the named `postgres-data` volume. The volume exists separately from the PostgreSQL container.

Persistence was tested by running `docker compose down`, confirming that the volume remained, recreating the containers and checking that the account and test suggestion still existed. This proved that containers can be replaced without deleting the application data.

The volume must not be removed unless the local database data is intentionally being deleted.

### Troubleshooting Docker DNS

A deliberate failure was introduced by changing the database hostname from `postgres` to `wrong-postgres`. Fider exited during its migration step and produced the following error:

```text
dial tcp: lookup wrong-postgres on 127.0.0.11:53: no such host
```

The error showed that Fider asked Docker's internal DNS server to resolve a service that did not exist. Restoring the Compose service name `postgres` and recreating the Fider container restored the connection.

This demonstrated that Compose service names act as internal hostnames.

### Non-Root Runtime

The runtime image creates a dedicated `fider` system user after completing the operating-system package installation. Ownership of `/app` is assigned to this user, and the Dockerfile switches to it before the health check and startup command run.

This prevents the Fider process from running as root and limits the permissions available if the application is compromised.

### Common Commands

```bash
# Build and start the complete environment
docker compose up -d --build

# Inspect service state and health
docker compose ps

# Read service logs
docker compose logs --tail=100 fider postgres mailhog

# Stop and remove containers while preserving database data
docker compose down
```

