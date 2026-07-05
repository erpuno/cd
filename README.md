ERP/1: Continuous Delivery
==========================

Інфраструктура "ERP/1: Підприємство" (5K LOC) для K8S тестується на Windows, Linux і Mac
через Docker Desktop і Kind Cluster Type для максимальної відтворюваності в продуктовому середовищі.

* [Архітектура ЦОД](deployment.pdf)
* [SRE Handbook](sre.pdf)
* [The Kind of Kubernetes](kind.pdf)

```sh
$ git clone git@github.com:erpuno/cd && cd cd
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
