#!/bin/bash

echo "=== Teste de Push ECR ==="

# Fazer login no ECR
echo "Fazendo login no ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 975050217683.dkr.ecr.us-east-1.amazonaws.com

# Verificar se a imagem existe localmente
echo "Verificando imagens locais..."
docker images | grep 975050217683.dkr.ecr.us-east-1.amazonaws.com/bia

# Tentar fazer push
echo "Tentando fazer push..."
REPOSITORY_URI=975050217683.dkr.ecr.us-east-1.amazonaws.com/bia
docker push $REPOSITORY_URI:latest

echo "Teste concluído!"
