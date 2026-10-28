# Serverless and DynamoDB, so every PR gets a from-scratch environment

Every PR gets its own environment built from scratch by the same reusable pipeline that deploys dev and prod, so environment create/destroy time and idle cost dominate the hosting choice. We use S3 + CloudFront for the UI, API Gateway (HTTP API) + Lambda for the API, and DynamoDB (on-demand) for data: each environment provisions in minutes and costs roughly nothing while idle.

## Considered Options

- **ECS Fargate + ALB**: rejected — ~£15–25/month idle per environment and slower to provision.
- **Aurora Serverless v2 (Postgres)**: rejected — ~10 minutes to create per environment, which makes PR environments painful. Our access patterns (Sweepstake by id, Entries by Sweepstake) are simple enough not to need relational queries.

## Consequences

DynamoDB is the hard-to-reverse part: data access is designed around known access patterns rather than ad-hoc queries, and moving to a relational store later would mean a data migration.
