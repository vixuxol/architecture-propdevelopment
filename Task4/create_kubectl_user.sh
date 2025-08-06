#!/bin/bash

set -ex;

# проверка аргументов (основной - 1 - это имя пользователя)
if [ "$#" -lt 1 ]; then
    echo "Использование: $0 <USER_NAME> [KUBERNETES_CLUSTER_NAME] [ROLE_LIST]"
    echo "Пример: $0 newuser"
    exit 1
fi

# настройка переменных для дальнейшей работы
USER_NAME="$1"
KUBERNETES_CLUSTER_NAME="${2:-minikube}"
ROLE_LIST="${3:-view-only}"
NAMESPACE="default"

echo "Starting to create user with USER_NAME=$USER_NAME in NAMESPACE=$NAMESPACE and KUBERNETES_CLUSTER_NAME=$KUBERNETES_CLUSTER_NAME using roles=$ROLE_LIST"

# Генерация приватного ключа пользователя
openssl genrsa -out "${USER_NAME}.key" 2048

# Создание запроса на сертификат (CSR)
openssl req -new -key "${USER_NAME}.key" -out "${USER_NAME}.csr" -subj "/CN=${USER_NAME}"

# кодирование .csr файла перед отправкой на сервер:
cat "${USER_NAME}.csr" | base64 | tr -d "\n" > "${USER_NAME}-base64.csr"

# Подписывание CSR с использованием CA Kubernetes
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
    name: ${USER_NAME}
spec:
    groups:
    - system:authenticated  
    request: $(cat ${USER_NAME}-base64.csr)
    signerName: kubernetes.io/kube-apiserver-client
    expirationSeconds: 864000  # ten days
    usages:
    - client auth
EOF
kubectl certificate approve "$USER_NAME"
kubectl get certificatesigningrequests "$USER_NAME" -o jsonpath='{ .status.certificate }' | base64 --decode > "${USER_NAME}.crt"

# Создание файла конфига для пользователя
kubectl config set-credentials "${USER_NAME}" --client-key="${USER_NAME}.key" --client-certificate="${USER_NAME}.crt" --embed-certs=true --kubeconfig="${USER_NAME}.conf"
kubectl config set-context "${USER_NAME}@${KUBERNETES_CLUSTER_NAME}" --cluster="${KUBERNETES_CLUSTER_NAME}" --user="${USER_NAME}"--kubeconfig="${USER_NAME}.conf" --namespace="${NAMESPACE}"


# Применение списка ролей
IFS=',' read -ra ROLES <<< "$ROLE_LIST"
for role in "${ROLES[@]}"; do
    role_file="${role}.yaml"
    if [ -f "$role_file" ]; then
        kubectl apply -f "$role_file"
        kubectl create rolebinding "${USER_NAME}-${role}-rolebinding" --role="$role" --user="$USER_NAME" --namespace "$NAMESPACE"
    else
        echo "Файл $role_file не найден!"
        exit 1
    fi
done

echo "Пользователь ${USER_NAME} создан и добавлен в контекст kubeconfig."