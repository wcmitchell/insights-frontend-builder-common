#!/bin/bash

# Local build script for front ends
# This script is used to build the front end locally
# Use this to test the frontend build system locally when making changes

# Usage:
# 1. Clone a frontend like https://github.com/RedHatInsights/edge-frontend/
# 2. Copy this file and frontend-build-history.sh into the root of the repo
# 3. Change the IMAGE var at the top of this script to the value from build_deploy.sh
# 3. Run the script
# 4. Run the container podman run -p 8000:8000 localhost/edge:5316bd7
# 5. Open the app in your browser at http://localhost:8000/apps/edge 
#
# Note: You can find the image name and tag by looking at the output of the script
# or by running `podman images`. Also, fill in the app name in the URL with the 
# app you are testing

# --------------------------------------------
# Export vars for helper scripts to use
# --------------------------------------------
export WORKSPACE=$(pwd)
export APP_NAME=$(node -e "console.log(require(\"${WORKSPACE:-.}${APP_DIR:-}/package.json\").insights.appname)")
export CONTAINER_NAME="$APP_NAME"
# main IMAGE var is exported from the pr_check.sh parent file
export IMAGE="quay.io/cloudservices/edge-frontend"
export IMAGE_TAG=$(git rev-parse --short=7 HEAD)
export IS_PR=false
COMMON_BUILDER=https://raw.githubusercontent.com/RedHatInsights/insights-frontend-builder-common/master

# Get the chrome config from cloud-services-config
function get_chrome_config() {
  # Create the directory we're gonna plop the config files in
  if [ -d $APP_ROOT/chrome_config ]; then
    rm -rf $APP_ROOT/chrome_config;
  fi
  mkdir -p $APP_ROOT/chrome_config;

  # If the env var is not set, we don't want to include the config
  if [ -z ${INCLUDE_CHROME_CONFIG+x} ] ; then
    return 0
  fi
  # If the env var is set to anything but true, we don't want to include the config
  if [[ "${INCLUDE_CHROME_CONFIG}" != "true" ]]; then
    return 0
  fi
  # If the branch isn't set in the env, we want to use the default
  if [ -z ${CHROME_CONFIG_BRANCH+x} ] ; then
    CHROME_CONFIG_BRANCH="ci-stable";
  fi
  # belt and braces mate, belt and braces
  if [ -d $APP_ROOT/cloud-services-config ]; then
    rm -rf $APP_ROOT/cloud-services-config;
  fi

  # Clone the config repo
  git clone --branch $CHROME_CONFIG_BRANCH https://github.com/RedHatInsights/cloud-services-config.git;
  # Copy the config files into the chrome_config dir
  cp -r cloud-services-config/chrome/* $APP_ROOT/chrome_config/;
  # clean up after ourselves? why not
  rm -rf cloud-services-config;
  # we're done here
  return 0
}

function getHistory() {
  mkdir aggregated_history
  ./frontend-build-history.sh -q $IMAGE -o aggregated_history -c dist
}

function teardown_docker() {
  docker rm -f $CONTAINER_NAME || true
}

set -ex
# NOTE: Make sure this volume is mounted 'ro', otherwise Jenkins cannot clean up the
# workspace due to file permission errors; the Z is used for SELinux workarounds
# -e NODE_BUILD_VERSION can be used to specify a version other than 12
docker run --rm -it --name $CONTAINER_NAME \
  -v $PWD:/workspace:ro,Z \
  -e APP_DIR=$APP_DIR \
  -e IS_PR=$IS_PR \
  -e CI_ROOT=$CI_ROOT \
  -e NODE_BUILD_VERSION=$NODE_BUILD_VERSION \
  -e SERVER_NAME=$SERVER_NAME \
  -e INCLUDE_CHROME_CONFIG \
  -e CHROME_CONFIG_BRANCH \
  quay.io/cloudservices/frontend-build-container:3cfd142
TEST_RESULT=$?

if [ $TEST_RESULT -ne 0 ]; then
  echo "Test failure observed; aborting"
  exit 1
fi

# Extract files needed to build contianer
mkdir -p $WORKSPACE/build
docker cp $CONTAINER_NAME:/container_workspace/ $WORKSPACE/build
cd $WORKSPACE/build/container_workspace/ && export APP_ROOT="$WORKSPACE/build/container_workspace/"


if [ $APP_NAME == "chrome" ] ; then
  get_chrome_config;
fi

docker build -t "${IMAGE}:${IMAGE_TAG}-single" $APP_ROOT -f $APP_ROOT/Dockerfile

# Get the history
getHistory

docker build -t "${IMAGE}:${IMAGE_TAG}" $APP_ROOT -f $APP_ROOT/Dockerfile

# Cleanup
teardown_docker
