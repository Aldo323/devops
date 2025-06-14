#!/bin/bash

# Script de migración a sistema unificado
# Repositorio: https://github.com/Aldo323/devops
# Autor: Aldo Moreno

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log "🚀 Iniciando migración a sistema unificado..."

# Verificar que se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   error "Este script debe ejecutarse como root"
   exit 1
fi

# 1. Crear directorio unificado
log "📁 Creando directorio para sistema unificado..."
mkdir -p /root/unified-apps
cd /root/unified-apps

# 2. Crear archivo .env
log "⚙️  Creando archivo de variables de entorno..."
cat > .env << 'EOF'
# Variables de base de datos
DB_PASSWORD=Ant_2019.

# Variables de MercadoPago (configurar después)
MERCADOPAGO_PUBLIC_KEY=
MERCADOPAGO_ACCESS_TOKEN=

# Variables OAuth Google (configurar después)
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

# Variables OAuth Facebook (configurar después)
FACEBOOK_APP_ID=
FACEBOOK_APP_SECRET=
EOF

# 3. Crear docker-compose.yml unificado
log "🐳 Creando docker-compose.yml unificado..."
cat > docker-compose.yml << 'EOF'
services:
  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: sqlserver_main
    environment:
      - ACCEPT_EULA=Y
      - MSSQL_SA_PASSWORD=Ant_2019.
      - MSSQL_PID=developer
    ports:
      - "1433:1433"
    volumes:
      - sqldata:/var/opt/mssql
      - /root/backups:/backups
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P 'Ant_2019.' -Q 'SELECT 1' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

  posapp:
    image: aldomoreno/posapp:latest
    container_name: posapp_main
    ports:
      - "8081:8080"
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:8080
      - ConnectionStrings__DefaultConnection=Server=sqlserver,1433;Database=POSDB;User Id=sa;Password=Ant_2019.;TrustServerCertificate=True;
    depends_on:
      sqlserver:
        condition: service_healthy
    networks:
      - app-network
    restart: unless-stopped

  buildtool:
    image: aldomoreno/buildtool:latest
    container_name: buildtool_main
    ports:
      - "8080:8080"
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:8080
      - ConnectionStrings__DefaultConnection=Server=sqlserver,1433;Database=POSDB;User Id=sa;Password=Ant_2019.;TrustServerCertificate=True;
    depends_on:
      sqlserver:
        condition: service_healthy
    networks:
      - app-network
    restart: unless-stopped

  ecommerceapp:
    image: aldomoreno/ecommerceapp:latest
    container_name: ecommerce_main
    ports:
      - "8082:8080"
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:8080
      - ConnectionStrings__DefaultConnection=Server=sqlserver,1433;Database=POSDB;User Id=sa;Password=Ant_2019.;TrustServerCertificate=True;
      - BaseUrl=https://lizzaaccesorios.com.mx
      - MercadoPago__PublicKey=${MERCADOPAGO_PUBLIC_KEY:-}
      - MercadoPago__AccessToken=${MERCADOPAGO_ACCESS_TOKEN:-}
      - Authentication__Google__ClientId=${GOOGLE_CLIENT_ID:-}
      - Authentication__Google__ClientSecret=${GOOGLE_CLIENT_SECRET:-}
      - Authentication__Facebook__AppId=${FACEBOOK_APP_ID:-}
      - Authentication__Facebook__AppSecret=${FACEBOOK_APP_SECRET:-}
    depends_on:
      sqlserver:
        condition: service_healthy
    networks:
      - app-network
    restart: unless-stopped

networks:
  app-network:
    driver: bridge
    name: unified_network

volumes:
  sqldata:
    name: unified_sqldata
EOF

# 4. Crear backup de datos actuales
log "💾 Creando backup de la base de datos..."
mkdir -p /root/backups
if docker ps | grep -q sqlserver; then
    docker exec $(docker ps | grep sqlserver | awk '{print $1}') /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P 'Ant_2019.' \
        -Q "BACKUP DATABASE [POSDB] TO DISK = '/backups/POSDB_backup_$(date +%Y%m%d_%H%M%S).bak'" || warn "No se pudo crear backup automático"
fi

# 5. Migrar datos de volumen SQL Server
log "📦 Preparando migración de datos SQL Server..."
if docker volume ls | grep -q buildtool_sqldata; then
    log "Copiando datos de SQL Server..."
    docker volume create unified_sqldata
    docker run --rm -v buildtool_sqldata:/from -v unified_sqldata:/to alpine ash -c "cd /from ; cp -av . /to"
fi

# 6. Parar contenedores actuales (gradualmente)
log "🛑 Deteniendo contenedores actuales..."

# Detener POSApp actual
if docker ps | grep -q posapp_posapp_1; then
    log "Deteniendo POSApp actual..."
    cd /root/posapp && docker compose down 2>/dev/null || docker stop posapp_posapp_1
fi

# Detener BuildTool actual
if docker ps | grep -q buildtool_webapp_1; then
    log "Deteniendo BuildTool actual..."
    cd /root/BuildTool && docker compose down webapp 2>/dev/null || docker stop buildtool_webapp_1
fi

# Detener SQL Server anterior (después de copiar datos)
if docker ps | grep -q buildtool_sqlserver_1; then
    log "Deteniendo SQL Server anterior..."
    cd /root/BuildTool && docker compose down sqlserver 2>/dev/null || docker stop buildtool_sqlserver_1
fi

# 7. Iniciar sistema unificado
log "🚀 Iniciando sistema unificado..."
cd /root/unified-apps

# Primero solo SQL Server
docker compose up -d sqlserver

# Esperar a que SQL Server esté listo
log "⏳ Esperando a que SQL Server esté listo..."
sleep 30

# Verificar SQL Server
for i in {1..10}; do
    if docker compose exec sqlserver /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P 'Ant_2019.' -Q "SELECT 1" > /dev/null 2>&1; then
        log "✅ SQL Server está funcionando"
        break
    else
        warn "Intento $i/10: SQL Server aún no está listo..."
        sleep 10
    fi
    
    if [ $i -eq 10 ]; then
        error "SQL Server no está respondiendo"
        exit 1
    fi
done

# Iniciar todas las aplicaciones
log "🚀 Iniciando todas las aplicaciones..."
docker compose up -d

# 8. Verificar servicios
log "🔍 Verificando servicios..."
sleep 20

services=("posapp:8081" "buildtool:8080" "ecommerceapp:8082")
for service in "${services[@]}"; do
    name=${service%:*}
    port=${service#*:}
    
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:$port | grep -q "200\|302\|404"; then
        log "✅ $name está funcionando en puerto $port"
    else
        warn "⚠️  $name no está respondiendo en puerto $port"
    fi
done

# 9. Configurar Nginx para EcommerceApp
log "🌐 Configurando Nginx para lizzaaccesorios.com.mx..."

cat > /etc/nginx/sites-available/lizzaaccesorios.com.mx << 'EOF'
upstream ecommerce_backend {
    server localhost:8082;
}

server {
    server_name lizzaaccesorios.com.mx www.lizzaaccesorios.com.mx;
    
    location / {
        proxy_pass http://ecommerce_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        client_max_body_size 50M;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location ~ ^/(hub|notificacionesHub|pedidoHub|entregaHub|enhanced-notifications) {
        proxy_pass http://ecommerce_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_buffering off;
        proxy_read_timeout 86400;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://ecommerce_backend;
        proxy_set_header Host $host;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/lizza.com.mx/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/lizza.com.mx/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    access_log /var/log/nginx/lizzaaccesorios_access.log;
    error_log /var/log/nginx/lizzaaccesorios_error.log;
}

server {
    listen 80;
    server_name lizzaaccesorios.com.mx www.lizzaaccesorios.com.mx;
    return 301 https://$server_name$request_uri;
}
EOF

# Habilitar el sitio
ln -sf /etc/nginx/sites-available/lizzaaccesorios.com.mx /etc/nginx/sites-enabled/

# Configurar SSL
log "🔐 Configurando certificados SSL..."
if command -v certbot &> /dev/null; then
    certbot --nginx -d lizzaaccesorios.com.mx -d www.lizzaaccesorios.com.mx --non-interactive --agree-tos --email admin@lizzaaccesorios.com.mx --expand || warn "No se pudo configurar SSL automáticamente"
fi

# Recargar Nginx
nginx -t && systemctl reload nginx

# 10. Crear scripts de administración
log "📝 Creando scripts de administración..."

cat > manage.sh << 'EOF'
#!/bin/bash
cd /root/unified-apps

case $1 in
    "logs")
        if [ -z "$2" ]; then
            docker compose logs -f
        else
            docker compose logs -f $2
        fi
        ;;
    "restart")
        if [ -z "$2" ]; then
            docker compose restart
        else
            docker compose restart $2
        fi
        ;;
    "status")
        docker compose ps
        ;;
    "update")
        docker compose pull
        docker compose up -d
        docker image prune -f
        ;;
    *)
        echo "Uso: ./manage.sh [logs|restart|status|update] [servicio]"
        echo "Servicios: sqlserver, posapp, buildtool, ecommerceapp"
        ;;
esac
EOF

chmod +x manage.sh

echo ""
log "🎉 ¡Migración completada exitosamente!"
echo ""
echo -e "${BLUE}📊 Sistema unificado configurado:${NC}"
echo "📁 Directorio: /root/unified-apps"
echo "🐳 Servicios: SQL Server, POSApp, BuildTool, EcommerceApp"
echo "🌐 EcommerceApp: https://lizzaaccesorios.com.mx"
echo ""
echo -e "${BLUE}📝 Gestión del sistema:${NC}"
echo "   Estado:     ./manage.sh status"
echo "   Logs:       ./manage.sh logs [servicio]"
echo "   Reiniciar:  ./manage.sh restart [servicio]"
echo "   Actualizar: ./manage.sh update"
echo ""
echo -e "${YELLOW}⚠️  Configurar después:${NC}"
echo "1. Variables de MercadoPago en .env"
echo "2. Variables OAuth en .env"
echo "3. Reiniciar EcommerceApp: ./manage.sh restart ecommerceapp"