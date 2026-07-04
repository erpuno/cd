ERP/1: Continuous Delivery
==========================

* Архітектура ЦОД
* SRE Handbook

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
├── cleant.sh
├── delete.sh
├── deploy.sh
├── prereq.sh
└── values.rn
```

Credits
-------

* 5HT
