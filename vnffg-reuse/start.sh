#!/bin/bash

network_name='net0'
net_id=$(openstack network list | grep $network_name | awk '{print $2}')

echo "Create http_client and http_server" servers
echo "Create HTTP client..."
openstack server create --flavor m1.tiny --image cirros-0.3.5-x86_64-disk --nic net-id=$net_id http_client
echo "Create HTTP server..."
openstack server create --flavor m1.tiny --image cirros-0.3.5-x86_64-disk --nic net-id=$net_id http_server

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

echo "Create VNFFGD1 descriptor VNF1-VNF2..."

cat > vnffgd-VNF1-VNF2.yaml << EOL
tosca_definitions_version: tosca_simple_profile_for_nfv_1_0_0

description: Sample VNFFG template

topology_template:
  description: Sample VNFFG template

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
                destination_port_range: 20-30
                ip_proto: 6
                ip_dst_prefix: ${ip_dst}/24
        path:
          - forwarder: VNFD1
            capability: CP12
          - forwarder: VNFD2
            capability: CP22

  groups:
    VNFFG1:
      type: tosca.groups.nfv.VNFFG
      description: HTTP to Corporate Net
      properties:
        vendor: tacker
        version: 1.0
        number_of_endpoints: 2
        dependent_virtual_link: [VL12,VL22]
        connection_point: [CP12,CP22]
        constituent_vnfs: [VNFD1,VNFD2]
      members: [Forwarding_path1]
EOL

echo "Create VNFFGD2 descriptor VNF2-VNF1..."

cat > vnffgd-VNF2-VNF1.yaml << EOL
tosca_definitions_version: tosca_simple_profile_for_nfv_1_0_0

description: Sample VNFFG template

topology_template:
  description: Sample VNFFG template

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
                destination_port_range: 40-50
                ip_proto: 6
                ip_dst_prefix: ${ip_dst}/24
        path:
          - forwarder: VNFD2
            capability: CP22
          - forwarder: VNFD1
            capability: CP12

  groups:
    VNFFG1:
      type: tosca.groups.nfv.VNFFG
      description: HTTP to Corporate Net
      properties:
        vendor: tacker
        version: 1.0
        number_of_endpoints: 2
        dependent_virtual_link: [VL22,VL12]
        connection_point: [CP22,CP12]
        constituent_vnfs: [VNFD2,VNFD1]
      members: [Forwarding_path1]
EOL


echo "Create VNFFGD1 descriptor VNF2..."

cat > vnffgd-VNF2.yaml << EOL
tosca_definitions_version: tosca_simple_profile_for_nfv_1_0_0

description: Sample VNFFG template

topology_template:
  description: Sample VNFFG template

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
                destination_port_range: 80-80
                ip_proto: 6
                ip_dst_prefix: ${ip_dst}/24
        path:
          - forwarder: VNFD2
            capability: CP22

  groups:
    VNFFG1:
      type: tosca.groups.nfv.VNFFG
      description: HTTP to Corporate Net
      properties:
        vendor: tacker
        version: 1.0
        number_of_endpoints: 1
        dependent_virtual_link: [VL22]
        connection_point: [CP22]
        constituent_vnfs: [VNFD2]
      members: [Forwarding_path1]
EOL

#echo "On-board VNFFG descriptor..."
tacker vnffgd-create --vnffgd-file vnffgd-VNF1-VNF2.yaml VNFFGD1
tacker vnffgd-create --vnffgd-file vnffgd-VNF2-VNF1.yaml VNFFGD2
tacker vnffgd-create --vnffgd-file vnffgd-VNF2.yaml VNFFGD3

echo "On-board VNFDs..."
tacker vnfd-create --vnfd-file tosca-vnffg-vnfd1.yaml VNFD1
tacker vnfd-create --vnfd-file tosca-vnffg-vnfd2.yaml VNFD2

echo "Create VNFs..."
tacker vnf-create --vnfd-name VNFD1 VNF1
tacker vnf-create --vnfd-name VNFD2 VNF2

sleep 15

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
tacker vnffg-create --vnffgd-name VNFFGD1 VNFFG1
tacker vnffg-create --vnffgd-name VNFFGD2 VNFFG2
tacker vnffg-create --vnffgd-name VNFFGD3 VNFFG3

sleep 5
neutron port-chain-list --fit-width
