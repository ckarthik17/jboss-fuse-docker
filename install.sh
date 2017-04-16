#!/bin/bash
#
# We configure the distro, here before it gets imported into docker
# to reduce the number of UFS layers that are needed for the Docker container.
#        
# Adjust the following env vars if needed.
FUSE_ARTIFACT_ID=jboss-fuse-full
FUSE_DISTRO_URL=http://origin-repository.jboss.org/nexus/content/groups/ea/org/jboss/fuse/${FUSE_ARTIFACT_ID}/${FUSE_VERSION}/${FUSE_ARTIFACT_ID}-${FUSE_VERSION}.zip
# Lets fail fast if any command in this script does succeed.
set -e
#
# Lets switch to the /opt/jboss dir
#
cd /opt/jboss
# Download and extract the distro
#curl -O ${FUSE_DISTRO_URL}
jar -xvf ${FUSE_ARTIFACT_ID}-${FUSE_VERSION}.zip
rm ${FUSE_ARTIFACT_ID}-${FUSE_VERSION}.zip
mv jboss-fuse-${FUSE_VERSION} jboss-fuse
chmod a+x jboss-fuse/bin/*
#rm jboss-fuse/bin/*.bat jboss-fuse/bin/start jboss-fuse/bin/stop jboss-fuse/bin/status jboss-fuse/bin/patch
# Lets remove some bits of the distro which just add extra weight in a docker image.
rm -rf jboss-fuse/extras
rm -rf jboss-fuse/quickstarts                                                                              
#
# Let the karaf container name/id come from setting the FUSE_KARAF_NAME && FUSE_RUNTIME_ID env vars
# default to using the container hostname.
#sed -i -e 's/environment.prefix=FABRIC8_/environment.prefix=FUSE_/' jboss-fuse/etc/system.properties
#sed -i -e '/karaf.name = root/d' jboss-fuse/etc/system.properties
#sed -i -e '/runtime.id=/d' jboss-fuse/etc/system.properties
echo '
if [ -z "$FUSE_KARAF_NAME" ]; then 
  export FUSE_KARAF_NAME="root"
fi
if [ -z "$FUSE_RUNTIME_ID" ]; then 
  export FUSE_RUNTIME_ID="$FUSE_KARAF_NAME"
fi          
export KARAF_OPTS="-Dkaraf.name=${FUSE_KARAF_NAME} -Druntime.id=${FUSE_RUNTIME_ID}"

JAVA_MIN_MEM=1024M # Minimum memory for the JVM
JAVA_MAX_MEM=2048M # Maximum memory for the JVM
export JAVA_MIN_MEM
export JAVA_MAX_MEM
'>> jboss-fuse/bin/setenv   
#
# Move the bundle cache and tmp directories outside of the data dir so it's not persisted between container runs
#
mv jboss-fuse/data/tmp jboss-fuse/tmp
echo '
org.osgi.framework.storage=${karaf.base}/tmp/cache
'>> jboss-fuse/etc/config.properties
sed -i -e 's/-Djava.io.tmpdir="$KARAF_DATA\/tmp"/-Djava.io.tmpdir="$KARAF_BASE\/tmp"/' jboss-fuse/bin/karaf
sed -i -e 's/-Djava.io.tmpdir="$KARAF_DATA\/tmp"/-Djava.io.tmpdir="$KARAF_BASE\/tmp"/' jboss-fuse/bin/fuse
sed -i -e 's/-Djava.io.tmpdir="$KARAF_DATA\/tmp"/-Djava.io.tmpdir="$KARAF_BASE\/tmp"/' jboss-fuse/bin/client
sed -i -e 's/-Djava.io.tmpdir="$KARAF_DATA\/tmp"/-Djava.io.tmpdir="$KARAF_BASE\/tmp"/' jboss-fuse/bin/admin
sed -i -e 's/${karaf.data}\/generated-bundles/${karaf.base}\/tmp\/generated-bundles/' jboss-fuse/etc/org.apache.felix.fileinstall-deploy.cfg

# lets remove the karaf.delay.console=true to disable the progress bar
sed -i -e 's/karaf.delay.console=true/karaf.delay.console=false/' jboss-fuse/etc/config.properties 
echo '
# Root logger
log4j.rootLogger=INFO, stdout, osgi:*VmLogAppender
log4j.throwableRenderer=org.apache.log4j.OsgiThrowableRenderer

# CONSOLE appender not used by default
log4j.appender.stdout=org.apache.log4j.ConsoleAppender
log4j.appender.stdout.layout=org.apache.log4j.PatternLayout
log4j.appender.stdout.layout.ConversionPattern=%d{ABSOLUTE} | %-5.5p | %-16.16t | %-32.32c{1} | %X{bundle.id} - %X{bundle.name} - %X{bundle.version} | %m%n
' > jboss-fuse/etc/org.ops4j.pax.logging.cfg

echo '
bind.address=0.0.0.0
'>> jboss-fuse/etc/system.properties
echo 'admin=admin,Operator, Maintainer, Deployer, Auditor, Administrator, SuperUser' >> jboss-fuse/etc/users.properties

cd /opt/jboss/jboss-fuse
./bin/fuse server &
echo '------------ Going to sleep...'
sleep 30
echo '------------ Back from sleep. Going to create fabric'
./bin/client -r 2 -d 20 -u admin -p admin "fabric:create --clean --resolver manualip --manual-ip 127.0.0.1 --wait-for-provisioning"
./bin/client -r 10 -d 20 -u admin -p admin "fabric:wait-for-provisioning"
#echo 'Going to create child containers...'
#./bin/client -u admin -p admin 'fabric:container-create-child root gateway'
#./bin/client -u admin -p admin 'fabric:container-create-child root sample'
echo '------------ Stopping the fuse server...'
./bin/stop
sleep 10
echo '------------ Done'

rm /opt/jboss/install.sh