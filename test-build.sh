#!/bin/bash

# Script para testar o build antes do pipeline
set -e

echo "=== Teste de Build Local ==="
echo "Simulando ambiente do CodeBuild..."

# Variáveis de ambiente simulando CodeBuild
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCOUNT_ID=975050217683
export CODEBUILD_RESOLVED_SOURCE_VERSION=$(git rev-parse HEAD)

echo "AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"
echo "AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
echo "CODEBUILD_RESOLVED_SOURCE_VERSION: $CODEBUILD_RESOLVED_SOURCE_VERSION"

# Simular variáveis do buildspec
REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/bia
COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
IMAGE_TAG=${COMMIT_HASH:=latest}

echo "REPOSITORY_URI: $REPOSITORY_URI"
echo "COMMIT_HASH: $COMMIT_HASH"
echo "IMAGE_TAG: $IMAGE_TAG"

echo ""
echo "=== Testando Build Docker ==="
docker build -t $REPOSITORY_URI:latest .
docker tag $REPOSITORY_URI:latest $REPOSITORY_URI:$IMAGE_TAG

echo ""
echo "=== Gerando imagedefinitions.json ==="
printf '[{"name":"bia","imageUri":"%s"}]' $REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json
echo "Conteúdo do imagedefinitions.json:"
cat imagedefinitions.json

echo ""
echo "=== Teste Concluído com Sucesso! ==="
echo "Imagens criadas:"
docker images | grep $REPOSITORY_URI
