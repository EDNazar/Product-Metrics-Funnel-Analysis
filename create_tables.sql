-- Создаем схемы
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS user_events;
DROP TABLE IF EXISTS ads;
DROP TABLE IF EXISTS users;

-- 1. Таблица пользователей (1000 пользователей)
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    registration_date DATE,
    user_type VARCHAR(20),
    city VARCHAR(100),
    is_verified BOOLEAN
);

-- Генерируем пользователей с разными паттернами
INSERT INTO users (registration_date, user_type, city, is_verified)
SELECT 
    -- Регистрации равномерно за последние 180 дней
    CURRENT_DATE - (random() * 180)::int,
    -- 70% частных, 30% бизнесов
    CASE WHEN random() < 0.7 THEN 'private' ELSE 'business' END,
    -- Города с весами
    CASE 
        WHEN random() < 0.4 THEN 'Москва'
        WHEN random() < 0.6 THEN 'СПб'
        WHEN random() < 0.75 THEN 'Казань'
        WHEN random() < 0.85 THEN 'Новосибирск'
        ELSE 'Другой'
    END,
    -- 60% верифицированных
    random() < 0.6
FROM generate_series(1, 1000);

-- 2. Таблица объявлений (5000 объявлений)
CREATE TABLE ads (
    ad_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    category_id INT,
    price DECIMAL(10,2),
    created_at DATE,
    status VARCHAR(20)
);

-- Генерируем объявления
INSERT INTO ads (user_id, category_id, price, created_at, status)
SELECT 
    u.user_id,
    -- Категории с распределением
    CASE 
        WHEN random() < 0.25 THEN 1 -- Авто
        WHEN random() < 0.45 THEN 2 -- Недвижимость
        WHEN random() < 0.65 THEN 3 -- Услуги
        WHEN random() < 0.80 THEN 4 -- Электроника
        ELSE 5 -- Прочее
    END,
    -- Цены в зависимости от категории
    CASE 
        WHEN random() < 0.25 THEN (random() * 1500000 + 50000)::int -- Авто дорого
        WHEN random() < 0.45 THEN (random() * 10000000 + 1000000)::int -- Недвижимость очень дорого
        WHEN random() < 0.65 THEN (random() * 5000 + 500)::int -- Услуги среднее
        WHEN random() < 0.80 THEN (random() * 30000 + 1000)::int -- Электроника
        ELSE (random() * 10000 + 100)::int -- Прочее
    END,
    -- Дата создания за последние 90 дней
    CURRENT_DATE - (random() * 90)::int,
    -- Статус: 60% активны, 30% проданы, 10% в архиве
    CASE 
        WHEN random() < 0.6 THEN 'active'
        WHEN random() < 0.9 THEN 'sold'
        ELSE 'archived'
    END
FROM users u, generate_series(1, 5) -- по 5 объявлений на пользователя в среднем
WHERE random() < 0.7; -- но не у всех

-- 3. Таблица событий (активность пользователей) - 50,000 записей
CREATE TABLE user_events (
    event_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    event_date DATE,
    event_type VARCHAR(50),
    page_url VARCHAR(200),
    device_type VARCHAR(20)
);

-- Генерируем события
INSERT INTO user_events (user_id, event_date, event_type, page_url, device_type)
SELECT 
    u.user_id,
    -- Дата события в течение последних 60 дней
    CURRENT_DATE - (random() * 60)::int,
    -- Тип события с распределением
    CASE 
        WHEN random() < 0.5 THEN 'view'
        WHEN random() < 0.75 THEN 'search'
        WHEN random() < 0.9 THEN 'create_ads'
        WHEN random() < 0.97 THEN 'call'
        ELSE 'payment'
    END,
    -- URL в зависимости от события
    CASE 
        WHEN random() < 0.5 THEN '/'
        ELSE '/category=' || (1 + (random() * 5)::int)
    END,
    -- 70% мобила, 30% десктоп
    CASE WHEN random() < 0.7 THEN 'mobile' ELSE 'desktop' END
FROM users u, generate_series(1, 50) -- по 50 событий на пользователя
WHERE random() < 0.6; -- но не у всех

-- 4. Таблица платежей (монетизация) - 1000 записей
CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    payment_date DATE,
    amount DECIMAL(10,2),
    service_type VARCHAR(50)
);

-- Генерируем платежи (только для части пользователей)
INSERT INTO payments (user_id, payment_date, amount, service_type)
SELECT 
    u.user_id,
    -- Дата платежа за последние 90 дней
    CURRENT_DATE - (random() * 90)::int,
    -- Сумма в зависимости от услуги
    CASE 
        WHEN random() < 0.4 THEN 299 -- выделение
        WHEN random() < 0.7 THEN 999 -- поднятие
        ELSE 4990 -- пакет
    END,
    CASE 
        WHEN random() < 0.4 THEN 'vip'
        WHEN random() < 0.7 THEN 'raise'
        ELSE 'package'
    END
FROM users u, generate_series(1, 3) -- по 3 платежа максимум
WHERE random() < 0.15; -- только 15% пользователей платят


-- Создадим 20 "идеальных" рекламодателей
WITH gold_users AS (
    SELECT user_id FROM users 
    WHERE user_type = 'business' 
    ORDER BY random() 
    LIMIT 20
)
-- Добавим им много платежей
INSERT INTO payments (user_id, payment_date, amount, service_type)
SELECT 
    g.user_id,
    CURRENT_DATE - (random() * 180)::int,
    CASE WHEN random() < 0.3 THEN 4990 ELSE 999 END,
    CASE WHEN random() < 0.3 THEN 'package' ELSE 'raise' END
FROM gold_users g, generate_series(1, 10)
WHERE random() < 0.8;

-- Добавим им много объявлений
INSERT INTO ads (user_id, category_id, price, created_at, status)
SELECT 
    g.user_id,
    1 + (random() * 4)::int,
    (random() * 100000)::int,
    CURRENT_DATE - (random() * 60)::int,
    'active'
FROM gold_users g, generate_series(1, 20)
WHERE random() < 0.9;

-- 100 пользователей, которые были активны только в первую неделю
WITH dead_users AS (
    SELECT user_id FROM users 
    ORDER BY random() 
    LIMIT 100
)
-- Добавим им события только в первую неделю после регистрации
INSERT INTO user_events (user_id, event_date, event_type, page_url, device_type)
SELECT 
    d.user_id,
    u.registration_date + (random() * 7)::int,
    'view',
    '/',
    'mobile'
FROM dead_users d
JOIN users u ON d.user_id = u.user_id
WHERE random() < 0.3;

-- Продавцы шин (сезонный товар)
WITH tire_sellers AS (
    SELECT user_id FROM users 
    WHERE city IN ('Москва', 'СПб')
    ORDER BY random() 
    LIMIT 30
)
-- Добавим объявления о шинах (категория авто) только в октябре-ноябре
INSERT INTO ads (user_id, category_id, price, created_at, status)
SELECT 
    t.user_id,
    1, -- авто
    (random() * 20000 + 5000)::int,
    '2024-10-' || (10 + (random() * 20)::int), -- даты в октябре
    'active'
FROM tire_sellers t, generate_series(1, 5);