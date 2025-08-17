#!/bin/bash
# Configura variáveis de ambiente padrão para executar a Suprema API

export DATABASE_URL=${DATABASE_URL:-sqlite:///./data.db}
export POLICY_DATABASE_URL=${POLICY_DATABASE_URL:-sqlite:///./policy.db}

echo "DATABASE_URL=$DATABASE_URL"
echo "POLICY_DATABASE_URL=$POLICY_DATABASE_URL"
