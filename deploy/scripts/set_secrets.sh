#!/bin/bash

#error codes include those from /usr/include/sysexits.h

#colors for terminal
boldreduscore="\e[1;4;31m"
boldred="\e[1;31m"
cyan="\e[1;36m"
resetformatting="\e[0m"

#External helper functions
#. "$(dirname "${BASH_SOURCE[0]}")/deploy_utils.sh"
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"

#call stack has full scriptname when using source
source "${script_directory}/deploy_utils.sh"

function showhelp {
    echo ""
    echo "#########################################################################################"
    echo "#                                                                                       #"
    echo "#                                                                                       #"
    echo "#   This file contains the logic to add the SPN secrets to the keyvault.                #"
    echo "#                                                                                       #"
    echo "#                                                                                       #"
    echo "#   Usage: set_secret.sh                                                                #"
    echo "#      -e or --environment                   environment name                           #"
    echo "#      -r or --region                        region name                                #"
    echo "#      -v or --vault                         Azure keyvault name                        #"
    echo "#      -s or --subscription                  subscription                               #"
    echo "#      -c or --spn_id                        SPN application id                         #"
    echo "#      -p or --spn_secret                    SPN password                               #"
    echo "#      -t or --tenant_id                     SPN Tenant id                              #"
    echo "#      -h or --help                          Show help                                  #"
    echo "#                                                                                       #"
    echo "#   Example:                                                                            #"
    echo "#                                                                                       #"
    echo "#   [REPO-ROOT]deploy/scripts/set_secret.sh \                                           #"
    echo "#      --environment PROD  \                                                            #"
    echo "#      --region weeu  \                                                                 #"
    echo "#      --vault prodweeuusrabc  \                                                        #"
    echo "#      --subscription xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \                            #"
    echo "#      --spn_id yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy \                                  #"
    echo "#      --spn_secret ************************ \                                          #"
    echo "#      --tenant_id zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz \                               #"
    echo "#                                                                                       #"
    echo "#########################################################################################"
}

INPUT_ARGUMENTS=$(getopt -n set_secrets -o e:r:v:s:c:p:t:hw --longoptions environment:,region:,vault:,subscription:,spn_id:,spn_secret:,tenant_id:,workload,help -- "$@")
VALID_ARGUMENTS=$?

if [ "$VALID_ARGUMENTS" != "0" ]; then
    showhelp
fi

eval set -- "$INPUT_ARGUMENTS"
while :; do
    case "$1" in
    -e | --environment)
        environment="$2"
        shift 2
        ;;
    -r | --region)
        region_code="$2"
        shift 2
        ;;
    -v | --vault)
        keyvault="$2"
        shift 2
        ;;
    -s | --subscription)
        subscription="$2"
        shift 2
        ;;
    -c | --spn_id)
        client_id="$2"
        shift 2
        ;;
    -p | --spn_secret)
        client_secret="$2"
        shift 2
        ;;
    -t | --tenant_id)
        tenant_id="$2"
        shift 2
        ;;
    -w | --workload)
        workload=1
        shift
        ;;
    -h | --help)
        showhelp
        exit 3
        shift
        ;;
    --)
        shift
        break
        ;;
    esac
done

while [ -z "${environment}" ]; do
    read -r -p "Environment name: " environment
done

while [ -z "${region_code}" ]; do
    read -r -p "Region name: " region
done

if [ -z "${region_code}" ]; then
  # Convert the region to the correct code
  get_region_code $region
fi

# if ! valid_environment "${environment}"; then
#     echo "The 'environment' must be at most 5 characters long, composed of uppercase letters and numbers!"
#     showhelp
#     exit 65	#/* data format error */
# fi

# if ! valid_region_code "${region_code}"; then
#    echo "The 'region' must be a non-empty string composed of 4 uppercase letters!"
#    showhelp
#    exit 65	#/* data format error */
# fi

automation_config_directory=~/.sap_deployment_automation
environment_config_information="${automation_config_directory}"/"${environment}""${region_code}"

if [ ! -d "${automation_config_directory}" ]; then
    # No configuration directory exists
    mkdir "${automation_config_directory}"
else
    touch "${environment_config_information}"
fi

if [ -z "$subscription" ]; then
    load_config_vars "${environment_config_information}" "subscription"
fi

if [ "$workload" != 1 ]; then
    load_config_vars "${environment_config_information}" "STATE_SUBSCRIPTION"
    subscription=${STATE_SUBSCRIPTION}
fi

if [ -z "$keyvault" ]; then
    load_config_vars "${environment_config_information}" "keyvault"
    if [ -z "$keyvault" ]; then
        read -r -p "Keyvault name: " keyvault
    fi
    if valid_kv_name "$keyvault" ; then
        echo "Valid keyvault name format specified"
    else
        printf -v val %-40.40s "$keyvault"
        echo "#########################################################################################"
        echo "#                                                                                       #"
        echo -e "#       The provided keyvault is not valid:$boldred ${val} $resetformatting  #"
        echo "#                                                                                       #"
        echo "#########################################################################################"
        exit 65
    fi

fi

if [ -z "${client_id}" ]; then
    load_config_vars "${environment_config_information}" "client_id"
    if [ -z "$client_id" ]; then
        read -r -p "SPN App ID: " client_id
    fi
else
    if is_valid_guid "${client_id}" ; then
        echo "Valid client_id specified"
    else
        printf -v val %-40.40s "$client_id"
        echo "#########################################################################################"
        echo "#                                                                                       #"
        echo -e "#       The provided client_id is not valid:$boldred ${val} $resetformatting  #"
        echo "#                                                                                       #"
        echo "#########################################################################################"
        exit 65
    fi
fi

if [ ! -n "$client_secret" ]; then
    #do not output the secret to screen
    read -rs -p "        -> Kindly provide SPN Password: " client_secret
    echo "********"
fi

if [ -z "${tenant_id}" ]; then
    load_config_vars "${environment_config_information}" "tenant_id"
    if [ ! -n "${tenant_id}" ]; then
        read -r -p "SPN Tenant ID: " tenant_id
    fi
else
    if is_valid_guid "${tenant_id}" ; then
        echo "Valid tenant_id specified"
    else
        printf -v val %-40.40s "$tenant_id"
        echo "#########################################################################################"
        echo "#                                                                                       #"
        echo -e "#       The provided tenant_id is not valid:$boldred ${val} $resetformatting  #"
        echo "#                                                                                       #"
        echo "#########################################################################################"
        exit 65
    fi
fi

if [ -z "${subscription}" ]; then
    read -r -p "SPN Subscription: " subscription
else
    if is_valid_guid "${subscription}" ; then
        echo "Valid subscription specified"
    else
        printf -v val %-40.40s "$subscription"
        echo "#########################################################################################"
        echo "#                                                                                       #"
        echo -e "#     The provided subscription is not valid:$boldred ${val} $resetformatting #"
        echo "#                                                                                       #"
        echo "#########################################################################################"
        exit 65
    fi
fi

if [ -z "${keyvault}" ]; then
    echo "Missing keyvault"
    showhelp
    exit 65	#/* data format error */
fi

if [ -z "${client_id}" ]; then
    echo "Missing client_id"
    showhelp
    exit 65	#/* data format error */
fi

if [ -z "$client_secret" ]; then
    echo "Missing client_secret"
    showhelp
    exit 65	#/* data format error */
fi

if [ -z "${tenant_id}" ]; then
    echo "Missing tenant_id"
    showhelp
    exit 65	#/* data format error */
fi

echo "#########################################################################################"
echo "#                                                                                       #"
echo "#                              Setting the secrets                                      #"
echo "#                                                                                       #"
echo "#########################################################################################"
echo ""

save_config_vars "${environment_config_information}" \
    keyvault \
    environment \
    subscription \
    client_id \
    tenant_id \
    STATE_SUBSCRIPTION

secretname="${environment}"-subscription-id

az keyvault secret show --name "${secretname}" --vault-name "${keyvault}" >stdout.az 2>&1
result=$(grep "ERROR: The user, group or application" stdout.az)

if [ -n "${result}" ]; then
    upn=$(az account show | grep name | grep @ | cut -d: -f2 | cut -d, -f1 | tr -d \" | xargs)
    az keyvault set-policy -n "${keyvault}" --secret-permissions get list recover restore set --upn "${upn}"
fi

if [ -n "$(az keyvault secret list-deleted --vault-name "${keyvault}" | grep "${secretname}")" ]; then
    echo -e "\t $cyan Recovering secret ${secretname} in keyvault ${keyvault} $resetformatting \n"
    az keyvault secret recover --name "${secretname}" --vault-name "${keyvault}"
    sleep 10
    az keyvault secret set --name "${secretname}" --vault-name "${keyvault}" --value "${subscription}" --only-show-errors --output none
else
    echo -e "\t $cyan Setting secret ${secretname} in keyvault ${keyvault} $resetformatting \n"
    az keyvault secret set --name "${secretname}" --vault-name "${keyvault}" --value "${subscription}" >stdout.az 2>&1
fi

result=$(grep "ERROR: The user, group or application" stdout.az)

if [ -n "${result}" ]; then
    echo "#########################################################################################"
    echo "#                                                                                       #"
    echo "#          No access to add the secrets in the" "${keyvault}" "keyvault             #"
    echo "#            Please add an access policy for the account you use                        #"
    echo "#                                                                                       #"
    echo "#########################################################################################"
    echo ""
    rm stdout.az
    exit 77	#/* permission denied */
fi

result=$(grep "The Vault may not exist" stdout.az)
if [ -n "${result}" ]; then
    printf -v val "%-20.20s could not be found!" "$keyvault"
    echo "#########################################################################################"
    echo "#                                                                                       #"
    echo "#                      Keyvault" "${val}" "               #"
    echo "#                                                                                       #"
    echo "#########################################################################################"
    echo ""
    rm stdout.az
    exit 68	#/* name unknown */
fi

#turn off output, we do not want to show the details being uploaded to keyvault
secretname="${environment}"-client-id
if [ -n "$(az keyvault secret list-deleted --vault-name "${keyvault}" | grep "${secretname}")" ]; then
    echo -e "\t $cyan Recovering secret ${secretname} in keyvault ${keyvault} $resetformatting \n"
    az keyvault secret recover --name "${secretname}" --vault-name "${keyvault}"
    sleep 10
    az keyvault secret set --name "${secretname}" --vault-name "${keyvault}" --value "${client_id}" --only-show-errors --output none
else
    echo -e "\t $cyan Setting secret ${secretname} in keyvault ${keyvault} $resetformatting \n"
    az keyvault secret set --name "${secretname}" --vault-name "${keyvault}" --value "${client_id}" --only-show-errors --output none
fi


secretname="${environment}"-tenant-id
if [ -n "$(az keyvault secret list-deleted --vault-name "${keyvault}" | grep "${secretname}")" ]; then
    echo -e "\t $cyan Recovering secret ${secretname} in keyvault ${keyvault} $resetformatting \n"
    az keyvault secret recover --name "${secretname}" --vault-name "${keyvault}"
    sleep 10
    az keyvault secret set --name "${secretname}" --vault-name "${keyvault}" --value "${tenant_id}" --only-show-errors --output none
else
    echo -e "\t $cyan Setting secret ${secretname} in keyvault ${keyvault} $resetformatting \n"
    az keyvault secret set --name "${secretname}" --vault-name "${keyvault}" --value "${tenant_id}" --only-show-errors --output none
fi


secretname="${environment}"-client-secret
if [ -n "$(az keyvault secret list-deleted --vault-name "${keyvault}" | grep "${secretname}")" ]; then
    echo -e "\t $cyan Recovering secret ${secretname} in keyvault ${keyvault} $resetformatting \n"
    az keyvault secret recover --name "${secretname}" --vault-name "${keyvault}"
    sleep 10
    az keyvault secret set --name "${secretname}" --vault-name "${keyvault}" --value "${client_secret}" --only-show-errors --output none
else
    echo -e "\t $cyan Setting secret ${secretname} in keyvault ${keyvault} $resetformatting \n"
    az keyvault secret set --name "${secretname}" --vault-name "${keyvault}" --value "${client_secret}" --only-show-errors --output none
fi

