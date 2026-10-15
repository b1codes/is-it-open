# Deploying to AWS EC2

This guide explains how to deploy the backend to an AWS EC2 instance using Docker and Docker Compose.

## 1. Prepare your EC2 Instance
- **OS**: Ubuntu 22.04 LTS (recommended)
- **Security Group**:
  - Inbound rules:
    - HTTP (80) or HTTPS (443) (if using Nginx/ALB)
    - Custom TCP (8000) (if exposing backend directly)
    - SSH (22)
- **Install Docker and Docker Compose**:
  ```bash
  sudo apt-get update
  sudo apt-get install docker.io docker-compose -y
  sudo usermod -aG docker $USER
  # Log out and log back in for group changes to take effect
  ```

## 2. Clone the Repository
```bash
git clone <your-repo-url>
cd is-it-open
```

## 3. Set Up Firestore
1. In the Google Cloud console, create (or pick) a project and create a Firestore database in **Native mode**.
2. Create a service account with the **Cloud Datastore User** role and download a JSON key.
3. Copy the key to the instance as `backend/gcp-service-account.json` (or set `GCP_CREDENTIALS_FILE` to its path). It is gitignored and excluded from the Docker image.

## 4. Configure Environment Variables
1. Copy the sample environment file:
   ```bash
   cp backend/sample.env backend/.env
   ```
2. Edit `.env` with your production values:
   - `SECRET_KEY`: Generate a secure one (e.g., `openssl rand -base64 32`)
   - `DEBUG`: Set to `0`
   - `ALLOWED_HOSTS`: Add your EC2 public IP or domain name
   - `TOMTOM_API_KEY`: Your TomTom API key
   - `GOOGLE_CLOUD_PROJECT`: Your GCP project ID
   - `FIRESTORE_DATABASE`: Only if you aren't using the `(default)` database
   - Leave `FIRESTORE_EMULATOR_HOST` unset in production

## 5. Run with Docker Compose
Use the production-specific compose file:
```bash
docker-compose -f docker-compose.prod.yml up --build -d
```

Firestore is schemaless, so there are no migrations to run.

## 6. (Optional) Reverse Proxy
It is highly recommended to place an Nginx reverse proxy or an AWS ALB in front of port 8000.
For Nginx on the same EC2:
```nginx
server {
    listen 80;
    server_name yourdomain.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
