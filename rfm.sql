- - фильтруем клиентов, выводим номера карт длинной 13 символов, дату транзакции, последнюю дату транзакции, сумму всех покупок за вычетом скидок
with filtr_clients as (
		select
			card AS client_id,
			datetime::date as transaction_date,
			max (datetime::date) over () as max_date,
			summ_with_disc as summ
			from bonuscheques
			WHERE LENGTH (card) = 13
),
- - выводим показатели recency, frequency, monetary для каждого клиента
rfm_value as (
		select
			client_id,
			max (max_date - transaction_date) as recency,
			count(*) as frequency,
			sum (summ) as monetary
		from filtr_clients
		group by client_id
),
- - вычисляем перцентиль для каждой группы по recency, frequency, monetary. Группы recency и monetary мы будем делить равномерно, потому что сильных разрывов нет, а вот frequency делим с пороговыми значениями 70 и 88, поскольку огромное количество клиентов, сделавших покупки 1 - 3 раза. Также есть небольшая группа клиентов, которые делали частые покупки (более 1 раза в месяц)
percentiles as (
		select
     		percentile_cont(0.33) within group (order by recency) as recency_percentile_33,
     		percentile_cont(0.66) within group (order by recency) as recency_percentile_66,
     		percentile_cont(0.70) within group (order by frequency) as frequency_percentile_70,
     		percentile_cont(0.88) within group (order by frequency) as frequency_percentile_88,
     		percentile_cont(0.33) within group (order by monetary) as monetary_percentile_33,
     		percentile_cont(0.66) within group (order by monetary) as monetary_percentile_66
     		from rfm_value
),
- - для каждого recency, monetary, frequency присваиваем числовые группы от 1 до 3, где 1 - отличный показатель, 2 - средний, 3 - плохой. Обращаю внимание, что показатель recency мы рассчитываем противоположно, потому что чем позднее дата покупки, тем хуже
rfm_groups as (
		select
			client_id,
			recency,
			frequency,
			monetary,
			case
					when v.recency > recency_percentile_66 then 3
          				when v.recency > recency_percentile_33 then 2
          				else 1
     			end as recency_group,
     		case
          				when v.frequency > frequency_percentile_88 then 1
          				when v.frequency > frequency_percentile_70 then 2
          				else 3
     			end as frequency_group,
     		case
          				when v.monetary > monetary_percentile_66 then 1
          				when v.monetary > monetary_percentile_33 then 2
          				else 3
     			end as monetary_group			
			from rfm_value v
			cross join percentiles p
),
- - объдиняем получившиеся группы в одну группу из трех цифр (111, 121, 123 и т.д.)
rfm_column as (
		select
			client_id,
			recency,
			recency_group,
			frequency,
			frequency_group,
			monetary,
			monetary_group,
			concat(recency_group, frequency_group, monetary_group) as rfm
		from rfm_groups		
)
- - присваиваем названия получившимся группам - сегментам, где, например, 111 - VIP-клиенты, поскольку покупали недавно, часто, и на большие суммы, а 333 - Потерянные и случайные, т.к. покупали давно, один раз и на небольшую сумму. Выводим полученные данные.
	select *,
		case
     	when rfm in ('111') then 'VIP-клиенты'
     	when rfm in ('112', '113', '121', '122', '123') then 'Постоянные клиенты'
     	when rfm in ('131', '132', '133' ) then 'Новички'
		when rfm in ('211', ‘311’) then 'Спящие VIP-клиенты'
     	when rfm in ( '212', '213', '221', '222', '223', '231', '232', '233') then 'Спящие'
     	when rfm in ('313', '312') then 'Уходящие постоянные'
     	when rfm in ('321', '322', '323') then 'Уходящие редкие'
     	when rfm in ('331', '332', '333') then 'Потерянные и случайные'
	end as rfm_segment
	from rfm_column
order by rfm
