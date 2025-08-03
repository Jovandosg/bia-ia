#!/bin/bash

echo "=== Verificação de Configurações CodeBuild ==="

# Verificar se há projetos CodeBuild com o nome relacionado
echo "Tentando listar projetos CodeBuild..."
aws codebuild list-projects 2>/dev/null | grep -i bia || echo "Sem permissão para listar projetos CodeBuild"

echo ""
echo "=== Verificações de ECR ==="
echo "Account ID atual:"
aws sts get-caller-identity --query Account --output text

echo ""
echo "Repositórios ECR disponíveis:"
aws ecr describe-repositories --query 'repositories[*].[repositoryName,repositoryUri]' --output table

echo ""
echo "=== Possíveis Problemas ==="
echo "1. Variável de ambiente AWS_ACCOUNT_ID no projeto CodeBuild pode estar definida como 905418381762"
echo "2. Configuração de ECR no projeto CodeBuild pode estar apontando para account antigo"
echo "3. Buildspec.yml pode estar sendo sobrescrito por configuração do projeto"

echo ""
echo "=== Soluções Recomendadas ==="
echo "1. Verificar variáveis de ambiente no projeto CodeBuild no console AWS"
echo "2. Verificar se há um buildspec.yml inline no projeto que sobrescreve o arquivo"
echo "3. Usar o buildspec-debug.yml temporariamente para identificar o problema"
