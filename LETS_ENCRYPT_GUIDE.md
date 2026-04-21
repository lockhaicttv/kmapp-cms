# Let's Encrypt SSL Setup Guide for Strapi CMS

## ❌ Common Mistake

**DON'T** try to setup SSL/Let's Encrypt **inside** the Strapi container!

## ✅ Correct Approach

Setup SSL in **Nginx Proxy Manager** - it will handle all SSL for you.

---

## 📐 Architecture Understanding

```
┌─────────────────────────────────────────────────────┐
│  Internet (Users)                                   │
└────────────────┬────────────────────────────────────┘
                 │ HTTPS (port 443) - Encrypted
                 │
        ┌────────▼──────────┐
        │  Nginx Proxy      │ ← SSL/Let's Encrypt HERE!
        │  Manager          │ ← Handles certificates
        └────────┬──────────┘
                 │ HTTP (port 1337) - Internal only
                 │ No encryption needed
        ┌────────▼──────────┐
        │  Strapi CMS       │ ← NO SSL needed!
        │  (kmapp-cms)      │ ← Plain HTTP is fine
        └───────────────────┘
```

**Why?**
- 🔒 Nginx handles SSL termination (decrypts HTTPS → HTTP)
- 🚀 Strapi runs plain HTTP internally (faster, simpler)
- 🔄 Internal traffic is already isolated in Docker network
- 🎯 One place to manage all SSL certificates

---

## 🚀 Step-by-Step: Setup Let's Encrypt

### **Prerequisites**

Before you start, verify:

```bash
# 1. DNS points to your server
nslookup cms.kmappify.com
# Should return your server's public IP

# 2. Ports 80 and 443 are open
sudo ufw status | grep -E "80|443"

# If not open:
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 3. Nginx Proxy Manager is running
docker ps | grep nginx

# 4. Strapi container is running
docker ps | grep kmapp-cms

# 5. Both containers are on same network
docker network inspect kmapp-network | grep -E "nginx|kmapp-cms"
```

---

### **Step 1: Access Nginx Proxy Manager**

1. Open browser: `http://your-server-ip:81`
2. Login (default credentials first time):
   - Email: `admin@example.com`
   - Password: `changeme`
3. Change password when prompted

---

### **Step 2: Add Proxy Host**

1. Click **"Hosts"** → **"Proxy Hosts"**
2. Click **"Add Proxy Host"**

---

### **Step 3: Configure Details Tab**

```
Domain Names
├─ cms.kmappify.com

Scheme: http  ← IMPORTANT: Use http, NOT https!

Forward Hostname / IP
├─ kmapp-cms  ← Use container name
└─ OR: Use container IP (get with: docker inspect kmapp-cms --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

Forward Port: 1337

☑️ Cache Assets
☑️ Block Common Exploits  
☑️ Websockets Support
```

Click **"Save"** (don't worry about SSL yet)

---

### **Step 4: Edit and Add SSL**

1. Click the **"..."** menu on your proxy host
2. Click **"Edit"**
3. Go to **"SSL"** tab

```
SSL Certificate
└─ ⚫ Request a new SSL Certificate

Email Address for Let's Encrypt
└─ your-email@example.com  ← Use your real email

☑️ Force SSL
☑️ HTTP/2 Support
☑️ HSTS Enabled
☑️ HSTS Subdomains (optional)
☑️ I Agree to the Let's Encrypt Terms of Service
```

4. Click **"Save"**

---

### **Step 5: Wait for Certificate**

Nginx will now:
1. ✅ Contact Let's Encrypt servers
2. ✅ Create verification files on port 80
3. ✅ Let's Encrypt verifies domain ownership
4. ✅ Certificate is issued and installed
5. ✅ Auto-renewal setup (every 90 days)

**This takes 10-30 seconds.**

---

### **Step 6: Verify SSL is Working**

```bash
# Test HTTPS
curl -I https://cms.kmappify.com

# Should return:
# HTTP/2 200
# server: nginx
# ...

# Or visit in browser
https://cms.kmappify.com/admin
```

You should see:
- ✅ Padlock icon in browser
- ✅ Valid certificate
- ✅ Strapi login page

---

## 🐛 Troubleshooting Let's Encrypt Issues

### **Issue 1: "Could not get Let's Encrypt certificate"**

**Possible Causes & Fixes:**

#### **1. DNS not pointing to server**

```bash
# Test DNS
nslookup cms.kmappify.com
# Should return your server's public IP

# If wrong:
# → Update DNS A record to point to server IP
# → Wait 5-30 minutes for propagation
```

#### **2. Port 80 blocked**

```bash
# Check if port 80 is accessible from internet
curl http://cms.kmappify.com

# Check firewall
sudo ufw status

# Open ports if needed
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

#### **3. Another service using port 80**

```bash
# Check what's using port 80
sudo netstat -tlnp | grep :80

# Or
sudo lsof -i :80

# If Apache or another web server is running:
sudo systemctl stop apache2
sudo systemctl disable apache2
```

#### **4. Nginx can't reach Strapi**

```bash
# Test connection
docker exec <nginx-container-name> curl http://kmapp-cms:1337

# If fails, check network
docker network inspect kmapp-network

# Connect Nginx to network
docker network connect kmapp-network <nginx-container-name>
docker restart <nginx-container-name>
```

---

### **Issue 2: "Internal Error" when requesting certificate**

**Fix:**

```bash
# Check Nginx Proxy Manager logs
docker logs <nginx-proxy-manager-container>

# Common issues:
# - Rate limit (too many requests)
# - Invalid email format
# - Domain verification timeout
```

---

### **Issue 3: Certificate works but Strapi shows errors**

**Fix: Update Strapi configuration**

Make sure Strapi knows it's behind a proxy:

```bash
# Check environment variables
docker exec kmapp-cms printenv | grep -E "IS_PROXIED|PUBLIC_URL"

# Should show:
# IS_PROXIED=true
# PUBLIC_URL=https://cms.kmappify.com
```

If missing, update your docker-compose and restart:

```bash
cd /path/to/cms
docker-compose down
docker-compose up -d
```

---

### **Issue 4: "Nginx is unable to connect to this host"**

This means Nginx can't reach your Strapi container.

**Debug:**

```bash
# 1. Get Nginx container name
NGINX_CONTAINER=$(docker ps --filter "name=nginx" --format "{{.Names}}" | head -1)
echo "Nginx container: $NGINX_CONTAINER"

# 2. Get Strapi container IP
STRAPI_IP=$(docker inspect kmapp-cms --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "Strapi IP: $STRAPI_IP"

# 3. Test connection by container name
docker exec $NGINX_CONTAINER curl -v http://kmapp-cms:1337

# 4. If fails, test by IP
docker exec $NGINX_CONTAINER curl -v http://$STRAPI_IP:1337

# 5. If IP works but name doesn't, use IP in Nginx config
```

**Temporary Fix:**
In Nginx Proxy Manager, use the container IP instead of `kmapp-cms`

**Permanent Fix:**
Ensure both containers are on the same Docker network:

```bash
# Create network if doesn't exist
docker network create kmapp-network

# Connect Strapi
docker network connect kmapp-network kmapp-cms

# Connect Nginx
docker network connect kmapp-network $NGINX_CONTAINER

# Restart both
docker restart kmapp-cms
docker restart $NGINX_CONTAINER
```

---

## 🔒 SSL Configuration Best Practices

### **In Nginx Proxy Manager Advanced Tab:**

```nginx
# Security headers
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;

# For Strapi admin panel
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;

# Increase timeouts for large uploads
client_max_body_size 100M;
proxy_read_timeout 300;
proxy_connect_timeout 300;
proxy_send_timeout 300;
```

---

## ✅ Verification Checklist

After setup, verify:

- [ ] Visit `https://cms.kmappify.com` - shows padlock
- [ ] Visit `http://cms.kmappify.com` - redirects to HTTPS
- [ ] Admin accessible at `https://cms.kmappify.com/admin`
- [ ] API accessible at `https://cms.kmappify.com/api/blogs`
- [ ] No browser warnings about certificate
- [ ] Certificate valid for 90 days
- [ ] Auto-renewal enabled in Nginx

---

## 📊 Certificate Information

Check certificate details:

```bash
# Using OpenSSL
echo | openssl s_client -servername cms.kmappify.com -connect cms.kmappify.com:443 2>/dev/null | openssl x509 -noout -dates

# Should show:
# notBefore=...
# notAfter=... (90 days from now)
```

Or visit in browser:
1. Click padlock icon
2. Click "Certificate"
3. Check:
   - Issued to: cms.kmappify.com
   - Issued by: Let's Encrypt Authority
   - Valid from/to dates

---

## 🔄 Certificate Renewal

Let's Encrypt certificates expire every **90 days**.

**Good news:** Nginx Proxy Manager **automatically renews** them!

**Verify auto-renewal:**
```bash
# Check Nginx Proxy Manager logs
docker logs <nginx-container> | grep -i "renew"

# Certificates are checked daily and renewed when < 30 days remain
```

**Manual renewal (if needed):**
1. Go to Nginx Proxy Manager UI
2. Click "SSL Certificates"
3. Find your certificate
4. Click "..." → "Renew"

---

## 🎯 Quick Setup Commands

If you're starting fresh:

```bash
# On your server

# 1. Ensure network exists
docker network create kmapp-network

# 2. Start Strapi with correct network
cd /path/to/cms
docker-compose -f docker-compose.local.yml down
docker-compose -f docker-compose.local.yml up -d

# 3. Connect Nginx to network
NGINX_CONTAINER=$(docker ps --filter "name=nginx" --format "{{.Names}}" | head -1)
docker network connect kmapp-network $NGINX_CONTAINER
docker restart $NGINX_CONTAINER

# 4. Test connectivity
docker exec $NGINX_CONTAINER curl http://kmapp-cms:1337

# 5. Now configure Let's Encrypt in Nginx Proxy Manager UI
```

---

## 📝 Summary

| Component | SSL | Port | Access |
|-----------|-----|------|--------|
| Nginx Proxy Manager | ✅ Yes (Let's Encrypt) | 80, 443 | Public |
| Strapi Container | ❌ No (plain HTTP) | 1337 | Internal only |
| PostgreSQL | ❌ No | 5432 | Internal only |

**Key Points:**
- ✅ Setup SSL in **Nginx Proxy Manager** (not Strapi)
- ✅ Use **container name** (`kmapp-cms`) as forward host
- ✅ Forward to port **1337** with **http** (not https)
- ✅ Enable **Websockets** for Strapi admin
- ✅ Nginx handles all SSL/TLS encryption
- ✅ Certificates auto-renew every 90 days

---

## 🆘 Still Having Issues?

Run this diagnostic:

```bash
# Save this as check-ssl.sh
cat > check-ssl.sh << 'EOF'
#!/bin/bash
echo "=== SSL Setup Diagnostic ==="
echo ""

echo "1. DNS Check:"
nslookup cms.kmappify.com
echo ""

echo "2. Port 80 accessible:"
timeout 5 curl -I http://cms.kmappify.com 2>&1 | head -5
echo ""

echo "3. Port 443 accessible:"
timeout 5 curl -I https://cms.kmappify.com 2>&1 | head -5
echo ""

echo "4. Strapi container running:"
docker ps --filter "name=kmapp-cms" --format "{{.Names}} - {{.Status}}"
echo ""

echo "5. Nginx container running:"
docker ps --filter "name=nginx" --format "{{.Names}} - {{.Status}}"
echo ""

echo "6. Network connectivity:"
NGINX=$(docker ps --filter "name=nginx" --format "{{.Names}}" | head -1)
docker exec $NGINX curl -s -o /dev/null -w "HTTP %{http_code}\n" http://kmapp-cms:1337 2>&1
echo ""

echo "7. Firewall status:"
sudo ufw status | grep -E "80|443"
EOF

chmod +x check-ssl.sh
./check-ssl.sh
```

Share the output if you need help troubleshooting!
