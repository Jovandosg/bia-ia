#!/bin/bash

# Script de Deploy para ECS - Projeto BIA
# Autor: Amazon Q
# Versão: 1.0

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações padrão
DEFAULT_REGION="us-east-1"
DEFAULT_CLUSTER="cluster-bia"
DEFAULT_SERVICE="service-bia"
DEFAULT_TASK_FAMILY="task-bia"
DEFAULT_ECR_REPO="bia"

# Função para exibir help
show_help() {
    echo -e "${BLUE}=== Script de Deploy ECS - Projeto BIA ===${NC}"
    echo ""
    echo -e "${YELLOW}DESCRIÇÃO:${NC}"
    echo "  Script para build e deploy da aplicação BIA no ECS com versionamento por commit hash"
    echo ""
    echo -e "${YELLOW}USO:${NC}"
    echo "  ./deploy.sh [OPÇÕES] COMANDO"
    echo ""
    echo -e "${YELLOW}COMANDOS:${NC}"
    echo "  build     - Faz build da imagem Docker com tag do commit hash"
    echo "  deploy    - Faz deploy da aplicação no ECS"
    echo "  full      - Executa build + deploy em sequência"
    echo "  rollback  - Faz rollback para uma versão anterior"
    echo "  list      - Lista as últimas 10 versões disponíveis no ECR"
    echo ""
    echo -e "${YELLOW}OPÇÕES:${NC}"
    echo "  -r, --region REGION        Região AWS (padrão: $DEFAULT_REGION)"
    echo "  -c, --cluster CLUSTER      Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)"
    echo "  -s, --service SERVICE      Nome do serviço ECS (padrão: $DEFAULT_SERVICE)"
    echo "  -t, --task-family FAMILY   Família da task definition (padrão: $DEFAULT_TASK_FAMILY)"
    echo "  -e, --ecr-repo REPO        Nome do repositório ECR (padrão: $DEFAULT_ECR_REPO)"
    echo "  -v, --version VERSION      Versão específica para rollback (formato: commit-hash)"
    echo "  -h, --help                 Exibe esta ajuda"
    echo ""
    echo -e "${YELLOW}EXEMPLOS:${NC}"
    echo "  ./deploy.sh build                    # Build da imagem atual"
    echo "  ./deploy.sh deploy                   # Deploy da última versão"
    echo "  ./deploy.sh full                     # Build + Deploy"
    echo "  ./deploy.sh rollback -v abc123       # Rollback para commit abc123"
    echo "  ./deploy.sh list                     # Lista versões disponíveis"
    echo "  ./deploy.sh -r us-west-2 full        # Deploy em região específica"
    echo ""
    echo -e "${YELLOW}PRÉ-REQUISITOS:${NC}"
    echo "  - AWS CLI configurado"
    echo "  - Docker instalado"
    echo "  - Permissões para ECR, ECS e IAM"
    echo "  - Repositório ECR criado"
    echo ""
}

# Função para log colorido
log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $*" ;;
    esac
}

# Função para verificar pré-requisitos
check_prerequisites() {
    log "INFO" "Verificando pré-requisitos..."
    
    # Verificar AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI não encontrado. Instale o AWS CLI primeiro."
        exit 1
    fi
    
    # Verificar Docker
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker não encontrado. Instale o Docker primeiro."
        exit 1
    fi
    
    # Verificar se está em um repositório git
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log "ERROR" "Este não é um repositório Git válido."
        exit 1
    fi
    
    # Verificar credenciais AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "Credenciais AWS não configuradas ou inválidas."
        exit 1
    fi
    
    log "INFO" "Pré-requisitos verificados com sucesso!"
}

# Função para obter commit hash
get_commit_hash() {
    git rev-parse --short=7 HEAD
}

# Função para obter account ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text --region $REGION
}

# Função para fazer build da imagem
build_image() {
    log "INFO" "Iniciando build da imagem..."
    
    local commit_hash=$(get_commit_hash)
    local account_id=$(get_account_id)
    local ecr_uri="${account_id}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"
    local image_tag="${commit_hash}"
    
    log "INFO" "Commit hash: $commit_hash"
    log "INFO" "ECR URI: $ecr_uri"
    log "INFO" "Image tag: $image_tag"
    
    # Login no ECR
    log "INFO" "Fazendo login no ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ecr_uri
    
    # Build da imagem
    log "INFO" "Fazendo build da imagem Docker..."
    docker build -t $ECR_REPO:$image_tag .
    docker tag $ECR_REPO:$image_tag $ecr_uri:$image_tag
    
    # Push da imagem
    log "INFO" "Fazendo push da imagem para ECR..."
    docker push $ecr_uri:$image_tag
    
    log "INFO" "Build concluído! Imagem: $ecr_uri:$image_tag"
    echo $image_tag > .last_build_tag
}

# Função para criar nova task definition
create_task_definition() {
    local image_tag=$1
    local account_id=$(get_account_id)
    local ecr_uri="${account_id}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}:${image_tag}"
    
    log "INFO" "Criando nova task definition..."
    log "INFO" "Imagem: $ecr_uri"
    
    # Obter task definition atual
    local current_task_def=$(aws ecs describe-task-definition \
        --task-definition $TASK_FAMILY \
        --region $REGION \
        --query 'taskDefinition' \
        --output json 2>/dev/null || echo "{}")
    
    if [ "$current_task_def" = "{}" ]; then
        log "ERROR" "Task definition $TASK_FAMILY não encontrada. Crie uma task definition base primeiro."
        exit 1
    fi
    
    # Atualizar imagem na task definition
    local new_task_def=$(echo $current_task_def | jq --arg image "$ecr_uri" '
        .containerDefinitions[0].image = $image |
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
    ')
    
    # Criar nova revisão
    local new_revision=$(aws ecs register-task-definition \
        --region $REGION \
        --cli-input-json "$new_task_def" \
        --query 'taskDefinition.revision' \
        --output text)
    
    log "INFO" "Nova task definition criada: $TASK_FAMILY:$new_revision"
    echo "$TASK_FAMILY:$new_revision"
}

# Função para fazer deploy
deploy_application() {
    local image_tag=${1:-$(cat .last_build_tag 2>/dev/null)}
    
    if [ -z "$image_tag" ]; then
        log "ERROR" "Tag da imagem não especificada. Execute build primeiro ou use -v para especificar uma versão."
        exit 1
    fi
    
    log "INFO" "Iniciando deploy da versão: $image_tag"
    
    # Criar nova task definition
    local task_definition=$(create_task_definition $image_tag)
    
    # Atualizar serviço ECS
    log "INFO" "Atualizando serviço ECS..."
    aws ecs update-service \
        --cluster $CLUSTER \
        --service $SERVICE \
        --task-definition $task_definition \
        --region $REGION \
        --query 'service.serviceName' \
        --output text > /dev/null
    
    log "INFO" "Deploy iniciado! Aguardando estabilização do serviço..."
    
    # Aguardar estabilização
    aws ecs wait services-stable \
        --cluster $CLUSTER \
        --services $SERVICE \
        --region $REGION
    
    log "INFO" "Deploy concluído com sucesso!"
    log "INFO" "Versão deployada: $image_tag"
    
    # Salvar versão atual
    echo $image_tag > .current_version
}

# Função para listar versões
list_versions() {
    log "INFO" "Listando últimas 10 versões no ECR..."
    
    local account_id=$(get_account_id)
    
    aws ecr describe-images \
        --repository-name $ECR_REPO \
        --region $REGION \
        --query 'sort_by(imageDetails,&imagePushedAt)[-10:].{Tag:imageTags[0],Pushed:imagePushedAt,Size:imageSizeInBytes}' \
        --output table
}

# Função para rollback
rollback_version() {
    local target_version=$1
    
    if [ -z "$target_version" ]; then
        log "ERROR" "Versão para rollback não especificada. Use -v para especificar a versão."
        exit 1
    fi
    
    log "WARN" "Iniciando rollback para versão: $target_version"
    
    # Verificar se a imagem existe no ECR
    local account_id=$(get_account_id)
    local image_exists=$(aws ecr describe-images \
        --repository-name $ECR_REPO \
        --image-ids imageTag=$target_version \
        --region $REGION \
        --query 'imageDetails[0].imageTags[0]' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$image_exists" = "None" ]; then
        log "ERROR" "Versão $target_version não encontrada no ECR."
        log "INFO" "Use './deploy.sh list' para ver versões disponíveis."
        exit 1
    fi
    
    deploy_application $target_version
    log "INFO" "Rollback concluído para versão: $target_version"
}

# Parsing de argumentos
REGION=$DEFAULT_REGION
CLUSTER=$DEFAULT_CLUSTER
SERVICE=$DEFAULT_SERVICE
TASK_FAMILY=$DEFAULT_TASK_FAMILY
ECR_REPO=$DEFAULT_ECR_REPO
VERSION=""
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER="$2"
            shift 2
            ;;
        -s|--service)
            SERVICE="$2"
            shift 2
            ;;
        -t|--task-family)
            TASK_FAMILY="$2"
            shift 2
            ;;
        -e|--ecr-repo)
            ECR_REPO="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        build|deploy|full|rollback|list)
            COMMAND="$1"
            shift
            ;;
        *)
            log "ERROR" "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verificar se comando foi especificado
if [ -z "$COMMAND" ]; then
    log "ERROR" "Comando não especificado."
    show_help
    exit 1
fi

# Verificar pré-requisitos
check_prerequisites

# Executar comando
case $COMMAND in
    "build")
        build_image
        ;;
    "deploy")
        deploy_application $VERSION
        ;;
    "full")
        build_image
        deploy_application
        ;;
    "rollback")
        rollback_version $VERSION
        ;;
    "list")
        list_versions
        ;;
    *)
        log "ERROR" "Comando inválido: $COMMAND"
        show_help
        exit 1
        ;;
esac

log "INFO" "Operação concluída!"
