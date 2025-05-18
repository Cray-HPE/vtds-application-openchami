export emulator_username=root
export emulator_password=root_password
export PATH=$PATH:/
export MASTER_KEY=$(magellan secrets generatekey)
magellan scan --subnet 172.25.0.0/24
magellan list
cd /tmp/nobody/magellan
magellan list | awk '{print $1}' | xargs -I{} magellan secrets store {} $emulator_username:$emulator_password
magellan secrets list
magellan secrets list | awk '{print $1}' | sed -e 's/:$//' | xargs -I{} magellan secrets retrieve {}
export ACCESS_TOKEN=$(curl -s -X GET http://opaal:3333/token | sed 's/.*"access_token":"\([^"]*\).*/\1/')
magellan collect --host http://smd:27779 --access-token "$ACCESS_TOKEN"
