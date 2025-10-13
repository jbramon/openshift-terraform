#!/bin/bash

# Read cluster info from environment variables
OC_CLUSTER_URL="${OC_CLUSTER_URL:?Environment variable OC_CLUSTER_URL is not set}"
OC_TOKEN="${OC_TOKEN:?Environment variable OC_TOKEN is not set}"

# Install oc CLI if not available
if ! command -v oc &> /dev/null; then
  echo "Installing OpenShift CLI..."
  curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
  tar -xzf openshift-client-linux.tar.gz
  sudo mv oc /usr/local/bin/
  chmod +x /usr/local/bin/oc
fi

# Login to OpenShift
echo "Logging into OpenShift..."
oc login --token="$OC_TOKEN" --server="$OC_CLUSTER_URL"

function usage() {
    echo
    echo "Usage:"
    echo " $0 [command] [options]"
    echo " $0 --help"
    echo
    echo "Example:"
    echo " $0 deploy --project-suffix kylecanonigo-dev"
    echo
    echo "COMMANDS:"
    echo "   deploy                   Deploy demo apps into an existing OpenShift project"
    echo "   delete                   Clean up all resources inside the project"
    echo 
    echo "OPTIONS:"
    echo "   --user [username]          Optional    The admin user. Required if logged in as kube:admin"
    echo "   --project-suffix [suffix]  Required    Suffix to locate the existing project (e.g., kylecanonigo-dev)"
    echo "   --ephemeral                Optional    Deploy demo without persistent storage. Default false"
    echo "   --oc-options               Optional    oc client options to pass to all oc commands"
    echo
}

ARG_USERNAME=
ARG_PROJECT_SUFFIX=
ARG_COMMAND=
ARG_EPHEMERAL=false
ARG_OC_OPS=

while :; do
    case $1 in
        deploy)
            ARG_COMMAND=deploy
            ;;
        delete)
            ARG_COMMAND=delete
            ;;
        --user)
            if [ -n "$2" ]; then
                ARG_USERNAME=$2
                shift
            else
                printf 'ERROR: "--user" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --project-suffix)
            if [ -n "$2" ]; then
                ARG_PROJECT_SUFFIX=$2
                shift
            else
                printf 'ERROR: "--project-suffix" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --oc-options)
            if [ -n "$2" ]; then
                ARG_OC_OPS=$2
                shift
            else
                printf 'ERROR: "--oc-options" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --ephemeral)
            ARG_EPHEMERAL=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            shift
            ;;
        *) 
            break
    esac
    shift
done

################################################################################
# CONFIGURATION                                                                #
################################################################################

LOGGEDIN_USER=$(oc $ARG_OC_OPS whoami)

if [ -z "$ARG_PROJECT_SUFFIX" ]; then
    echo "ERROR: --project-suffix is required to target an existing project"
    exit 255
fi

# Use the full project name
PROJECT_NAME="$ARG_PROJECT_SUFFIX"

function deploy() {
    echo "Using existing project: $PROJECT_NAME"
    oc $ARG_OC_OPS project $PROJECT_NAME >/dev/null 2>&1 || {
        echo "ERROR: Project $PROJECT_NAME does not exist or is inaccessible."
        exit 1
    }

    echo "Deploying Jenkins (ephemeral)..."
    oc new-app jenkins-ephemeral -n $PROJECT_NAME

    sleep 2

    echo "Creating BuildConfig 'ci-cd' in project $PROJECT_NAME..."

    oc apply -n $PROJECT_NAME -f - <<EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: ci-cd
  namespace: $PROJECT_NAME
spec:
  source:
    git:
      ref: main
      uri: 'https://gitlab.com/kylecanonigo-group/kylecanonigo-project.git'
    type: Git
  strategy:
    type: JenkinsPipeline
    jenkinsPipelineStrategy:
      jenkinsfilePath: Jenkinsfile
  triggers:
    - type: ImageChange
      imageChange: {}
    - type: ConfigChange
EOF

    echo "BuildConfig 'ci-cd' created."
}

function set_default_project() {
    if [ "$LOGGEDIN_USER" == 'kube:admin' ]; then
        oc $ARG_OC_OPS project default >/dev/null
    fi
}

function echo_header() {
    echo
    echo "########################################################################"
    echo $1
    echo "########################################################################"
}

################################################################################
# MAIN                                                                         #
################################################################################

if [ "$LOGGEDIN_USER" == 'kube:admin' ] && [ -z "$ARG_USERNAME" ]; then
    echo "--user must be provided when running as 'kube:admin'"
    exit 255
fi

pushd ~ >/dev/null
START=$(date +%s)

echo_header "OpenShift CI/CD Demo ($(date))"

case "$ARG_COMMAND" in
    delete)
        echo "Cleaning up resources inside $PROJECT_NAME..."

        oc $ARG_OC_OPS project $PROJECT_NAME >/dev/null 2>&1 || {
            echo "ERROR: Project $PROJECT_NAME does not exist or is inaccessible."
            exit 1
        }

        oc $ARG_OC_OPS delete all --all -n $PROJECT_NAME
        oc $ARG_OC_OPS delete pvc --all -n $PROJECT_NAME
        oc $ARG_OC_OPS delete secret --all -n $PROJECT_NAME
        oc $ARG_OC_OPS delete configmap --all -n $PROJECT_NAME

        echo "Cleanup completed inside project: $PROJECT_NAME"
        ;;
    deploy)
        echo "Starting deployment..."
        deploy
        echo "Deployment completed successfully!"
        ;;
    *)
        echo "Invalid or missing command: '$ARG_COMMAND'"
        usage
        ;;
esac

set_default_project
popd >/dev/null

END=$(date +%s)
echo "(Completed in $(( ($END - $START)/60 )) min $(( ($END - $START)%60 )) sec)"
