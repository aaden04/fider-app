# Application CI

## Purpose

The application CI workflow checks code changes before and after they are merged into `main`. Its goal is to produce a tested, secure and traceable container image that can eventually be pushed to a container registry.

## Workflow Triggers

The workflow runs when:

- A pull request targets `main`.
- Code is pushed to `main`.

The workflow has read-only access to the repository contents.

## Frontend Checks

The frontend job runs on its own Ubuntu runner. It:

- Checks out the source code.
- Installs Node.js.
- Installs the JavaScript dependencies using `npm ci`.
- Runs the frontend linter.
- Runs the frontend tests.

Running this as a separate job makes frontend failures easier to identify.

## Backend Checks

The backend job runs on a separate Ubuntu runner. It:

- Checks out the source code.
- Installs Go and downloads the Go dependencies.
- Runs the Go linter.
- Installs Node.js for the SSR build required by the server tests.
- Installs `godotenv`.
- Runs the Fider server tests.

`godotenv` loads the test configuration from `.test.env` before migrations and tests run.

PostgreSQL and MinIO run as service containers because the backend tests depend on database and object-storage services.

The runner connects to PostgreSQL through port `5566`, which forwards traffic to PostgreSQL’s internal port `5432`.

## Container Build

The container job starts only after the frontend, backend and secret scanning jobs pass. This avoids building an image when an earlier quality check has already failed.

The job:

- Checks out the source code.
- Builds the image using the project Dockerfile.
- Tags the image with `${{ github.sha }}`.

The Git commit SHA identifies the exact source code used to create the image. This will allow the same image version to be traced and promoted through different environments.

## Security Scanning

Trivy performs two different security scans.

The repository scan checks source files for exposed credentials and secrets.

The container scan checks the completed image for known vulnerabilities in its operating-system and application packages.

The container job fails when fixable `HIGH` or `CRITICAL` vulnerabilities are detected. This prevents a vulnerable image from passing the CI security gate.

## Troubleshooting Evidence

The repository secret scan initially detected a development private key and a test JWT. These files were reviewed and confirmed as test fixtures before exact file exclusions were added.

The backend tests initially failed because they required MinIO on port `9000`. A MinIO service container was added to provide the required test object storage.

The container scan later found four high-severity vulnerabilities in three Go dependencies. The affected packages were located in `go.mod`, upgraded to fixed versions and verified locally.

After the changes were pushed, CI rebuilt and rescanned the image. The container image job passed successfully.