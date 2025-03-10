#!/usr/bin/env bash

################## CMD ALIAS ##################
KUBECTL=$(command -v oc || command -v kubectl)
if ! [ -x "${KUBECTL}" ]; then
    echo "ERROR: Command 'oc' and 'kubectl' are not found, please install either of them to proceed." >&2
    exit 1
fi
#The yq command-line tool is needed for extracting, updating, and processing YAML configuration 
#files to dynamically modify configurations and apply them correctly to the Kubernetes cluster.
YQ=$(command -v yq)
if ! [ -x "${YQ}" ]; then
    echo "ERROR: YAML processor 'yq' is not installed. Please install 'yq' to proceed." >&2
    exit 1
fi

################## CONSTANT ##################
CATALOG_SOURCE="certified-operators"
CATALOG_SOURCE_NS="openshift-marketplace"

DEFAULT_RELEASE="stable"
DEFAULT_NS="prometurbo-operator"
DEFAULT_PROMETURBO_NAME="prometurbo-release"
DEFAULT_TARGET_NAME="Prometheus_DCGM"
DEFAULT_CR_PROMETHEUS_SERVER_CONFIG="metrics_v1alpha1_prometheusserverconfig_with_token.yaml"
DEFAULT_CR_PROMETHEUS_QUERY_MAPPING="metrics_v1alpha1_nvidia-dcgm-exporter.yaml"
DEFAULT_CRD_PROMETHEUS_QUERY_MAPPING="metrics.turbonomic.io_prometheusquerymappings.yaml"
DEFAULT_CRD_PROMETHEUS_SERVER_CONFIG="metrics.turbonomic.io_prometheusserverconfigs.yaml"
DEFAULT_THANOS_SECRET="secret_thanos_authorization_token.yaml"
DEFAULT_PROMETHEUS_QUERY_MAPPING_NAME="prometheusquerymappings.metrics.turbonomic.io"
DEFAULT_PROMETHEUS_SERVER_CONFIG_NAME="prometheusserverconfigs.metrics.turbonomic.io"

RETRY_INTERVAL=10 # in seconds
MAX_RETRY=10

################## DYNAMIC VARS ##################
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_PROMETURBO_OP_NAME="<EMPTY>"
CERT_PROMETURBO_OP_RELEASE="<EMPTY>"
CERT_PROMETURBO_OP_VERSION="<EMPTY>"

################## ARGS ##################
ACTION=${ACTION:-"create"}
OPERATOR_NS=${OPERATOR_NS:-${DEFAULT_NS}}
TARGET_NAME=${TARGET_NAME:-${DEFAULT_TARGET_NAME}}
TARGET_RELEASE=${TARGET_RELEASE:-${DEFAULT_RELEASE}}
PROMETURBO_NAME=${PROMETURBO_NAME:-${DEFAULT_PROMETURBO_NAME}}
CR_PROMETHEUS_SERVER_CONFIG=${DEFAULT_CR_PROMETHEUS_SERVER_CONFIG}
CR_PROMETHEUS_QUERY_MAPPING=${DEFAULT_CR_PROMETHEUS_QUERY_MAPPING}

################## FUNCTIONS ##################
# Function to validate and parse command-line arguments
function validate_args() {
    while [ $# -gt 0 ]; do
        case $1 in
            # required args
            --host) shift; TARGET_HOST="$1"; [ -n "${TARGET_HOST}" ] && shift;;
            --username) shift; TARGET_USERNAME="$1"; [ -n "${TARGET_USERNAME}" ] && shift;;
            --password) shift; TARGET_PASSWORD="$1"; [ -n "${TARGET_PASSWORD}" ] && shift;;
            # optional args
            --namespace) shift; OPERATOR_NS="$1"; [ -n "${OPERATOR_NS}" ] && shift;;
            --targetName) shift; TARGET_NAME="$1"; [ -n "${TARGET_NAME}" ] && shift;;
            --CR_PROMETHEUS_SERVER_CONFIG) shift; CR_PROMETHEUS_SERVER_CONFIG="$1"; [ -n "${CR_PROMETHEUS_SERVER_CONFIG}" ] && shift;;
            --CR_PROMETHEUS_QUERY_MAPPING) shift; CR_PROMETHEUS_QUERY_MAPPING="$1"; [ -n "${CR_PROMETHEUS_QUERY_MAPPING}" ] && shift;;
            -*|--*) echo "ERROR: Unknown option $1" >&2; usage; exit 1;;
            *) shift;;
        esac
    done
    # Check if required arguments are set, if not, print an error message, show usage, and exit with an error
    if [ -z "${TARGET_HOST}" ] || [ -z "${TARGET_USERNAME}" ] || [ -z "${TARGET_PASSWORD}" ]; then
        echo "ERROR: Missing required fields or values" >&2
        usage
        exit 1
    fi
    # Set the paths for Prometheus server configuration, Prometheus query mapping, and Thanos secret
    CR_PROMETHEUS_SERVER_CONFIG="$ROOT_DIR/../config/samples/${CR_PROMETHEUS_SERVER_CONFIG}"
    CR_PROMETHEUS_QUERY_MAPPING="$ROOT_DIR/../config/samples/${CR_PROMETHEUS_QUERY_MAPPING}"
    CRD_PROMETHEUS_QUERY_MAPPING="$ROOT_DIR/../config/crd/bases/${DEFAULT_CRD_PROMETHEUS_QUERY_MAPPING}"
    CRD_PROMETHEUS_SERVER_CONFIG="$ROOT_DIR/../config/crd/bases/${DEFAULT_CRD_PROMETHEUS_SERVER_CONFIG}"
    SECRET_PATH="$ROOT_DIR/../config/samples/${DEFAULT_THANOS_SECRET}"
    # Print out the values related to the install/delete action for the operator
    echo "TARGET_HOST=${TARGET_HOST}"
    echo "OPERATOR_NS=${OPERATOR_NS}"
    echo "TARGET_NAME=${TARGET_NAME}"
    echo "CR_PROMETHEUS_SERVER_CONFIG=$(basename ${CR_PROMETHEUS_SERVER_CONFIG})"
    echo "CR_PROMETHEUS_QUERY_MAPPING=$(basename ${CR_PROMETHEUS_QUERY_MAPPING})"
    echo "CRD_PROMETHEUS_QUERY_MAPPING=$(basename ${CRD_PROMETHEUS_QUERY_MAPPING})"
    echo "CRD_PROMETHEUS_SERVER_CONFIG=$(basename ${CRD_PROMETHEUS_SERVER_CONFIG})"
}
# Function to display the usage information for the script
function usage() {
    echo "This program helps to install Prometurbo to the cluster via the OperatorHub"
    echo "Syntax: ./$0 --host <IP> --username <TARGET_USERNAME> --password <TARGET_PASSWORD> [options]"
    echo
    echo "Required arguments:"
    echo "--host         <VAL>    host IP of the Turbonomic instance (required)"
    echo "--username     <VAL>    host username of the Turbonomic instance (required)"
    echo "--password     <VAL>    host password of the Turbonomic instance (required)"
    echo
    echo "Optional arguments:"
    echo "--namespace    <VAL>    namespace to deploy the operator (optional)"
    echo "--targetName   <VAL>    target name of the operator (optional)"
    echo "--CR_PROMETHEUS_SERVER_CONFIG     <VAL>    prometheusserverconfig cr to be applied (optional)"
    echo "--CR_PROMETHEUS_QUERY_MAPPING     <VAL>    prometheusquerymappings cr to be applied (optional)"
    echo
}
# Main function to orchestrate the deployment or deletion of Prometurbo in the specified namespace
function main() {
    echo "${ACTION} ${OPERATOR_NS} namespace to ${ACTION} Certified Prometurbo operator"
    if ${KUBECTL} create ns ${OPERATOR_NS} 2>/dev/null; then
        echo "Namespace ${OPERATOR_NS} created successfully."
    else
        if ${KUBECTL} get ns ${OPERATOR_NS} &>/dev/null; then
            echo "Namespace ${OPERATOR_NS} already exists. Proceeding with the existing namespace."
        else
            echo "Failed to create or access namespace ${OPERATOR_NS}. Please check the namespace status."
            exit 1
        fi
    fi
    # Select the Certified Prometurbo operator from the OperatorHub
    select_cert_prometurbo_op_from_operatorhub
    # Select the channel for the Certified Prometurbo operator from the OperatorHub
    select_cert_prometurbo_op_channel_from_operatorhub

    if [ "${ACTION}" == "delete" ]; then
        apply_prometurbo
        apply_prometurbo_op_subscription
        apply_crds
        create_thanos_secret
    else
        apply_prometurbo_op_subscription
        apply_prometurbo
        apply_crds
        apply_cr
        create_thanos_secret
    fi

    echo "Successfully ${ACTION} Prometurbo in ${OPERATOR_NS} namespace!"
    echo -e "\nPrometurbo Resources:"
    ${KUBECTL} -n ${OPERATOR_NS} get OperatorGroup,Subscription,pod,deploy
    echo -e "\nPrometurbo CRDs:"
    ${KUBECTL} get crd ${DEFAULT_PROMETHEUS_QUERY_MAPPING_NAME}
    ${KUBECTL} get crd ${DEFAULT_PROMETHEUS_SERVER_CONFIG_NAME}
    echo -e "\nPrometurbo CRs:"
    ${KUBECTL} -n ${OPERATOR_NS} get PrometheusQueryMapping,PrometheusServerConfig
    echo -e "\nPrometurbo Thanos Secret:"
    ${KUBECTL} -n ${OPERATOR_NS} get secrets | grep ocp-thanos-authorization
}
# Function to select the certified Prometurbo operator from the OperatorHub
function select_cert_prometurbo_op_from_operatorhub() {
    echo "Fetching Openshift certified Prometurbo operator from OperatorHub ..."
    local cert_prometurbo_ops
    # Fetch the package manifests from the OperatorHub, filter for Prometurbo operators
    # matching the specified catalog source and namespace, and extract the names
    cert_prometurbo_ops=$(${KUBECTL} get packagemanifests -o jsonpath="{range .items[*]}{.metadata.name} {.status.catalogSource} {.status.catalogSourceNamespace}{'\n'}{end}" \
                         | grep -e "prometurbo" | grep -e "${CATALOG_SOURCE}.*${CATALOG_SOURCE_NS}" | awk '{print $1}')
    local cert_prometurbo_ops_count
    cert_prometurbo_ops_count=$(echo "${cert_prometurbo_ops}" | wc -l | awk '{print $1}')

    if [ -z "${cert_prometurbo_ops}" ] || [ ${cert_prometurbo_ops_count} -lt 1 ]; then
        echo "There aren't any certified Prometurbo operators in the OperatorHub, please contact administrator for more information!" && exit 1
    # Check if multiple certified Prometurbo operators were found
    elif [ ${cert_prometurbo_ops_count} -gt 1 ]; then
    # Prompt the user to select one of the multiple certified Prometurbo operators found
        PS3="Fetched multiple certified Prometurbo operators in the OperatorHub, please select a number to proceed OR type 'exit' to exit: "
        select opt in ${cert_prometurbo_ops[@]}; do
            validate_select_input ${cert_prometurbo_ops_count} ${REPLY}
            if [ $? -eq 0 ]; then
                cert_prometurbo_ops=${opt}
                break
            fi
        done
    fi
    CERT_PROMETURBO_OP_NAME=${cert_prometurbo_ops}
}
# Function to select the certified Prometurbo operator release channel from the OperatorHub
function select_cert_prometurbo_op_channel_from_operatorhub() {
    echo "Fetching Openshift certified Prometurbo operator channels from OperatorHub ..."
    local cert_prometurbo_op_name=${1-${CERT_PROMETURBO_OP_NAME}}
    local channels
    # Fetch the channels of the certified Prometurbo operator and filter by the target release
    channels=$(${KUBECTL} get packagemanifests ${cert_prometurbo_op_name} -o jsonpath="{range .status.channels[*]}{.name}:{.currentCSV}{'\n'}{end}" | grep "${TARGET_RELEASE}")
    local channel_count
    channel_count=$(echo "${channels}" | wc -l | awk '{print $1}')
    # Check if no channels were found
    if [ -z "${channels}" ] || [ ${channel_count} -lt 1 ]; then
        echo "There aren't any channels created for ${cert_prometurbo_op_name}, please contact administrator for more information!" && exit 1
    # Check if multiple channels were found
    elif [ ${channel_count} -gt 1 ]; then
    # Prompt the user to select one of the multiple channels found
        PS3="Fetched multiple release channels, please select a number to proceed OR type 'exit' to exit: "
        select opt in ${channels[@]}; do
            validate_select_input ${channel_count} ${REPLY}
            if [ $? -eq 0 ]; then
                channels=${opt}
                break
            fi
        done
    fi
    # Extract the release channel name and version from the selected channel
    CERT_PROMETURBO_OP_RELEASE=$(echo ${channels} | awk -F':' '{print $1}')
    CERT_PROMETURBO_OP_VERSION=$(echo ${channels} | awk -F':' '{print $2}')
    echo "Using Openshift certified Prometurbo channel: ${CERT_PROMETURBO_OP_RELEASE}, version: ${CERT_PROMETURBO_OP_VERSION}"
}
# This function ensures that there is only one OperatorGroup in the specified namespace.
function apply_operator_group() {
    op_gp_count=$(${KUBECTL} -n ${OPERATOR_NS} get OperatorGroup -o name | wc -l)
    if [ ${op_gp_count} -eq 1 ]; then 
        return
    elif [ ${op_gp_count} -gt 1 ]; then 
        echo "ERROR: Found multiple Operator Groups in the namespace ${OPERATOR_NS}" >&2 && exit 1
    fi
    echo "${ACTION} Certified Prometurbo operator group ..."
    cat <<-EOF | ${KUBECTL} ${ACTION} -f -
	---
	apiVersion: operators.coreos.com/v1
	kind: OperatorGroup
	metadata:
	  name: ${CERT_PROMETURBO_OP_NAME}-operatorgroup
	  namespace: ${OPERATOR_NS}
	spec:
	  targetNamespaces:
	  - ${OPERATOR_NS}
	---
	EOF
}
# Function to apply or delete the Prometurbo operator subscription in the specified namespace
function apply_prometurbo_op_subscription() {
    echo "${ACTION} Certified Prometurbo operator subscription ..."
    if [ "${ACTION}" == "delete" ]; then
        ${KUBECTL} -n ${OPERATOR_NS} delete Subscription ${CERT_PROMETURBO_OP_NAME}-subscription
        ${KUBECTL} -n ${OPERATOR_NS} delete csv ${CERT_PROMETURBO_OP_VERSION}
        ${KUBECTL} -n ${OPERATOR_NS} delete OperatorGroup ${CERT_PROMETURBO_OP_NAME}-operatorgroup
        return
    fi
    # Apply the OperatorGroup
    apply_operator_group
    # Apply the Prometurbo operator subscription
    cat <<-EOF | ${KUBECTL} ${ACTION} -f -
	---
	apiVersion: operators.coreos.com/v1alpha1
	kind: Subscription
	metadata:
	  name: ${CERT_PROMETURBO_OP_NAME}-subscription
	  namespace: ${OPERATOR_NS}
	spec:
	  channel: ${CERT_PROMETURBO_OP_RELEASE}
	  installPlanApproval: Automatic
	  name: ${CERT_PROMETURBO_OP_NAME}
	  source: ${CATALOG_SOURCE}
	  sourceNamespace: ${CATALOG_SOURCE_NS}
	  startingCSV: ${CERT_PROMETURBO_OP_VERSION}
	---
	EOF
    wait_for_deployment ${OPERATOR_NS} "deploy" "prometurbo-operator"
}
# Function to apply or delete the Prometurbo Custom Resource and related secret in the specified namespace
function apply_prometurbo() {
    echo "${ACTION} Prometurbo CR ..."
    cat <<-EOF | ${KUBECTL} ${ACTION} -f -
	---
	kind: Prometurbo
	apiVersion: charts.helm.k8s.io/v1
	metadata:
	  name: ${PROMETURBO_NAME}
	  namespace: ${OPERATOR_NS}
	spec:
	  restAPIConfig:
	    opsManagerUserName: ${TARGET_USERNAME}
	    opsManagerPassword: ${TARGET_PASSWORD}
	  serverMeta:
	    turboServer: ${TARGET_HOST}
	  targetName: ${TARGET_NAME}
	---
	apiVersion: v1
	kind: Secret
	metadata:
	  name: turbonomic-credentials
	  namespace: ${OPERATOR_NS}
	type: Opaque
	data:
	  username: $(encode_inline ${TARGET_USERNAME})
	  password: $(encode_inline ${TARGET_PASSWORD})
	---
	EOF
    wait_for_deployment ${OPERATOR_NS} "deploy" ${PROMETURBO_NAME}
}
# Function to apply or delete the Custom Resource Definitions (CRDs) for Prometurbo
function apply_crds() {
    echo "${ACTION} Prometurbo CRDs for prometheusquerymappings and prometheusserverconfigs"
    if [ "${ACTION}" == "delete" ]; then
        ${KUBECTL} delete crd ${DEFAULT_PROMETHEUS_QUERY_MAPPING_NAME}
        ${KUBECTL} delete crd ${DEFAULT_PROMETHEUS_SERVER_CONFIG_NAME}
        if [ $? -ne 0 ]; then
            echo "Failed to delete Prometurbo CRDs. Please check the resources and try again."
        else
            echo "Successfully deleted Prometurbo CRDs for prometheusquerymappings and prometheusserverconfigs"
        fi
        return
    fi

    local crd_paths=(
        "${CRD_PROMETHEUS_QUERY_MAPPING}"
        "${CRD_PROMETHEUS_SERVER_CONFIG}"
    )

    for crd_path in "${crd_paths[@]}"; do
        if [ -f "${crd_path}" ]; then
            ${KUBECTL} apply -f ${crd_path}
            if [ $? -ne 0 ]; then
                echo "Failed to apply Prometheus CRD from $(basename ${crd_path}). Please check the file and try again." && exit 1
            else
                echo "Successfully applied Prometheus CRD from $(basename ${crd_path})"
            fi
        else
            echo "Prometheus CRD file $(basename ${crd_path}) not found. Please ensure the path is correct." && exit 1
        fi
    done

    echo "CRDs ${DEFAULT_PROMETHEUS_QUERY_MAPPING_NAME}, ${DEFAULT_PROMETHEUS_SERVER_CONFIG_NAME} have been applied successfully."
    # Wait for the resources of the PrometheusQueryMapping and PrometheusServerConfig CRD to complete
    wait_for_deployment ${OPERATOR_NS} "crd" "${DEFAULT_PROMETHEUS_QUERY_MAPPING_NAME}"
    wait_for_deployment ${OPERATOR_NS} "crd" "${DEFAULT_PROMETHEUS_SERVER_CONFIG_NAME}"
}

# Function to apply Prometheus Custom Resources: PrometheusQueryMapping and PrometheusServerConfig
# The steps involved in this function are as follows:
# 1. Retrieve the PrometheusServerConfig file from the default file path or user input.
# 2. Fetch the cluster ID from the Kubernetes service and update the PrometheusServerConfig with the cluster ID using the 'yq' command-line tool.
# 3. Backup the original PrometheusServerConfig file to ensure changes can be reverted if necessary.
# 4. Check if Thanos is configured for the PrometheusServerConfig by verifying the presence of a bearer token with the key "authorizationToken". If configured, fetch the Thanos Querier address and update PrometheusServerConfig.
# 5. Apply the updated PrometheusServerConfig. If the application fails, revert the changes using the backup file and exit with an error.
# 6. Retrieve the PrometheusQueryMapping file from the default file path or user input.
# 7. Apply the PrometheusQueryMapping.
# 8. Use the 'wait_for_deployment' function to ensure the deployment of the applied resources is complete and successful.
function apply_cr() {
    echo "Applying Prometheus CRs"

    if [ -f "${CR_PROMETHEUS_SERVER_CONFIG}" ]; then
        echo "Fetching cluster ID to update prometheusserverconfigs"
        CLUSTER_ID=$(${KUBECTL} -n default get svc kubernetes -ojsonpath='{.metadata.uid}')

        if [ -z "${CLUSTER_ID}" ]; then
            echo "Failed to fetch cluster ID. Please ensure the cluster is running and try again." && exit 1
        fi

        cp ${CR_PROMETHEUS_SERVER_CONFIG} ${CR_PROMETHEUS_SERVER_CONFIG}.bak

        echo "Updating prometheusserverconfigs with cluster ID: ${CLUSTER_ID}"
        ${YQ} e ".spec.clusters[0].identifier.id = \"${CLUSTER_ID}\"" ${CR_PROMETHEUS_SERVER_CONFIG} -i

        if is_thanos_configured_for_psc ${CR_PROMETHEUS_SERVER_CONFIG}; then
            echo "Fetching Thanos Querier address to update prometheusserverconfigs"
            THANOS_ADDRESS=$(${KUBECTL} -n openshift-monitoring get route thanos-querier -o jsonpath='{.spec.host}')

            if [ -z "${THANOS_ADDRESS}" ]; then
                echo "Failed to fetch Thanos Querier address. Please ensure the Thanos Querier route is correct and try again." && exit 1
            fi

            echo "Updating Thanos address in prometheusserverconfigs"
            ${YQ} e ".spec.address = \"https://${THANOS_ADDRESS}\"" ${CR_PROMETHEUS_SERVER_CONFIG} -i
        else
            echo "Thanos authorization is not configured for $(basename ${CR_PROMETHEUS_SERVER_CONFIG}). Skipping Thanos server address update in prometheusserverconfigs."
        fi

        echo "Applying Prometheus CR from $(basename ${CR_PROMETHEUS_SERVER_CONFIG})"
        ${KUBECTL} apply -n ${OPERATOR_NS} -f ${CR_PROMETHEUS_SERVER_CONFIG}

        if [ $? -ne 0 ]; then
            echo "Failed to apply Prometheus CR from $(basename ${CR_PROMETHEUS_SERVER_CONFIG}). Please check the file and try again." && exit 1
        else
            echo "Successfully applied Prometheus CR from $(basename ${CR_PROMETHEUS_SERVER_CONFIG})"
        fi

        mv ${CR_PROMETHEUS_SERVER_CONFIG}.bak ${CR_PROMETHEUS_SERVER_CONFIG}
    else
        echo "Prometheus CR file $(basename ${CR_PROMETHEUS_SERVER_CONFIG}) not found. Please ensure the path is correct." && exit 1
    fi

    wait_for_deployment ${OPERATOR_NS} "cr" "${DEFAULT_PROMETHEUS_SERVER_CONFIG_NAME}"

    if [ -f "${CR_PROMETHEUS_QUERY_MAPPING}" ]; then
        echo "Applying Prometheus CR from $(basename ${CR_PROMETHEUS_QUERY_MAPPING})"
        ${KUBECTL} apply -n ${OPERATOR_NS} -f ${CR_PROMETHEUS_QUERY_MAPPING}

        if [ $? -ne 0 ]; then
            echo "Failed to apply Prometheus CR from $(basename ${CR_PROMETHEUS_QUERY_MAPPING}). Please check the file and try again." && exit 1
        else
            echo "Successfully applied Prometheus CR from $(basename ${CR_PROMETHEUS_QUERY_MAPPING})"
        fi
    else
        echo "Prometheus CR file $(basename ${CR_PROMETHEUS_QUERY_MAPPING}) not found. Please ensure the path is correct." && exit 1
    fi

    wait_for_deployment ${OPERATOR_NS} "cr" "${DEFAULT_PROMETHEUS_QUERY_MAPPING_NAME}"
}
# Function to create or delete the Thanos authorization token secret
# The steps involved in this function are as follows:
# 1. If the action is 'delete', check if Thanos is configured for the PrometheusServerConfig by verifying the presence of a bearer token with the key "authorizationToken".
#    - If Thanos is configured, fetch the secret name from the SECRET_PATH file using 'yq'.
#    - Delete the secret
# 2. If the action is not 'delete', check if Thanos is configured for the PrometheusServerConfig.
#    - If Thanos is configured, fetch the 'prometheus-k8s-token' secret from the 'openshift-monitoring' namespace.
#    - Extract the token from the secret and re-encode it in base64.
#    - Update the file with the base64-encoded token using 'yq'.
#    - Apply the updated secret.
function create_thanos_secret() {
    if [[ "${ACTION}" == "delete" ]]; then
     # Check if Thanos is configured for the PrometheusServerConfig
        if is_thanos_configured_for_psc ${CR_PROMETHEUS_SERVER_CONFIG}; then
            SECRET_NAME=$(${YQ} e '.metadata.name' ${SECRET_PATH})
            if [ -z "${SECRET_NAME}" ]; then
                echo "Failed to find the secret name in the file $(basename ${SECRET_PATH}). Please check the file and try again."
                return
            fi
            
            echo "Deleting Secret ${SECRET_NAME}"
            ${KUBECTL} -n ${OPERATOR_NS} delete secret ${SECRET_NAME}
            if [ $? -ne 0 ]; then
                echo "Failed to delete Secret ${SECRET_NAME}. Please check the resources and try again."
            else
                echo "Successfully deleted Secret ${SECRET_NAME}"
            fi
        else
            echo "Thanos authorizationToken is not configured for prometheusserverconfig. Skip Thanos secret deletion."
        fi
        return
    fi
    # Check if Thanos is configured for the PrometheusServerConfig
    if is_thanos_configured_for_psc ${CR_PROMETHEUS_SERVER_CONFIG}; then
        echo "Creating Thanos Authorization Token Secret"

        echo "Fetching prometheus-k8s-token secret..."
        # Fetch the 'prometheus-k8s-token' secrets from the 'openshift-monitoring' namespace'
        TOKEN_SECRETS=$(${KUBECTL} -n openshift-monitoring get secret -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='prometheus-k8s')].metadata.name}")

        TOKEN_SECRET_NAME=""
        # Loop through the fetched secrets to find the one starting with 'prometheus-k8s-token-, as there might be other dockercfg tokens'
        for SECRET in $TOKEN_SECRETS; do
            if [[ $SECRET == prometheus-k8s-token-* ]]; then
                TOKEN_SECRET_NAME=$SECRET
                break
            fi
        done

        if [ -z "${TOKEN_SECRET_NAME}" ]; then
            echo "Failed to find prometheus-k8s-token secret. Please ensure the service account exists and try again." && exit 1
        fi

        TOKEN=$(${KUBECTL} -n openshift-monitoring get secret ${TOKEN_SECRET_NAME} -o jsonpath="{.data.token}" | base64 --decode)

        if [ -z "${TOKEN}" ]; then
            echo "Failed to fetch the token from prometheus-k8s-token. Please ensure the secret contains a token and try again." && exit 1
        fi
        # encode the token in base64
        TOKEN_BASE64=$(encode_inline "${TOKEN}")

        echo "Updating Secret $(basename ${SECRET_PATH}) with base64-encoded token..."
        # Backup the original secret file
        cp ${SECRET_PATH} ${SECRET_PATH}.bak

        ${YQ} e ".data.authorizationToken = \"${TOKEN_BASE64}\"" ${SECRET_PATH} -i

        echo "Applying the Secret from $(basename ${SECRET_PATH})..."
        ${KUBECTL} apply -n ${OPERATOR_NS} -f ${SECRET_PATH}

        if [ $? -ne 0 ]; then
            echo "Failed to apply the Secret from $(basename ${SECRET_PATH}). Please check the file and try again." && exit 1
        else
            echo "Successfully applied the Secret from $(basename ${SECRET_PATH})"
        fi
        # Restore the original secret file from the backup
        mv ${SECRET_PATH}.bak ${SECRET_PATH}
    else
        echo "Thanos authorization is not configured for $(basename ${CR_PROMETHEUS_SERVER_CONFIG}). Skipping Thanos secret creation."
    fi
}
# Function to validate user input in a selection menu, check if input is valid number and with in range of options (from 1 to opts_count).
function validate_select_input() {
    local opts_count=$1 && local opt=$2
    if [ "${opt}" == "exit" ]; then
        echo "Exiting the program ..." >&2 && exit 0
    elif ! [[ "${opt}" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: Input not a number: ${opt}" >&2 && return 1
    elif [ ${opt} -le 0 ] || [ ${opt} -gt ${opts_count} ]; then
        echo "ERROR: Input out of range [1 - ${opts_count}]: ${opt}" >&2 && return 1
    fi
}
# Function to wait for a deployment, CRD, or CR to be ready in the specified namespace
# The function continuously checks the status of the specified resource and waits until it is ready.
#    a. For deployments, check if the deployment is available and its pods are ready.
#    b. For CRDs, check if the CRD is established.
#    c. For CRs, check if the specific CR exists.
function wait_for_deployment() {
    if [ "${ACTION}" == "delete" ]; then return; fi
    local namespace=$1
    local resource_type=$2
    local resource_name=$3

    echo "Waiting for ${resource_type} '${resource_name}' to be ready in namespace '${namespace}'..."
    local retry_count=0
    while true; do
        case ${resource_type} in
            deploy)
                local deploy_status
                deploy_status=$(${KUBECTL} -n ${namespace} get deployment ${resource_name} -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
                if [ "${deploy_status}" == "True" ]; then
                    echo "Deployment ${resource_name} is successfully rolled out"
                    local deploy_pods
                    deploy_pods=$(${KUBECTL} -n ${namespace} get pods -l app=${resource_name} -o name)
                    for pod in ${deploy_pods}; do
                        ${KUBECTL} -n ${namespace} wait --for=condition=Ready ${pod}
                    done
                    break
                fi
                ;;
            crd)
                local crd_status
                crd_status=$(${KUBECTL} get crd ${resource_name} -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null)
                if [ "${crd_status}" == "True" ]; then
                    echo "Proemtheus CRD ${resource_name} is established."
                    break
                else
                    echo "Prometheus CRD ${resource_name} is not yet ready."
                fi
                ;;
            cr)
                local cr_exists
                local cr_resource_name
                if [ "${resource_name}" == "${DEFAULT_PROMETHEUS_SERVER_CONFIG_NAME}" ]; then
                    cr_resource_name=$(${YQ} e '.metadata.name' ${CR_PROMETHEUS_SERVER_CONFIG})
                elif [ "${resource_name}" == "${DEFAULT_PROMETHEUS_QUERY_MAPPING_NAME}" ]; then
                    cr_resource_name=$(${YQ} e '.metadata.name' ${CR_PROMETHEUS_QUERY_MAPPING})
                else
                    echo "Unknown Prometheus CR: ${resource_name}" && exit 1
                fi

                cr_exists=$(${KUBECTL} -n ${namespace} get ${resource_name} ${cr_resource_name} -o jsonpath='{.metadata.name}' 2>/dev/null)
                if [ -n "${cr_exists}" ]; then
                    echo "Prometheus CR ${resource_name} is established."
                    break
                else
                    echo "Prometheus CR ${cr_resource_name} is not yet ready."
                fi
                ;;
            *)
                echo "Unknown Prometheus CR type: ${resource_type}" && exit 1
                ;;
        esac
        ((++retry_count))
        echo "Waiting for resource to be established: ${resource_name}"
        sleep 5
    done
}
# Function to check if the PrometheusServerConfig is configured for Thanos
# It checks if the bearer token with the key "authorizationToken" is present in the configuration
# This ensures to decide if thanos authorization secret should be configured or not, 
# such that this script can function for other PrometheusServerConfig
function is_thanos_configured_for_psc() {
    local file_path=$1
    local token_key=$(${YQ} e '.spec.bearerToken.secretKeyRef.key' "$file_path")
    [[ "$token_key" == "authorizationToken" ]]
    return $?
}

function retry() {
    local retry_count=$1
    if [ ${retry_count} -ge ${MAX_RETRY} ]; then
        echo "Max retries reached, exiting." && exit 1
    fi
    echo "Retrying... (${retry_count})"
    sleep ${RETRY_INTERVAL}
}
# Function to base64 encode a string without line breaks.
# This function ensures compatibility across different operating systems (macOS and Linux).
# macOS uses 'base64' without options to avoid line breaks.
# Linux requires the '-w 0' option to prevent line breaks in the base64 output
function encode_inline() {
    local input=$1
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -n "$input" | base64
    else
        echo -n "$input" | base64 -w 0
    fi
}

################## MAIN ##################
validate_args $@ && main
