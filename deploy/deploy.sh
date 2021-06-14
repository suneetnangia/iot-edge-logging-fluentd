# Script to create environment for push model logging.
if [ -z "$1" ] ; then
  echo "A new resource group name is required." && exit 1;
fi

if [ -z "$2" ] ; then
  echo "SSH public key is required for the edge vm ssh connection." && exit 2;
fi

resourceGroup=$1
sshPublicKey=$2
location="eastus"

# Create resource group.
az deployment sub create --name $resourceGroup --template-file ./resourceGroup.json --location=$location --parameters rgLocation=$location rgName=$resourceGroup

# Create IoT Hub
iotHubOutputs=$(az deployment group create -g $resourceGroup --template-file ./iotHub.json --query properties.outputs)
iotHubName=$(jq -r .iotHubName.value <<< $iotHubOutputs)

# Create Log Analytics Workspace
logAnalyticsOutputs=$(az deployment group create -g $resourceGroup --template-file ./logAnalytics.json --query properties.outputs)
logAnalyticsCustomerId=$(jq -r .logAnalyticsCustomerId.value <<< $logAnalyticsOutputs)
logAnalyticsKey=$(jq -r .logAnalyticsKey.value <<< $logAnalyticsOutputs)

# TODO: Make this idempotent so reruns are not errored if device exists.
# Create Edge Device
az iot hub device-identity create --hub-name $iotHubName --device-id edgeDevice --edge-enabled

# TODO: Make this idempotent so reruns are not errored if deployment exists.
# Deploy edge device manifest with createOptions for log driver.
az iot edge deployment create -d edgeDeviceDeployment  -n $iotHubName  --content ./edgedeploymentmanifest.json --target-condition "deviceid='edgeDevice'"

# # Create edge device VM
vmOutputs=$(az deployment group create \
--resource-group $resourceGroup \
--template-file "./edgeVM.json" \
--parameters adminUsername='vmadmin' \
--parameters deviceConnectionString=$(az iot hub device-identity connection-string show --device-id edgeDevice --hub-name  $iotHubName -o tsv) \
--parameters logAnalyticsWorkspaceId=$logAnalyticsCustomerId \
--parameters logAnalyticsWorkspaceKey=$logAnalyticsKey \
--parameters authenticationType='sshPublicKey' \
--parameters adminPasswordOrKey="$sshPublicKey" \
--query properties.outputs)

echo "---------------To connect to edge vm, please use the following---------------"
echo $(jq -r .publicSSH.value <<< $vmOutputs)