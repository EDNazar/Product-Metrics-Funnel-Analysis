-- DAU (Daily Active Users) Активные пользователи за день
--За конкретный день 
select event_date, count(distinct user_id) as dau
from user_events 
where event_date = '2026-07-13'
group by event_date


--DAU для каждого дня за последнюю неделю
with daily_users as (
	select
		event_date,
		count(distinct user_id) as dau,
		count(distinct case when device_type = 'mobile' then user_id end) as mobile_dau,
		count(distinct case when device_type = 'desktop' then user_id end) as desktop_dau
	from user_events
	where event_date between current_date - 7 and current_date - 1 
	group by event_date
)
select 
	event_date,
	dau,
	mobile_dau,
	desktop_dau,
	round(
		(dau-lag(dau) over (order by event_date))*100.0 /
		lag(dau) over (order by event_date),
		2
	) as daily_change_percent
	from daily_users
	order by event_date desc

--WAU 
WITH cnt_for_wau as (
	select 
		to_char(event_date, 'yyyy-ww') as week,
		count(distinct user_id) as cnt
	from user_events
	group by week
)
SELECT avg(cnt) AS wau
FROM cnt_for_wau

--Stickiness(Липкость) DAU/MAU

with monthly_stats as (
-- MAU
	select 
		count(distinct user_id) as mau
		from user_events
		where event_date between current_date - 30 and current_date - 1
),
daily_avg as (
-- средний DAU за 30 дней
	select 
		avg(daily_users) as avg_dau
	from (
		select 
			event_date,
			count(distinct user_id) as daily_users
		from user_events 
		where event_date between current_date - 30 and current_date - 1
		group by event_date
	) t
)
select 
	round(avg_dau/mau*100, 2) as stickiness_percent
	from monthly_stats, daily_avg

-- Воронка конверсии
-- Шаги воронки:
-- Визит - пользователь зашёл на сайт
-- Поиск - начал искать
-- Создание - дошел до публикации объявления

with funnel_base as (
	select
		user_id,
		max(case when event_type = 'view' then 1 else 0 end) as visited,
		max(case when event_type = 'search' then 1 else 0 end) as searched,
		max(case when event_type = 'create_ads' then 1 else 0 end) as created_ads
	from user_events
	where event_date between current_date - 30 and current_date -1
	group by user_id
),
funnel_stats as (
	select 
		count(*) as total_users,
		sum(visited) as visited_users,
		sum(searched) as searched_users,
		sum(created_ads) as creators
	from funnel_base
)
select
	visited_users as step_1_visit,
	-- конверсия из визита в поиск
	round(100.0 * searched_users/visited_users, 2) as search_conv_percent,
	searched_users as step_2_search,
	round(100.0 * creators/searched_users, 2) as create_conv_percent,
	creators as step_3_create,
	--общая конверсия - из визита в создание
	round(100.0 * creators/visited_users, 2) as overall_conv_percent
from funnel_stats;

-- Детализация воронки по категориям

with ads_funnel as (
	select 
		u.user_id,
		u.city,
		--берём категория из объявления, если оно есть
		coalesce(a.category_id::text, 'no_ads') as category,
		-- был ли факт создания объявления за период
		max(case when ue.event_type = 'create_ads' then 1 else 0 end) as created
	from users u
	-- присоединяем события (left join, чтобы были все пользователи)
	left join user_events ue on ue.user_id = u.user_id
		and ue.event_date between current_date - 30 and current_date - 1
	-- присоединям объявления, созданные за период
	left join ads a on a.user_id = u.user_id
		and a.created_at between current_date - 30 and current_date - 1
	where u.registration_date <= current_date - 1
	group by u.user_id, u.city, coalesce(a.category_id::text, 'no_ads')
)
select
	category,
	count(*) as users_in_category,
	sum(created) as created_ads,
	round(100.0 * sum(created)/count(*), 2) as conversion_rate
from ads_funnel
where category != 'no_ads' -- убираем тех, у кого нет объявления
group by category
order by conversion_rate desc

-- Retention(удержание) -когортный анализ
-- 1. Определяем когорты
with user_cohorts as (
	select 
		user_id,
		date_trunc('week', registration_date) as cohort_week
	from users
	where registration_date >= current_date - 90
),
-- 2. Посмотрим активность пользователей по неделям
user_activity as (
	select
		uc.user_id,
		uc.cohort_week,
		date_trunc('week', ue.event_date) as activity_week
		from user_cohorts uc
		join user_events ue on uc.user_id = ue.user_id
		where ue.event_date >= uc.cohort_week -- только после регистрации
		group by uc.user_id, uc.cohort_week, date_trunc('week', ue.event_date)
),
-- считаем размер каждой когорты
cohort_size as (
	select 
		cohort_week,
		count(distinct user_id) as users_in_cohort
	from user_cohorts
	group by cohort_week
)
--считаем retention
select
	cs.cohort_week,
	cs.users_in_cohort,
	round(100.0 * count(distinct case when ua.activity_week = cs.cohort_week then ua.user_id end)/cs.users_in_cohort, 2) as week_0,
	round(100.0 * count(distinct case when ua.activity_week = cs.cohort_week + interval '1 week' then ua.user_id end)/cs.users_in_cohort, 2) as week_1,
	round(100.0 * count(distinct case when ua.activity_week = cs.cohort_week + interval '2 week' then ua.user_id end)/cs.users_in_cohort, 2) as week_2,
	round(100.0 * count(distinct case when ua.activity_week = cs.cohort_week + interval '4 week' then ua.user_id end)/cs.users_in_cohort, 2) as week_4
from cohort_size cs
left join user_activity ua on cs.cohort_week = ua.cohort_week
group by cs.cohort_week, cs.users_in_cohort
order by cs.cohort_week desc

-- Метрики монетизации (ARPU, ARPPU)
with monthly_revenue as (
	select
		date_trunc('month', payment_date) as month,
		count(distinct user_id) as paying_users,
		sum(amount) as total_revenue,
		avg(amount) as avg_check
	from payments
	where payment_date >= current_date - 90
	group by date_trunc('month', payment_date)
),
monthly_active as (
	select 
		date_trunc('month', event_date) as month,
		count(distinct user_id) as active_users
	from user_events
	where event_date >= current_date - 90
	group by date_trunc('month', event_date)
)
select
	mr.month,
	ma.active_users,
	mr.paying_users,
	-- Доля платящих
	round(100.0 * mr.paying_users/ma.active_users, 2) as paying_share_percent,
	--ARPU
	round(mr.total_revenue/ma.active_users, 2) as arpu,
	--ARPPU
	round(mr.total_revenue/mr.paying_users, 2) as arppu,
	round(mr.avg_check, 2) as avg_check
from monthly_active ma
left join monthly_revenue mr on mr.month=ma.month
order by mr.month desc

--LTV (Life Time Value)
with user_ltv as (
	select
		u.user_id,
		date_trunc('month', u.registration_date) as cohort,
		--количество месяцев с регистрации до платежа
		extract(month from age(p.payment_date, u.registration_date)) as lifetime_month,
		sum(p.amount) as monthly_revenue
	from users u
	left join payments p on p.user_id = u.user_id
	where u.registration_date >= current_date - 180
	group by u.user_id, date_trunc('month', u.registration_date),
		extract(month from age(p.payment_date, u.registration_date))
)
select 
	cohort,
	lifetime_month,
	count(distinct user_id) as users_in_cohort,
	sum(monthly_revenue) as total_revenue,
	--накопленный доход на пользователя
	round(sum(monthly_revenue)/nullif(count(distinct user_id), 0), 2) as revenue_per_user
from user_ltv
where lifetime_month <= 6
group by cohort, lifetime_month
order by cohort, lifetime_month

--Выводим все метрики за последнюю неделю

with last_week as (
	select 
		(select count(distinct user_id)
		from user_events
		where event_date = current_date - 7) as dau,

		(select count(*)
		from ads
		where created_at = current_date - 10) as new_ads_week,

		(select coalesce(sum(amount), 0)
		from payments
		where payment_date = current_date - 10) as revenue_week,

		(select count(distinct user_id)
		from payments
		where payment_date = current_date - 10) as paying_users_week
)
select 
	dau,
	new_ads_week,
	revenue_week,
	paying_users_week,
	-- процент платящих от активных
	case
		when dau > 0
		then round(100.0*paying_users_week/dau, 2)
		else 0
	end as paying_share_percent,
	--arpu за сегодня
	case 
		when dau > 0
		then round(revenue_week/dau, 2)
		else 0
	end as arpu_week
from last_week