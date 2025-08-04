#!/bin/bash

kubectl create serviceaccount developer

kubectl apply -f role.yaml
kubectl apply -f rolebinding.yaml
