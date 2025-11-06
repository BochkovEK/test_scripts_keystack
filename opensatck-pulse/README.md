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