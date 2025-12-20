# OpenStack SDK

Набор скриптов на основе модуля OpenStack-SDK.

## Скрипты
- **migration_tester.py** - циклическая миграция ВМ между гипревизорами

## Конфигурация

Конфигурация OpenStack Pulse осуществлятся по средствам переменных окружения и параметров запуска:

### Общие переменные окружения
Общие переменных окружения отвечают за авторизацию в облаке. Данные переменные определены в файле **openrc**

### Переменные окружения **migration_tester.py**
<details><summary>⚙️ Список переменных окружения migration_tester.py</summary>

```bash
# Основные настройки

# Список гипервизоров для миграции (обязательный параметр)
#export MIGRATION_TEST_HYPERVISORS="hyper-1,hyper-2,hyper-3,...,hyper-N"

# Общая длительность теста в секундах (60)
#export MIGRATION_TEST_DURATION=60

# Количество полных циклов миграции (колличество миграций всех ВМ по всем гиперам)
# Папамерт имеет преоритет над MIGRATION_TEST_DURATION
#export MIGRATION_TEST_FULL_CIRCLE=1	

# Таймаут для одной миграции (секунды; 300)
#export MIGRATION_TEST_MIGRATION_TIMEOUT=300

# Максимальное количество параллельных миграций (-1 = без ограничений; 2)
# Рекомендуется выбирать в соответсвии со значением max_concurrent_live_migrations  
#export MIGRATION_TEST_MAX_PARALLEL_MIGRATIONS=2

# Настройки повторных попыток

# Количество попыток повтора для неудачных миграций (3)
#export MIGRATION_TEST_RETRY_ATTEMPTS=3

# Задержка между повторными попытками (секунды; 10)
#export MIGRATION_TEST_RETRY_DELAY=10	

# Настройки вывода и логирования

# Уровень логирования (DEBUG, INFO, WARNING, ERROR; INFO)
#export MIGRATION_TEST_LOG_LEVEL=INFO

# Формат вывода результатов (table, json, text; table)
#export MIGRATION_TEST_OUTPUT_FORMAT=table	

# Файл для сохранения результатов JSON	(migration_results.json)
#export MIGRATION_TEST_RESULTS_FILE=migration_results.json
```
</details>

### Параметры запуска **migration_tester.py**
<details><summary>🚀 Список параметров запуска</summary>

```bash
🔧 Основные параметры миграции:
--hypervisors	Список гипервизоров для циклической миграции (через запятую)	--hypervisors hv1,hv2,hv3
--duration	Общее время теста в секундах (режим времени)	--duration 300
--full-circle	Количество полных циклов (режим циклов)	--full-circle 5
--max-parallel	Макс. параллельных миграций (-1 = без ограничений)	--max-parallel 3

⚡ Параметры выполнения:
--migration-timeout   Таймаут одной миграции в секундах	--migration-timeout 600
--retry-attempts      Количество попыток для неудачных миграций	--retry-attempts 5
--retry-delay         Задержка между попытками в секундах	--retry-delay 15
```
</details>

### Пример команд
```bash
python ~/test_scripts_keystack/openstack-sdk/migration_tester.py --hypervisors cdm-bl-pca10,cdm-bl-pca11,cdm-bl-pca12 --max-parallel 5 --full-circle 1
```
