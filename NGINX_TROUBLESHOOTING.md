# Nginx Proxy Manager + Strapi Troubleshooting Guide

## Current Issue
✅ `curl localhost:1337` works and shows logs
❌ `cms.kmappify.com` through Nginx doesn't show logs or connect

This indicates a **network connectivity issue** between Nginx Proxy Manager and Strapi.

---

## 🔍 Diagnostic Steps (Run on Your Server)

### 1. Check Both Containers Are Running

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**Expected:** Both `kmapp-cms` and Nginx Proxy Manager should be listed and "Up"

---

### 2. Verify Network Configuration

```bash
# Get kmapp-cms networks
docker inspect kmapp-cms --format='{{range $net, $v := .NetworkSettings.Networks}}{{$net}} {{end}}'

# Get Nginx Proxy Manager networks (replace with your NPM container name)
docker inspect <nginx-container-name> --format='{{range $net, $v := .NetworkSettings.Networks}}{{$net}} {{end}}'
```

**Expected:** They must share at least ONE network in common

**If they don't share a network:**

```bash
# Add Nginx to kmapp-network
docker network connect kmapp-network <nginx-container-name>
```

---

### 3. Test Container-to-Container Connectivity

```bash
# Find Nginx container name
docker ps --filter "name=nginx" --format "{{.Names}}"

# Test connection FROM Nginx TO Strapi
docker exec <nginx-container-name> ping -c 3 kmapp-cms

# Test HTTP connection
docker exec <nginx-container-name> curl -v http://kmapp-cms:1337/_health
```

**Expected:** Should get HTTP 200 response

**If curl fails with "Could not resolve host":**
- Containers are NOT on the same network
- Add Nginx to kmapp-network (see step 2)

**If curl fails with "Connection refused":**
- Strapi is not listening on 0.0.0.0
- Check Strapi logs: `docker logs kmapp-cms`

---

### 4. Verify Nginx Proxy Manager Configuration

In Nginx Proxy Manager Web UI (http://your-server:81):

1. **Go to:** "Proxy Hosts" → Click on `cms.kmappify.com`

2. **Details Tab:**
   - Domain Names: `cms.kmappify.com`
   - Scheme: `http` (internal communication)
   - Forward Hostname/IP: **`kmapp-cms`** ← Use container name, NOT localhost!
   - Forward Port: `1337`
   - Cache Assets: ✅ (optional)
   - Block Common Exploits: ✅
   - Websockets Support: ✅ **IMPORTANT for Strapi admin**

3. **SSL Tab:**
   - SSL Certificate: Request new or use existing Let's Encrypt
   - Force SSL: ✅
   - HTTP/2 Support: ✅
   - HSTS Enabled: ✅

4. **Advanced Tab (optional but recommended):**
   ```nginx
   # Trust proxy headers
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header X-Forwarded-Proto $scheme;
   proxy_set_header X-Forwarded-Host $host;
   
   # Increase timeouts for admin panel
   proxy_read_timeout 300;
   proxy_connect_timeout 300;
   proxy_send_timeout 300;
   ```

5. **Click "Save"**

---

### 5. Check DNS Resolution

On your **local machine** (not server):

```bash
# Check if DNS is pointing to your server
nslookup cms.kmappify.com

# Or use dig
dig cms.kmappify.com
```

**Expected:** Should resolve to your server's public IP

**If it doesn't resolve:**
- Update your DNS A record to point to server IP
- Wait for DNS propagation (can take up to 48 hours, usually 5-30 minutes)

**Temporary test (add to your local hosts file):**

Windows: `C:\Windows\System32\drivers\etc\hosts`
Linux/Mac: `/etc/hosts`

```
YOUR_SERVER_IP  cms.kmappify.com
```

---

### 6. Test from Server Itself

On your server, test if Nginx is actually receiving requests:

```bash
# Test with curl from server
curl -H "Host: cms.kmappify.com" http://localhost:80/_health

# Or test HTTPS
curl -k https://cms.kmappify.com/_health
```

---

## 🎯 Common Issues & Solutions

### Issue 1: "502 Bad Gateway"

**Cause:** Nginx can't reach Strapi

**Fix:**
```bash
# 1. Check if containers are on same network
docker network ls
docker network inspect kmapp-network

# 2. Add Nginx to the network
docker network connect kmapp-network <nginx-container-name>

# 3. Restart Nginx Proxy Manager
docker restart <nginx-container-name>
```

---

### Issue 2: "This site can't be reached"

**Possible causes:**

1. **DNS not pointing to server:**
   ```bash
   # Check DNS
   nslookg cms.kmappify.com
   ```
   Fix: Update DNS A record

2. **Firewall blocking port 80/443:**
   ```bash
   # Check if ports are open
   sudo ufw status
   sudo netstat -tulpn | grep :80
   sudo netstat -tulpn | grep :443
   ```
   Fix: Open ports
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. **Nginx Proxy Manager not running:**
   ```bash
   docker ps | grep nginx
   ```
   Fix: Start Nginx
   ```bash
   docker start <nginx-container-name>
   ```

---

### Issue 3: Logs Not Showing

**This is your current issue!**

**Cause:** Request never reaches Strapi

**Debug steps:**

```bash
# 1. Watch Nginx logs
docker logs -f <nginx-container-name>

# 2. Watch Strapi logs
docker logs -f kmapp-cms

# 3. Test from within Nginx container
docker exec <nginx-container-name> curl -v http://kmapp-cms:1337

# 4. Check if port 1337 is exposed in kmapp-cms
docker inspect kmapp-cms --format='{{.Config.ExposedPorts}}'

# 5. Check network connectivity
docker exec <nginx-container-name> nc -zv kmapp-cms 1337
```

---

### Issue 4: Container Name Resolution Fails

**Symptoms:** 
- `docker exec nginx curl http://kmapp-cms:1337` fails
- Error: "Could not resolve host: kmapp-cms"

**Fix:**

Option A - Use IP address instead:
```bash
# Get Strapi container IP
STRAPI_IP=$(docker inspect kmapp-cms --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo $STRAPI_IP

# In Nginx Proxy Manager, use this IP instead of "kmapp-cms"
```

Option B - Use custom network with DNS:
```bash
# Create network with embedded DNS
docker network create --driver bridge kmapp-network

# Connect both containers
docker network connect kmapp-network kmapp-cms
docker network connect kmapp-network <nginx-container-name>

# Restart both
docker restart kmapp-cms
docker restart <nginx-container-name>
```

---

## ✅ Updated Configuration Files

I've updated your Strapi config to work properly behind a proxy:

### 1. `config/server.ts`
- Added `proxy: true` - Tells Strapi it's behind a proxy
- Added `url` - Sets the public URL for Strapi

### 2. `config/middlewares.ts`
- Updated CORS to allow `cms.kmappify.com`
- Updated CSP (Content Security Policy) for admin panel

### 3. `docker-compose.yml`
- Added `IS_PROXIED=true` environment variable
- Added `PUBLIC_URL=https://cms.kmappify.com`

---

## 🚀 After Fixing Configuration

**Rebuild and restart Strapi:**

```bash
# On your server, in the cms directory
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# Watch logs
docker-compose logs -f
```

---

## 📝 Final Verification Checklist

Run these on your **server**:

```bash
# 1. Both containers running?
docker ps | grep -E "kmapp-cms|nginx"

# 2. Same network?
docker network inspect kmapp-network | grep -A 5 "Containers"

# 3. Can Nginx reach Strapi?
docker exec <nginx-container-name> curl http://kmapp-cms:1337/_health

# 4. Can you access from server?
curl -H "Host: cms.kmappify.com" http://localhost/_health

# 5. DNS working?
nslookup cms.kmappify.com

# 6. Firewall open?
sudo ufw status | grep -E "80|443"

# 7. Check Strapi logs when accessing via domain
docker logs -f kmapp-cms
# In another terminal, try accessing cms.kmappify.com
```

---

## 🆘 Still Not Working?

Share the output of these commands:

```bash
# 1. Container status
docker ps -a

# 2. Network inspection
docker network inspect kmapp-network

# 3. Nginx config test
docker exec <nginx-container-name> curl -v http://kmapp-cms:1337

# 4. Strapi logs
docker logs --tail 50 kmapp-cms

# 5. Nginx logs
docker logs --tail 50 <nginx-container-name>

# 6. DNS check
nslookup cms.kmappify.com
```

---

## 📌 Quick Reference

**Container names you need:**
- Strapi: `kmapp-cms`
- Nginx: `<find with: docker ps | grep nginx>`

**Network:** `kmapp-network`

**Nginx forward to:** `kmapp-cms:1337`

**NOT:** `localhost:1337` or `127.0.0.1:1337`

**Ports to open:** 80 (HTTP), 443 (HTTPS)

**DNS A record:** `cms.kmappify.com` → Your server IP
