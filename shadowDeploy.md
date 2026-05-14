# **Архитектура и реализация систем теневого развертывания в сетях мобильной связи четвертого поколения**

Современная индустрия телекоммуникаций находится в фазе глубокой трансформации, где парадигма программно-определяемых сетей (SDN) и виртуализации сетевых функций (NFV) диктует необходимость внедрения гибких методологий разработки и эксплуатации. Одной из наиболее сложных и востребованных стратегий в этом контексте является теневое развертывание (Shadow Deployment), позволяющее проводить валидацию новых версий программного обеспечения на реальном трафике без риска для конечных пользователей.1 В сетях 4G/LTE, характеризующихся жесткими требованиями к задержкам и сложной инкапсуляцией протоколов, таких как GTP-U, создание надежного полигона для теневого тестирования требует междисциплинарного подхода, объединяющего SRE-практики, глубокое понимание стека протоколов 3GPP и современные методы оркестрации микросервисов.3  
Использование теневого развертывания, также известного как зеркалирование трафика (Traffic Mirroring) или shadowing, позволяет инженерным командам получать сигналы производственного уровня — кривые задержек, паттерны ошибок и профили потребления ресурсов — при нулевом воздействии на клиентский опыт.5 В отличие от традиционных стратегий, таких как канареечные релизы (Canary) или сине-зеленые развертывания (Blue-Green), где часть пользователей неизбежно подвергается риску взаимодействия с потенциально нестабильным кодом, теневое развертывание обеспечивает безопасную среду для «прожарки» сервиса в реальных условиях эксплуатации.6

## **Стратегический анализ архитектурных пробелов и технических вызовов**

Прежде чем приступить к технической реализации системы на сервере с объемом оперативной памяти 128 ГБ, необходимо провести детальный анализ критических зон, которые могут стать узкими местами при зеркалировании трафика мобильных клиентов. Одной из наиболее острых проблем является обеспечение консистентности данных (State Consistency). Если тестируемое приложение выполняет операции записи в базу данных, простое дублирование запросов приведет к дублированию записей или нарушению целостности транзакций в основной БД.1 Решением здесь выступает использование теневых баз данных (Shadow DB), которые представляют собой изолированные клоны продуктивных хранилищ, или реализация транзакционных фильтров на уровне приложения, подавляющих побочные эффекты при обнаружении флага зеркалированного запроса.2  
Вторым значимым вызовом является оверхед протокола GTP-U. В реальном стеке 4G пользовательский трафик инкапсулируется в туннели GTP, что добавляет 36 байт заголовков к каждому пакету: 20 байт IP, 8 байт UDP и 8 байт GTP.3 Это неизбежно влияет на максимальный размер полезной нагрузки (MTU) и может приводить к фрагментации пакетов внутри Service Mesh, что критически сказывается на производительности прокси-серверов Envoy, используемых в Istio.10 Неправильная обработка фрагментации часто становится причиной труднодиагностируемых задержек в «хвосте» распределения (P99).3  
Третий аспект касается корреляции метрик. В экосистеме 4G-ядра, реализованного на базе Open5GS, сетевые показатели (RTT, джиттер, потери на радиоинтерфейсе) фиксируются на уровне инфраструктуры связи, в то время как прикладные метрики собираются Service Mesh.13 Создание единого аналитического слоя, способного связать задержку в туннеле GTP с временем ответа конкретного микросервиса, требует внедрения сквозных идентификаторов запросов (Correlation IDs) и интеграции систем сбора метрик, таких как Prometheus и Iter8.8  
Наконец, анализ ответов теневой версии (Shadow Response Analysis) представляет собой отдельную инженерную задачу. Поскольку Envoy-proxy по умолчанию отбрасывает ответы от зеркалированной службы, захват «тела ответа» для проведения Diff-анализа (сравнения с ответом основной версии) требует внедрения специализированных фильтров Lua или модулей WebAssembly (Wasm).12 Это должно быть реализовано таким образом, чтобы буферизация ответов в памяти прокси-сервера не создавала дополнительной нагрузки на основную ветку трафика.12

## **Проектирование высокопроизводительного полигона на базе K3s и Open5GS**

Выбор сервера со 128 ГБ ОЗУ в качестве аппаратной базы обусловлен необходимостью одновременного запуска сотен контейнеров, имитирующих как узлы ядра сети (Network Functions), так и тысячи пользовательских устройств (UE).18 Архитектура системы строится по многослойному принципу, обеспечивающему изоляцию уровней инфраструктуры, связи и аналитики.

### **Инфраструктурный слой и сетевая оркестрация**

В качестве операционной системы рекомендуется Ubuntu 22.04 LTS, обеспечивающая стабильную работу ядра Linux, необходимую для функционирования модулей SCTP и GTP.18 Оркестрация осуществляется с помощью K3s — легковесного дистрибутива Kubernetes, который идеально подходит для создания граничных (edge) лабораторий.21  
Для обеспечения специфических требований мобильной сети к сетевым интерфейсам применяется Multus CNI. Этот плагин позволяет подключать к одному поду несколько сетевых интерфейсов, что критично для разделения плоскости управления (Control Plane, интерфейс N2) и плоскости пользователя (User Plane, интерфейс N3).21 Без Multus стандартная модель Kubernetes с одним интерфейсом на под не смогла бы обеспечить реалистичную имитацию маршрутизации в сетях 4G.23

### **Ядро сети: Open5GS и реализация EPC**

Open5GS выступает в роли эмулятора ядра сети (EPC/5G Core). В контексте 4G основными компонентами являются MME (Mobility Management Entity), HSS (Home Subscriber Server) и связка SGW/PGW (Serving/PDN Gateway).9 Каждый из этих компонентов разворачивается как отдельный микросервис в Kubernetes.  
Важной особенностью Open5GS является использование MongoDB для хранения данных абонентов. При работе с 128 ГБ ОЗУ база данных может быть полностью кэширована в памяти, что минимизирует задержки при аутентификации и регистрации устройств.4 Регистрация абонентов производится через WebUI или CLI, при этом каждому устройству присваивается уникальный IMSI и ключи безопасности, которые должны точно совпадать с настройками на стороне симулятора радиодоступа.9

### **Слой доступа: UERANSIM и имитация радиоканала**

UERANSIM является ключевым инструментом для создания реалистичного трафика. Он эмулирует работу как базовой станции (eNodeB/gNodeB), так и пользовательского терминала (UE).25 Программный стек UERANSIM создает виртуальный сетевой интерфейс uesimtun0, который ведет себя как реальное мобильное соединение.27  
Особенность работы с UERANSIM в Kubernetes заключается в использовании инструмента nr-binder. Он позволяет принудительно связывать (bind) трафик любого приложения с интерфейсом uesimtun0, направляя пакеты через полный стек протоколов 4G, включая шифрование и инкапсуляцию GTP.25 Это позволяет использовать стандартные инструменты нагрузочного тестирования, такие как k6, для генерации трафика, который ядро сети будет воспринимать как подлинный мобильный трафик.28

## **Реализация Service Mesh и логика зеркалирования в Istio**

Istio является центральным элементом управления трафиком в описываемой системе. Используя прокси-серверы Envoy в качестве sidecar-контейнеров, Istio обеспечивает гибкое управление маршрутизацией через ресурс VirtualService.2

### **Конфигурация VirtualService для теневого развертывания**

Для активации зеркалирования создается манифест, описывающий основное направление трафика (v1) и теневое направление (v2). Важным параметром является mirrorPercentage, который в исследовательских целях обычно устанавливается на 100%, но в высоконагруженных продуктивных средах может быть снижен для экономии ресурсов.6  
При зеркалировании трафика Istio выполняет следующие действия:

1. Дублирует входящий HTTP-запрос.  
2. Изменяет заголовок Host/Authority, добавляя к нему суффикс \-shadow.15  
3. Отправляет запрос теневой версии асинхронно, не дожидаясь ответа.  
4. Игнорирует и отбрасывает любой ответ от теневой версии, чтобы он не попал обратно клиенту.2

Эта модель «выстрелил и забыл» (fire-and-forget) гарантирует, что даже если теневая версия работает медленно или выдает ошибки, это никак не скажется на времени ответа для основного пользователя.5

### **Управление сетевым оверхедом: MTU и MSS Clamping**

Использование GTP-туннелей накладывает ограничения на размер передаваемых данных. Поскольку стандартный MTU в Ethernet составляет 1500 байт, а заголовки GTP-U отнимают 36 байт, эффективный MTU для мобильного клиента снижается до 1464 байт или ниже (часто до 1400 байт для компенсации других уровней инкапсуляции).3  
Если приложение в Service Mesh пытается отправить пакет размером 1500 байт в туннель с меньшим MTU, пакет будет либо фрагментирован, что увеличивает нагрузку на CPU, либо отброшен, если установлен бит DF (Don't Fragment).10 Для решения этой проблемы применяется техника MSS Clamping (фиксация максимального размера сегмента TCP). В Istio это реализуется через EnvoyFilter, который модифицирует параметры сокетов на слушателях (listeners), принудительно ограничивая MSS в пакетах SYN/SYN-ACK.30 Это заставляет стек TCP на обоих концах соединения договариваться о меньшем размере сегмента, предотвращая фрагментацию на уровне IP.10  
Сводная таблица параметров MTU и MSS для различных сегментов сети:

| Сегмент сети | MTU (байт) | MSS (байт) | Комментарий |
| :---- | :---- | :---- | :---- |
| Стандартный Ethernet | 1500 | 1460 | Базовая конфигурация 10 |
| GTP-U Туннель (4G) | 1464 | 1424 | Учет заголовка GTP-U (36 байт) 3 |
| UERANSIM (Рекомендуемый) | 1400 | 1360 | Запас на инкапсуляцию в K8s 3 |
| Istio Ingress Gateway | 1500 | 1460 | Требует MSS Clamping для 4G клиентов 30 |

## **Обеспечение консистентности данных и обработка побочных эффектов**

Одной из самых сложных задач при внедрении Shadow Deployment является обработка запросов, изменяющих состояние системы (POST/PUT/DELETE). Прямое зеркалирование таких запросов приведет к тому, что теневая версия попытается выполнить те же действия в базе данных, что и основная.1

### **Теневые базы данных (Shadow Databases)**

Наиболее распространенным и надежным методом является использование выделенной базы данных для теневой версии.2 Перед началом тестирования создается снимок (snapshot) продуктивной БД, который разворачивается в изолированном экземпляре. Это позволяет теневой версии выполнять реальные операции записи, проверять миграции схем и оценивать производительность запросов без риска повреждения живых данных.2

### **Режим подавления записи (Write Suppression)**

В ситуациях, когда создание копии БД невозможно из\-за ее объема или требований безопасности, применяется режим подавления записи. Приложение настраивается таким образом, что при получении запроса с заголовком \-shadow оно выполняет всю бизнес-логику, рассчитывает результат, но пропускает этап фиксации (commit) транзакции в БД.2  
Пример логики на уровне приложения:

Python

@app.post("/orders")  
async def create\_order(request: Request):  
    is\_shadow \= request.headers.get("x-istio-attributes", "").find("shadow")\!= \-1  
    order\_data \= await request.json()  
      
    \# Полная валидация и расчет логики  
    order \= process\_business\_logic(order\_data)  
      
    if is\_shadow:  
        \# Симуляция успешного ответа без сохранения в БД  
        logger.info(f"Shadow request processed: {order.id}")  
        return {"status": "simulated", "id": order.id}  
      
    \# Реальное сохранение в продуктивную БД  
    db.save(order)  
    return {"status": "created", "id": order.id}

Этот подход позволяет тестировать вычислительную часть сервиса, но не дает полной уверенности в корректности взаимодействия с БД.2

## **Глубокий анализ ответов и корреляция метрик**

Для того чтобы Shadow Deployment приносил пользу, необходимо иметь механизм сравнения результатов работы двух версий приложения. Основная проблема заключается в том, что Envoy отбрасывает ответы теневой версии.5

### **Использование Lua-фильтров для захвата Payload**

Для извлечения тела ответа из теневой версии используются Lua-скрипты, встраиваемые в Envoy через EnvoyFilter.12 Скрипт перехватывает ответ, буферизирует его и отправляет копию в систему аналитики или записывает в логи прокси-сервера.32  
Однако стоит учитывать, что полная буферизация ответов в памяти прокси-сервера может значительно увеличить потребление ресурсов, особенно при больших объемах передаваемых данных.12 При использовании сервера со 128 ГБ ОЗУ это менее критично, чем в ограниченных средах, но все же требует мониторинга утечек памяти и накопления сокетов в состоянии TIME\_WAIT.31

### **Дифференциальный анализ (Diff Analysis)**

Захваченные ответы передаются в анализатор, который выполняет посимвольное или структурное сравнение JSON-тел.8 Для повышения точности сравнения применяется нормализация: из ответов удаляются динамические поля, такие как временные метки (timestamps), идентификаторы запросов (request\_id) и случайно сгенерированные токены, которые заведомо будут различаться между двумя запусками кода.8  
Ключевым показателем здесь является Payload Match Rate — процент запросов, для которых тела ответов после нормализации совпали полностью.8 Снижение этого показателя ниже определенного порога (например, 99%) должно автоматически блокировать продвижение новой версии в продуктивную среду.1

## **Автоматизация исследовательского цикла через Terraform и CI/CD**

Эффективность работы с полигоном 4G напрямую зависит от скорости развертывания и повторяемости экспериментов. Использование Terraform позволяет описать всю инфраструктуру — от кластера K3s до конфигураций Open5GS — как код.

### **Оркестрация с Terraform**

Terraform управляет жизненным циклом ресурсов, используя Helm-провайдер для установки компонентов. Это позволяет изменять параметры 4G-ядра, такие как код страны (MCC) или код сети (MNC), простой сменой переменных в файлах .tfvars.9  
Пример структуры проекта автоматизации:

* infra/: Описание виртуальных машин или bare-metal ресурсов.  
* k8s/: Конфигурации кластера K3s и Multus CNI.  
* telecom/: Развертывание Open5GS и настройка абонентов в MongoDB.  
* mesh/: Установка Istio, настройка Ingress Gateway и MSS Clamping.  
* apps/: Развертывание Prod и Shadow версий пользовательских приложений.

### **Пайплайн тестирования**

Автоматизированный процесс тестирования (Pipeline) включает в себя стадии подготовки среды, генерации нагрузки и анализа результатов. Особенностью мобильного сегмента является необходимость динамического изменения условий сети.  
Этапы пайплайна:

1. **Provisioning:** Terraform применяет актуальные конфиги.  
2. **Traffic Generation:** k6 запускается через nr-binder, направляя трафик в uesimtun0.28  
3. **Network Impairment:** С помощью Toxiproxy или параметров UERANSIM вносятся задержки (Latency), потери пакетов (Packet Loss) и джиттер.  
4. **Analysis:** Iter8 опрашивает Prometheus, сравнивая метрики Prod и Shadow.  
5. **Report:** Генерация отчета о поведении системы при деградации 4G-канала.14

## **Мониторинг и ключевые показатели эффективности (KPI)**

Для оценки успеха теневого развертывания в сетях 4G необходимо отслеживать метрики на нескольких уровнях абстракции. Благодаря наличию 128 ГБ ОЗУ, система мониторинга может хранить детальные метрики с высоким разрешением, что критично для выявления кратковременных всплесков задержек.29

### **Сетевые показатели уровня L3/L4**

На этом уровне фиксируется состояние мобильного ядра и радиоканала:

* **RTT (Round Trip Time):** Задержка прохождения пакета от UE до UPF и обратно.13  
* **Packet Loss Ratio:** Процент потерянных пакетов в туннеле GTP-U.3  
* **SCTP Association Health:** Стабильность контрольного канала между базовой станцией и MME.9

### **Прикладные показатели уровня L7**

Эти метрики отражают качество работы самого приложения:

* **Response Time Delta:** Разница в миллисекундах между ответом Prod и Shadow версии на один и тот же запрос.2  
* **Error Rate Divergence:** Появление специфических ошибок в теневой версии, отсутствующих в основной (например, таймауты из\-за неоптимального TCP-стека).6  
* **Throughput Per Slice:** Пропускная способность в разрезе сетевых слайсов 4G/5G.4

### **Системные показатели**

Учитывая большой объем памяти, важно следить за эффективностью ее использования:

* **Memory Footprint Per UE:** Объем памяти, потребляемый инфраструктурой на одно активное мобильное устройство.19  
* **Socket Accumulation:** Количество соединений в состоянии ESTABLISHED и CLOSE\_WAIT, что позволяет выявить утечки ресурсов при нестабильном 4G-соединении.31

| Категория KPI | Метрика | Целевое значение | Инструмент сбора |
| :---- | :---- | :---- | :---- |
| Производительность | Latency Delta | \< 5 мс 2 | Istio Envoy Metrics 14 |
| Стабильность | Error Rate Divergence | 0% 1 | Prometheus / Loki 14 |
| Корректность | Payload Match Rate | \> 99.5% 8 | Custom Diff-Service 16 |
| Ресурсы | CPU/RAM Utilization | \< 80% 6 | Kubernetes Metrics Server |
| Сеть 4G | GTP-U Fragmentation | 0 3 | Node Exporter / Wireshark |

## **Имитация сбоев и стресс-тестирование в мобильном контексте**

Одной из уникальных возможностей 128 ГБ лаборатории является имитация сложных сценариев мобильности, таких как «вход в туннель» или «переход между сотами» (handover).

### **Сценарий «Tunnel Entrance»**

С помощью API Toxiproxy имитируется мгновенное увеличение потерь пакетов до 100% на 5-10 секунд с последующим восстановлением. В этот момент анализируется поведение теневой версии: насколько корректно она обрабатывает прерванные сессии и не происходит ли переполнения очередей запросов в Service Mesh.1  
Теневое развертывание позволяет увидеть, как новая версия кода реагирует на массовое переподключение клиентов (Burst Traffic), которое всегда следует за восстановлением связи в мобильных сетях. Если новая версия тратит на восстановление сессий на 20% больше времени, чем текущая, это является критическим показателем для доработки.5

### **Проверка на утечки ресурсов при джиттере**

Сети 4G характеризуются высоким джиттером (вариацией задержки). При больших задержках в канале 4G теневая версия может начать накапливать открытые TCP-соединения, ожидая ответов от медленных клиентов.31 Наличие 128 ГБ памяти позволяет проводить тесты длительностью в несколько суток, что необходимо для выявления медленных утечек памяти и деградации пула потоков (thread pool saturation).6

## **Заключение: стратегические рекомендации по эксплуатации**

Создание системы Shadow Deployment для 4G-клиентов на базе сервера со 128 ГБ ОЗУ превращает стандартный сервер в полноценную цифровую лабораторию сотового оператора. Интеграция Open5GS, UERANSIM и Istio обеспечивает беспрецедентную глубину анализа, позволяя выявлять проблемы производительности на стыке сетевых протоколов и прикладного кода.13  
Для достижения максимальной эффективности рекомендуется следовать трем основным принципам:

1. **Приоритет сетевой идентичности:** Не допускать различий в MTU и параметрах TCP между тестовой и продуктивной средой, так как в сетях 4G это является основным источником ложноположительных результатов.3  
2. **Глубокая изоляция данных:** Использовать теневые базы данных для полной проверки write-path, что критично для телеком-сервисов со сложной логикой биллинга и профилирования.2  
3. **Непрерывный Diff-анализ:** Считать Payload Match Rate ключевым индикатором готовности релиза, внедряя автоматизированные проверки на каждом этапе пайплайна.8

Внедрение данных подходов позволяет радикально снизить риск при обновлении критических узлов мобильной инфраструктуры, обеспечивая стабильность связи и высокое качество обслуживания абонентов в условиях постоянно растущей сложности сетевых архитектур.18 Применение автоматизации через Terraform и анализа через Iter8 делает процесс исследования предсказуемым и масштабируемым, что соответствует высшим стандартам современной SRE-инженерии в телекоммуникациях.

#### **Works cited**

1. Shadow Deployments: Best Practices for Real-World Testing \- Zesty, accessed May 14, 2026, [https://zesty.co/finops-glossary/shadow-deployments/](https://zesty.co/finops-glossary/shadow-deployments/)  
2. Safely Replacing Production Services Using Shadow Traffic with Istio on Kubernetes, accessed May 14, 2026, [https://medium.com/@sonishubham65/safely-replacing-production-services-using-shadow-traffic-with-istio-on-kubernetes-57c0516602e2](https://medium.com/@sonishubham65/safely-replacing-production-services-using-shadow-traffic-with-istio-on-kubernetes-57c0516602e2)  
3. uesimtun0 interface MTU 1500 setup Problem · Issue \#265 ... \- GitHub, accessed May 14, 2026, [https://github.com/aligungr/UERANSIM/issues/265](https://github.com/aligungr/UERANSIM/issues/265)  
4. niloysh/open5gs-k8s: 5G Core deployment using Open5gs on Kubernetes \- GitHub, accessed May 14, 2026, [https://github.com/niloysh/open5gs-k8s](https://github.com/niloysh/open5gs-k8s)  
5. Shadow deployment: Risk-free performance comparison \- Statsig, accessed May 14, 2026, [https://www.statsig.com/perspectives/shadow-deployment-comparison](https://www.statsig.com/perspectives/shadow-deployment-comparison)  
6. How to Implement Shadow Deployments That Mirror Production Traffic \- OneUptime, accessed May 14, 2026, [https://oneuptime.com/blog/post/2026-02-09-shadow-deployments-mirror-production-traffic/view](https://oneuptime.com/blog/post/2026-02-09-shadow-deployments-mirror-production-traffic/view)  
7. Model Deployment Strategies: Discover How to Boost your ML Deployment Success | by Juan C Olamendy | Medium, accessed May 14, 2026, [https://medium.com/@juanc.olamendy/model-deployment-strategies-discover-how-to-boost-your-ml-deployment-success-d82b320ac118](https://medium.com/@juanc.olamendy/model-deployment-strategies-discover-how-to-boost-your-ml-deployment-success-d82b320ac118)  
8. How to Create Shadow Deployment \- OneUptime, accessed May 14, 2026, [https://oneuptime.com/blog/post/2026-01-30-shadow-deployment/view](https://oneuptime.com/blog/post/2026-01-30-shadow-deployment/view)  
9. Simple Issue | Open5GS, accessed May 14, 2026, [https://open5gs.org/open5gs/docs/troubleshoot/01-simple-issues/](https://open5gs.org/open5gs/docs/troubleshoot/01-simple-issues/)  
10. How to Troubleshoot MTU and Fragmentation in GRE Tunnels \- OneUptime, accessed May 14, 2026, [https://oneuptime.com/blog/post/2026-03-20-troubleshoot-mtu-fragmentation-gre/view](https://oneuptime.com/blog/post/2026-03-20-troubleshoot-mtu-fragmentation-gre/view)  
11. GRE Tunnel and MSS cramping : r/networking \- Reddit, accessed May 14, 2026, [https://www.reddit.com/r/networking/comments/1fegyhq/gre\_tunnel\_and\_mss\_cramping/](https://www.reddit.com/r/networking/comments/1fegyhq/gre_tunnel_and_mss_cramping/)  
12. How to Configure Request Body Transformation with Istio \- OneUptime, accessed May 14, 2026, [https://oneuptime.com/blog/post/2026-02-24-how-to-configure-request-body-transformation-with-istio/view](https://oneuptime.com/blog/post/2026-02-24-how-to-configure-request-body-transformation-with-istio/view)  
13. Open5GS and UERANSIM | Gradiant 5G Charts \- GitHub Pages, accessed May 14, 2026, [https://gradiant.github.io/5g-charts/open5gs-ueransim-gnb.html](https://gradiant.github.io/5g-charts/open5gs-ueransim-gnb.html)  
14. Performance testing with Iter8, now with custom metrics\! | by Alan ..., accessed May 14, 2026, [https://itnext.io/performance-testing-with-iter8-now-with-custom-metrics-8c97bb7449c8](https://itnext.io/performance-testing-with-iter8-now-with-custom-metrics-8c97bb7449c8)  
15. Mirroring \- Istio, accessed May 14, 2026, [https://istio.io/latest/docs/tasks/traffic-management/mirroring/](https://istio.io/latest/docs/tasks/traffic-management/mirroring/)  
16. From Risk to Safety: Mastering Deployments with Shadow Analysis | by Sai Kiran Saindla, accessed May 14, 2026, [https://engineering.razorpay.com/from-risk-to-safety-mastering-deployments-with-shadow-analysis-1e2402161083](https://engineering.razorpay.com/from-risk-to-safety-mastering-deployments-with-shadow-analysis-1e2402161083)  
17. Istio Envoy filters (Parsing, Fault Injection, Retry, Duplicate Headers) \- Medium, accessed May 14, 2026, [https://medium.com/@syedhassaniiui/istio-envoy-filters-parsing-fault-injection-retry-duplicate-headers-72f390ae2193](https://medium.com/@syedhassaniiui/istio-envoy-filters-parsing-fault-injection-retry-duplicate-headers-72f390ae2193)  
18. Red Hat Service Interconnect Example: Open5GS Deployment on Multi-Private Clusters, accessed May 14, 2026, [https://cloudcult.dev/red-hat-service-interconnect-example-open5gs-deployment-on-multi-private-clusters-2-2/](https://cloudcult.dev/red-hat-service-interconnect-example-open5gs-deployment-on-multi-private-clusters-2-2/)  
19. Roaming | Open5GS, accessed May 14, 2026, [https://open5gs.org/open5gs/docs/tutorial/05-roaming/](https://open5gs.org/open5gs/docs/tutorial/05-roaming/)  
20. Setting Up Open5GS: A Step-by-Step Guide | by Roman Palenik | Networks @ FIIT STU, accessed May 14, 2026, [https://medium.com/networkers-fiit-stu/setting-up-open5gs-a-step-by-step-guide-or-how-we-set-up-our-lab-environment-5da1c8db0439](https://medium.com/networkers-fiit-stu/setting-up-open5gs-a-step-by-step-guide-or-how-we-set-up-our-lab-environment-5da1c8db0439)  
21. Exploring Multus: An Advanced Networking Solution for Kubernetes \- KubeOps, accessed May 14, 2026, [https://kubeops.net/blog/exploring-multus-an-advanced-networking-solution-for-kubernetes](https://kubeops.net/blog/exploring-multus-an-advanced-networking-solution-for-kubernetes)  
22. How to Configure Multus CNI for Multiple Network Interfaces per Pod \- OneUptime, accessed May 14, 2026, [https://oneuptime.com/blog/post/2026-02-09-multus-cni-multiple-network-interfaces/view](https://oneuptime.com/blog/post/2026-02-09-multus-cni-multiple-network-interfaces/view)  
23. Enable Pods with Multiple Network Interfaces \- Juniper Networks, accessed May 14, 2026, [https://www.juniper.net/documentation/us/en/software/cn-cloud-native22/cn-cloud-native-feature-guide/cn-cloud-native-network-feature/topics/task/cn-cloud-native-multiple-interface-pod.html](https://www.juniper.net/documentation/us/en/software/cn-cloud-native22/cn-cloud-native-feature-guide/cn-cloud-native-network-feature/topics/task/cn-cloud-native-multiple-interface-pod.html)  
24. Multiple network interfaces for CNFs | Design and Optimize a 5G Telco Cloud, accessed May 14, 2026, [https://infohub.delltechnologies.com/en-sg/l/design-and-optimize-a-5g-telco-cloud/multiple-network-interfaces-for-cnfs/](https://infohub.delltechnologies.com/en-sg/l/design-and-optimize-a-5g-telco-cloud/multiple-network-interfaces-for-cnfs/)  
25. Deploying 5G Core Network with Open5GS and UERANSIM | by (λx.x)eranga \- Medium, accessed May 14, 2026, [https://medium.com/rahasak/5g-core-network-setup-with-open5gs-and-ueransim-cd0e77025fd7](https://medium.com/rahasak/5g-core-network-setup-with-open5gs-and-ueransim-cd0e77025fd7)  
26. My first 5G Core: Open5Gs and UERANSIM \- Nick vs Networking, accessed May 14, 2026, [https://nickvsnetworking.com/my-first-5g-core-open5gs-and-ueransim/](https://nickvsnetworking.com/my-first-5g-core-open5gs-and-ueransim/)  
27. Tun Setup on UEsim \- Amarisoft Tech Academy, accessed May 14, 2026, [https://tech-academy.amarisoft.com/UESim\_Tun.html](https://tech-academy.amarisoft.com/UESim_Tun.html)  
28. Usage · aligungr/UERANSIM Wiki \- GitHub, accessed May 14, 2026, [https://github.com/aligungr/UERANSIM/wiki/Usage/c830f7989935683f93a094e3f045ab1c763d9d71](https://github.com/aligungr/UERANSIM/wiki/Usage/c830f7989935683f93a094e3f045ab1c763d9d71)  
29. How to Use k6 with Prometheus \- OneUptime, accessed May 14, 2026, [https://oneuptime.com/blog/post/2026-01-28-k6-prometheus-integration/view](https://oneuptime.com/blog/post/2026-01-28-k6-prometheus-integration/view)  
30. How to Configure Connection Limits at Istio Gateway \- OneUptime, accessed May 14, 2026, [https://oneuptime.com/blog/post/2026-02-24-how-to-configure-connection-limits-at-istio-gateway/view](https://oneuptime.com/blog/post/2026-02-24-how-to-configure-connection-limits-at-istio-gateway/view)  
31. Istio Ingress Gateway TCP keepalive \- MyF5 | Support, accessed May 14, 2026, [https://my.f5.com/manage/s/article/K00026550](https://my.f5.com/manage/s/article/K00026550)  
32. Capturing HTTP Requests and Responses with Istio Filters \- peterwynroberts.com, accessed May 14, 2026, [https://peterwynroberts.com/kubernetes/k8s/istio/2022/07/16/Capture-HTTP-Requests-And-Responses.html](https://peterwynroberts.com/kubernetes/k8s/istio/2022/07/16/Capture-HTTP-Requests-And-Responses.html)  
33. Istio Envoy Filter Lua \- Updating Response Body get stuck \- Stack Overflow, accessed May 14, 2026, [https://stackoverflow.com/questions/73025689/istio-envoy-filter-lua-updating-response-body-get-stuck](https://stackoverflow.com/questions/73025689/istio-envoy-filter-lua-updating-response-body-get-stuck)  
34. Scalable Load Testing with K6 Operator, Prometheus, and Grafana on K8s \- Medium, accessed May 14, 2026, [https://medium.com/@elyasimt/scalable-load-testing-with-k6-operator-prometheus-and-grafana-on-k8s-e8dac5062f7c](https://medium.com/@elyasimt/scalable-load-testing-with-k6-operator-prometheus-and-grafana-on-k8s-e8dac5062f7c)  
35. Configuring SCTP & NGAP with UERANSIM and Open5GS on a Single VM for the Open5GS & UERANSIM Series \- YouTube, accessed May 14, 2026, [https://www.youtube.com/watch?v=INgEX5L5fkE](https://www.youtube.com/watch?v=INgEX5L5fkE)  
36. Shadow Deployment in Microservices \- GeeksforGeeks, accessed May 14, 2026, [https://www.geeksforgeeks.org/system-design/shadow-deployment-in-microservices/](https://www.geeksforgeeks.org/system-design/shadow-deployment-in-microservices/)  
37. Deployment \- Istio, accessed May 14, 2026, [https://istio.io/latest/about/deployment/](https://istio.io/latest/about/deployment/)