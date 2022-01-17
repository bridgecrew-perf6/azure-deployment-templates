#!/bin/bash

replSetName=$1
secondaryNodes=$2
mongoAdminUser=$3
mongoAdminPasswd=$4
staticIp=$5
zabbixServer=$6

install_mongo3() {

# Create repo.
cat > /etc/yum.repos.d/mongodb-org-3.2.repo <<EOF
[mongodb-org-3.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/3.2/x86_64/
gpgcheck=0
enabled=1
EOF

	# Install.
	yum install -y mongodb-org

	# Ignore update.
	sed -i '$a exclude=mongodb-org,mongodb-org-server,mongodb-org-shell,mongodb-org-mongos,mongodb-org-tools' /etc/yum.conf

	# Disable SELinux.
	sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/sysconfig/selinux
	sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
	setenforce 0

	# Kernel settings.
	if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]];then
		echo never > /sys/kernel/mm/transparent_hugepage/enabled
	fi
	if [[ -f /sys/kernel/mm/transparent_hugepage/defrag ]];then
		echo never > /sys/kernel/mm/transparent_hugepage/defrag
	fi

	# Configure.
	sed -i 's/\(bindIp\)/#\1/' /etc/mongod.conf
}

disk_format() {
	cd /tmp
	yum install wget -y
	for ((j=1;j<=3;j++))
	do
		wget https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/shared_scripts/ubuntu/vm-disk-utils-0.1.sh
		if [[ -f /tmp/vm-disk-utils-0.1.sh ]]; then
			bash /tmp/vm-disk-utils-0.1.sh -b /var/lib/mongo -s
			if [[ $? -eq 0 ]]; then
				sed -i 's/disk1//' /etc/fstab
				umount /var/lib/mongo/disk1
				mount /dev/md0 /var/lib/mongo
			fi
			break
		else
			echo "download vm-disk-utils-0.1.sh failed. try again."
			continue
		fi
	done
}

install_zabbix() {
	# Install Zabbix agent.
	cd /tmp
	yum install -y gcc wget > /dev/null
	wget http://jaist.dl.sourceforge.net/project/zabbix/ZABBIX%20Latest%20Stable/2.2.5/zabbix-2.2.5.tar.gz > /dev/null 2>&1
	tar zxvf zabbix-2.2.5.tar.gz
	cd zabbix-2.2.5
	groupadd zabbix
	useradd zabbix -g zabbix -s /sbin/nologin
	mkdir -p /usr/local/zabbix
	./configure --prefix=/usr/local/zabbix --enable-agent
	make install > /dev/null
	cp misc/init.d/fedora/core/zabbix_agentd /etc/init.d/
	sed -i 's/BASEDIR=\/usr\/local/BASEDIR=\/usr\/local\/zabbix/g' /etc/init.d/zabbix_agentd
	sed -i '$azabbix-agent    10050/tcp\nzabbix-agent    10050/udp' /etc/services
	sed -i '/^LogFile/s/tmp/var\/log/' /usr/local/zabbix/etc/zabbix_agentd.conf
	hostName=`hostname`
	sed -i "s/^Hostname=Zabbix server/Hostname=$hostName/" /usr/local/zabbix/etc/zabbix_agentd.conf
	if [[ $zabbixServer =~ ([0-9]{1,3}.){3}[0-9]{1,3} ]];then
		sed -i "s/^Server=127.0.0.1/Server=$zabbixServer/" /usr/local/zabbix/etc/zabbix_agentd.conf
		sed -i "s/^ServerActive=127.0.0.1/ServerActive=$zabbixServer/" /usr/local/zabbix/etc/zabbix_agentd.conf
		sed -i "s/^Server=127.0.0.1/Server=$zabbixServer/" /usr/local/zabbix/etc/zabbix_agent.conf
	fi
	touch /var/log/zabbix_agentd.log
	chown zabbix:zabbix /var/log/zabbix_agentd.log

	# Start Zabbix agent.
	chkconfig --add zabbix_agentd
	chkconfig zabbix_agentd on
	/etc/init.d/zabbix_agentd start
}

install_mongo3
disk_format
install_zabbix

# Start mongod service. 
mongod --dbpath /var/lib/mongo/ --logpath /var/log/mongodb/mongod.log --fork

sleep 30
ps -ef |grep "mongod --dbpath /var/lib/mongo/" | grep -v grep
n=$(ps -ef |grep "mongod --dbpath /var/lib/mongo/" | grep -v grep |wc -l)
echo "the number of mongod process is: $n"
if [[ $n -eq 1 ]];then
    echo "mongod started successfully"
else
    echo "Error: The number of mongod processes is 2+ or mongod failed to start because of the db path issue!"
fi

# Create default users.
mongo <<EOF
use admin
db.createUser({user:"$mongoAdminUser",pwd:"$mongoAdminPasswd",roles:[{role: "userAdminAnyDatabase", db: "admin" },{role: "readWriteAnyDatabase", db: "admin" },{role: "root", db: "admin" }]})
exit
EOF
if [[ $? -eq 0 ]];then
    echo "mongo user added succeefully."
else
    echo "mongo user added failed!"
fi

# Stop mongod.
sleep 15
echo "the running mongo process id is below:"
ps -ef |grep "mongod --dbpath /var/lib/mongo/" | grep -v grep |awk '{print $2}'
MongoPid=`ps -ef |grep "mongod --dbpath /var/lib/mongo/" | grep -v grep |awk '{print $2}'`
kill -2 $MongoPid

# Set keyfile.
echo "
CtQTcxY/s8uVmnU+dQQtZ0FYUvsezaWPxzpnnc3q+vCVf2NNS27U5+127XXzjC1t
Id+wpqY5z09OVItALNQR7EbyFOPfEf3Raasn3jrzO8xnwC9JrnnpEnh4fbywXBsN
WjGoYAeLm5yX+yCkovzqY+tLAAiSbhE/r2v4hOvaWVPpAP9x4TYiwe+8KZtJQtvk
yD4p7QrARYQOnWXUwjpf5M1kEg+PwKOLkv6R9OYuIh+tyTPAPjtpb+PCrbCTfVpC
nZfl+TIEQ1YMZuwg8S/Wy8pdv9X/5Yz1MY7PD1GasG+jiRW1+jLtROBvhCmL9hfO
6L3uUR0v/NPoSxOiBDkIyxiXqwzVsW0VOo5LSGE3JY989QCg4g3pJRu5lCTsIPeZ
vQKoLayF3EXFNFCBehTbG7demoRh9bY6p/XyxtSMBbzg8zIDWpsxh43IbntvGX1+
UPqP2oGOj957GmOvWlRfo+NaWKEKXTw2yA/JfAY8N9q85tDBQ4QxZ2syG35Iw8T4
IzNz7K1fk8iAP/RoGZoGeB0pdOM1+317cfGGlZEAOi/udlmG4X+MxW7WLTHXwYke
fsfnCMik+U6Bt0sX9xHBRlIpbKZCTj1Vy2QB84oCkOg/Pcp4CNZW0FGeNC5P5b6k
ruBQQP8Ym9eCxkV8hYujalbzeaFpATxxpoaN+sW3YiaQhSPMKWp5TYT7/ywhEMS7
eF3lQ+sOV7dKqE9e+ZtWrTvX7uyplgJ3Voi3dTEqxLQG4dfEhywaML2dGcEVp2sy
NMXaaKxNDuOHU9qatN11cZaMNwKqhOpJnkxkZyfBhaeh6p0KYnHo/B7JRaGySTI0
cQUwqXjfHMjMNWatqBQWxmtfprRSE9JqiozUQumPAKwZmCApv0f+Y7lgyLXgT+iY
AjzvhPbnaDANw9NRNVumDyFLY5zo6JLSquzJaEBx2tTKu0THxpg3dK+szj8sWqsK
vlHpbHvcTlQ3/+xim8Ul69GXUi6y
" > /etc/mongokeyfile
chown mongod:mongod /etc/mongokeyfile
chmod 600 /etc/mongokeyfile
sed -i 's/^#security/security/' /etc/mongod.conf
sed -i '/^security/akeyFile: /etc/mongokeyfile' /etc/mongod.conf
sed -i 's/^keyFile/  keyFile/' /etc/mongod.conf

sleep 15
MongoPid1=`ps -ef |grep "mongod --dbpath /var/lib/mongo/" | grep -v grep |awk '{print $2}'`
if [[ -z $MongoPid1 ]];then
    echo "shutdown mongod successfully"
else
    echo "shutdown mongod failed!"
    kill $MongoPid1
    sleep 15
fi

# Restart mongod with auth and replica set.
mongod --dbpath /var/lib/mongo/ --replSet $replSetName --logpath /var/log/mongodb/mongod.log --fork --config /etc/mongod.conf

# Initiate replica set.
for((i=1;i<=3;i++))
    do
        sleep 15
        n=`ps -ef |grep "mongod --dbpath /var/lib/mongo/" | grep -v grep  |wc -l`
        if [[ $n -eq 1 ]];then
            echo "mongo replica set started successfully"
            break
        else
            mongod --dbpath /var/lib/mongo/ --replSet $replSetName --logpath /var/log/mongodb/mongod.log --fork --config /etc/mongod.conf
            continue
        fi
    done

n=`ps -ef |grep "mongod --dbpath /var/lib/mongo/" | grep -v grep  |wc -l`
if [[ $n -ne 1 ]];then
    echo "mongo replica set tried to start 3 times but failed!"
fi

echo "start initiating the replica set"
publicIp=`curl -s ip.cn|grep -Po '\d+.\d+.\d+.\d+'`
if [[ -z $publicIp ]];then
	finalIp=$staticIp
else
	finalIp=$publicIp
fi

echo "the ip address is $finalIp"

mongo<<EOF
use admin
db.auth("$mongoAdminUser", "$mongoAdminPasswd")
config ={_id:"$replSetName",members:[{_id:0,host:"$finalIp:27017"}]}
rs.initiate(config)
exit
EOF
if [[ $? -eq 0 ]];then
    echo "replica set initiation succeeded."
else
    echo "replica set initiation failed!"
fi

# Add secondary nodes.
for((i=1;i<=$secondaryNodes;i++))
    do
        let a=3+$i
        mongo -u "$mongoAdminUser" -p "$mongoAdminPasswd" "admin" --eval "printjson(rs.add('10.0.1.${a}:27017'))"
        if [[ $? -eq 0 ]];then
            echo "adding server 10.0.1.${a} successfully"
        else
            echo "adding server 10.0.1.${a} failed!"
        fi
    done

# Set mongod auto start.
cat > /etc/init.d/mongod1 <<EOF
#!/bin/bash
#chkconfig: 35 84 15
#description: mongod auto start
. /etc/init.d/functions

Name=mongod1
start() {
if [[ ! -d /var/run/mongodb ]];then
mkdir /var/run/mongodb
chown -R mongod:mongod /var/run/mongodb
fi
mongod --dbpath /var/lib/mongo/ --replSet $replSetName --logpath /var/log/mongodb/mongod.log --fork --config /etc/mongod.conf
}
stop() {
pkill mongod
}
restart() {
stop
sleep 15
start
}

case "\$1" in
    start)
	start;;
	stop)
	stop;;
	restart)
	restart;;
	status)
	status \$Name;;
	*)
	echo "Usage: service mongod1 start|stop|restart|status"
esac
EOF
chmod +x /etc/init.d/mongod1
chkconfig mongod1 on
