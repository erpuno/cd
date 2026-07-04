ERP/1: Continuous Delivery
==========================

Крім шаблонів "ERP/1: Підприємство" (5K LOC) для K8S цей репозиторій містить 3 статті:

* Архітектура ЦОД
* SRE Handbook
* The Kind of Kubernetes

```sh
$ tree -L 3 .
.
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

Credits
-------

* 5HT
