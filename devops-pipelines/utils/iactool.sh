#!/bin/bash
##########################################################################################################################################################################################
#- Purpose: Script used to install pre-requisites, deploy/undeploy service, start/stop service, test service
#- Parameters are:
#- [-a] action - value: login, install, deploy, undeploy, createapp, buildfe, buildbe, deployfe, deploybe, deployev 
#- [-e] Stop on Error - by default false
#- [-s] Silent mode - by default false
#- [-d] Deployment type: 'web-app-api-cosmosdb', 'web-app-api-storage', 'web-storage-api-storage', 'eventhub', 'eventhub-asa' - by default 'web-storage-api-storage'
#- [-c] configuration file - which contains the list of path of each iactool.sh to call (configuration/default.env by default)
#- [-z] authorization disabled - Azure AD Authorization disabled for Web UI and Web API - by default false
#- [-k] service Plan Sku - Azure Service Plan Sku - by default B2  values: "B1","B2","B3","S1","S2","S3","P1V2","P2V2","P3V2","P1V3","P2V3","P3V3"
#- [-h] event Hub Sku - Event Hub Sku - by default Standard  values: "Basic","Standard","Premium"
#

# executable
###########################################################################################################################################################################################
set -eu
#repoRoot="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# shellcheck disable=SC2034
parent_path=$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../../"
    pwd -P
)
# Read variables in configuration file
SCRIPTS_DIRECTORY=$(dirname "$0")
# shellcheck disable=SC1090
source "$SCRIPTS_DIRECTORY"/common.sh


# container version (current date)
APPLICATION_VERSION=$(date +"%y%m%d.%H%M%S")
export APP_VERSION="$APPLICATION_VERSION"
# container internal HTTP port
export APP_PORT=80
# webapp prefix 
export AZURE_APP_PREFIX="visits01"
# webapp appId 
export AZURE_APP_ID=""
#######################################################
#- function used to print out script usage
#######################################################
function usage() {
    echo
    echo "Arguments:"
    echo -e " -a  Sets iactool action {login, install, deploy, undeploy, createapp, buildfe, buildbe, deployfe, deploybe, deployev}"
    echo -e " -c  Sets the iactool configuration file"
    echo -e " -e  Sets the stop on error (false by defaut)"
    echo -e " -s  Sets Silent mode installation or deployment (false by defaut)"
    echo -e " -d  Deployment type: 'web-app-api-cosmosdb', 'web-app-api-storage', 'web-storage-api-storage', 'eventhub', 'eventhub-asa', - by default 'web-storage-api-storage'"
    echo -e " -i  Application Id in Microsoft Graph associated with Web API and Web UI"
    echo -e " -z  Authorization disabled - Azure AD Authorization disabled for Web UI and Web API - by default false"
    echo -e " -k  Service Plan Sku - Azure Service Plan Sku - by default B1"
    echo -e " -h  Event Hub Sku - Azure Event Hub Sku - by default Standard (Basic, Standard, Premium)"

    echo
    echo "Example:"
    echo -e " bash ./iactool.sh -a install "
    echo -e " bash ./iactool.sh -a deploy -c .mtstool.env -e true -s true"
    
}

action=
configuration_file="$(dirname "${BASH_SOURCE[0]}")/../../configuration/.default.env"
stoperror=false
silentmode=false
authorizationDisabled=false
deploymentType="web-storage-api-storage"
servicePlanSku="B2"
eventhubSku="Standard"

# shellcheck disable=SC2034
while getopts "a:c:e:s:g:o:u:r:n:d:i:x:k:h:z:t:hq" opt; do
    case $opt in
    a) action=$OPTARG ;;
    c) configuration_file=$OPTARG ;;
    e) stoperror=$OPTARG ;;
    s) silentmode=$OPTARG ;;
    z) authorizationDisabled=$OPTARG ;;
    k) servicePlanSku=$OPTARG ;;
    h) eventhubSku=$OPTARG ;;
    d) deploymentType=$OPTARG ;;
    i) AZURE_APP_ID=$OPTARG ;;
    :)
        echo "Error: -${OPTARG} requires a value"
        exit 1
        ;;
    *)
        usage
        exit 1
        ;;
    esac
done

# Validation
if [[ $# -eq 0 || -z $action || -z $configuration_file ]]; then
    echo "Required parameters are missing"
    usage
    exit 1
fi
if [[ ! $action == login && ! $action == install && ! $action == createapp && ! $action == buildbe && ! $action == buildfe && ! $action == deploybe && ! $action == deployfe && ! $action == deployev && ! $action == deploycontainer && ! $action == buildcontainer && ! $action == deploy && ! $action == undeploy ]]; then
    echo "Required action is missing, values: login, install, deploy, undeploy, createapp, buildfe, buildbe, deployfe, deploybe"
    usage
    exit 1
fi
# colors for formatting the ouput
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
GREEN='\033[1;32m'
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
BLUE='\033[1;34m'
# shellcheck disable=SC2034
NC='\033[0m' # No Color

# check if configuration file is set 
if [[ -z $configuration_file ]]; then
    configuration_file="$(dirname "${BASH_SOURCE[0]}")/../../configuration/.default.env"
fi

# get Azure Subscription and Tenant Id if already connected
AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv 2> /dev/null) || true
AZURE_TENANT_ID=$(az account show --query tenantId -o tsv 2> /dev/null) || true

# check if configuration file is set 
if [[ -z ${AZURE_SUBSCRIPTION_ID} || -z ${AZURE_TENANT_ID}  ]]; then
    printError "Connection to Azure required, launching 'az login'"
    printMessage "Login..."
    azLogin
    checkLoginAndSubscription
    printMessage "Login done"    
    AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv 2> /dev/null) || true
    AZURE_TENANT_ID=$(az account show --query tenantId -o tsv 2> /dev/null) || true
fi
AZURE_APP_PREFIX="visit$(shuf -i 1000-9999 -n 1)"


# Check if configuration file exists
if [[ ! -f "$configuration_file" ]]; then
    cat > "$configuration_file" << EOF
AZURE_REGION="eastus2"
AZURE_APP_PREFIX=${AZURE_APP_PREFIX}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
EOF
fi

if [[ $configuration_file ]]; then
    if [ ! -f "$configuration_file" ]; then
        printError "$configuration_file does not exist."
        exit 1
    fi
    readConfigurationFile "$configuration_file"
else
    printWarning "No env. file specified. Using environment variables."
fi

if [[ "${action}" == "install" ]] ; then
    printMessage "Installing pre-requisite"
    printProgress "Installing azure cli"
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    az config set extension.use_dynamic_install=yes_without_prompt
    sudo apt-get -y update
    sudo apt-get -y install  jq
    printProgress "Installing .Net 6.0 SDK "
    wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
    sudo apt-get update; \
    sudo apt-get install -y apt-transport-https && \
    sudo apt-get update && \
    sudo apt-get install -y dotnet-sdk-6.0
    printProgress "Installing Typescript and node services "
    sudo npm install -g npm@latest 
    printProgress "NPM version:"
    sudo npm --version 
    sudo npm install --location=global -g typescript
    tsc --version
    sudo npm install --location=global -g webpack
    sudo npm install --location=global  --save-dev @types/jquery
    sudo npm install --location=global -g http-server
    sudo npm install --location=global -g forever
    printMessage "Installing pre-requisites done"
    exit 0
fi
if [[ "${action}" == "login" ]] ; then
    printMessage "Login..."
    azLogin
    checkLoginAndSubscription
    printMessage "Login done"
    exit 0
fi

if [[ "${action}" == "deploy" ]] ; then
    printMessage "Deploying the infrastructure..."
    # Check Azure connection
    printProgress "Check Azure connection for subscription: '$AZURE_SUBSCRIPTION_ID'"
    azLogin
    checkError    
    if [ "$deploymentType" == 'web-app-api-cosmosdb' ] ; then
        printMessage "Deploy infrastructure subscription: '$AZURE_SUBSCRIPTION_ID' region: '$AZURE_REGION' prefix: '$AZURE_APP_PREFIX'"
        printMessage "       Frontend: 'Azure App Service', Backend: 'Azure Function', Database: 'CosmosDB'"
        deployAzureInfrastructure "$AZURE_SUBSCRIPTION_ID" "$AZURE_REGION" "$AZURE_APP_PREFIX" "$servicePlanSku" "$SCRIPTS_DIRECTORY/../../infra/web-app-api-cosmosdb/arm/global.json"    
        printMessage "Clear Azure CosmosDB table: visittable"
        cmd="az cosmosdb sql container delete --account-name ${COSMOS_DB_SERVICE_NAME} --database-name ${COSMOS_DB_NAME} --name visittable --resource-group ${RESOURCE_GROUP} --yes 2> /dev/null"
        printProgress "$cmd"
        eval "$cmd"        
    elif [ "$deploymentType" == 'web-app-api-storage' ] ; then
        printMessage "Deploy infrastructure subscription: '$AZURE_SUBSCRIPTION_ID' region: '$AZURE_REGION' prefix: '$AZURE_APP_PREFIX'"
        printMessage "       Frontend: 'Azure App Service', Backend: 'Azure Function', Database: 'Table Storage'"
        deployAzureInfrastructure "$AZURE_SUBSCRIPTION_ID" "$AZURE_REGION" "$AZURE_APP_PREFIX" "$servicePlanSku" "$SCRIPTS_DIRECTORY/../../infra/web-app-api-storage/arm/global.json"
        printMessage "Clear Azure Storage table: visittable"
        cmd="az storage table delete --name 'visittable' --account-name \"${STORAGE_ACCOUNT_NAME}\" --sas-token \"${STORAGE_ACCOUNT_TOKEN}\" --only-show-errors"
        printProgress "$cmd"
        eval "$cmd"
    elif [ "$deploymentType" == 'web-storage-api-storage' ] ; then
        printMessage "Deploy infrastructure subscription: '$AZURE_SUBSCRIPTION_ID' region: '$AZURE_REGION' prefix: '$AZURE_APP_PREFIX'"
        printMessage "       Frontend: 'Azure Storage', Backend: 'Azure Function', Database: 'Table Storage'"
        deployAzureInfrastructure "$AZURE_SUBSCRIPTION_ID" "$AZURE_REGION" "$AZURE_APP_PREFIX" "$servicePlanSku" "$SCRIPTS_DIRECTORY/../../infra/web-storage-api-storage/arm/global.json"
        printMessage "Clear Azure Storage table: visittable"
        cmd="az storage table delete --name 'visittable' --account-name \"${STORAGE_ACCOUNT_NAME}\" --sas-token \"${STORAGE_ACCOUNT_TOKEN}\" --only-show-errors"
        printProgress "$cmd"
        eval "$cmd"
    elif [ "$deploymentType" == 'eventhub' ] ; then
        printMessage "Deploy infrastructure subscription: '$AZURE_SUBSCRIPTION_ID' region: '$AZURE_REGION' prefix: '$AZURE_APP_PREFIX'"
        printMessage "       Backend: 'Azure EventHubs'"
        deployAzureInfrastructure "$AZURE_SUBSCRIPTION_ID" "$AZURE_REGION" "$AZURE_APP_PREFIX" "$eventhubSku" "$SCRIPTS_DIRECTORY/../../infra/eventhub/arm/global.json"
    elif [ "$deploymentType" == 'eventhub-firewall' ] ; then
        printMessage "Deploy infrastructure subscription: '$AZURE_SUBSCRIPTION_ID' region: '$AZURE_REGION' prefix: '$AZURE_APP_PREFIX'"
        printMessage "       Backend: 'Azure EventHubs with Firewall'"
        # Get Agent IP address
        ip=$(curl -s http://ifconfig.me/ip) || true
        deployAzureInfrastructure "$AZURE_SUBSCRIPTION_ID" "$AZURE_REGION" "$AZURE_APP_PREFIX" "$eventhubSku" "$SCRIPTS_DIRECTORY/../../infra/eventhub-firewall/arm/global.json" "$ip"
    elif [ "$deploymentType" == 'eventhub-asa' ] ; then
        printMessage "Deploy infrastructure subscription: '$AZURE_SUBSCRIPTION_ID' region: '$AZURE_REGION' prefix: '$AZURE_APP_PREFIX'"
        printMessage "       Backend: 'Azure EventHubs'"
        deployAzureInfrastructure "$AZURE_SUBSCRIPTION_ID" "$AZURE_REGION" "$AZURE_APP_PREFIX" "$eventhubSku" "$SCRIPTS_DIRECTORY/../../infra/eventhub-asa/arm/global.json"
    fi
    updateConfigurationFile "${configuration_file}" "RESOURCE_GROUP" "${RESOURCE_GROUP}"
    
    if [ "$deploymentType" == 'web-app-api-cosmosdb' ] || [ "$deploymentType" == 'web-app-api-storage' ] || [ "$deploymentType" == 'web-storage-api-storage' ] ; then
        printMessage "Azure Container Registry DNS name: ${ACR_LOGIN_SERVER}"
        printMessage "Azure Web App Url: ${WEB_APP_SERVER}"
        printMessage "Azure function Url: ${FUNCTION_SERVER}"
        # set Azure DevOps variable AZURE_APP_ID if run from a pipeline
        WEB_APP_DOMAIN=$(echo "${WEB_APP_SERVER}" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
        FUNCTION_DOMAIN=$(echo "${FUNCTION_SERVER}" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
        updateConfigurationFile "${configuration_file}" "ACR_LOGIN_SERVER" "${ACR_LOGIN_SERVER}"
        updateConfigurationFile "${configuration_file}" "WEB_APP_SERVER" "${WEB_APP_SERVER}"
        updateConfigurationFile "${configuration_file}" "FUNCTION_SERVER" "${FUNCTION_SERVER}"
        updateConfigurationFile "${configuration_file}" "WEB_APP_DOMAIN" "${WEB_APP_DOMAIN}"
        updateConfigurationFile "${configuration_file}" "FUNCTION_DOMAIN" "${FUNCTION_DOMAIN}"


    else 
        updateConfigurationFile "${configuration_file}" "ACR_LOGIN_SERVER" ""
        updateConfigurationFile "${configuration_file}" "WEB_APP_SERVER" ""
        updateConfigurationFile "${configuration_file}" "FUNCTION_SERVER" ""
        updateConfigurationFile "${configuration_file}" "WEB_APP_DOMAIN" ""
        updateConfigurationFile "${configuration_file}" "FUNCTION_DOMAIN" ""

    fi
    if [ "$deploymentType" == 'web-app-api-cosmosdb' ] ; then
        printMessage "Cosmos DB Service: ${COSMOS_DB_SERVICE_NAME}"
        updateConfigurationFile "${configuration_file}" "COSMOS_DB_SERVICE_NAME" "${COSMOS_DB_SERVICE_NAME}"  
    else
        updateConfigurationFile "${configuration_file}" "COSMOS_DB_SERVICE_NAME" ""
    fi
    if [ "$deploymentType" == 'eventhub' ] || [ "$deploymentType" == 'eventhub-firewall' ] || [ "$deploymentType" == 'eventhub-asa' ]; then
        printMessage "Eventhub name space:  ${EVENTHUB_NAME_SPACE}"
        printMessage "Eventhub input 1:  ${EVENTHUB_INPUT_1_NAME}"
        printMessage "Eventhub input 2:  ${EVENTHUB_INPUT_2_NAME}"
        printMessage "Eventhub output 1:  ${EVENTHUB_OUTPUT_1_NAME}"
        printMessage "Eventhub output 1 consumer group:  ${EVENTHUB_OUTPUT_1_CONSUMER_GROUP_NAME}"
        updateConfigurationFile "${configuration_file}" "EVENTHUB_NAME_SPACE" "${EVENTHUB_NAME_SPACE}" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_INPUT_1_NAME" "${EVENTHUB_INPUT_1_NAME}" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_INPUT_2_NAME" "${EVENTHUB_INPUT_2_NAME}" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_OUTPUT_1_NAME" "${EVENTHUB_OUTPUT_1_NAME}" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_INPUT_1_CONSUMER_GROUP_NAME" "${EVENTHUB_INPUT_1_CONSUMER_GROUP_NAME}" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_INPUT_2_CONSUMER_GROUP_NAME" "${EVENTHUB_INPUT_2_CONSUMER_GROUP_NAME}" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_OUTPUT_1_CONSUMER_GROUP_NAME" "${EVENTHUB_OUTPUT_1_CONSUMER_GROUP_NAME}" 

    else      
        updateConfigurationFile "${configuration_file}" "EVENTHUB_NAME_SPACE" "" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_INPUT_1_NAME" "" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_INPUT_2_NAME" "" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_OUTPUT_1_NAME" "" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_INPUT_1_CONSUMER_GROUP_NAME" "" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_INPUT_2_CONSUMER_GROUP_NAME" "" 
        updateConfigurationFile "${configuration_file}" "EVENTHUB_OUTPUT_1_CONSUMER_GROUP_NAME" ""         
    fi
    if [ "$deploymentType" == 'eventhub-asa' ]; then
        printMessage "Stream Analytics Job:  ${STREAM_ANALYTICS_JOB_NAME}"
        updateConfigurationFile "${configuration_file}" "STREAM_ANALYTICS_JOB_NAME" "${STREAM_ANALYTICS_JOB_NAME}"   
    else      
        updateConfigurationFile "${configuration_file}" "STREAM_ANALYTICS_JOB_NAME" ""   
    fi    
    printMessage "Storage Account Name: ${STORAGE_ACCOUNT_NAME}"
    printMessage "AppInsights Name: ${APP_INSIGHTS_NAME}"
    updateConfigurationFile "${configuration_file}" "STORAGE_ACCOUNT_NAME" "${STORAGE_ACCOUNT_NAME}"   
    updateConfigurationFile "${configuration_file}" "APP_INSIGHTS_NAME" "${APP_INSIGHTS_NAME}"   
    echo "File: ${configuration_file}"
    cat "${configuration_file}"
    printMessage "Deploying the infrastructure done"
    exit 0
fi

if [[ "${action}" == "undeploy" ]] ; then
    printMessage "Undeploying the infrastructure..."
    # Check Azure connection
    printProgress "Check Azure connection for subscription: '$AZURE_SUBSCRIPTION_ID'"
    azLogin
    checkError
    undeployAzureInfrastructure "$AZURE_SUBSCRIPTION_ID" "$AZURE_APP_PREFIX"

    printMessage "Undeploying the infrastructure done"
    exit 0
fi


if [[ "${action}" == "deployev" ]] ; then
    printMessage "Deploying the Event Hub backend..."

    # Check Azure connection
    printProgress "Check Azure connection for subscription: '$AZURE_SUBSCRIPTION_ID'"
    azLogin
    checkError

    # Read the environnment variables
    getDeploymentVariables "${AZURE_APP_PREFIX}"

    # Get current user objectId
    printProgress "Get current user objectId"
    UserType="User"
    UserSPMsiPrincipalId=$(az ad signed-in-user show --query id --output tsv 2>/dev/null) || true  
    if [[ -z $UserSPMsiPrincipalId ]]; then
        printProgress "Get current service principal objectId"
        UserType="ServicePrincipal"
        # shellcheck disable=SC2154        
        UserSPMsiPrincipalId=$(az ad sp show --id "$(az account show | jq -r .user.name)" --query id --output tsv  2> /dev/null) || true
    fi

    if [[ -n $UserSPMsiPrincipalId ]]; then
        printProgress "Checking role assignment 'Azure Event Hubs Data Sender' between '${UserSPMsiPrincipalId}' and name space '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_INPUT_1_NAME}'"
        UserSPMsiRoleAssignmentCount=$(az role assignment list --assignee "${UserSPMsiPrincipalId}" --scope /subscriptions/"${AZURE_SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP}"/providers/Microsoft.EventHub/namespaces/"${EVENTHUB_NAME_SPACE}"/eventhubs/"${EVENTHUB_INPUT_1_NAME}"   2>/dev/null | jq -r 'select(.[].roleDefinitionName=="Azure Event Hubs Data Sender") | length')

        if [ "$UserSPMsiRoleAssignmentCount" != "1" ];
        then
            printProgress  "Assigning 'Azure Event Hubs Data Sender' role assignment on scope '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_INPUT_1_NAME}'..."
            cmd="az role assignment create --assignee-object-id \"$UserSPMsiPrincipalId\" --assignee-principal-type $UserType --scope /subscriptions/\"${AZURE_SUBSCRIPTION_ID}\"/resourceGroups/\"${RESOURCE_GROUP}\"/providers/Microsoft.EventHub/namespaces/\"${EVENTHUB_NAME_SPACE}\"/eventhubs/\"${EVENTHUB_INPUT_1_NAME}\" --role \"Azure Event Hubs Data Sender\"  2>/dev/null"
            printProgress "$cmd"
            eval "$cmd"
        fi


        printProgress "Checking role assignment 'Azure Event Hubs Data Sender' between  '${UserSPMsiPrincipalId}' and name space '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_INPUT_2_NAME}'"
        UserSPMsiRoleAssignmentCount=$(az role assignment list --assignee "${UserSPMsiPrincipalId}" --scope /subscriptions/"${AZURE_SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP}"/providers/Microsoft.EventHub/namespaces/"${EVENTHUB_NAME_SPACE}"/eventhubs/"${EVENTHUB_INPUT_2_NAME}"   2>/dev/null | jq -r 'select(.[].roleDefinitionName=="Azure Event Hubs Data Sender") | length')

        if [ "$UserSPMsiRoleAssignmentCount" != "1" ];
        then
            printProgress  "Assigning 'Azure Event Hubs Data Sender' role assignment on scope '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_INPUT_2_NAME}'..."
            cmd="az role assignment create --assignee-object-id \"$UserSPMsiPrincipalId\" --assignee-principal-type $UserType --scope /subscriptions/\"${AZURE_SUBSCRIPTION_ID}\"/resourceGroups/\"${RESOURCE_GROUP}\"/providers/Microsoft.EventHub/namespaces/\"${EVENTHUB_NAME_SPACE}\"/eventhubs/\"${EVENTHUB_INPUT_2_NAME}\" --role \"Azure Event Hubs Data Sender\"  2>/dev/null"
            printProgress "$cmd"
            eval "$cmd"
        fi

        printProgress "Checking role assignment 'Azure Event Hubs Data Receiver' between  '${UserSPMsiPrincipalId}' and name space '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_OUTPUT_1_NAME}'"
        UserSPMsiRoleAssignmentCount=$(az role assignment list --assignee "${UserSPMsiPrincipalId}" --scope /subscriptions/"${AZURE_SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP}"/providers/Microsoft.EventHub/namespaces/"${EVENTHUB_NAME_SPACE}"/eventhubs/"${EVENTHUB_OUTPUT_1_NAME}"  2>/dev/null | jq -r 'select(.[].roleDefinitionName=="Azure Event Hubs Data Receiver") | length')

        if [ "$UserSPMsiRoleAssignmentCount" != "1" ];
        then
            printProgress  "Assigning 'Azure Event Hubs Data Sender' role assignment on scope '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_OUTPUT_1_NAME}'..."
            cmd="az role assignment create --assignee-object-id \"$UserSPMsiPrincipalId\" --assignee-principal-type $UserType --scope /subscriptions/\"${AZURE_SUBSCRIPTION_ID}\"/resourceGroups/\"${RESOURCE_GROUP}\"/providers/Microsoft.EventHub/namespaces/\"${EVENTHUB_NAME_SPACE}\"/eventhubs/\"${EVENTHUB_OUTPUT_1_NAME}\" --role \"Azure Event Hubs Data Receiver\"  2>/dev/null"
            printProgress "$cmd"
            eval "$cmd"
        fi
    fi
    if [ "$deploymentType" == 'eventhub-asa' ]; then
        printProgress "Checking role assignment between Stream Analytics Jobs and Event Hubs"
        # Role assignement between Stream Analytics Jobs and Event Hubs
        # Allow installation for stream analytics
        cmd="az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null"
        eval "$cmd"

        asaJobId=$(az stream-analytics job show --job-name ${STREAM_ANALYTICS_JOB_NAME} --resource-group ${RESOURCE_GROUP} -o json 2>/dev/null | jq -r .identity.principalId)
        if [[ -n $asaJobId ]]; then                
            printProgress "Checking role assignment 'Azure Event Hubs Data Receiver' between ASA '${STREAM_ANALYTICS_JOB_NAME}' and name space '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_INPUT_1_NAME}'"
            asaJobMsiRoleAssignmentCount=$(az role assignment list --assignee "${asaJobId}" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENTHUB_NAME_SPACE}/eventhubs/${EVENTHUB_INPUT_1_NAME}"  2>/dev/null | jq -r 'select(.[].roleDefinitionName=="Azure Event Hubs Data Receiver") | length')
            if [ "$asaJobMsiRoleAssignmentCount" != "1" ];
            then
                printProgress  "Assigning 'Azure Event Hubs Data Receiver' role assignment to  ASAJob '${STREAM_ANALYTICS_JOB_NAME}' on scope '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_INPUT_1_NAME}'..."
                cmd="az role assignment create --assignee-object-id \"$asaJobId\" --assignee-principal-type ServicePrincipal --scope \"/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENTHUB_NAME_SPACE}/eventhubs/${EVENTHUB_INPUT_1_NAME}\" --role \"Azure Event Hubs Data Receiver\"  2>/dev/null"
                printProgress "$cmd"
                eval "$cmd"
            fi
            
            printProgress "Checking role assignment 'Azure Event Hubs Data Receiver' between ASA '${STREAM_ANALYTICS_JOB_NAME}' and name space '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_INPUT_2_NAME}'"
            asaJobMsiRoleAssignmentCount=$(az role assignment list --assignee "${asaJobId}" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENTHUB_NAME_SPACE}/eventhubs/${EVENTHUB_INPUT_2_NAME}"  2>/dev/null | jq -r 'select(.[].roleDefinitionName=="Azure Event Hubs Data Receiver") | length')
            if [ "$asaJobMsiRoleAssignmentCount" != "1" ];
            then
                printProgress  "Assigning 'Azure Event Hubs Data Receiver' role assignment to  ASAJob '${STREAM_ANALYTICS_JOB_NAME}' on scope '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_INPUT_2_NAME}'..."
                cmd="az role assignment create --assignee-object-id \"$asaJobId\" --assignee-principal-type ServicePrincipal --scope \"/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENTHUB_NAME_SPACE}/eventhubs/${EVENTHUB_INPUT_2_NAME}\" --role \"Azure Event Hubs Data Receiver\"  2>/dev/null"
                printProgress "$cmd"
                eval "$cmd"
            fi

            printProgress "Checking role assignment 'Azure Event Hubs Data Sender' between ASA '${STREAM_ANALYTICS_JOB_NAME}' and name space '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_OUTPUT_1_NAME}'"
            asaJobMsiRoleAssignmentCount=$(az role assignment list --assignee "${asaJobId}" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENTHUB_NAME_SPACE}/eventhubs/${EVENTHUB_OUTPUT_1_NAME}"  2>/dev/null | jq -r 'select(.[].roleDefinitionName=="Azure Event Hubs Data Sender") | length')
            if [ "$asaJobMsiRoleAssignmentCount" != "1" ];
            then
                printProgress  "Assigning 'Azure Event Hubs Data Receiver' role assignment to  ASAJob '${STREAM_ANALYTICS_JOB_NAME}' on scope '${EVENTHUB_NAME_SPACE}' '${EVENTHUB_OUTPUT_1_NAME}'..."
                cmd="az role assignment create --assignee-object-id \"$asaJobId\" --assignee-principal-type ServicePrincipal --scope \"/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENTHUB_NAME_SPACE}/eventhubs/${EVENTHUB_OUTPUT_1_NAME}\" --role \"Azure Event Hubs Data Sender\"  2>/dev/null"
                printProgress "$cmd"
                eval "$cmd"
            fi
        else
            printError "Stream Analytics Job: '${STREAM_ANALYTICS_JOB_NAME}' not found"
            exit 1
        fi
    fi    
    printMessage "Deploying the Event Hub backend done"
    exit 0
fi


if [[ "${action}" == "deploybe" ]] ; then
    printMessage "Deploying the backend container hosting web api in the infrastructure..."

    # Check Azure connection
    printProgress "Check Azure connection for subscription: '$AZURE_SUBSCRIPTION_ID'"
    azLogin
    checkError

    # Read the environnment variables
    getDeploymentVariables "${AZURE_APP_PREFIX}"

    # get latest image version
    latest_dotnet_version=$(getLatestImageVersion "${ACR_NAME}" "dotnet-web-api")
    if [ -z "${latest_dotnet_version}" ]; then
        latest_dotnet_version=$APP_VERSION
    fi
    printProgress "Latest version to deploy: '$latest_dotnet_version'"

    # deploy dotnet-web-api
    printProgress "Deploy image dotnet-web-api:${latest_dotnet_version} from Azure Container Registry ${ACR_LOGIN_SERVER}"
    deployWebAppContainer "$AZURE_SUBSCRIPTION_ID" "$AZURE_APP_PREFIX" "functionapp" "$FUNCTION_NAME" "${ACR_LOGIN_SERVER}" "${ACR_NAME}"  "dotnet-web-api" "latest" "${latest_dotnet_version}" "${APP_PORT}"
    
    printProgress "Checking role assignment 'Storage Table Data Contributor' between '${FUNCTION_NAME}' and Storage '${STORAGE_ACCOUNT_NAME}' "  

    WebAppMsiPrincipalId=$(az functionapp show -n "${FUNCTION_NAME}" -g "${RESOURCE_GROUP}" -o json 2> /dev/null | jq -r .identity.principalId)
    WebAppMsiAcrPullAssignmentCount=$(az role assignment list --assignee "${WebAppMsiPrincipalId}" --scope /subscriptions/"${AZURE_SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP}"/providers/Microsoft.Storage/storageAccounts/"${STORAGE_ACCOUNT_NAME}" 2> /dev/null | jq -r 'select(.[].roleDefinitionName=="Storage Table Data Contributor") | length')

    if [ "$WebAppMsiAcrPullAssignmentCount" != "1" ];
    then
        printProgress  "Assigning 'Storage Table Data Contributor' role assignment on scope ${STORAGE_ACCOUNT_NAME}..."
        az role assignment create --assignee-object-id "$WebAppMsiPrincipalId" --assignee-principal-type ServicePrincipal --scope /subscriptions/"${AZURE_SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP}"/providers/Microsoft.Storage/storageAccounts/"${STORAGE_ACCOUNT_NAME}" --role "Storage Table Data Contributor" 2> /dev/null
    fi

    # Get current user objectId
    printProgress "Get current user objectId"
    UserType="User"
    WebAppMsiPrincipalId=$(az ad signed-in-user show --query id --output tsv 2>/dev/null ) || true  
    if [[ -z $WebAppMsiPrincipalId ]]; then
        printProgress "Get current service principal objectId"
        UserType="ServicePrincipal"
        WebAppMsiPrincipalId=$(az ad sp show --id "$(az account show | jq -r .user.name)" --query id --output tsv  2> /dev/null) || true
    fi

    if [[ -n $WebAppMsiPrincipalId ]]; then
        printProgress  "Check 'Storage Blob Data Contributor' role assignment on scope ${STORAGE_ACCOUNT_NAME}..."
        WebAppMsiAcrPullAssignmentCount=$(az role assignment list --assignee "${WebAppMsiPrincipalId}" --scope /subscriptions/"${AZURE_SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP}"/providers/Microsoft.Storage/storageAccounts/"${STORAGE_ACCOUNT_NAME}" 2> /dev/null | jq -r 'select(.[].roleDefinitionName=="Storage Blob Data Contributor") | length')
        if [ "$WebAppMsiAcrPullAssignmentCount" != "1" ];
        then
            printProgress  "Assigning 'Storage Blob Data Contributor' role assignment on scope ${STORAGE_ACCOUNT_NAME}..."
            az role assignment create --assignee-object-id "$WebAppMsiPrincipalId" --assignee-principal-type $UserType --scope /subscriptions/"${AZURE_SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP}"/providers/Microsoft.Storage/storageAccounts/"${STORAGE_ACCOUNT_NAME}" --role "Storage Blob Data Contributor" 2> /dev/null
        fi
    fi
    # Test services
    # Test dotnet-web-api
    dotnet_rest_api_url="${FUNCTION_SERVER}version"
    printProgress "Testing dotnet-web-api url: $dotnet_rest_api_url expected version: ${latest_dotnet_version}"
    result=$(checkWebUrl "${dotnet_rest_api_url}" "${latest_dotnet_version}" 420)
    if [[ $result != "true" ]]; then
        printError "Error while testing dotnet-web-api"
        exit 1
    else
        printMessage "Testing dotnet-web-api successful"
    fi

    printMessage "Deploying the backend container hosting web api in the infrastructure done"
    exit 0
fi

if [[ "${action}" == "deployfe" ]] ; then
    printMessage "Deploying the frontend container hosting web ui in the infrastructure..."

    # Check Azure connection
    printProgress "Check Azure connection for subscription: '$AZURE_SUBSCRIPTION_ID'"
    azLogin
    checkError

    # Read the environnment variables
    getDeploymentVariables "${AZURE_APP_PREFIX}"

    # get latest image version
    latest_webapp_version=$(getLatestImageVersion "${ACR_NAME}" "ts-web-app")
    if [ -z "${latest_webapp_version}" ]; then
        latest_webapp_version=$APP_VERSION
    fi

    # deploy ts-web-app
    if [ "$deploymentType" == 'web-storage-api-storage' ]; then

        printProgress "Enable Static Web Page on Azure Storage: ${STORAGE_ACCOUNT_NAME} "
        cmd="az storage blob service-properties update --account-name ${STORAGE_ACCOUNT_NAME} --static-website  --index-document index.html --only-show-errors"
        printProgress "$cmd"
        eval "$cmd"
        printProgress "Deploy  ts-web-app:${latest_webapp_version} to Azure Storage \$web"
        cmd="az storage azcopy blob upload -c \"\\\$web\" --account-name ${STORAGE_ACCOUNT_NAME} -s \"./src/ts-web-app/build/*\" --recursive --only-show-errors"
        printProgress "$cmd"
        eval "$cmd"
    else
        printProgress "Deploy image ts-web-app:${latest_webapp_version} from Azure Container Registry ${ACR_LOGIN_SERVER}"
        deployWebAppContainer "$AZURE_SUBSCRIPTION_ID" "$AZURE_APP_PREFIX" "webapp" "$WEB_APP_NAME" "${ACR_LOGIN_SERVER}" "${ACR_NAME}"  "ts-web-app" "latest" "${latest_webapp_version}" "${APP_PORT}"
    fi
    # Test web-app
    node_web_app_url="${WEB_APP_SERVER}config.json"
    printProgress "Testing node_web_app_url url: $node_web_app_url expected version: ${latest_webapp_version}"
    result=$(checkWebUrl "${node_web_app_url}" "${latest_webapp_version}" 420)
    if [[ $result != "true" ]]; then
        printError "Error while testing node_web_app_url"
        exit 1
    else
        printMessage "Testing node_web_app_url successful"
    fi

    printMessage "Deploying the frontend container hosting web ui in the infrastructure done"
    exit 0
fi

if [[ "${action}" == "createapp" ]] ; then
    printMessage "Create Azure AD Application..."
    # Check Azure connection
    printProgress "Check Azure connection for subscription: '$AZURE_SUBSCRIPTION_ID'"
    azLogin
    checkError

    # Read the environnment variables
    getDeploymentVariables "${AZURE_APP_PREFIX}"

    # if AZURE_APP_ID is not defined in variable group 
    # Create application
    if [[ -z ${AZURE_APP_ID} || ${AZURE_APP_ID} == 'null' || ${AZURE_APP_ID} == '' ]] ; then
        # Create or update application
        printProgress "As AZURE_APP_ID is not set, check if Application 'sp-${AZURE_APP_PREFIX}-app' exists"
        cmd="az ad app list --filter \"displayName eq 'sp-${AZURE_APP_PREFIX}-app'\" -o json --only-show-errors | jq -r .[0].appId"
        printProgress "$cmd"
        appId=$(eval "$cmd") || true    
        if [[ -z ${appId} || ${appId} == 'null' ]] ; then
            # Create application 
            printProgress "Create Application 'sp-${AZURE_APP_PREFIX}-app' "        
            cmd="az ad app create  --display-name \"sp-${AZURE_APP_PREFIX}-app\"  --required-resource-access \"[{\\\"resourceAppId\\\": \\\"00000003-0000-0000-c000-000000000000\\\",\\\"resourceAccess\\\": [{\\\"id\\\": \\\"e1fe6dd8-ba31-4d61-89e7-88639da4683d\\\",\\\"type\\\": \\\"Scope\\\"}]},{\\\"resourceAppId\\\": \\\"e406a681-f3d4-42a8-90b6-c2b029497af1\\\",\\\"resourceAccess\\\": [{\\\"id\\\": \\\"03e0da56-190b-40ad-a80c-ea378c433f7f\\\",\\\"type\\\": \\\"Scope\\\"}]}]\" --only-show-errors | jq -r \".appId\" "
            printProgress "$cmd"
            appId=$(eval "$cmd")
            # wait 30 seconds
            printProgress "Wait 30 seconds after app creation"
            # Wait few seconds before updating the Application record in Azure AD
            sleep 30
            # Get application objectId  
            cmd="az ad app list --filter \"displayName eq 'sp-${AZURE_APP_PREFIX}-app'\" -o json --only-show-errors | jq -r .[0].id"    
            printProgress "$cmd"
            objectId=$(eval "$cmd") || true    
            if [[ -n ${objectId} && ${objectId} != 'null' ]] ; then
                printProgress "Update Application 'sp-${AZURE_APP_PREFIX}-app' in Microsoft Graph "   
                # Azure CLI Application Id : 04b07795-8ddb-461a-bbee-02f9e1bf7b46 
                # Azure CLI will be authorized to get access token to the API using the commands below:
                #  token=$(az account get-access-token --resource api://<WebAPIAppId> | jq -r .accessToken)
                #  curl -i -X GET --header "Authorization: Bearer $token"  https://<<WebAPIDomain>/visit
                cmd="az rest --method PATCH --uri \"https://graph.microsoft.com/v1.0/applications/$objectId\" \
                    --headers \"Content-Type=application/json\" \
                    --body \"{\\\"api\\\":{\\\"oauth2PermissionScopes\\\":[{\\\"id\\\": \\\"1619f87e-396b-48f1-91cf-9dedd9c786c8\\\",\\\"adminConsentDescription\\\": \\\"Grants full access to Visit web services APIs\\\",\\\"adminConsentDisplayName\\\": \\\"Full access to Visit API\\\",\\\"userConsentDescription\\\": \\\"Grants full access to Visit web services APIs\\\",\\\"userConsentDisplayName\\\": null,\\\"isEnabled\\\": true,\\\"type\\\": \\\"User\\\",\\\"value\\\": \\\"user_impersonation\\\"}]},\\\"spa\\\":{\\\"redirectUris\\\":[\\\"${WEB_APP_SERVER}\\\"]},\\\"identifierUris\\\":[\\\"api://${appId}\\\"]}\""
                printProgress "$cmd"
                eval "$cmd"
                # Wait few seconds before updating the Application record in Azure AD 
                sleep 10
                cmd="az rest --method PATCH --uri \"https://graph.microsoft.com/v1.0/applications/$objectId\" \
                    --headers \"Content-Type=application/json\" \
                    --body \"{\\\"api\\\":{\\\"preAuthorizedApplications\\\": [{\\\"appId\\\": \\\"04b07795-8ddb-461a-bbee-02f9e1bf7b46\\\",\\\"delegatedPermissionIds\\\": [\\\"1619f87e-396b-48f1-91cf-9dedd9c786c8\\\"]}]}}\""
                printProgress "$cmd"
                eval "$cmd"            
            else
                printError "Error while creating application sp-${AZURE_APP_PREFIX}-app can't get objectId"
                exit 1
            fi
            cmd="az ad app list --filter \"displayName eq 'sp-${AZURE_APP_PREFIX}-app'\" -o json --only-show-errors | jq -r .[0].appId"
            printProgress "$cmd"
            appId=$(eval "$cmd") || true    
            if [[ -n ${appId} && ${appId} != 'null' ]] ; then
                printProgress "Create Service principal associated with application 'sp-${AZURE_APP_PREFIX}-app' "        
                cmd="az ad sp create-for-rbac --name 'sp-${AZURE_APP_PREFIX}-app'  --role contributor --scopes /subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP} --only-show-errors"        
                printProgress "$cmd"
                eval "$cmd" || true
            fi 
            printProgress  "Application 'sp-${AZURE_APP_PREFIX}-app' with application Id: ${appId} and object Id: ${objectId} has been created"
        else
            printProgress  "Application 'sp-${AZURE_APP_PREFIX}-app' with application Id: ${appId} already exists"
            printProgress  "Update application 'sp-${AZURE_APP_PREFIX}-app' with the new redirectUri ${WEB_APP_SERVER}"
            # Get application objectId  
            cmd="az ad app list --filter \"displayName eq 'sp-${AZURE_APP_PREFIX}-app'\" -o json --only-show-errors | jq -r .[0].id"    
            printProgress "$cmd"
            objectId=$(eval "$cmd") || true    
            if [[ -n ${objectId} && ${objectId} != 'null' ]] ; then
                printProgress "Update Application 'sp-${AZURE_APP_PREFIX}-app' in Microsoft Graph "   
                # Azure CLI Application Id : 04b07795-8ddb-461a-bbee-02f9e1bf7b46 
                # Azure CLI will be authorized to get access token to the API using the commands below:
                #  token=$(az account get-access-token --resource api://<WebAPIAppId> | jq -r .accessToken)
                #  curl -i -X GET --header "Authorization: Bearer $token"  https://<<WebAPIDomain>/visit
                cmd="az rest --method PATCH --uri \"https://graph.microsoft.com/v1.0/applications/$objectId\" \
                    --headers \"Content-Type=application/json\" \
                    --body \"{\\\"api\\\":{\\\"oauth2PermissionScopes\\\":[{\\\"id\\\": \\\"1619f87e-396b-48f1-91cf-9dedd9c786c8\\\",\\\"adminConsentDescription\\\": \\\"Grants full access to Visit web services APIs\\\",\\\"adminConsentDisplayName\\\": \\\"Full access to Visit API\\\",\\\"userConsentDescription\\\": \\\"Grants full access to Visit web services APIs\\\",\\\"userConsentDisplayName\\\": null,\\\"isEnabled\\\": true,\\\"type\\\": \\\"User\\\",\\\"value\\\": \\\"user_impersonation\\\"}]},\\\"spa\\\":{\\\"redirectUris\\\":[\\\"${WEB_APP_SERVER}\\\"]},\\\"identifierUris\\\":[\\\"api://${appId}\\\"]}\""
                printProgress "$cmd"
                eval "$cmd"
            fi
        fi
        printMessage "Azure AD Application creation done"
    else
        printProgress "As AZURE_APP_ID is set, it's not necessary to create the application 'sp-${AZURE_APP_PREFIX}-app'"
        printProgress "AZURE_APP_ID: ${AZURE_APP_ID}"
        appId=${AZURE_APP_ID}
    fi
    # set Azure DevOps variable AZURE_APP_ID if run from a pipeline
    updateConfigurationFile "${configuration_file}" "AZURE_APP_ID" "${appId}"

    # Get Application service principal appId  
    if [[ -n ${appId} && ${appId} != 'null' ]] ; then
        printProgress  "Check 'Storage Blob Data Contributor' role assignment on scope ${STORAGE_ACCOUNT_NAME} for Application sp-${AZURE_APP_PREFIX}-app..."
        cmd="az role assignment list --assignee \"${appId}\" --scope /subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME} --only-show-errors  | jq -r 'select(.[].roleDefinitionName==\"Storage Blob Data Contributor\") | length'"
        printProgress "$cmd"
        WebAppMsiAcrPullAssignmentCount=$(eval "$cmd") || true  
        if [ "$WebAppMsiAcrPullAssignmentCount" != "1" ];
        then
            printProgress  "Assigning 'Storage Blob Data Contributor' role assignment on scope ${STORAGE_ACCOUNT_NAME} for  appId..."
            cmd="az role assignment create --assignee \"${appId}\"  --scope /subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME} --role \"Storage Blob Data Contributor\" --only-show-errors"        
            printProgress "$cmd"
            eval "$cmd"
        fi
    fi
    exit 0
fi

if [[ "${action}" == "buildfe" ]] ; then
    printMessage "Building the Front End hosting the Web UI..."
    # Check Azure connection
    printProgress "Check Azure connection for subscription: '$AZURE_SUBSCRIPTION_ID'"
    azLogin
    checkError

    # Read the environnment variables
    getDeploymentVariables "${AZURE_APP_PREFIX}"
    # Create or update application
    printProgress "Check if Application 'sp-${AZURE_APP_PREFIX}-app' appId exists"
    if [[ -z ${AZURE_APP_ID} || ${AZURE_APP_ID} == 'null' || ${AZURE_APP_ID} == '' ]] ; then
        cmd="az ad app list --filter \"displayName eq 'sp-${AZURE_APP_PREFIX}-app'\" -o json 2> /dev/null | jq -r .[0].appId"
        printProgress "$cmd"
        appId=$(eval "$cmd") || true    
        if [[ -z ${appId} || ${appId} == 'null' ]] ; then
            printError "Application sp-${AZURE_APP_PREFIX}-app appId not available"
            exit 1
        else
            AZURE_APP_ID=${appId} 
        fi
    fi
    printProgress  "Building Application 'sp-${AZURE_APP_PREFIX}-app' with application Id: ${AZURE_APP_ID} "

    printMessage "Building ts-web-app container version:${APP_VERSION} port: ${APP_PORT}"

    # Update version in HTML package
    TEMPDIR=$(mktemp -d)
    printProgress  "Update file: ./src/ts-web-app/src/config/config.json application Id: ${AZURE_APP_ID} name: 'sp-${AZURE_APP_PREFIX}-app'"
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.version = \"${APP_VERSION}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.clientId = \"${AZURE_APP_ID}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"   

    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.tokenAPIRequest.scopes = [\"api://${AZURE_APP_ID}/user_impersonation\" ]' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"   

    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.authority = \"https://login.microsoftonline.com/${AZURE_TENANT_ID}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.tenantId = \"${AZURE_TENANT_ID}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.redirectUri = \"${WEB_APP_SERVER}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.storageAccountName = \"${STORAGE_ACCOUNT_NAME}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.storageInputContainerName = \"${STORAGE_ACCOUNT_INPUT_CONTAINER}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.storageOutputContainerName = \"${STORAGE_ACCOUNT_OUTPUT_CONTAINER}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.storageSASToken = \"\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.apiEndpoint = \"${FUNCTION_SERVER}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.appInsightsKey = \"${APP_INSIGHTS_INSTRUMENTATION_KEY}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd"    
    cmd="cat ./src/ts-web-app/src/config/config.json  | jq -r '.authorizationDisabled = ${authorizationDisabled,,}' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/ts-web-app/src/config/config.json"
    eval "$cmd" 
    echo "Content of config.json:"
    cat ./src/ts-web-app/src/config/config.json

    # build web app
    pushd ./src/ts-web-app

    printProgress "NPM version:"
    npm --version
    printProgress "NPM Install..."
    npm install -s    
    npm audit fix -s
    printProgress "Typescript build..."
    tsc --build tsconfig.json
    printProgress "Webpack..."
    webpack --config webpack.config.min.js
    popd    
    buildWebAppContainer "${ACR_LOGIN_SERVER}" "./src/ts-web-app" "ts-web-app" "${APP_VERSION}" "latest" ${APP_PORT}
    checkError    
    printMessage "Building the Front End containers done"
    exit 0
fi

if [[ "${action}" == "buildbe" ]] ; then
    printMessage "Building the backend hosting the Web API containers..."
    # Check Azure connection
    printProgress "Check Azure connection for subscription: '$AZURE_SUBSCRIPTION_ID'"
    azLogin
    checkError

    # Read the environnment variables
    getDeploymentVariables "${AZURE_APP_PREFIX}"
    # Create or update application
    printProgress "Check if Application 'sp-${AZURE_APP_PREFIX}-app' appId exists"
    if [[ -z ${AZURE_APP_ID} || ${AZURE_APP_ID} == 'null' || ${AZURE_APP_ID} == '' ]] ; then
        cmd="az ad app list --filter \"displayName eq 'sp-${AZURE_APP_PREFIX}-app'\" -o json 2>/dev/null | jq -r .[0].appId"
        printProgress "$cmd"
        appId=$(eval "$cmd") || true    
        if [[ -z ${appId} || ${appId} == 'null' ]] ; then
            printError "Application sp-${AZURE_APP_PREFIX}-app appId not available"
            exit 1
        else
            AZURE_APP_ID=${appId} 
        fi
    fi
    printProgress  "Building Application 'sp-${AZURE_APP_PREFIX}-app' with application Id: ${AZURE_APP_ID} "

    # Build dotnet-api docker image
    TEMPDIR=$(mktemp -d)
    printProgress  "Update file: ./src/dotnet-web-api/appsettings.json application Id: ${AZURE_APP_ID} name: 'sp-${AZURE_APP_PREFIX}-app'"
    cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.AzureAd.ClientId = \"${AZURE_APP_ID}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
    eval "$cmd"    
    cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.AzureAd.ClientId = \"${AZURE_APP_ID}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
    eval "$cmd"    
    cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.AzureAd.TenantId = \"${AZURE_TENANT_ID}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
    eval "$cmd"    
    cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.AzureAd.TenantId = \"${AZURE_TENANT_ID}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
    eval "$cmd"    


    printProgress "Check if connected as Service Principal"
    UserSPMsiPrincipalId=$(az ad signed-in-user show --query id --output tsv 2>/dev/null) || true  
    if [[ -z $UserSPMsiPrincipalId ]]; then
        printProgress "Connected as Service Principal"
        # shellcheck disable=SC2154        
        SPMsiPrincipalId=$(az ad sp show --id "$(az account show | jq -r .user.name)" --query appId --output tsv  2> /dev/null)
    fi
    if [[ -n $SPMsiPrincipalId ]]; then
        cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.AzureAd.AllowWebApiToBeAuthorizedByACL = true ' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
        eval "$cmd"    
        cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.AzureAd.AllowWebApiToBeAuthorizedByACL = true ' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
        eval "$cmd"

        cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.AzureAd.AccessControlList = [ \"${SPMsiPrincipalId}\" ]' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
        eval "$cmd"    
        cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.AzureAd.AccessControlList = [ \"${SPMsiPrincipalId}\" ]' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
        eval "$cmd"
    else
        cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.AzureAd.AllowWebApiToBeAuthorizedByACL = false ' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
        eval "$cmd"    
        cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.AzureAd.AllowWebApiToBeAuthorizedByACL = false ' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
        eval "$cmd"

        cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.AzureAd.AccessControlList = [  ]' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
        eval "$cmd"    
        cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.AzureAd.AccessControlList = [  ]' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
        eval "$cmd"
    fi    

    cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.ApplicationInsights.ConnectionString = \"${APP_INSIGHTS_CONNECTION_STRING}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
    eval "$cmd"    
    cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.ApplicationInsights.ConnectionString = \"${APP_INSIGHTS_CONNECTION_STRING}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
    eval "$cmd"    
    cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.Services.StorageVisit.Endpoint = \"https://${STORAGE_ACCOUNT_NAME}.table.core.windows.net\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
    eval "$cmd"    
    cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.Services.StorageVisit.Endpoint = \"https://${STORAGE_ACCOUNT_NAME}.table.core.windows.net\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
    eval "$cmd"    
    if [ "$deploymentType" ==  'web-app-api-cosmosdb' ] ; then
        cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.Services.CosmosDBSubcriptionId = \"${AZURE_SUBSCRIPTION_ID}\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.json"
        eval "$cmd"    
        cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.Services.CosmosDBSubcriptionId = \"${AZURE_SUBSCRIPTION_ID}\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.Development.json"
        eval "$cmd"    

        cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.Services.CosmosDBResourceGroupName = \"${RESOURCE_GROUP}\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.json"
        eval "$cmd"    
        cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.Services.CosmosDBResourceGroupName = \"${RESOURCE_GROUP}\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.Development.json"
        eval "$cmd"    

        cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.Services.CosmosDBAccount = \"${COSMOS_DB_SERVICE_NAME}\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.json"
        eval "$cmd"    
        cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.Services.CosmosDBAccount = \"${COSMOS_DB_SERVICE_NAME}\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.Development.json"
        eval "$cmd"    

        cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.Services.CosmosDBDatabaseName = \"${COSMOS_DB_NAME}\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.json"
        eval "$cmd"    
        cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.Services.CosmosDBDatabaseName = \"${COSMOS_DB_NAME}\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.Development.json"
        eval "$cmd"    

        cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.Services.CosmosDBVisit.Endpoint = \"https://${COSMOS_DB_SERVICE_NAME}.documents.azure.com:443/\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.json"
        eval "$cmd"    
        cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.Services.CosmosDBVisit.Endpoint = \"https://${COSMOS_DB_SERVICE_NAME}.documents.azure.com:443/\"' > tmp.$$.json && mv tmp.$$.json ./src/dotnet-web-api/appsettings.Development.json"
        eval "$cmd"    
    fi
    cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.Services.StorageAccount = \"${STORAGE_ACCOUNT_NAME}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
    eval "$cmd"    
    cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.Services.StorageAccount = \"${STORAGE_ACCOUNT_NAME}\"' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
    eval "$cmd"    

    cmd="cat ./src/dotnet-web-api/appsettings.json  | jq -r '.Services.AuthorizationDisabled = ${authorizationDisabled,,}' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.json"
    eval "$cmd"    
    cmd="cat ./src/dotnet-web-api/appsettings.Development.json  | jq -r '.Services.AuthorizationDisabled = ${authorizationDisabled,,}' > "${TEMPDIR}tmp.$$.json" && mv "${TEMPDIR}tmp.$$.json" ./src/dotnet-web-api/appsettings.Development.json"
    eval "$cmd"    
 

    echo "Content of appsettings.json:"
    cat ./src/dotnet-web-api/appsettings.json

    if [ "$deploymentType" ==  'web-app-api-cosmosdb' ] ; then
        if [[ -n $AZURE_SUBSCRIPTION_ID && -n  $RESOURCE_GROUP && -n $COSMOS_DB_SERVICE_NAME ]]; then
            echo "Check for role 'DocumentDB Account Contributor' with ${FUNCTION_NAME} and CosmosDB ${COSMOS_DB_SERVICE_NAME} "
            WebAppMsiPrincipalId=$(az functionapp show -n "${FUNCTION_NAME}" -g "${RESOURCE_GROUP}" -o json  2>/dev/null | jq -r .identity.principalId)
            WebAppMsiAcrPullAssignmentCount=$(az role assignment list --assignee "${WebAppMsiPrincipalId}" --scope /subscriptions/"${AZURE_SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP}"/providers/Microsoft.DocumentDB/databaseAccounts/"${COSMOS_DB_SERVICE_NAME}" 2>/dev/null | jq -r 'select(.[].roleDefinitionName=="DocumentDB Account Contributor") | length')

            if [ "$WebAppMsiAcrPullAssignmentCount" != "1" ];
            then
                echo "Assign role 'DocumentDB Account Contributor' with ${FUNCTION_NAME} and CosmosDB ${COSMOS_DB_SERVICE_NAME} "
                printProgress  "Assigning 'Storage Table Data Contributor' role assignment on scope ${STORAGE_ACCOUNT_NAME}..."
                cmd="az role assignment create --assignee-object-id \"$WebAppMsiPrincipalId\" --assignee-principal-type ServicePrincipal --scope \"/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DocumentDB/databaseAccounts/${COSMOS_DB_SERVICE_NAME}\" --role \"DocumentDB Account Contributor\" 2>/dev/null "
                printProgress "$cmd"
                eval "$cmd"
            fi
        fi
    fi

    # Build dotnet-api docker image
    printMessage "Building dotnet-rest-api container version:${APP_VERSION} port: ${APP_PORT}"
    buildWebAppContainer "${ACR_LOGIN_SERVER}" "./src/dotnet-web-api" "dotnet-web-api" "${APP_VERSION}" "latest" ${APP_PORT}

    printMessage "Building the backend hosting the Web API containers done"
    exit 0
fi