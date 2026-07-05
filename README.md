ERP/1: Continuous Delivery
==========================

Політики інфраструктури і адміністрування "ERP/1: Підприємство" (5K LOC) для K8S тестується на Windows, Linux і Mac
через Docker Desktop і Kind Cluster Type для максимальної відтворюваності в продуктовому середовищі.

Статті
------

* М. Сохацький, [The Kind of Kubernetes](kind.pdf), 2026 — The Kind of Kubernetes: Using Docker Desktop for Local Kubernetes Clusters
* М. Сохацький, [Архітектура ЦОД](deployment.pdf), 2026 — Настанови системного архiтектора для проектування кластерiв ЦОД
* М. Сохацький, [SRE Handbook](sre.pdf), 2026 — Настанови системного адмiнiстратора для розгортання, спостереження i обслуговування кластерiв ЦОД

Розповсюдження
--------------

```
$ git clone git@github.com:erpuno/cd && cd cd
```

Структура
---------

```
├── helm/
│   ├── templates/
│   │   ├── deployments.yaml
│   │   ├── hpa.yaml
│   │   ├── namespaces.yaml
│   │   └── services.yaml
│   ├── cleanup.sh
│   ├── deploy.sh
│   ├── patch.sh
│   ├── validate.sh
│   ├── Chart.yaml
│   └── values.yaml
├── lib/
│   ├── erp-ai/
│   ├── erp-apps/
│   ├── erp-infra/
│   ├── erp-security/
│   ├── erp-services/
│   └── erp-telemetry/
├── share/
│   ├── namespaces.yaml
│   ├── networkpolicy.yaml
│   ├── rbac.yaml
│   └── storage-class.yaml
├── kind.sh
├── kind.pdf
├── deployment.pdf
├── sre.pdf
├── cleant.sh
├── delete.sh
├── deploy.sh
├── prereq.sh
└── values.rn
```

Автор
-----

* Максим Сохацький

