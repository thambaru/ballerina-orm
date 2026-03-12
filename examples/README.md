# Ballerina ORM Examples

This directory contains runnable examples for the core ORM library.

## Available Example

### `complete_blog_example.bal`

A complete blog-style application demonstrating:
- Annotated schema definitions for users, posts, categories, and comments
- CRUD operations
- Relation queries and eager loading
- Filtering, pagination, and sorting
- Aggregations and transactions
- Raw SQL escape hatches

Run it with:

```bash
cd examples
bal run complete_blog_example.bal
```

## Prerequisites

Before running the example, start either MySQL or PostgreSQL.

Quick start with Docker Compose from repository root:

```bash
docker-compose -f docker-compose.test.yml up -d
```

## Next Steps

- Read [API_REFERENCE.md](../docs/API_REFERENCE.md) for the full API surface
- Read [README.md](../README.md) for package-level usage guidance

## Contributing

Found an issue with examples or want to add another one? Open an issue or submit a PR.
