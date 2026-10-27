# Database for service `${NAME}`: role and database `${PG}` in cluster main;
# credentials as Secret `postgres` in namespace `${NAME}` (keys: host, port, dbname, username, password, uri).
# Dropped with the service (reclaim policies below); CI requires label drop-data for that.
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ${NAME}-password
  namespace: postgres
spec:
  refreshPolicy: CreatedOnce # generated once; Periodic would rotate it under running services
  target:
    name: ${NAME}-password
    template:
      type: kubernetes.io/basic-auth
      metadata:
        labels:
          cnpg.io/reload: "true"
      data:
        username: ${PG}
        password: "{{ .password }}"
  dataFrom:
    - sourceRef:
        generatorRef:
          apiVersion: generators.external-secrets.io/v1alpha1
          kind: Password
          name: db-password
---
apiVersion: postgresql.cnpg.io/v1
kind: DatabaseRole
metadata:
  name: ${NAME}
  namespace: postgres
spec:
  cluster:
    name: main
  name: ${PG}
  login: true
  passwordSecret:
    name: ${NAME}-password
  databaseRoleReclaimPolicy: delete
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: ${NAME}
  namespace: postgres
spec:
  cluster:
    name: main
  name: ${PG}
  owner: ${PG}
  databaseReclaimPolicy: delete
---
# Lands in namespace ${NAME} whenever it exists; no ordering with the service deploy.
apiVersion: external-secrets.io/v1
kind: ClusterExternalSecret
metadata:
  name: ${NAME}-postgres
spec:
  namespaceSelectors:
    - matchLabels:
        kubernetes.io/metadata.name: ${NAME}
  refreshTime: 1m
  externalSecretSpec:
    refreshInterval: 1h
    secretStoreRef:
      kind: ClusterSecretStore
      name: postgres
    target:
      name: postgres
      template:
        data:
          host: main-rw.postgres.svc
          port: "5432"
          dbname: ${PG}
          username: "{{ .username }}"
          password: "{{ .password }}"
          uri: "postgresql://{{ .username }}:{{ .password }}@main-rw.postgres.svc:5432/${PG}"
    dataFrom:
      - extract:
          key: ${NAME}-password
