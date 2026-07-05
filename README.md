ERP/1: Continuous Delivery
==========================

Політики інфраструктури і адміністрування "ERP/1: Підприємство" (5K LOC) для K8S.
Тестуються на Windows, Linux і Mac через Docker Desktop і Kind Cluster Type
для максимальної відтворюваності в продуктовому середовищі.

Статті
------

* М. Сохацький, [The Kind of Kubernetes](kind.pdf), 2026 <br>
     The Kind of Kubernetes: Using Docker Desktop for Reproducible Kubernetes Clusters
* М. Сохацький, [Архітектура ЦОД](deployment.pdf), 2026 <br>
     Настанови системного архiтектора для проектування кластерiв ЦОД
* М. Сохацький, [SRE Handbook](sre.pdf), 2026 <br>
     Настанови системного адмiнiстратора для розгортання, спостереження i обслуговування кластерiв ЦОД

Розповсюдження
--------------

Постійна адреса твору:

```
$ git clone git@github.com:erpuno/cd
```

Загальні файли
--------------

Загальні файли інфраструктури K8S відповідають за цементування фундаменту ERP/1.
Вони запускаються першими перед чистими або пакетованими компонентами через `kubectl apply`.

* `namespaces.yaml`
* `networkpolicy.yaml`
* `rbac.yaml`
* `storage-class.yaml`

Файли компонент
---------------

Далі для кожного компоненту запусткається цикл по його файлам.

```sh
    for kind in pvc.yaml deployment.yaml service.yaml hpa.yaml ingress.yaml; do
      if [ -f "$service_path/$kind" ]; then
        sed "s/namespace: .*/namespace: $namespace/" "$service_path/$kind" | \
        kubectl apply -f -
      fi
    done
```
Перелік компонент секретний для кожного підприємства, тут надається типова конфігурація.
Кожен компонент може мати наступні файли, цей перелік можна доповнювати.

* `deployment.yaml`
* `service.yaml`
* `hpa.yaml`
* `pvc.yaml`
* `ingress.yaml`
* `values.yaml`

Пакетування
-----------

* `Chart.yaml`
* `values.yaml`
* `templates/`
* `deploy.sh` — Helm розгортання
* `path.sh` — Додавання прав для Helm тулчейну в будь який кластер
* `cleanup.sh` — видалення пакетів і кластера
* `validate.sh` — ваділація згенерованого уніфікованого ERP/1 чарта
* `values.rb` – скрипт генерації уніфікованого ERP/1 чарта

В каталозі `templates/` імена файли повторюють номенклатуру файлів компонент.

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

