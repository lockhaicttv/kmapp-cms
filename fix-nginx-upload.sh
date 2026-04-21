#!/bin/bash

# Fix Nginx Proxy Manager Upload Size Limit
# Run this on your server

set -e

echo "================================================"
echo "🔧 Fixing Nginx Upload Size Limit for Strapi"
echo "================================================"
echo ""

# Get Nginx container name
NGINX_CONTAINER=$(docker ps --filter "name=nginx" --format "{{.Names}}" | head -1)

if [ -z "$NGINX_CONTAINER" ]; then
    echo "❌ Nginx Proxy Manager container not found"
    exit 1
fi

echo "Found Nginx container: $NGINX_CONTAINER"
echo ""

# Backup current config
echo "Creating backup of nginx.conf..."
docker exec $NGINX_CONTAINER cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
echo "✅ Backup created"
echo ""

# Check if client_max_body_size is already set
CURRENT_SIZE=$(docker exec $NGINX_CONTAINER grep -r "client_max_body_size" /etc/nginx/ 2>/dev/null || echo "not found")

echo "Current client_max_body_size setting:"
echo "$CURRENT_SIZE"
echo ""

# Add to nginx.conf if not present in http block
echo "Adding upload size limit to nginx.conf..."

docker exec $NGINX_CONTAINER bash -c 'cat > /tmp/add_upload_limit.sh << "EOF"
#!/bin/bash

# Check if already present
if ! grep -q "client_max_body_size 100M" /etc/nginx/nginx.conf; then
    # Add to http block
    sed -i "/http {/a \    client_max_body_size 100M;" /etc/nginx/nginx.conf
    echo "✅ Added client_max_body_size 100M to nginx.conf"
else
    echo "ℹ️  client_max_body_size already configured"
fi
EOF
chmod +x /tmp/add_upload_limit.sh
/tmp/add_upload_limit.sh'

echo ""

# Test nginx configuration
echo "Testing Nginx configuration..."
docker exec $NGINX_CONTAINER nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Configuration is valid"
    echo ""

    # Reload Nginx
    echo "Reloading Nginx..."
    docker exec $NGINX_CONTAINER nginx -s reload
    echo "✅ Nginx reloaded"
    echo ""

    echo "================================================"
    echo "✅ Upload limit increased to 100MB"
    echo "================================================"
    echo ""
    echo "You can now upload files up to 100MB in Strapi"
    echo ""
else
    echo "❌ Configuration test failed"
    echo "Restoring backup..."
    docker exec $NGINX_CONTAINER cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
    echo "Configuration restored"
    exit 1
fi
