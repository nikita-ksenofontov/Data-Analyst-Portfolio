-- Задача 1. Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id,
    city_id,
    type_id,
    total_area
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Распределили недвижимость по региону и сегменту активности
filtered_estate as (
	select
		case when city_id = '6X8I' then 'Санкт-Петербург'
			else 'Лен Область'
		end as "Регион",
		case when days_exposition <= 30 then '1-30 дней'
			when days_exposition > 30 and days_exposition <= 90 then '31-90 дней'
			when days_exposition > 90 and days_exposition <= 180 then '91-180 дней'
			when days_exposition > 180 then '180+ дней'
			else 'Активные объявления'
		end as "Сегмент активности",
		fi.id,
		last_price/total_area as price_metr
	from filtered_id fi
	join advertisement a using(id)
	join type t USING(type_id)
	where type = 'город'
)
-- Выведем объявления без выбросов:
select
	fe."Регион",
	fe."Сегмент активности",
	COUNT(fe.id) as "Кол-во объявлений",
    ROUND(COUNT(fe.id) * 100.0 / SUM(COUNT(fe.id)) OVER (PARTITION by "Регион"), 2) as "Доля объявлений",
	round(avg(fe.price_metr::numeric), 2) as "Средняя стоимость кв. метра",
	round(avg(total_area::numeric), 2) as "Средняя площадь",
	PERCENTILE_CONT(0.5) within group(order by rooms) as "Медиана кол-ва комнат",
	PERCENTILE_CONT(0.5) within group(order by balcony) as "Медиана кол-ва балконов",
	PERCENTILE_CONT(0.5) within group(order by floor) as "Медиана этажности",
	round(PERCENTILE_CONT(0.5) within group(order by ceiling_height)::numeric, 2) as "Медиана потолка"
from filtered_estate fe
join flats f using(id)
group by "Регион", "Сегмент активности"
order by "Регион", "Кол-во объявлений"; 

-- Задача 2. Сезонность объявлений
with limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Выделяем месяц публикации объявления и снятия с продажи
month_estate AS (
	SELECT
		a.id,
		last_price/total_area as price_metr,
		first_day_exposition,
		days_exposition,
		TO_CHAR(first_day_exposition::DATE, 'Month') as public_month,
		first_day_exposition + interval '1 day' * days_exposition as remove_date,
		TO_CHAR(first_day_exposition::DATE + interval '1 day' * days_exposition, 'Month') as remove_month
	from advertisement a
	JOIN flats f using(id)
	JOIN TYPE t using(type_id)
	where type = 'город'
	AND EXTRACT(YEAR FROM first_day_exposition) BETWEEN 2015 AND 2018
	AND total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Вычисляем по месяцам публикации
public_statistic AS (
	SELECT
		public_month,
		count(me.id) AS public_count,
		avg(total_area) AS public_area,
		avg(price_metr) as public_price
	FROM month_estate me
	JOIN flats f using(id)
	GROUP BY public_month
),
-- Вычисляем по месяцам снятия с продажи
remove_statistic AS (
	SELECT
		remove_month,
		count(me.id) AS remove_count,
		avg(total_area) AS remove_area,
		avg(price_metr) as remove_price
	FROM month_estate me
	JOIN flats f using(id)
	WHERE days_exposition IS NOT null
	GROUP BY remove_month
)
SELECT
	public_month AS "Месяц",
	RANK() over(ORDER BY public_count DESC) AS "Топ активности публикаций",
	ROUND(sum(public_count) * 100.0 / sum(public_count) OVER(), 2) as "Доля публикаций",
	public_count AS "Кол-во публикаций",
	round(public_area::numeric, 2) AS "Средняя площадь",
	round(public_price::NUMERIC, 2) AS "Средняя цена кв. метра",
	RANK() over(ORDER BY remove_count DESC) AS "Топ активности снятий",
	ROUND(sum(remove_count) * 100.0 / sum(remove_count) OVER(), 2) as "Доля снятий",
	remove_count AS "Кол-во снятий",
	round(remove_area::numeric, 2) AS "Средняя площадь",
	round(remove_price::NUMERIC, 2) AS "Средняя цена кв. метра"
FROM public_statistic ps 
FULL OUTER JOIN remove_statistic rs ON rs.remove_month = ps.public_month
GROUP BY public_month, public_count, public_area, public_price, remove_count, remove_area, remove_price


-- Задача 3. Анализ рынка недвижимости Ленобласти.
with limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
len_region AS (
	SELECT
		a.id,
		total_area,
		last_price/total_area AS price_metr,
		city,
		TYPE,
		days_exposition
	FROM advertisement a 
	JOIN flats f ON f.id = a.id
	JOIN TYPE t ON t.type_id = f.type_id
	JOIN city c ON c.city_id = f.city_id
	WHERE f.city_id <> '6X8I'
	AND total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
)
SELECT
	city AS "Населённый пункт",
	TYPE AS "Тип",
	count(id) AS "Кол-во объявлений",
	ROUND(COUNT(id) * 100.0 / SUM(COUNT(id)) OVER (), 2) as "Доля объявлений",
	round(count(days_exposition)/ count(id)::NUMERIC * 100, 2) AS "Доля снятых",
	round(avg(total_area)::numeric, 2) AS "Средняя площадь",
	round(avg(price_metr)::numeric, 2) AS "Средняя цена за кв. метр",
	round(avg(days_exposition)::numeric) AS "Средняя длительность публикации"
FROM len_region lr
GROUP BY city, TYPE
ORDER BY "Кол-во объявлений" DESC
LIMIT 15