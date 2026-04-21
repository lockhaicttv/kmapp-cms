# KMAPP CMS (Strapi) Docker Deployment

This guide explains how to build and deploy the KMAPP Strapi CMS using Docker.

## Prerequisites

- Docker and Docker Compose installed
- Docker Hub account (for pushing to registry)
- PostgreSQL database (recommended for production)

## Files Created

1. **Dockerfile** - Multi-stage build for Strapi 5.42.1
2. **.dockerignore** - Excludes unnecessary files from Docker build
3. **docker-compose.yml** - Complete setup with PostgreSQL database
4. **.env.example** - Updated with database configuration

## Quick Start

### 1. Local Development with Docker

```bash
# Copy environment variables
cp .env.example .env

# Edit .env with your values (important for security!)
# At minimum, change all the secret keys and passwords

# Build and run with PostgreSQL
docker-compose up --build
```

Visit http://localhost:1337/admin

### 2. Generate Secure Keys

Before deploying to production, generate secure random keys:

```bash
# Generate APP_KEYS (generate 4 separate keys)
openssl rand -base64 32
openssl rand -base64 32
openssl rand -base64 32
openssl rand -base64 32

# Generate other secrets
openssl rand -base64 32  # API_TOKEN_SALT
openssl rand -base64 32  # ADMIN_JWT_SECRET
openssl rand -base64 32  # TRANSFER_TOKEN_SALT
openssl rand -base64 32  # JWT_SECRET
```

Update your `.env` file with these generated values.

### 3. Build for Production

```bash
# Build the image
docker build -t kmapp-cms:latest .

# Test locally
docker run -p 1337:1337 \
  -e DATABASE_CLIENT=postgres \
  -e DATABASE_HOST=your-db-host \
  -e DATABASE_PORT=5432 \
  -e DATABASE_NAME=strapi \
  -e DATABASE_USERNAME=strapi \
  -e DATABASE_PASSWORD=secure-password \
  -e APP_KEYS=key1,key2,key3,key4 \
  kmapp-cms:latest
```

### 4. Push to Docker Hub

```bash
# Login to Docker Hub
docker login

# Tag the image
docker tag kmapp-cms:latest yourusername/kmapp-cms:latest

# Push to Docker Hub
docker push yourusername/kmapp-cms:latest
```

## Environment Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `APP_KEYS` | Comma-separated encryption keys (4 keys) | `key1,key2,key3,key4` |
| `API_TOKEN_SALT` | Salt for API tokens | Random base64 string |
| `ADMIN_JWT_SECRET` | Admin JWT secret | Random base64 string |
| `TRANSFER_TOKEN_SALT` | Transfer token salt | Random base64 string |
| `JWT_SECRET` | JWT secret for users | Random base64 string |

### Database Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_CLIENT` | Database type | `postgres` |
| `DATABASE_HOST` | Database host | `kmapp-postgres` |
| `DATABASE_PORT` | Database port | `5432` |
| `DATABASE_NAME` | Database name | `strapi` |
| `DATABASE_USERNAME` | Database user | `strapi` |
| `DATABASE_PASSWORD` | Database password | ⚠️ Change this! |

### Optional Variables

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | Full database connection string |
| `AWS_ACCESS_KEY_ID` | S3 access key (for file uploads) |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key |
| `AWS_REGION` | S3 region |
| `AWS_BUCKET` | S3 bucket name |

## Docker Image Details

### Multi-Stage Build

1. **base** - Node.js 20 Alpine with build dependencies (vips, etc.)
2. **kmapp-cms-builder** - Installs dependencies and builds Strapi admin
3. **kmapp-cms-runner** - Production runtime with only necessary files

### Features

- ✅ Uses Yarn (matches your project)
- ✅ Runs as non-root user (security)
- ✅ Includes PostgreSQL in docker-compose
- ✅ Alpine Linux for smaller image size
- ✅ Persistent data volumes
- ✅ Health checks included

## Production Deployment

### Option 1: Using Docker Compose with External Database

Create a `.env` file:

```env
# Generate these with: openssl rand -base64 32
APP_KEYS=your-key1,your-key2,your-key3,your-key4
API_TOKEN_SALT=your-salt
ADMIN_JWT_SECRET=your-secret
TRANSFER_TOKEN_SALT=your-salt
JWT_SECRET=your-secret

# External database
DATABASE_CLIENT=postgres
DATABASE_HOST=your-rds-endpoint.amazonaws.com
DATABASE_PORT=5432
DATABASE_NAME=strapi_prod
DATABASE_USERNAME=strapi
DATABASE_PASSWORD=very-secure-password
DATABASE_SSL=true
```

Then deploy:

```bash
docker-compose up -d kmapp-cms  # Only CMS, skip postgres
```

### Option 2: Using Docker Run

```bash
docker run -d \
  --name kmapp-cms \
  -p 1337:1337 \
  -e APP_KEYS=key1,key2,key3,key4 \
  -e API_TOKEN_SALT=salt \
  -e ADMIN_JWT_SECRET=secret \
  -e TRANSFER_TOKEN_SALT=salt \
  -e JWT_SECRET=secret \
  -e DATABASE_CLIENT=postgres \
  -e DATABASE_HOST=your-db-host \
  -e DATABASE_PORT=5432 \
  -e DATABASE_NAME=strapi \
  -e DATABASE_USERNAME=strapi \
  -e DATABASE_PASSWORD=password \
  -v $(pwd)/uploads:/opt/app/public/uploads \
  --restart unless-stopped \
  yourusername/kmapp-cms:latest
```

### Option 3: With AWS S3 for Uploads

Install Strapi S3 provider first (add to package.json):

```json
{
  "dependencies": {
    "@strapi/provider-upload-aws-s3": "^5.0.0"
  }
}
```

Then configure:

```bash
docker run -d \
  --name kmapp-cms \
  -p 1337:1337 \
  -e AWS_ACCESS_KEY_ID=your-key \
  -e AWS_SECRET_ACCESS_KEY=your-secret \
  -e AWS_REGION=us-east-1 \
  -e AWS_BUCKET=kmapp-uploads \
  [... other env vars ...] \
  yourusername/kmapp-cms:latest
```

## Persistent Data

### Uploads

By default, uploads are stored in `public/uploads` and mounted as a volume:

```yaml
volumes:
  - ./public/uploads:/opt/app/public/uploads
```

**For production**, consider using:
- AWS S3
- Google Cloud Storage
- Azure Blob Storage

### Database

PostgreSQL data is persisted in a Docker volume:

```yaml
volumes:
  - kmapp-postgres-data:/var/lib/postgresql/data
```

## Troubleshooting

### Build fails with "sharp" or "vips" errors

The Dockerfile includes all necessary dependencies for image processing. If issues persist:

```dockerfile
RUN apk add --no-cache vips-dev vips-tools
```

### Database connection fails

- Ensure PostgreSQL is running and accessible
- Check `DATABASE_HOST` matches your setup
- Verify database credentials
- Check network connectivity between containers

### Admin panel won't load

- Wait 30-60 seconds after first start for admin build
- Check logs: `docker logs kmapp-cms`
- Verify `APP_KEYS` is set correctly

### File uploads fail

- Check volume mount permissions
- Ensure `public/uploads` directory exists and is writable
- Consider using S3 for production

## Security Checklist

Before deploying to production:

- ✅ Generate new random secrets (don't use defaults!)
- ✅ Use strong database password
- ✅ Enable DATABASE_SSL if supported
- ✅ Run behind HTTPS reverse proxy (nginx, Traefik, etc.)
- ✅ Configure CORS properly
- ✅ Limit admin panel access (IP whitelist or VPN)
- ✅ Regular backups of database and uploads
- ✅ Keep Strapi updated

## Reverse Proxy Configuration

### Nginx Example

```nginx
server {
    listen 80;
    server_name kmappify.com;

    location / {
        proxy_pass http://localhost:1337;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Health Check

Add to your production deployment:

```yaml
healthcheck:
  test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:1337/_health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

## Backup Strategy

### Database Backup

```bash
# Backup
docker exec kmapp-postgres pg_dump -U strapi strapi > backup.sql

# Restore
docker exec -i kmapp-postgres psql -U strapi strapi < backup.sql
```

### Uploads Backup

```bash
# Backup
tar -czf uploads-backup.tar.gz public/uploads

# Restore
tar -xzf uploads-backup.tar.gz
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Push CMS Image

on:
  push:
    branches: [main]
    paths:
      - 'cms/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      
      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: ./cms
          push: true
          tags: |
            yourusername/kmapp-cms:latest
            yourusername/kmapp-cms:${{ github.sha }}
```

## Migration from SQLite to PostgreSQL

If you're currently using SQLite in development:

```bash
# Export data from SQLite
yarn strapi export --file backup

# Update DATABASE_CLIENT to postgres
# Start with PostgreSQL database
docker-compose up -d

# Import data
yarn strapi import --file backup.tar.gz.enc
```

---

**Important**: This Strapi 5.42.1 deployment uses PostgreSQL by default. Make sure to generate secure keys before production deployment!
