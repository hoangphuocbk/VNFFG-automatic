#!/bin/bash

network_name='k8s-pod-net'
net_id=$(openstack network list | grep $network_name | awk '{print $2}')

# Set dhcp for pod subnet
openstack subnet set --dhcp $network_name

# Create 
echo "Create http_client and http_server" servers
echo "Create HTTP client..."
openstack server create --flavor m1.tiny --image cirros-0.3.5-x86_64-disk --nic net-id=$net_id http_client
echo "Create HTTP server..."
openstack server create --flavor m1.tiny --image cirros-0.3.5-x86_64-disk --nic net-id=$net_id --user-data launchHTTPserver.sh http_server

sleep 10

echo "Collect information from client and server"
client_ip=$(openstack server list | grep http_client | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
echo "HTTP client IP address: $client_ip"
network_source_port_id=$(openstack port list | grep $client_ip | awk '{print $2}')
echo "HTTP client port id: $network_source_port_id"
ip_dst=$(openstack server list | grep http_server | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
echo "HTTP server IP address: $ip_dst"
network_dest_port_id=$(openstack port list | grep $ip_dst | awk '{print $2}')
echo "HTTP port id: $network_dest_port_id"

echo "Create VNFFGD1 descriptor..."

cat > tosca-vnffgd-sample.yaml << EOL
tosca_definitions_version: tosca_simple_profile_for_nfv_1_0_0

description: Sample VNFFG template

topology_template:

  node_templates:

    Forwarding_path1:
      type: tosca.nodes.nfv.FP.TackerV2
      description: creates path (CP12->CP22)
      properties:
        id: 51
        policy:
          type: ACL
          criteria:
            - name: block_tcp
              classifier:
                network_src_port_id: ${network_source_port_id}
                ip_proto: 6
                destination_port_range: 80-80
                ip_dst_prefix: ${ip_dst}/26
        path:
          - forwarder: VNFD1
            capability: CP11
          - forwarder: VNFD2
            capability: CP21

  groups:
    VNFFG1:
      type: tosca.groups.nfv.VNFFG
      description: HTTP to Corporate Net
      properties:
        vendor: tacker
        version: 1.0
        number_of_endpoints: 2
        dependent_virtual_link: [VL11,VL21]
        connection_point: [CP11,CP21]
        constituent_vnfs: [VNFD1,VNFD2]
      members: [Forwarding_path1]

EOL

echo "Create VIMs..."
cat > vim_config.yaml << EOL
auth_url: 'http://127.0.0.1/identity'
username: 'admin'
password: 'devstack'
project_name: 'admin'
project_domain_name: 'Default'
user_domain_name: 'Default'
EOL

tacker vim-register --config-file vim_config.yaml --is-default VIM1
openstack_vim_id=$(tacker vim-list | grep VIM1 | awk '{print $2}')

cat > vim_kubernetes.yaml << EOL
auth_url: "https://192.168.10.222:6443"
username: "admin"
password: "admin"
project_name: "default"
openstack_vim_id: $openstack_vim_id
type: "kubernetes"
EOL

tacker vim-register --config-file vim_kubernetes.yaml VIM0

echo "Create container based VNFD file"
cat > tosca-vnfd-containerized-nosvc.yaml << EOL
tosca_definitions_version: tosca_simple_profile_for_nfv_1_0_0
description: A sample containerized VNF with one container per VDU

metadata:
    template_name: sample-tosca-vnfd

topology_template:
  node_templates:
    VDU1:
      type: tosca.nodes.nfv.VDU.Tacker
      properties:
        namespace: default
        vnfcs:
          web_server:
            num_cpus: 0.2
            mem_size: 100 MB
            image: hoangphuocbk/fw-container
            config: |
              param0: key1
              param1: key2
    CP11:
      type: tosca.nodes.nfv.CP.Tacker
      properties:
        management: true
      requirements:
        - virtualLink:
            node: VL11
        - virtualBinding:
            node: VDU1
    VL11:
      type: tosca.nodes.nfv.VL
      properties:
        network_name: k8s-pod-subnet
        vendor: Tacker

EOL

echo "Create VM based VNFD file"
cat > tosca-vnffg-vnfd2.yaml << EOL
tosca_definitions_version: tosca_simple_profile_for_nfv_1_0_0

description: Demo example

metadata:
  template_name: sample-tosca-vnfd1

topology_template:
  node_templates:
    VDU1:
      type: tosca.nodes.nfv.VDU.Tacker
      capabilities:
        nfv_compute:
          properties:
            num_cpus: 1
            mem_size: 512 MB
            disk_size: 1 GB
      properties:
        image: cirros-0.3.5-x86_64-disk
        availability_zone: nova
        mgmt_driver: noop
        config: |
          param0: key1
          param1: key2
        user_data_format: RAW
        user_data: |
          #!/bin/sh
          echo 1 > /proc/sys/net/ipv4/ip_forward
    CP21:
      type: tosca.nodes.nfv.CP.Tacker
      properties:
        management: true
        order: 0
        anti_spoofing_protection: false
      requirements:
        - virtualLink:
            node: VL21
        - virtualBinding:
            node: VDU1

    VL21:
      type: tosca.nodes.nfv.VL
      properties:
        network_name: k8s-pod-net
        vendor: Tacker

EOL

tacker vnfd-create --vnfd-file tosca-vnfd-containerized-nosvc.yaml VNFD1
tacker vnf-create --vnfd-name VNFD1 --vim-name VIM0 VNF1
tacker vnfd-create --vnfd-file tosca-vnffg-vnfd2.yaml VNFD2
tacker vnf-create --vnfd-name VNFD2 VNF2

echo "Waiting VNF is launched completely..."
while true; do
	COUNT=0
	STATUS_VNF1=$(tacker vnf-list | grep VNF1 | awk '{print $9}')
	STATUS_VNF2=$(tacker vnf-list | grep VNF2 | awk '{print $9}')
	if [ "$STATUS_VNF1" = "ACTIVE" ]; then
		COUNT=$[$COUNT + 1]
	fi
	if [ "$STATUS_VNF2" = "ACTIVE" ]; then
		COUNT=$[$COUNT + 1]
	fi
	if [ "$COUNT" -eq 2 ]; then
		echo "VNFs were launched completely!"
		break
	else
		echo "Waiting for 5 seconds"
		sleep 5
	fi
done

echo "Create VNFFG..."
tacker vnffgd-create --vnffgd-file tosca-vnffgd-sample.yaml VNFFGD1
tacker vnffg-create --vnffgd-name VNFFGD1 VNFFG1

echo "Congratz :). Work done!"

