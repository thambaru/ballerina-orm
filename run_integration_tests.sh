#!/bin/bash

# Integration Test Runner for Ballerina ORM
# This script sets up Docker containers and runs integration tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Ballerina ORM Integration Test Runner"
echo "========================================"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TEST_FAILURE=0
CONTAINERS_STARTED=0

if docker compose version > /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker compose)
elif command -v docker-compose > /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=(docker-compose)
else
    echo -e "${RED}❌ Docker Compose is not available. Install Docker Compose and try again.${NC}"
    exit 1
fi

compose() {
    "${DOCKER_COMPOSE_CMD[@]}" -f docker-compose.test.yml "$@"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Function to wait for database to be ready
wait_for_db() {
    local db_name=$1
    local service_name=$2
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}⏳ Waiting for ${db_name} to be ready...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if compose ps "$service_name" | grep -q "healthy"; then
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

run_test_step() {
    local test_name=$1
    shift

    if "$@"; then
        echo -e "${GREEN}✅ ${test_name} passed${NC}"
    else
        echo -e "${RED}❌ ${test_name} failed${NC}"
        TEST_FAILURE=1
    fi
}

cleanup_containers() {
    if [ "$CONTAINERS_STARTED" -eq 1 ]; then
        echo ""
        echo "🧹 Cleaning up containers..."
        compose down
    fi
}

trap cleanup_containers EXIT

# Parse command line arguments
TEST_TARGET="${1:-all}"

case $TEST_TARGET in
    "all")
        echo "📋 Running all integration tests (MySQL + PostgreSQL)"
        
        echo ""
        echo "🐳 Starting database containers..."
        compose up -d
        CONTAINERS_STARTED=1
        
        wait_for_db "MySQL" "mysql"
        wait_for_db "PostgreSQL" "postgresql"
        
        echo ""
        echo "🧪 Running unit tests..."
        run_test_step "Unit tests" bal test --disable-groups integration
        
        echo ""
        echo "🔗 Running MySQL integration tests..."
        run_test_step "MySQL integration tests" bal test --groups mysql
        
        echo ""
        echo "🐘 Running PostgreSQL integration tests..."
        run_test_step "PostgreSQL integration tests" bal test --groups postgresql
        ;;
        
    "mysql")
        echo "📋 Running MySQL integration tests only"
        
        echo ""
        echo "🐳 Starting MySQL container..."
        compose up -d mysql
        CONTAINERS_STARTED=1
        
        wait_for_db "MySQL" "mysql"
        
        echo ""
        echo "🔗 Running MySQL integration tests..."
        run_test_step "MySQL integration tests" bal test --groups mysql
        ;;
        
    "postgresql")
        echo "📋 Running PostgreSQL integration tests only"
        
        echo ""
        echo "🐳 Starting PostgreSQL container..."
        compose up -d postgresql
        CONTAINERS_STARTED=1
        
        wait_for_db "PostgreSQL" "postgresql"
        
        echo ""
        echo "🐘 Running PostgreSQL integration tests..."
        run_test_step "PostgreSQL integration tests" bal test --groups postgresql
        ;;
        
    "unit")
        echo "📋 Running unit tests only (no Docker required)"
        
        echo ""
        echo "🧪 Running unit tests..."
        run_test_step "Unit tests" bal test --disable-groups integration
        ;;
        
    "cleanup")
        echo "🧹 Cleaning up test containers and volumes..."
        compose down -v
        CONTAINERS_STARTED=0
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
if [ "$TEST_FAILURE" -eq 0 ]; then
    echo -e "${GREEN}✨ Test run complete!${NC}"
else
    echo -e "${RED}❌ Test run completed with failures.${NC}"
    exit 1
fi
