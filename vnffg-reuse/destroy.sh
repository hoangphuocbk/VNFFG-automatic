#!/bin/bash


tacker vnffg-delete VNFFG1 VNFFG2 VNFFG3

echo "Deleting VNFFG descriptor..."
tacker vnffgd-delete VNFFGD1 VNFFGD2 VNFFGD3

echo "Terminating VNFs..."
tacker vnf-delete VNF1 VNF2

echo "Deleting VNF descriptors..."
tacker vnfd-delete VNFD1 VNFD2

echo "Terminating HTTP client and HTTP server"
openstack server delete http_client http_server

echo "Deleting VNFFGD file..."
rm vnffgd-VNF1-VNF2.yaml vnffgd-VNF2-VNF1.yaml vnffgd-VNF2.yaml

echo "Done :)"
