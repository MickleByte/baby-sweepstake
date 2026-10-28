# Baby Sweepstake

Friends and family guess facts about an expected baby (date of birth, weight, sex) for bragging rights. See [`GLOSSARY.md`](GLOSSARY.md) for the domain language and [`docs/adr/`](docs/adr/) for the decisions behind the design.

## Repository layout

A pnpm workspace orchestrated by Turborepo:

| Path              | What it is                                                   |
| ----------------- | ------------------------------------------------------------ |
| `apps/web`        | The UI: Vite + React + Tailwind, served from S3 + CloudFront |
| `apps/api`        | The API: Lambda handlers behind a small router               |
| `packages/domain` | The domain model, shared by both apps                        |
| `infra/`          | Terraform root modules, one per stack                        |

## Prerequisites

- **Node 24 LTS**, the version in [`.nvmrc`](.nvmrc). With nvm: `nvm use`.
- **pnpm**, the version pinned in `package.json`'s `packageManager` field. Run `corepack enable` once to get it automatically.
- **Terraform**, only when working under `infra/`.

## AWS setup

Deploying needs a one-off bootstrap of the AWS account and the GitHub repository settings. Follow [`docs/setup/aws-bootstrap.md`](docs/setup/aws-bootstrap.md).

## Common commands

Run these from the repository root:

| Command          | What it does                                                               |
| ---------------- | -------------------------------------------------------------------------- |
| `pnpm install`   | Install dependencies for every package                                     |
| `pnpm dev`       | Start the web app's dev server                                             |
| `pnpm lint`      | Run ESLint, then check formatting with Prettier                            |
| `pnpm format`    | Rewrite files with Prettier                                                |
| `pnpm typecheck` | Type-check every package                                                   |
| `pnpm test`      | Run every package's tests once (Vitest)                                    |
| `pnpm build`     | Build the web app to `apps/web/dist` and the API bundle to `apps/api/dist` |

To work on a single package, filter it, e.g. `pnpm --filter @baby-sweepstake/web dev`. To run one test file, pass its path: `pnpm test apps/api/src/index.test.ts`.

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every pull request and every push to `main`. It installs, lints, type-checks, tests and builds, and runs `terraform fmt -check`, `terraform validate`, `terraform test` (with mocked providers) and `tflint` on every root module under `infra/`.
