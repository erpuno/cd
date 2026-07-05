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
    if [ -f "$service_path/$kind" ]; then kubectl apply -f "$service_path/$kind" ; fi
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

Хоча Helm чарти були придумані не для цього, їх механізм зручно використовувати для обліку
стану пакетів в ЦОД та кількості їх деплоїв для юридичних рослідувань. Для сього система пакетів
Helm використовується в реверсивному режимі, не з неї генеруються пакети, а з пакетів
генерується уніфікований чарт, в якому зібрані усі компонент які потрібно розгортати.
Це елімінує необхідність репозиторія пакетів Helm і зберігає всі транзакційні властивості
пакетного менеджера, які потрібні на продакшині. Для цього використовується Ruby скрипт `values.rb`.
В каталозі `templates/` імена файли повторюють номенклатуру файлів компонент.

* `Chart.yaml`
* `values.yaml`
* `templates/`
* `deploy.sh` — Helm розгортання
* `path.sh` — Додавання прав для Helm тулчейну в будь який кластер
* `cleanup.sh` — видалення пакетів і кластера
* `validate.sh` — ваділація згенерованого уніфікованого ERP/1 чарта
* `values.rb` – скрипт генерації уніфікованого ERP/1 чарта

Резервне копіювання
-------------------

Для зберігання персистентний станів подів використовується універсальний механізм.

* `backup.sh` — Копіювати всі PVC та STS
* `restore.sh` — Відновити PVC та STS репліки з перезапуском подів
* `view.sh` — Переглядач резервних копій

Настанови адміністратора з резервного копіювання читайте в [BACKUP.md](BACKUP.md).

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

