# RabbitMQ user for service `${NAME}` (generated username) in vhost alterworld: configure/write `${NAME}.*`, read own + `*.events`;
# credentials as Secret `rabbitmq` in namespace `${NAME}` (keys: host, port, vhost, username, password, uri).
apiVersion: rabbitmq.com/v1beta1
kind: User
metadata:
  name: ${NAME}
  namespace: rabbitmq
# The operator generates username and password into Secret ${NAME}-user-credentials.
# (importCredentialsSecret would need the Secret before the webhook admits the User.)
spec:
  rabbitmqClusterReference:
    name: main
---
apiVersion: rabbitmq.com/v1beta1
kind: Permission
metadata:
  name: ${NAME}
  namespace: rabbitmq
spec:
  vhost: alterworld
  userReference:
    name: ${NAME}
  permissions:
    configure: '^${NAME}\.'
    write: '^${NAME}\.'
    read: '^(${NAME}\..*|.*\.events)$'
  rabbitmqClusterReference:
    name: main
---
# Lands in namespace ${NAME} whenever it exists; no ordering with the service deploy.
apiVersion: external-secrets.io/v1
kind: ClusterExternalSecret
metadata:
  name: ${NAME}-rabbitmq
spec:
  namespaceSelectors:
    - matchLabels:
        kubernetes.io/metadata.name: ${NAME}
  refreshTime: 1m
  externalSecretSpec:
    refreshInterval: 1h
    secretStoreRef:
      kind: ClusterSecretStore
      name: rabbitmq
    target:
      name: rabbitmq
      template:
        data:
          host: main.rabbitmq.svc
          port: "5672"
          vhost: alterworld
          username: "{{ .username }}"
          password: "{{ .password }}"
          uri: "amqp://{{ .username }}:{{ .password }}@main.rabbitmq.svc:5672/alterworld"
    dataFrom:
      - extract:
          key: ${NAME}-user-credentials
