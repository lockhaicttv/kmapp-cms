#!/bin/bash

# Nginx + Strapi Diagnostic Script
# Run this on your server to diagnose connection issues

echo "======================================"
echo "🔍 Nginx + Strapi Diagnostic Tool"
echo "======================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Check if containers are running
echo "1️⃣  Checking if containers are running..."
echo "---"

STRAPI_RUNNING=$(docker ps --filter "name=kmapp-cms" --format "{{.Names}}" | grep -w "kmapp-cms")
NGINX_RUNNING=$(docker ps --filter "name=nginx" --format "{{.Names}}" | head -1)

if [ -n "$STRAPI_RUNNING" ]; then
    echo -e "${GREEN}✅ Strapi container is running: $STRAPI_RUNNING${NC}"
else
    echo -e "${RED}❌ Strapi container is NOT running${NC}"
    echo "   Run: docker-compose up -d"
fi

if [ -n "$NGINX_RUNNING" ]; then
    echo -e "${GREEN}✅ Nginx container is running: $NGINX_RUNNING${NC}"
else
    echo -e "${RED}❌ Nginx Proxy Manager is NOT running${NC}"
fi

echo ""

# 2. Check networks
echo "2️⃣  Checking network configuration..."
echo "---"

if [ -n "$STRAPI_RUNNING" ]; then
    STRAPI_NETWORKS=$(docker inspect $STRAPI_RUNNING --format='{{range $net, $v := .NetworkSettings.Networks}}{{$net}} {{end}}')
    echo "Strapi networks: $STRAPI_NETWORKS"
fi

if [ -n "$NGINX_RUNNING" ]; then
    NGINX_NETWORKS=$(docker inspect $NGINX_RUNNING --format='{{range $net, $v := .NetworkSettings.Networks}}{{$net}} {{end}}')
    echo "Nginx networks: $NGINX_NETWORKS"

    # Check if they share a network
    SHARED_NETWORK=$(comm -12 <(echo $STRAPI_NETWORKS | tr ' ' '\n' | sort) <(echo $NGINX_NETWORKS | tr ' ' '\n' | sort))

    if [ -n "$SHARED_NETWORK" ]; then
        echo -e "${GREEN}✅ Containers share network(s): $SHARED_NETWORK${NC}"
    else
        echo -e "${RED}❌ Containers are NOT on the same network${NC}"
        echo -e "${YELLOW}   Fix: docker network connect kmapp-network $NGINX_RUNNING${NC}"
    fi
fi

echo ""

# 3. Test connectivity from Nginx to Strapi
echo "3️⃣  Testing connectivity from Nginx to Strapi..."
echo "---"

if [ -n "$NGINX_RUNNING" ] && [ -n "$STRAPI_RUNNING" ]; then
    # Test ping
    echo "Testing ping..."
    docker exec $NGINX_RUNNING ping -c 2 kmapp-cms &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Ping successful${NC}"
    else
        echo -e "${RED}❌ Ping failed - containers can't see each other${NC}"
    fi

    # Test HTTP connection
    echo "Testing HTTP connection..."
    CURL_RESULT=$(docker exec $NGINX_RUNNING curl -s -o /dev/null -w "%{http_code}" http://kmapp-cms:1337/_health 2>&1)

    if [[ "$CURL_RESULT" =~ ^[0-9]+$ ]]; then
        if [ "$CURL_RESULT" -eq 200 ] || [ "$CURL_RESULT" -eq 404 ]; then
            echo -e "${GREEN}✅ HTTP connection successful (Status: $CURL_RESULT)${NC}"
        else
            echo -e "${YELLOW}⚠️  HTTP connection received status: $CURL_RESULT${NC}"
        fi
    else
        echo -e "${RED}❌ HTTP connection failed${NC}"
        echo "   Error: $CURL_RESULT"
    fi
else
    echo -e "${YELLOW}⚠️  Skipping - one or both containers not running${NC}"
fi

echo ""

# 4. Check if Strapi is listening
echo "4️⃣  Checking if Strapi is listening on port 1337..."
echo "---"

if [ -n "$STRAPI_RUNNING" ]; then
    LISTENING=$(docker exec $STRAPI_RUNNING netstat -tuln 2>/dev/null | grep :1337 || docker exec $STRAPI_RUNNING ss -tuln 2>/dev/null | grep :1337)

    if [ -n "$LISTENING" ]; then
        echo -e "${GREEN}✅ Strapi is listening on port 1337${NC}"
    else
        echo -e "${RED}❌ Strapi is NOT listening on port 1337${NC}"
        echo "   Check Strapi logs: docker logs kmapp-cms"
    fi
fi

echo ""

# 5. Check DNS resolution
echo "5️⃣  Checking DNS resolution for cms.kmappify.com..."
echo "---"

DNS_IP=$(nslookup cms.kmappify.com 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')

if [ -n "$DNS_IP" ]; then
    echo -e "${GREEN}✅ DNS resolves to: $DNS_IP${NC}"

    # Check if it matches server IP
    SERVER_IPS=$(hostname -I 2>/dev/null || ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}')
    if echo "$SERVER_IPS" | grep -q "$DNS_IP"; then
        echo -e "${GREEN}✅ DNS points to this server${NC}"
    else
        echo -e "${YELLOW}⚠️  DNS IP doesn't match server IPs${NC}"
        echo "   Server IPs: $SERVER_IPS"
    fi
else
    echo -e "${RED}❌ DNS not resolving${NC}"
    echo "   Update your DNS A record to point to this server"
fi

echo ""

# 6. Check firewall
echo "6️⃣  Checking firewall status..."
echo "---"

if command -v ufw &> /dev/null; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null)

    if echo "$UFW_STATUS" | grep -q "Status: active"; then
        echo "Firewall is active"

        if echo "$UFW_STATUS" | grep -q "80.*ALLOW"; then
            echo -e "${GREEN}✅ Port 80 is open${NC}"
        else
            echo -e "${RED}❌ Port 80 is NOT open${NC}"
            echo -e "${YELLOW}   Fix: sudo ufw allow 80/tcp${NC}"
        fi

        if echo "$UFW_STATUS" | grep -q "443.*ALLOW"; then
            echo -e "${GREEN}✅ Port 443 is open${NC}"
        else
            echo -e "${RED}❌ Port 443 is NOT open${NC}"
            echo -e "${YELLOW}   Fix: sudo ufw allow 443/tcp${NC}"
        fi
    else
        echo -e "${GREEN}✅ Firewall is inactive${NC}"
    fi
else
    echo "UFW not installed, skipping firewall check"
fi

echo ""

# 7. Test local access
echo "7️⃣  Testing local access to Strapi..."
echo "---"

LOCAL_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:1337/_health 2>&1)

if [[ "$LOCAL_TEST" =~ ^[0-9]+$ ]]; then
    if [ "$LOCAL_TEST" -eq 200 ] || [ "$LOCAL_TEST" -eq 404 ]; then
        echo -e "${GREEN}✅ Strapi accessible on localhost:1337 (Status: $LOCAL_TEST)${NC}"
    else
        echo -e "${YELLOW}⚠️  Received status: $LOCAL_TEST${NC}"
    fi
else
    echo -e "${RED}❌ Cannot access Strapi on localhost:1337${NC}"
fi

echo ""

# 8. Check Strapi environment
echo "8️⃣  Checking Strapi configuration..."
echo "---"

if [ -n "$STRAPI_RUNNING" ]; then
    HOST=$(docker exec $STRAPI_RUNNING printenv HOST 2>/dev/null)
    PORT=$(docker exec $STRAPI_RUNNING printenv PORT 2>/dev/null)
    IS_PROXIED=$(docker exec $STRAPI_RUNNING printenv IS_PROXIED 2>/dev/null)
    PUBLIC_URL=$(docker exec $STRAPI_RUNNING printenv PUBLIC_URL 2>/dev/null)

    echo "HOST: ${HOST:-'not set'}"
    echo "PORT: ${PORT:-'not set'}"
    echo "IS_PROXIED: ${IS_PROXIED:-'not set'}"
    echo "PUBLIC_URL: ${PUBLIC_URL:-'not set'}"

    if [ "$HOST" == "0.0.0.0" ]; then
        echo -e "${GREEN}✅ HOST is correctly set to 0.0.0.0${NC}"
    else
        echo -e "${YELLOW}⚠️  HOST should be 0.0.0.0${NC}"
    fi

    if [ "$IS_PROXIED" == "true" ]; then
        echo -e "${GREEN}✅ IS_PROXIED is set${NC}"
    else
        echo -e "${YELLOW}⚠️  IS_PROXIED should be 'true' when using Nginx${NC}"
    fi
fi

echo ""

# Summary
echo "======================================"
echo "📊 Summary & Next Steps"
echo "======================================"
echo ""

if [ -z "$STRAPI_RUNNING" ]; then
    echo -e "${RED}❌ CRITICAL: Start Strapi container${NC}"
    echo "   Run: docker-compose up -d"
elif [ -z "$NGINX_RUNNING" ]; then
    echo -e "${RED}❌ CRITICAL: Start Nginx Proxy Manager${NC}"
elif [ -z "$SHARED_NETWORK" ]; then
    echo -e "${RED}❌ CRITICAL: Containers not on same network${NC}"
    echo "   Run: docker network connect kmapp-network $NGINX_RUNNING"
    echo "   Then: docker restart $NGINX_RUNNING"
else
    echo -e "${GREEN}✅ Basic setup looks good!${NC}"
    echo ""
    echo "If still not working, check:"
    echo "1. Nginx Proxy Manager UI configuration:"
    echo "   - Forward Hostname: kmapp-cms (not localhost!)"
    echo "   - Forward Port: 1337"
    echo "   - Websockets: Enabled"
    echo ""
    echo "2. Rebuild Strapi with updated config:"
    echo "   docker-compose down"
    echo "   docker-compose build --no-cache"
    echo "   docker-compose up -d"
    echo ""
    echo "3. Watch logs while testing:"
    echo "   Terminal 1: docker logs -f kmapp-cms"
    echo "   Terminal 2: docker logs -f $NGINX_RUNNING"
    echo "   Terminal 3: curl https://cms.kmappify.com"
fi

echo ""
echo "For detailed logs:"
echo "  Strapi: docker logs kmapp-cms --tail 50"
echo "  Nginx:  docker logs $NGINX_RUNNING --tail 50"
echo ""
