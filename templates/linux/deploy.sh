#!/bin/bash

# utilities
gyp_rebuild_inside_node_modules () {
  for npmModule in ./*; do
    cd $npmModule

    isBinaryModule="no"
    # recursively rebuild npm modules inside node_modules
    check_for_binary_modules () {
      if [ -f binding.gyp ]; then
        isBinaryModule="yes"
      fi

      if [ $isBinaryModule != "yes" ]; then
        if [ -d ./node_modules ]; then
          cd ./node_modules
          for module in ./*; do
            cd $module
            check_for_binary_modules
            cd ..
          done
          cd ../
        fi
      fi
    }

    check_for_binary_modules

    if [ $isBinaryModule = "yes" ]; then
      echo " > $npmModule: npm install due to binary npm modules"
      rm -rf node_modules
      if [ -f binding.gyp ]; then
        sudo npm install
        sudo node-gyp rebuild || :
      else
        sudo npm install
      fi
    fi

    cd ..
  done
}

rebuild_binary_npm_modules () {
  for package in ./*; do
    if [ -d $package/node_modules ]; then
      cd $package/node_modules
        gyp_rebuild_inside_node_modules
      cd ../../
    elif [ -d $package/main/node_module ]; then
      cd $package/node_modules
        gyp_rebuild_inside_node_modules
      cd ../../../
    fi
  done
}

revert_app (){
  date
  if [[ -d old_app ]]; then
    sudo rm -rf app
    sudo mv old_app app
    sudo stop <%= appName %> || :
    sudo start <%= appName %> || :

    echo "Latest deployment failed! Reverted back to the previous version." 1>&2
    exit 1
  else
    echo "App did not pick up! Please check app logs." 1>&2
    exit 1
  fi
}


# logic
set -e

date
TMP_DIR=/opt/<%= appName %>/tmp
date
BUNDLE_DIR=${TMP_DIR}/bundle

date
cd ${TMP_DIR}
sudo rm -rf bundle
sudo tar xvzf bundle.tar.gz > /dev/null
sudo chmod -R +x *
sudo chown -R ${USER} ${BUNDLE_DIR}

# rebuilding fibers
date
cd ${BUNDLE_DIR}/programs/server

date
if [ -d ./npm ]; then
  cd npm
  time rebuild_binary_npm_modules
  cd ../
fi

date
if [ -d ./node_modules ]; then
  cd ./node_modules
  time gyp_rebuild_inside_node_modules
  cd ../
fi

date
if [ -f package.json ]; then
  # support for 0.9
  time sudo npm install
else
  # support for older versions
  time sudo npm install fibers
  time sudo npm install bcrypt
fi

date
cd /opt/<%= appName %>/

# remove old app, if it exists
if [ -d old_app ]; then
  sudo rm -rf old_app
fi

## backup current version
if [[ -d app ]]; then
  sudo mv app old_app
fi

sudo mv tmp/bundle app

#wait and check
date
echo "Waiting for MongoDB to initialize. (5 minutes)"
time . /opt/<%= appName %>/config/env.sh
wait-for-mongo ${MONGO_URL} 300000

# restart app
date
echo "Stopping app"
sudo stop <%= appName %> || :
date
echo "Starting app"
sudo start <%= appName %> || :

echo "Waiting for <%= deployCheckWaitTime %> seconds while app is booting up"
WAIT_UNTIL_SECS=$(date +%s)
CURL_RV=0
(( WAIT_UNTIL_SECS = WAIT_UNTIL_SECS + <%= deployCheckWaitTime %> ))
while [[ $WAIT_UNTIL_SECS -gt $(date +%s) ]]; do
    echo "Checking if app is alive: $(date +%s) / ${WAIT_UNTIL_SECS}"
    curl -o /dev/null --max-time 1 localhost:${PORT} | true
    CURL_RV=${PIPESTATUS[0]}
    if [[ ${CURL_RV} = 0 ]]; then
        # No longer need to wait
        CURL_RV=1
        break
    else
        echo "  No, it is not: ${CURL_RV}"
        sleep 1
    fi
done

# One last check
if [[ $CURL_RV = 0 ]]; then
    echo "Checking is app booted or not?"
    curl localhost:${PORT} || revert_app
fi

# chown to support dumping heapdump and etc
sudo chown -R meteoruser app
