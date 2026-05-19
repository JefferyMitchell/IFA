# GitHub Actions Workflows

CI/CD pipeline definitions for automating the image factory.

## Planned Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `build-image.yml` | Manual / scheduled | Deploy AIB template and trigger an image build |
| `publish-image.yml` | On build success | Validate and publish new image version to Compute Gallery |
| `infra-deploy.yml` | Push to `main` | Deploy or update the factory infrastructure via Bicep |
