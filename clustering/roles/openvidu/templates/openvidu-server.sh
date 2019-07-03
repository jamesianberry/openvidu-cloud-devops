#!/bin/bash

# This script will launch OpenVidu Server on your machine

OV_PROPERTIES="/opt/openvidu/application.properties"

{% if whichcert == "letsencrypt" or whichcert == "owncert" %}
PUBLIC_HOSTNAME={{ domain_name }}
{% else %}
{% if run_ec2 == true %}
PUBLIC_HOSTNAME=$(curl http://169.254.169.254/latest/meta-data/public-hostname)
{% else %}
PUBLIC_HOSTNAME={{ ov_public_hostname }}
{% endif %}
{% endif %}

# Wait for kibana
while true
do 
  HTTP_STATUS=$(curl -I http://localhost:5601/app/kibana | head -n1 | awk '{print $2}')
  if [ $HTTP_STATUS == 200 ]; then
    break
  fi
  sleep 1
done

OPENVIDU_OPTIONS+="-Dopenvidu.publicurl=https://${PUBLIC_HOSTNAME}:{{ openvidu_port }} "
OPENVIDU_OPTIONS+="-DMY_UID=$(id -u $USER) "
OPENVIDU_OPTIONS+="-Dopenvidu.recording.composed-url=https://${PUBLIC_HOSTNAME}/inspector/ "

HEADERS="{{ webhook_headers }}"
if [ "x${HEADERS}" != "x" ]; then
	H=$(echo ${HEADERS} | sed -e 's/[^a-zA-Z0-9,._+@%/-]/\\&/g; 1{$s/^$/""/}; 1!s/^/"/; $!s/$/"/')
	OPENVIDU_HEADERS="openvidu.webhook.headers=[\\\"${H}\\\"] "
	if ! grep -Fq "openvidu.webhook.headers" ${OV_PROPERTIES}
	then
		echo ${OPENVIDU_HEADERS} >> ${OV_PROPERTIES}
	fi
fi

EVENTS_LIST=$(echo {{ webhook_events }} | tr , ' ')
if [ "x$EVENTS_LIST" != "x" ]; then
	E=$(for EVENT in ${EVENTS_LIST}
	do
		echo $EVENT | awk '{ print "\"" $1 "\"" }'
	done
	)
	EVENTS=$(echo $E | tr ' ' ,)
	if ! grep -Fq "openvidu.webhook.events" ${OV_PROPERTIES}
	then
		echo "openvidu.webhook.events=[${EVENTS}]" >> ${OV_PROPERTIES}
	fi
fi

{% if run_ec2 == true %}
export AWS_DEFAULT_REGION={{ aws_default_region }}
KMS_IPs=$(aws ec2 describe-instances --query 'Reservations[].Instances[].[PrivateIpAddress]' --output text --filters Name=instance-state-name,Values=running Name=tag:ov-cluster-member,Values=kms)
{% else %}
KMS_IPs=$(echo {{ kms_endpoint_ips }} | tr , ' ')
{% endif %}
KMS_ENDPOINTS=$(for IP in $KMS_IPs
do
  echo $IP | awk '{ print "\"ws://" $1 ":8888/kurento\"" }'
done
)
KMS_ENDPOINTS_LINE=$(echo $KMS_ENDPOINTS | tr ' ' ,)
OPENVIDU_OPTIONS+="-Dkms.uris=[${KMS_ENDPOINTS_LINE}] "

# Wait for KMS
for IP in ${KMS_IPs}
do
	while ! nc -z $IP 8888; do
		echo "Waiting for Kurento Media Server (${IP}) to be available"
    	sleep 10
    done
done

pushd /opt/openvidu
exec java -jar ${OPENVIDU_OPTIONS} -Dspring.config.additional-location=${OV_PROPERTIES} /opt/openvidu/openvidu-server.jar

