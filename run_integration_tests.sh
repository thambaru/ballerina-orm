#!/bin/bash

# Integration Test Runner for Ballerina ORM
# This script sets up Docker containers and runs integration tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Ballerina ORM Integration Test Runner"
echo "========================================"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Function to wait for database to be ready
wait_for_db() {
    local db_name=$1
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}⏳ Waiting for ${db_name} to be ready...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if docker-compose -f docker-compose.test.yml ps | grep -q "healthy"; then
            echo -e "${GREEN}✅ ${db_name} is ready!${NC}"
            return 0
        fi
        
        echo "   Attempt $attempt/$max_attempts..."
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}❌ ${db_name} failed to become ready${NC}"
    return 1
}

# Parse command line arguments
TEST_TARGET="${1:-all}"

case $TEST_TARGET in
    "all")
        echo "📋 Running all integration tests (MySQL + PostgreSQL)"
        
        echo ""
        echo "🐳 Starting database containers..."
        docker-compose -f docker-compose.test.yml up -d
        
        wait_for_db "MySQL"
        wait_for_db "PostgreSQL"
        
        echo ""
        echo "🧪 Running unit tests..."
        bal test --groups unit || true
        
        echo ""
        echo "🔗 Running MySQL integration tests..."
        bal test tests/integration_mysql_test.bal || true
        
        echo ""
        echo "🐘 Running PostgreSQL integration tests..."
        bal test tests/integration_postgresql_test.bal || true
        
        echo ""
        echo "🧹 Cleaning up containers..."
        docker-compose -f docker-compose.test.yml down
        ;;
        
    "mysql")
        echo "📋 Running MySQL integration tests only"
        
        echo ""
        echo "🐳 Starting MySQL container..."
        docker-compose -f docker-compose.test.yml up -d mysql
        
        wait_for_db "MySQL"
        
        echo ""
        echo "🔗 Running MySQL integration tests..."
        bal test tests/integration_mysql_test.bal
        
        echo ""
        echo "🧹 Cleaning up..."
        docker-compose -f docker-compose.test.yml down
        ;;
        
    "postgresql")
        echo "📋 Running PostgreSQL integration tests only"
        
        echo ""
        echo "🐳 Starting PostgreSQL container..."
        docker-compose -f docker-compose.test.yml up -d postgresql
        
        wait_for_db "PostgreSQL"
        
        echo ""
        echo "🐘 Running PostgreSQL integration tests..."
        bal test tests/integration_postgresql_test.bal
        
        echo ""
        echo "🧹 Cleaning up..."
        docker-compose -f docker-compose.test.yml down
        ;;
        
    "unit")
        echo "📋 Running unit tests only (no Docker required)"
        
        echo ""
        echo "🧪 Running unit tests..."
        bal test --groups unit
        ;;
        
    "cleanup")
        echo "🧹 Cleaning up test containers and volumes..."
        docker-compose -f docker-compose.test.yml down -v
        echo -e "${GREEN}✅ Cleanup complete${NC}"
        ;;
        
    *)
        echo "Usage: ./run_integration_tests.sh [all|mysql|postgresql|unit|cleanup]"
        echo ""
        echo "Options:"
        echo "  all         - Run all tests (MySQL + PostgreSQL + unit)"
        echo "  mysql       - Run MySQL integration tests only"
        echo "  postgresql  - Run PostgreSQL integration tests only"
        echo "  unit        - Run unit tests only (no Docker)"
        echo "  cleanup     - Stop and remove all test containers"
        echo ""
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}✨ Test run complete!${NC}"
