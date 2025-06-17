#!/bin/bash
# Script de actualización de aplicaciones
# Uso: ./update-app.sh [posapp|ecommerceapp|buildtool|all]

set -e

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar que estamos en el directorio correcto
if [ ! -f "docker-compose.yml" ]; then
    error "No se encontró docker-compose.yml. Ejecutar desde /root/unified-apps"
    exit 1
fi

# Función para hacer backup
backup_db() {
    log "💾 Creando backup de la base de datos..."
    mkdir -p /root/backups
    docker exec sqlserver_main /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P 'Ant_2019.' \
        -Q "BACKUP DATABASE [POSDB] TO DISK = '/backups/POSDB_backup_$(date +%Y%m%d_%H%M%S).bak'" || warn "No se pudo crear backup"
}

# Función para actualizar un servicio específico
update_service() {
    local service=$1
    log "🔄 Actualizando $service..."
    
    # Detener el servicio
    docker-compose stop $service
    
    # Descargar nueva imagen
    docker-compose pull $service
    
    # Recrear el contenedor
    docker-compose up -d $service
    
    # Esperar un momento
    sleep 10
    
    # Verificar estado
    if docker-compose ps $service | grep -q "Up"; then
        log "✅ $service actualizado correctamente"
        docker-compose logs --tail=20 $service
    else
        error "❌ $service falló al iniciar"
        docker-compose logs --tail=50 $service
        return 1
    fi
}

# Verificar parámetro
if [ -z "$1" ]; then
    echo "Uso: $0 [posapp|ecommerceapp|buildtool|all]"
    echo ""
    echo "Ejemplos:"
    echo "  $0 ecommerceapp    # Actualiza solo EcommerceApp"
    echo "  $0 all             # Actualiza todas las aplicaciones"
    exit 1
fi

# Crear backup antes de actualizar
backup_db

case $1 in
    "posapp")
        update_service posapp
        ;;
    "ecommerceapp")
        update_service ecommerceapp
        # Verificar el sitio web
        sleep 5
        if curl -s -o /dev/null -w "%{http_code}" https://lizzaaccesorios.com.mx | grep -q "200\|302"; then
            log "✅ Sitio web lizzaaccesorios.com.mx funcionando"
        else
            warn "⚠️ Sitio web no responde correctamente"
        fi
        ;;
    "buildtool")
        update_service buildtool
        ;;
    "all")
        log "🚀 Actualizando todas las aplicaciones..."
        update_service buildtool
        update_service posapp
        update_service ecommerceapp
        
        log "🧹 Limpiando imágenes no utilizadas..."
        docker image prune -f
        ;;
    *)
        error "Servicio no válido: $1"
        echo "Servicios disponibles: posapp, ecommerceapp, buildtool, all"
        exit 1
        ;;
esac

log "🎉 Actualización completada"

# Mostrar estado final
echo ""
log "📊 Estado actual de los servicios:"
docker-compose ps