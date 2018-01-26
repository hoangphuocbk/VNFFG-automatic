#!/bin/bash

echo "Cleaning VNFFG resources..."

echo "Terminating VNFFG..."
tacker vnffg-delete VNFFG1

echo "Deleting VNFFG descriptor..."
tacker vnffgd-delete VNFFGD1

echo "Terminating VNFs..."
tacker vnf-delete VNF1 VNF2

echo "Deleting VNF descriptors..."
tacker vnfd-delete VNFD1 VNFD2

echo "Terminating HTTP client and HTTP server"
openstack server delete http_client http_server

echo "Deleting VNFFGD file..."
rm tosca-vnffgd-legacy-sample.yaml

echo "Done :)"
