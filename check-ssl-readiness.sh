#!/bin/bash

# SSL Setup Diagnostic Tool for Strapi CMS
# Run this on your server to check Let's Encrypt setup

set +e  # Don't exit on error

echo "================================================"
echo "🔒 SSL Setup Diagnostic for cms.kmappify.com"
echo "================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DOMAIN="cms.kmappify.com"
STRAPI_CONTAINER="kmapp-cms"

echo -e "${BLUE}1️⃣  Checking DNS Resolution...${NC}"
echo "───────────────────────────────────────"
DNS_IP=$(nslookup $DOMAIN 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
if [ -n "$DNS_IP" ]; then
    echo -e "${GREEN}✅ DNS resolves to: $DNS_IP${NC}"

    # Check if it matches server IP
    SERVER_IPS=$(hostname -I 2>/dev/null || ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}')
    if echo "$SERVER_IPS" | grep -q "$DNS_IP"; then
        echo -e "${GREEN}✅ DNS points to this server${NC}"
    else
        echo -e "${YELLOW}⚠️  WARNING: DNS IP doesn't match server${NC}"
        echo "   DNS IP: $DNS_IP"
        echo "   Server IPs: $SERVER_IPS"
    fi
else
    echo -e "${RED}❌ DNS not resolving${NC}"
    echo "   Fix: Update DNS A record to point to this server"
fi
echo ""

echo -e "${BLUE}2️⃣  Checking Firewall (Ports 80 & 443)...${NC}"
echo "───────────────────────────────────────"
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
        echo -e "${GREEN}✅ Firewall is inactive (all ports open)${NC}"
    fi
else
    echo "UFW not installed - skipping firewall check"
fi
echo ""

echo -e "${BLUE}3️⃣  Checking Port Accessibility from Internet...${NC}"
echo "───────────────────────────────────────"
echo "Testing HTTP (port 80)..."
HTTP_RESULT=$(timeout 5 curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN 2>&1)
if [[ "$HTTP_RESULT" =~ ^[0-9]+$ ]]; then
    if [ "$HTTP_RESULT" -eq 301 ] || [ "$HTTP_RESULT" -eq 302 ] || [ "$HTTP_RESULT" -eq 200 ]; then
        echo -e "${GREEN}✅ Port 80 accessible (HTTP $HTTP_RESULT)${NC}"
    else
        echo -e "${YELLOW}⚠️  Port 80 responds with: $HTTP_RESULT${NC}"
    fi
else
    echo -e "${RED}❌ Port 80 not accessible${NC}"
    echo "   Error: $HTTP_RESULT"
fi

echo "Testing HTTPS (port 443)..."
HTTPS_RESULT=$(timeout 5 curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN 2>&1)
if [[ "$HTTPS_RESULT" =~ ^[0-9]+$ ]]; then
    if [ "$HTTPS_RESULT" -eq 200 ] || [ "$HTTPS_RESULT" -eq 404 ]; then
        echo -e "${GREEN}✅ Port 443 accessible with SSL (HTTPS $HTTPS_RESULT)${NC}"
    else
        echo -e "${YELLOW}⚠️  Port 443 responds with: $HTTPS_RESULT${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  HTTPS not configured yet${NC}"
    echo "   This is normal before Let's Encrypt setup"
fi
echo ""

echo -e "${BLUE}4️⃣  Checking Containers...${NC}"
echo "───────────────────────────────────────"
if docker ps --format '{{.Names}}' | grep -q "^${STRAPI_CONTAINER}$"; then
    echo -e "${GREEN}✅ Strapi container running: $STRAPI_CONTAINER${NC}"
    STRAPI_STATUS=$(docker ps --filter "name=$STRAPI_CONTAINER" --format "{{.Status}}")
    echo "   Status: $STRAPI_STATUS"
else
    echo -e "${RED}❌ Strapi container not running${NC}"
    echo -e "${YELLOW}   Fix: docker-compose up -d${NC}"
fi

NGINX_CONTAINER=$(docker ps --filter "name=nginx" --format "{{.Names}}" | head -1)
if [ -n "$NGINX_CONTAINER" ]; then
    echo -e "${GREEN}✅ Nginx container running: $NGINX_CONTAINER${NC}"
    NGINX_STATUS=$(docker ps --filter "name=$NGINX_CONTAINER" --format "{{.Status}}")
    echo "   Status: $NGINX_STATUS"
else
    echo -e "${RED}❌ Nginx Proxy Manager not running${NC}"
fi
echo ""

echo -e "${BLUE}5️⃣  Checking Docker Network...${NC}"
echo "───────────────────────────────────────"
if docker network inspect kmapp-network &> /dev/null; then
    echo -e "${GREEN}✅ Network 'kmapp-network' exists${NC}"

    # Check if containers are on the network
    STRAPI_ON_NET=$(docker network inspect kmapp-network --format '{{range .Containers}}{{.Name}} {{end}}' | grep -w "$STRAPI_CONTAINER")
    NGINX_ON_NET=$(docker network inspect kmapp-network --format '{{range .Containers}}{{.Name}} {{end}}' | grep -w "$NGINX_CONTAINER")

    if [ -n "$STRAPI_ON_NET" ]; then
        echo -e "${GREEN}✅ Strapi is on kmapp-network${NC}"
    else
        echo -e "${RED}❌ Strapi is NOT on kmapp-network${NC}"
        echo -e "${YELLOW}   Fix: docker network connect kmapp-network $STRAPI_CONTAINER${NC}"
    fi

    if [ -n "$NGINX_ON_NET" ]; then
        echo -e "${GREEN}✅ Nginx is on kmapp-network${NC}"
    else
        echo -e "${RED}❌ Nginx is NOT on kmapp-network${NC}"
        echo -e "${YELLOW}   Fix: docker network connect kmapp-network $NGINX_CONTAINER${NC}"
    fi
else
    echo -e "${RED}❌ Network 'kmapp-network' doesn't exist${NC}"
    echo -e "${YELLOW}   Fix: docker network create kmapp-network${NC}"
fi
echo ""

if [ -n "$NGINX_CONTAINER" ] && docker ps --format '{{.Names}}' | grep -q "^${STRAPI_CONTAINER}$"; then
    echo -e "${BLUE}6️⃣  Testing Container-to-Container Connectivity...${NC}"
    echo "───────────────────────────────────────"

    # Test by container name
    echo "Testing connection from Nginx to Strapi..."
    CONN_TEST=$(docker exec $NGINX_CONTAINER curl -s -o /dev/null -w "%{http_code}" http://$STRAPI_CONTAINER:1337 2>&1)

    if [[ "$CONN_TEST" =~ ^[0-9]+$ ]]; then
        if [ "$CONN_TEST" -eq 200 ] || [ "$CONN_TEST" -eq 404 ]; then
            echo -e "${GREEN}✅ Nginx can reach Strapi (HTTP $CONN_TEST)${NC}"
        else
            echo -e "${YELLOW}⚠️  Connection status: $CONN_TEST${NC}"
        fi
    else
        echo -e "${RED}❌ Nginx cannot reach Strapi${NC}"
        echo "   Error: $CONN_TEST"
        echo -e "${YELLOW}   This means Let's Encrypt will fail!${NC}"
        echo ""
        echo "   Possible fixes:"
        echo "   1. Ensure both containers on same network"
        echo "   2. Restart containers"
        echo "   3. Use container IP instead of name"
    fi
    echo ""
fi

echo -e "${BLUE}7️⃣  Checking Strapi Configuration...${NC}"
echo "───────────────────────────────────────"
if docker ps --format '{{.Names}}' | grep -q "^${STRAPI_CONTAINER}$"; then
    IS_PROXIED=$(docker exec $STRAPI_CONTAINER printenv IS_PROXIED 2>/dev/null)
    PUBLIC_URL=$(docker exec $STRAPI_CONTAINER printenv PUBLIC_URL 2>/dev/null)
    HOST=$(docker exec $STRAPI_CONTAINER printenv HOST 2>/dev/null)

    if [ "$IS_PROXIED" == "true" ]; then
        echo -e "${GREEN}✅ IS_PROXIED=true${NC}"
    else
        echo -e "${YELLOW}⚠️  IS_PROXIED not set or false${NC}"
        echo "   Should be: IS_PROXIED=true"
    fi

    if [ "$PUBLIC_URL" == "https://$DOMAIN" ]; then
        echo -e "${GREEN}✅ PUBLIC_URL=https://$DOMAIN${NC}"
    else
        echo -e "${YELLOW}⚠️  PUBLIC_URL=$PUBLIC_URL${NC}"
        echo "   Should be: PUBLIC_URL=https://$DOMAIN"
    fi

    if [ "$HOST" == "0.0.0.0" ]; then
        echo -e "${GREEN}✅ HOST=0.0.0.0${NC}"
    else
        echo -e "${YELLOW}⚠️  HOST=$HOST${NC}"
        echo "   Should be: HOST=0.0.0.0"
    fi
fi
echo ""

echo -e "${BLUE}8️⃣  Testing SSL Certificate (if exists)...${NC}"
echo "───────────────────────────────────────"
SSL_CHECK=$(echo | timeout 5 openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)

if [ -n "$SSL_CHECK" ]; then
    echo -e "${GREEN}✅ SSL Certificate found${NC}"
    echo "$SSL_CHECK"

    # Check expiry
    EXPIRY=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    echo "   Expires: $EXPIRY"
else
    echo -e "${YELLOW}⚠️  No SSL certificate found${NC}"
    echo "   This is normal before Let's Encrypt setup"
fi
echo ""

# Summary
echo "================================================"
echo -e "${BLUE}📊 Summary & Recommendations${NC}"
echo "================================================"
echo ""

# Check if ready for Let's Encrypt
READY=true

if [ -z "$DNS_IP" ]; then
    echo -e "${RED}❌ DNS not configured${NC}"
    READY=false
fi

if ! echo "$UFW_STATUS" | grep -q "80.*ALLOW" && echo "$UFW_STATUS" | grep -q "Status: active"; then
    echo -e "${RED}❌ Port 80 blocked by firewall${NC}"
    READY=false
fi

if [ -z "$NGINX_CONTAINER" ]; then
    echo -e "${RED}❌ Nginx Proxy Manager not running${NC}"
    READY=false
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${STRAPI_CONTAINER}$"; then
    echo -e "${RED}❌ Strapi not running${NC}"
    READY=false
fi

if [[ ! "$CONN_TEST" =~ ^[0-9]+$ ]] && [ -n "$NGINX_CONTAINER" ]; then
    echo -e "${RED}❌ Nginx cannot reach Strapi${NC}"
    READY=false
fi

if [ "$READY" = true ]; then
    echo -e "${GREEN}✅ System is ready for Let's Encrypt setup!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Go to Nginx Proxy Manager: http://$(hostname -I | awk '{print $1}'):81"
    echo "2. Add Proxy Host:"
    echo "   - Domain: $DOMAIN"
    echo "   - Forward to: $STRAPI_CONTAINER:1337"
    echo "   - Enable Websockets"
    echo "3. Request SSL Certificate (Let's Encrypt)"
    echo "4. Enable Force SSL and HTTP/2"
else
    echo -e "${RED}❌ System is NOT ready for Let's Encrypt${NC}"
    echo ""
    echo "Fix the issues above before attempting Let's Encrypt setup"
fi
echo ""

echo "For detailed setup guide, see: LETS_ENCRYPT_GUIDE.md"
echo ""
