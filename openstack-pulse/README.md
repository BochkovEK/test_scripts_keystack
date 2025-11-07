openstack_pulse/
├── pulse.py              # Основной скрипт (запуск + логика сбора)
├── region.yml            # Конфигурация региона
├── logger.py             # Логирование и сохранение отчетов
├── .env                  # Секретные данные (в .gitignore)
├── .env-template         # Шаблон для .env с примерами
├── services/               # Модули проверок
│   ├── keystone.py
│   ├── nova.py
│   ├── neutron.py
│   ├── rabbitmq.py
│   └── galera.py
└── config/               # Конфигурация
    ├── config.py         # Загрузчик конфигов
    └── config.yml        # Базовые настройки

Для зауска необходимо:
    1) Наличие переменных окружения согласно .env-template
        cp .env.template .env
        vi .env
    2) Назначить переменные окружения
        source .env
    3) Файл inventory в корне проекта openstack-pulse (описание узлов стенда)
    4) Настроить параметры диагностики
        сp ./config/config.yml.template ./config/config.yml
        vi ./config/config.yml
    4) Запустить скрипт
        python ./openstack_pulse.py