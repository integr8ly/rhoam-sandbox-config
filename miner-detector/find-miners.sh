#!/usr/bin/env bash

set -e

setup_vars() {

    DATE=$(date '+%Y-%m-%d')
    DATE_YESTERDAY=$(date '+%Y-%m-%d' -d '1 day ago')

    DATE_HOUR=$(date '+%Y-%m-%d-%H-00')
    HOUR_PRETTY=$(date '+%H:00')

    DATE_ONE_HOUR_AGO=$(date '+%Y-%m-%d-%H-00' -d '1 hour ago')
    DATE_ONE_HOUR_AGO_PRETTY=$(date '+%Y-%m-%d %H:00' -d '1 hour ago')

    DATE_TIME=$(date '+%Y-%m-%d-%H-%M')
    PRETTY_DATE_TIME=$(date '+%Y-%m-%d %H:%M')

    SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

    OUT_DIR=/tmp
    if [[ "${IN_CLUSTER}" != "true" ]]; then
        OUT_DIR=${SCRIPTS_DIR}/out
        mkdir ${OUT_DIR} || true
    fi

    NAMESPACES_WITH_PODS_FILE_NAME=namespaces_with_pods.txt
    NAMESPACES_WITH_PODS=${OUT_DIR}/${NAMESPACES_WITH_PODS_FILE_NAME}

    SUSPICIOUS_NAMESPACES_WITH_PODS_FILE_NAME=suspicious_namespaces_with_pods.txt
    SUSPICIOUS_NAMESPACES_WITH_PODS=${OUT_DIR}/${SUSPICIOUS_NAMESPACES_WITH_PODS_FILE_NAME}

    BANNED_EMAILS_FILE_NAME=banned_emails.txt
    BANNED_EMAILS=${OUT_DIR}/${BANNED_EMAILS_FILE_NAME}

    BAN_COMMANDS_FILE_NAME=ban_commands.txt
    BAN_COMMANDS=${OUT_DIR}/${BAN_COMMANDS_FILE_NAME}

    BANNED_USER_SIGNUPS_FILE_NAME=banned_usersignups.txt
    BANNED_USER_SIGNUPS=${OUT_DIR}/${BANNED_USER_SIGNUPS_FILE_NAME}

    PODS_FILE=${OUT_DIR}/pods.txt
    PS_AUX_FILE=${OUT_DIR}/aux.txt
    DOCKERFILE_CONTENT_FILE=${OUT_DIR}/dockerfile.txt
    MATCHED_ENTRIES_IN_FILES=${OUT_DIR}/matched_entries_in_files.txt
    MATCHED_FILE_NAMES=${OUT_DIR}/matched_file_names.txt
    FOUND_REJECTED_FILE=${OUT_DIR}/found_rejected_file.txt
    JPS_OUTPUT_FILE=${OUT_DIR}/jps_output_file.txt
    JAR_TF_OUTPUT_FILE=${OUT_DIR}/jar_tf_output_file.txt

    HOST_KUBECONFIG="${HOME}/.kube/config_sandbox-sa"
    MEMBER_KUBECONFIGS=(${HOST_KUBECONFIG})

    MINING_TOOLS_GREP="xmrig\|nheqminer\|hellminer\|verus\|redhat.jupyter\|miner\|luckpool\|unmineable\|--disableNVIDIA\|chukwa\|mine.zpool\|vanitygen\|mining\|xmr-stak\|monero\|bcoin\|rplant.xyz\|yescryptR16\|zergpool\|pool.srizbi\|pool.pktpool\|pool.pkt\|pool.pkteer\|pktco.in"
    MINING_TOOLS_FILES_GREP="xmrig\|nheqminer\|hellminer\|verus-solver\|xmr-stak\|monero\|bcoin"
    MINING_TOOLS_FILE_NAMES_REGEX=".*(xmrig|nheqminer|hellminer|verus-solver|xmr-stak|bcoin).*"
    MINING_TOOLS_FILE_NAMES_EXCLUSION="\.che/gopath\|/nix/store/"
    MINING_TOOLS_GREP_EXCLUSION="determin\|README"
    DOCKERFILE_ENTRIES_GREP="node-process-hider"

    REJECTED_FILES=("/usr/local/lib/libprocesshider.so")

    IGNORED_REGEX="jboss-modules\.jar\|jolokia-jvm\.jar\|jenkins.war\|node src-gen/backend/main.js /projects\|ps aux\|org\.jetbrains\.projector\.server\.ProjectorLauncher\|/var/lib/rabbitmq\|gunicorn wsgi\|spring\|server\.jar nogui\|Minecraft"

    BANNED_MINERS_CONFIGMAP=banned-miners
    SUSPICIOUS_USERS_CONFIGMAP=suspicious-users
}

send_notification() {
    echo "${TO_SEND}"

    WITH_PREFIX_TO_SEND=$(echo "${TO_SEND}" | sed -e 's/^/    &/' )
    NOTIFICATION="apiVersion: toolchain.dev.openshift.com/v1alpha1
kind: Notification
metadata:
  labels:
    toolchain.dev.openshift.com/type: detected-miners
  generateName: ${1}-${DATE_TIME}-
spec:
  recipient: '${MINER_DETECTOR_REPORT_RECIPIENT}'
  subject: ${2}
  content: |
    <div><pre><code>
    ${2}:
    ${WITH_PREFIX_TO_SEND}
    </code></pre></div>"

    echo "Notification to be created: ${NOTIFICATION}"

    cat <<EOF | oc --kubeconfig ${HOST_KUBECONFIG} -n toolchain-host-operator create -f -
${NOTIFICATION}
EOF
}


send_banned_notification() {
    if [[ -n $(cat ${BANNED_EMAILS}) ]]; then
        TO_SEND="

=======
Emails:
=======
$(cat ${BANNED_EMAILS} || true)


============
UserSignups:
============
$(cat ${BANNED_USER_SIGNUPS} || true)


==============
Detected pods:
==============
$(cat ${NAMESPACES_WITH_PODS} || true)
"

        send_notification "banned-miners" "Banned miners ${DATE_YESTERDAY}"
    else
        echo "Nothing to send - there was no miner detected nor banned"
    fi
}

send_suspicious_notification() {
    if [[ -n $(cat ${SUSPICIOUS_NAMESPACES_WITH_PODS}) ]]; then
        TO_SEND="

$(cat ${SUSPICIOUS_NAMESPACES_WITH_PODS} || true)
"

        send_notification "suspicious-users" "Suspicious users ${DATE_ONE_HOUR_AGO_PRETTY}-${HOUR_PRETTY}"
    else
        echo "Nothing to send - there was no miner detected nor banned"
    fi
}

store_cm_data_in_file() {
    oc --kubeconfig ${HOST_KUBECONFIG} get configmap ${1}-${2} -o jsonpath="{.data.$(echo ${3} | sed 's/\./\\./g')}" > ${4}
    cp ${4} ${4}_backup
}

store_banned_in_file() {
    store_cm_data_in_file ${BANNED_MINERS_CONFIGMAP} ${1} ${NAMESPACES_WITH_PODS_FILE_NAME} ${NAMESPACES_WITH_PODS}
    store_cm_data_in_file ${BANNED_MINERS_CONFIGMAP} ${1} ${BANNED_EMAILS_FILE_NAME} ${BANNED_EMAILS}
    store_cm_data_in_file ${BANNED_MINERS_CONFIGMAP} ${1} ${BANNED_USER_SIGNUPS_FILE_NAME} ${BANNED_USER_SIGNUPS}
}

store_suspicious_in_file() {
    store_cm_data_in_file ${SUSPICIOUS_USERS_CONFIGMAP} ${1} ${SUSPICIOUS_NAMESPACES_WITH_PODS_FILE_NAME} ${SUSPICIOUS_NAMESPACES_WITH_PODS}
}

reset_banned_files() {
    echo "" > ${NAMESPACES_WITH_PODS}
    echo "" > ${BANNED_EMAILS}
    echo "" > ${BANNED_USER_SIGNUPS}
    echo "" > ${BAN_COMMANDS}
}

reset_suspicious_files() {
    echo "" > ${SUSPICIOUS_NAMESPACES_WITH_PODS}
}

setup_banned_configmaps_and_files() {

    if [[ "${IN_CLUSTER}" == "true" ]]; then
        echo "running in cluster - checking ConfigMap with banned miners"
        if [[ -n $(oc --kubeconfig ${HOST_KUBECONFIG} get configmap ${BANNED_MINERS_CONFIGMAP}-${DATE} || true) ]]; then
            echo "found today's ConfigMap, so just store it in local file"
            store_banned_in_file ${DATE}

        elif [[ -n $(oc --kubeconfig ${HOST_KUBECONFIG} get configmap ${BANNED_MINERS_CONFIGMAP}-${DATE_YESTERDAY} || true) ]]; then
            echo "found yesterday's ConfigMap, so store it in local file...."
            store_banned_in_file ${DATE_YESTERDAY}
            echo "send notification ..."
            send_banned_notification
            echo "delete the yesterday's ConfigMap..."
            oc --kubeconfig ${HOST_KUBECONFIG} delete configmap ${BANNED_MINERS_CONFIGMAP}-${DATE_YESTERDAY}
            echo "and reset the files"
            reset_banned_files

        else
            echo "none of the expected ConfigMaps was found - reset the files"
            reset_banned_files
        fi
    else
        reset_banned_files
    fi
}

setup_suspicious_configmaps_and_files() {

    if [[ "${IN_CLUSTER}" == "true" ]]; then
        echo "running in cluster - checking ConfigMap with suspicious users"
        if [[ -n $(oc --kubeconfig ${HOST_KUBECONFIG} get configmap ${SUSPICIOUS_USERS_CONFIGMAP}-${DATE_HOUR} || true) ]]; then
            echo "found ConfigMap for the current hour, so just store it in local file"
            store_suspicious_in_file ${DATE_HOUR}

        elif [[ -n $(oc --kubeconfig ${HOST_KUBECONFIG} get configmap ${SUSPICIOUS_USERS_CONFIGMAP}-${DATE_ONE_HOUR_AGO} || true) ]]; then
            echo "found ConfigMap for the previous hour, so store it in local file...."
            store_suspicious_in_file ${DATE_ONE_HOUR_AGO}
            echo "send notification ..."
            send_suspicious_notification
            echo "delete the ConfigMap..."
            oc --kubeconfig ${HOST_KUBECONFIG} delete configmap ${SUSPICIOUS_USERS_CONFIGMAP}-${DATE_ONE_HOUR_AGO}
            echo "and reset the files"
            reset_suspicious_files

        else
            echo "none of the expected ConfigMaps was found - reset the files"
            reset_suspicious_files
        fi
    else
        reset_suspicious_files
    fi
}

save_banned_miners_to_configmap() {
    if [[ "${IN_CLUSTER}" == "true" ]]; then
        oc --kubeconfig ${HOST_KUBECONFIG} delete configmap ${BANNED_MINERS_CONFIGMAP}-${DATE} || true
        oc --kubeconfig ${HOST_KUBECONFIG} create configmap ${BANNED_MINERS_CONFIGMAP}-${DATE} --from-file=${NAMESPACES_WITH_PODS} --from-file=${BANNED_EMAILS} --from-file=${BANNED_USER_SIGNUPS}
    fi
}

save_suspicious_users_to_configmap() {
    if [[ "${IN_CLUSTER}" == "true" ]]; then
        oc --kubeconfig ${HOST_KUBECONFIG} delete configmap ${SUSPICIOUS_USERS_CONFIGMAP}-${DATE_HOUR} || true
        oc --kubeconfig ${HOST_KUBECONFIG} create configmap ${SUSPICIOUS_USERS_CONFIGMAP}-${DATE_HOUR} --from-file=${SUSPICIOUS_NAMESPACES_WITH_PODS}
    fi
}

save_to_configmaps_or_print() {

    if [[ "${IN_CLUSTER}" == "true" ]]; then
        save_banned_miners_to_configmap
        save_suspicious_users_to_configmap
    else
        echo "
#######################################################
#######        Detected miners                  #######
#######################################################

================================================
Emails:
================================================
$(cat ${BANNED_EMAILS} || true)


================================================
Ban commands:
================================================
$(cat ${BAN_COMMANDS} || true)


================================================
Detected pods:
================================================
$(cat ${NAMESPACES_WITH_PODS} || true)


#######################################################
#######        Suspicious users/pods            #######
#######################################################

$(cat ${SUSPICIOUS_NAMESPACES_WITH_PODS} || true)
"
    fi
}

ban_and_record() {
    echo "a mining process was detected"
    echo "
------------------------------------------
Email: ${EMAIL}:
------------------------------------------
oc --kubeconfig ${MEMBER_KUBECONFIG_TO_PRINT} rsh -n ${NAMESPACE} -c ${CONTAINER} ${POD}

${SOURCE_OF_CONTENT}:
${DETECTED_CONTENT}
" >> ${NAMESPACES_WITH_PODS}

    if [[ -z $(grep "${EMAIL}" ${BANNED_EMAILS}) ]]; then
        echo ${EMAIL} >> ${BANNED_EMAILS}

        if [[ "${IN_CLUSTER}" == "true" ]]; then
            echo "is running in cluster so banning the user ${USER_SIGNUP}"
            sandbox-cli --config /root/.sandbox.yaml ban ${USER_SIGNUP} <<< y
            echo "${USER_SIGNUP}" >> ${BANNED_USER_SIGNUPS}
            save_banned_miners_to_configmap
        else
            echo "is not running in cluster"
            echo "sandbox-cli-prod ban ${USER_SIGNUP} <<< y" >> ${BAN_COMMANDS}
        fi
    else
        echo "this user was already either banned or already added to the report"
    fi
}

record_suspicious() {
    echo "found suspicious process"

    if [[ -z $(grep "${CONTAINER} ${POD}" ${SUSPICIOUS_NAMESPACES_WITH_PODS} || true) ]]; then
        echo "================================================
Email: ${EMAIL}
================================================

Ban command:
------------------------------------------------
sandbox-cli-prod ban ${USER_SIGNUP} <<< y
------------------------------------------------

To rsh the suspicious pod/container:
------------------------------------------------
oc --kubeconfig ${MEMBER_KUBECONFIG_TO_PRINT} rsh -n ${NAMESPACE} -c ${CONTAINER} ${POD}
------------------------------------------------

${SOURCE_OF_CONTENT}:
------------------------------------------------
$(cat ${DETECTED_CONTENT})
------------------------------------------------

" >> ${SUSPICIOUS_NAMESPACES_WITH_PODS}
        save_suspicious_users_to_configmap
    else
        echo "The combination of the pod ${POD} and the container ${CONTAINER} is already reported"
    fi
}

check_files() {
    echo "checking files"
    oc --kubeconfig ${MEMBER_KUBECONFIG} rsh -n ${NAMESPACE} -c ${CONTAINER} ${POD} <<< "[ -f Dockerfile ] && cat Dockerfile 2>/dev/null || true && exit" > ${DOCKERFILE_CONTENT_FILE} || true
    DOCKERFILE_ENTRIES=$(cat ${DOCKERFILE_CONTENT_FILE} | grep -i "${DOCKERFILE_ENTRIES_GREP}" || true)

    oc --kubeconfig ${MEMBER_KUBECONFIG} rsh -n ${NAMESPACE} -c ${CONTAINER} ${POD} <<< "find . -maxdepth 2 -type f | xargs grep -I '${MINING_TOOLS_FILES_GREP}' | grep -vi '${MINING_TOOLS_GREP_EXCLUSION}' 2>/dev/null || true && exit" > ${MATCHED_ENTRIES_IN_FILES} || true
    oc --kubeconfig ${MEMBER_KUBECONFIG} rsh -n ${NAMESPACE} -c ${CONTAINER} ${POD} <<< "find ./ -regextype posix-extended -regex '${MINING_TOOLS_FILE_NAMES_REGEX}' 2>/dev/null | grep -vi '${MINING_TOOLS_FILE_NAMES_EXCLUSION}' 2>/dev/null || true && exit" > ${MATCHED_FILE_NAMES} || true

    if [[ -n ${DOCKERFILE_ENTRIES} ]]; then
        SOURCE_OF_CONTENT="Dockerfile" DETECTED_CONTENT="${DOCKERFILE_ENTRIES}

and potentially found some entries in files:
$(cat ${MATCHED_ENTRIES_IN_FILES} || true)" ban_and_record

    else
        if [[ -n "$(cat ${MATCHED_FILE_NAMES} || true)" ]]; then
            SOURCE_OF_CONTENT="File name match" DETECTED_CONTENT=${MATCHED_FILE_NAMES} record_suspicious
        else
            if [[ -n "$(cat ${MATCHED_ENTRIES_IN_FILES} || true)" ]]; then
                SOURCE_OF_CONTENT="File content" DETECTED_CONTENT=${MATCHED_ENTRIES_IN_FILES} record_suspicious
            else
                for REJECTED_FILE in ${REJECTED_FILES[@]}
                do
                    oc --kubeconfig ${MEMBER_KUBECONFIG} rsh -n ${NAMESPACE} -c ${CONTAINER} ${POD} <<< "ls '${REJECTED_FILE}' 2>/dev/null || true && exit" > ${FOUND_REJECTED_FILE} || true
                    if [[ -n "$(cat ${FOUND_REJECTED_FILE} || true)" ]]; then
                        SOURCE_OF_CONTENT="Rejected file" DETECTED_CONTENT=${FOUND_REJECTED_FILE} record_suspicious
                    fi
                done
            fi
        fi
    fi
}

check_jars() {
    PID=$(echo ${THE_MOST_GREEDY} | awk '{print $2}')
    oc --kubeconfig ${MEMBER_KUBECONFIG} rsh -n ${NAMESPACE} -c ${CONTAINER} ${POD} <<< "jps -l 2>&1 || true && exit" > ${JPS_OUTPUT_FILE} || true

    if [[ -n $(cat ${JPS_OUTPUT_FILE} | grep ${PID}) ]]; then
        JAVA_FILE_PATH=$(cat ${JPS_OUTPUT_FILE} | grep ${PID} | awk '{print $2}')
        oc --kubeconfig ${MEMBER_KUBECONFIG} rsh -n ${NAMESPACE} -c ${CONTAINER} ${POD} <<< "jar tf ${JAVA_FILE_PATH} 2>&1 || true && exit" > ${JAR_TF_OUTPUT_FILE} || true
        CRYPTO_NIGHT=$(cat ${JAR_TF_OUTPUT_FILE} | grep -i "cryptonight" || true)

        if [[ -n ${CRYPTO_NIGHT} ]]; then
            SOURCE_OF_CONTENT="Jar content of ${JAVA_FILE_PATH}" DETECTED_CONTENT=${CRYPTO_NIGHT} ban_and_record
            return
        else
            MINING_CLASS=$(cat ${JAR_TF_OUTPUT_FILE} | grep -i "${MINING_TOOLS_GREP}" || true)
            if [[ -n ${MINING_CLASS} ]]; then
                SOURCE_OF_CONTENT="Jar content of ${JAVA_FILE_PATH}" DETECTED_CONTENT=${MINING_CLASS} record_suspicious
                return
            else
                echo "no suspicious java class found"
            fi
        fi
    else
        echo "the most greedy process is not found in jps output"
        echo "the most greedy is:"
        echo "${THE_MOST_GREEDY}"
        echo "jps -l output:"
        echo "${JPS_OUTPUT_FILE}"
    fi
    # if nothing was found and the most greedy process eats more than 98%, then mark it as suspicious
    if (( $(echo "${PERCENTAGE_CPU} > 98" | bc -l) )); then
        SOURCE_OF_CONTENT="PS output" DETECTED_CONTENT=${PS_AUX_FILE} record_suspicious
    else
        echo "no suspicious process detected"
    fi
}


detect_miners() {
    for MEMBER_KUBECONFIG in ${MEMBER_KUBECONFIGS[@]}
    do
        if [[ -n $(oc --kubeconfig ${MEMBER_KUBECONFIG} get pods -A | grep "\-dev\|\-stage" | grep Running) ]]; then
            oc --kubeconfig ${MEMBER_KUBECONFIG} get pods -A | grep "\-dev\|\-stage" | grep Running > ${PODS_FILE}

            echo "========================================================================================"
            echo "for member cluster using a config: ${MEMBER_KUBECONFIG}"
            echo "========================================================================================"

            MEMBER_KUBECONFIG_TO_PRINT=$(echo ${MEMBER_KUBECONFIG} | sed 's/-sa//' | sed 's/\/root/\~/')

            while read LINE; do
                NAMESPACE=$(echo ${LINE} | awk '{print $1}')
                POD=$(echo ${LINE} | awk '{print $2}')
                echo ""
                echo "------------------------------------------------------------------------------"
                echo "in namespace: ${NAMESPACE} pod: ${POD}"
                echo "------------------------------------------------------------------------------"

                for CONTAINER in $(oc --kubeconfig ${MEMBER_KUBECONFIG} get pod ${POD} -n ${NAMESPACE} -o jsonpath="{.spec.containers[*].name}");
                do
                    echo "---> container: ${CONTAINER}:"
                    oc --kubeconfig ${MEMBER_KUBECONFIG} rsh -n ${NAMESPACE} -c ${CONTAINER} ${POD} <<< "ps aux && exit" > ${PS_AUX_FILE} || true
                    MINING_PROCESS=$(cat ${PS_AUX_FILE} | grep -i "${MINING_TOOLS_GREP}" | grep -v "grep -" || true)

                    MUR=$(echo ${NAMESPACE} | sed -e "s/-dev$\|-stage$//")
                    USER_SIGNUP=$(oc --kubeconfig ${HOST_KUBECONFIG} get mur ${MUR} -o jsonpath='{.metadata.labels.toolchain\.dev\.openshift\.com/owner}')
                    EMAIL=$(oc --kubeconfig ${HOST_KUBECONFIG} get usersignup ${USER_SIGNUP} -o jsonpath='{.metadata.annotations.toolchain\.dev\.openshift\.com/user-email}')

                    if [[ -n ${MINING_PROCESS} ]]; then
                        SOURCE_OF_CONTENT="Process" DETECTED_CONTENT=${MINING_PROCESS} ban_and_record
                    else
                        echo "checking if it is suspicious or java mining process"
                        if [[ -n $(cat ${PS_AUX_FILE} | head -n 1 | grep CPU) ]]; then
                            THE_MOST_GREEDY=$(cat ${PS_AUX_FILE} | sed '1d' | sort -nrk 3,3 | head -n 1)
                            PERCENTAGE_CPU=$(echo ${THE_MOST_GREEDY} | awk '{print $3}')

                            if (( $(echo "${PERCENTAGE_CPU} > 50" | bc -l) )); then

                                if [[ -z $(echo ${THE_MOST_GREEDY} | grep "${IGNORED_REGEX}") ]]; then
                                    SOURCE_OF_CONTENT="PS output" DETECTED_CONTENT=${PS_AUX_FILE} record_suspicious
                                else
                                    check_jars
                                fi
                            else
                                echo "There is no process eating too much of CPU - the most greedy is:"
                                echo "${THE_MOST_GREEDY}"
                                check_files
                            fi
                        else
                            echo "doesn't contain cpu"
                            check_files
                        fi
                    fi
                    echo ""
                done
            done <${PODS_FILE}
        else
            echo "Won't check for miners because there are no running pods in -dev or -stage namespaces"
        fi
    done
}


IN_CLUSTER=false
if [[ "${1}" == "--in-cluster" ]]; then
    IN_CLUSTER=true
fi
setup_vars
setup_banned_configmaps_and_files
setup_suspicious_configmaps_and_files
detect_miners
save_to_configmaps_or_print

rm  ${PS_AUX_FILE} ${DOCKERFILE_CONTENT_FILE} ${FOUND_REJECTED_FILE} ${MATCHED_ENTRIES_IN_FILES} ${PODS_FILE} || true
