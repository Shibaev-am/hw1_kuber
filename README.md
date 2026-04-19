# Распределённая система логирования и хранения с резервным копированием и Istio

Kubernetes-система, которая разворачивает Flask API, балансирует нагрузку между репликами, собирает логи с узлов и автоматически архивирует их по расписанию.

## Архитектура проекта

```
.
├── app/
│   ├── app.py              # Flask REST API (4 эндпоинта)
│   ├── requirements.txt    # Зависимости (flask)
│   └── Dockerfile          # Сборка образа на базе python:3.11-slim
├── k8s/
│   ├── configmap.yaml              # Конфигурация приложения
│   ├── pod.yaml                    # Тестовый Pod
│   ├── deployment.yaml             # Deployment с 3 репликами
│   ├── service.yaml                # ClusterIP Service
│   ├── statefulset.yaml            # StatefulSet с PersistentVolumeClaim
│   ├── daemonset.yaml              # DaemonSet log-agent
│   ├── cronjob.yaml                # CronJob log-archiver
│   ├── istio-gateway.yaml          # Istio Gateway (входящий HTTP-трафик на порт 80)
│   ├── istio-virtualservice.yaml   # VirtualService (маршрутизация, 404, fault injection)
│   └── istio-destinationrule.yaml  # DestinationRule (LEAST_CONN, conn pool, mTLS)
├── deploy.sh               # Единый скрипт развёртывания всей системы
└── README.md
```

## Требования

- Docker Desktop с включённым Kubernetes
- `kubectl` (устанавливается вместе с Docker Desktop)
- `istioctl` (устанавливается автоматически скриптом `deploy.sh`, либо вручную: `curl -L https://istio.io/downloadIstio | sh -`)

## Запуск

```bash
bash deploy.sh
```

## Результат запуска deploy.sh

```
Building Docker image custom-app:latest
[+] Building 25.1s (11/11) FINISHED                                docker:desktop-linux
 => [internal] load build definition from Dockerfile
 => [internal] load metadata for docker.io/library/python:3.11-slim
 => [1/6] FROM docker.io/library/python:3.11-slim
 => [2/6] WORKDIR /app
 => [3/6] COPY requirements.txt .
 => [4/6] RUN pip install --no-cache-dir -r requirements.txt
 => [5/6] COPY app.py .
 => [6/6] RUN mkdir -p /app/logs
 => exporting to image
 => => naming to docker.io/library/custom-app:latest

Applying ConfigMap:
configmap/app-config created

Deploying initial test Pod:
pod/custom-app-pod created
Waiting for pod/custom-app-pod to be Ready...
pod/custom-app-pod condition met

Deploying Deployment with 3 replicas:
deployment.apps/custom-app created
Waiting for rollout:
Waiting for deployment "custom-app" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "custom-app" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "custom-app" rollout to finish: 2 of 3 updated replicas are available...
deployment "custom-app" successfully rolled out

Service:
service/custom-app-service created

DaemonSet log-agent:
daemonset.apps/log-agent created
Waiting for DaemonSet to be available:
Waiting for daemon set "log-agent" rollout to finish: 0 of 1 updated pods are available...
daemon set "log-agent" successfully rolled out

Deploying StatefulSet:
statefulset.apps/custom-app-stateful created
service/custom-app-stateful-headless created
Waiting for StatefulSet rollout:
Waiting for 2 pods to be ready...
Waiting for 1 pods to be ready...
partitioned roll out complete: 2 new pods have been updated...

CronJob log-archiver:
cronjob.batch/log-archiver created
```

## Проверка статуса компонентов

```
$ kubectl get pods -o wide
NAME                          READY   STATUS    RESTARTS   AGE   IP          NODE             NOMINATED NODE   READINESS GATES
custom-app-5b8db8d666-7pck7   1/1     Running   0          41s   10.1.0.8    docker-desktop   <none>           <none>
custom-app-5b8db8d666-7pnwd   1/1     Running   0          41s   10.1.0.7    docker-desktop   <none>           <none>
custom-app-5b8db8d666-l66d7   1/1     Running   0          41s   10.1.0.9    docker-desktop   <none>           <none>
custom-app-pod                1/1     Running   0          42s   10.1.0.6    docker-desktop   <none>           <none>
custom-app-stateful-0         1/1     Running   0          24s   10.1.0.11   docker-desktop   <none>           <none>
custom-app-stateful-1         1/1     Running   0          12s   10.1.0.12   docker-desktop   <none>           <none>
log-agent-597gb               1/1     Running   0          29s   10.1.0.10   docker-desktop   <none>           <none>

$ kubectl get services
NAME                           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
custom-app-service             ClusterIP   10.107.143.191   <none>        80/TCP    29s
custom-app-stateful-headless   ClusterIP   None             <none>        80/TCP    24s
kubernetes                     ClusterIP   10.96.0.1        <none>        443/TCP   6m57s

$ kubectl get statefulset
NAME                  READY   AGE
custom-app-stateful   2/2     24s

$ kubectl get daemonset
NAME        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
log-agent   1         1         1       1            1           <none>          29s

$ kubectl get cronjob
NAME           SCHEDULE       TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
log-archiver   */10 * * * *   <none>     False     0        <none>          0s
```

## API-эндпоинты

| Метод | Путь | Описание | Пример ответа |
|---|---|---|---|
| GET | `/` | Приветственное сообщение из ConfigMap | `Welcome to the custom app` |
| GET | `/status` | Проверка здоровья приложения | `{"status": "ok"}` |
| POST | `/log` | Записать сообщение в лог-файл | `{"status": "logged", "message": "..."}` |
| GET | `/logs` | Получить содержимое лог-файла | Текстовый вывод app.log |

## Тестирование API

### Проброс порта

В первом терминале:

```
$ kubectl port-forward service/custom-app-service 8080:80
Forwarding from 127.0.0.1:8080 -> 5000
Forwarding from [::1]:8080 -> 5000
```

### Проверка эндпоинтов

Во втором терминале:

```
$ curl http://localhost:8080/
Welcome to the custom app

$ curl http://localhost:8080/status
{"status":"ok"}

$ curl -X POST http://localhost:8080/log -H 'Content-Type: application/json' -d '{"message": "hello world"}'
{"message":"hello world","status":"logged"}

$ curl http://localhost:8080/logs
2026-03-30 20:11:33,734 - INFO - Starting app on port 5000
2026-03-30 20:12:56,359 - INFO - GET /
2026-03-30 20:13:00,514 - INFO - GET /status
2026-03-30 20:13:05,769 - INFO - POST /log: hello world
hello world
2026-03-30 20:13:22,480 - INFO - POST /log: hello world
hello world
```

### Проверка DaemonSet (log-agent)

```
$ kubectl logs -l app=log-agent --tail=20
--- Mon Mar 30 20:29:50 UTC 2026 : scanning /var/log/containers ---
--- Mon Mar 30 20:30:20 UTC 2026 : scanning /var/log/containers ---
--- Mon Mar 30 20:30:50 UTC 2026 : scanning /var/log/containers ---
--- Mon Mar 30 20:31:20 UTC 2026 : scanning /var/log/containers ---
--- Mon Mar 30 20:31:50 UTC 2026 : scanning /var/log/containers ---
--- Mon Mar 30 20:32:20 UTC 2026 : scanning /var/log/containers ---
```

### Ручной запуск CronJob

```bash
kubectl create job --from=cronjob/log-archiver manual-archive-test
kubectl logs -l job-name=manual-archive-test
```

## Обновление конфигурации

Отредактировать `k8s/configmap.yaml`, затем применить и перезапустить Pod-ы:

```bash
kubectl apply -f k8s/configmap.yaml
kubectl patch deployment custom-app \
  -p '{"spec":{"template":{"metadata":{"annotations":{"configmap-version":"v2"}}}}}'
```

## Istio: тестирование

### Результат deploy.sh (Istio-часть)

```
Installing Istio (profile: demo)...
✔ Istio core installed ⛵️
✔ Istiod installed 🧠
✔ Egress gateways installed 🛫
✔ Ingress gateways installed 🛬
✔ Installation complete
Enabling sidecar injection for namespace default...
namespace/default labeled
Restarting workloads to inject sidecars...
deployment.apps/custom-app restarted
daemonset.apps/log-agent restarted
deployment "custom-app" successfully rolled out
Applying Istio Gateway...
gateway.networking.istio.io/custom-app-gateway created
Applying VirtualService...
virtualservice.networking.istio.io/custom-app-vs created
Applying DestinationRule...
destinationrule.networking.istio.io/custom-app-dr created
```

### Поды с Istio sidecar (2/2 READY)

```
$ kubectl get pods -o wide
NAME                          READY   STATUS      RESTARTS   AGE   IP           NODE
custom-app-5675d6d84f-h6knj   2/2     Running     0          16m   10.1.0.195   docker-desktop
custom-app-5675d6d84f-jnjsf   2/2     Running     0          15m   10.1.0.196   docker-desktop
custom-app-5675d6d84f-lrgcz   2/2     Running     0          15m   10.1.0.198   docker-desktop
log-agent-ds4t5               2/2     Running     0          15m   10.1.0.197   docker-desktop
```

`2/2 READY` — Istio sidecar (envoy-proxy) внедрён в каждый pod (было `1/1`).

### Получить внешний IP ingress-gateway

```
$ kubectl get svc istio-ingressgateway -n istio-system
NAME                   TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)
istio-ingressgateway   LoadBalancer   10.98.122.115   localhost     15021:31632/TCP,80:32395/TCP,...

$ export INGRESS_IP=localhost
```

### Проверка маршрутов

```
$ curl http://$INGRESS_IP/
Welcome to the custom app

$ curl http://$INGRESS_IP/status
{"status":"ok"}

$ curl http://$INGRESS_IP/logs
2026-04-19 17:03:33,844 - INFO - Starting app on port 5000
...

$ curl http://$INGRESS_IP/wrong
{"error": "Not Found"}
```

### Fault injection на POST /log

Задержка 2с + abort 504 — запрос завершится с **504 Gateway Timeout** примерно за 2 секунды.
Istio выполняет до 2 повторных попыток, каждая тоже получает 504.

```
$ time curl -s -o /dev/null -w "%{http_code} %{time_total}s" \
    -X POST http://$INGRESS_IP/log \
    -H 'Content-Type: application/json' \
    -d '{"message": "test fault injection"}'
504 2.008201s
```

### Проверка mTLS (сертификаты Istio в pod-е)

```
$ istioctl proxy-config secret \
    $(kubectl get pod -l app=custom-app -o name | head -1 | cut -d/ -f2)
RESOURCE NAME   TYPE        STATUS   VALID CERT   SERIAL NUMBER                        NOT AFTER                NOT BEFORE
default         Cert Chain  ACTIVE   true         109dd87254bca690b7ccf55f6447e488     2026-04-20T17:03:15Z     2026-04-19T17:01:15Z
ROOTCA          CA          ACTIVE   true         4405be81ed3385fbc984cc1cc3bf7e7e     2036-04-16T17:02:53Z     2026-04-19T17:02:53Z
```

Активные mTLS-сертификаты подтверждают работу ISTIO_MUTUAL режима, заданного в DestinationRule.

## Пошаговые скрипты

| Скрипт | Задание |
|---|---|
| `bash scripts/task1_build.sh` | Сборка Docker-образа |
| `bash scripts/task2_pod.sh` | Тестовый Pod |
| `bash scripts/task3_deployment.sh` | Deployment с 3 репликами |
| `bash scripts/task4_service.sh` | ClusterIP Service |
| `bash scripts/task5_daemonset.sh` | DaemonSet log-agent |
| `bash scripts/task6_cronjob.sh` | CronJob log-archiver |
| `bash scripts/task7_statefulset.sh` | StatefulSet |
| `bash scripts/task8_istio.sh` | Istio Gateway + VirtualService + DestinationRule |

## Удаление всех ресурсов

```bash
kubectl delete -f k8s/
kubectl delete pvc -l app=custom-app-stateful
istioctl uninstall --purge -y
kubectl label namespace default istio-injection-
docker rmi custom-app:latest
```
