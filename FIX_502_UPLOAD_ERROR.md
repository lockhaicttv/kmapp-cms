# Fix Strapi 502 Error on Media Upload

## 🔴 Problem

When uploading images/files in Strapi admin, you get:
- **502 Bad Gateway** error
- Upload fails silently
- Large files don't upload

## 🎯 Root Cause

**Nginx Proxy Manager** has a default upload size limit (usually 1-2MB). When you try to upload larger files, Nginx rejects them **before** they reach Strapi.

---

## ✅ Solution 1: Via Nginx Proxy Manager UI (Recommended)

### **Step 1: Edit Proxy Host**

1. Go to Nginx Proxy Manager: `http://your-server-ip:81`
2. Click **Hosts** → **Proxy Hosts**
3. Find `cms.kmappify.com` and click **Edit**

### **Step 2: Add Upload Configuration**

Go to **Advanced** tab and add this:

```nginx
# Increase upload size limit to 100MB
client_max_body_size 100M;

# Increase timeouts for large uploads (10 minutes)
proxy_connect_timeout 600;
proxy_send_timeout 600;
proxy_read_timeout 600;
send_timeout 600;

# Disable buffering for large uploads
proxy_buffering off;
proxy_request_buffering off;

# Headers for upload
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
```

### **Step 3: Save and Test**

1. Click **Save**
2. Try uploading a file in Strapi
3. Should work now!

---

## ✅ Solution 2: Direct Nginx Configuration

If Solution 1 doesn't work:

```bash
# Get Nginx container name
NGINX_CONTAINER=$(docker ps --filter "name=nginx" --format "{{.Names}}" | head -1)

# Add to nginx config
docker exec $NGINX_CONTAINER bash -c "echo 'client_max_body_size 100M;' >> /data/nginx/custom/http_top.conf"

# Test configuration
docker exec $NGINX_CONTAINER nginx -t

# Reload Nginx
docker exec $NGINX_CONTAINER nginx -s reload
```

---

## 🧪 Testing

1. Go to Strapi Admin: `https://cms.kmappify.com/admin`
2. Go to **Media Library**
3. Upload a large image (5-10MB)
4. Should work now!

---

## 🐛 Still Getting 502?

Check Nginx logs:
```bash
docker logs -f $(docker ps --filter "name=nginx" --format "{{.Names}}" | head -1)
```

Look for:
- "413 Request Entity Too Large" = limit still too low
- "upstream timed out" = need to increase timeouts

---

## 📝 Summary

**The fix:** Add `client_max_body_size 100M;` to Nginx Proxy Manager Advanced tab

That's it! Your uploads should work now.
