Delete from netflix_raw_data

-- Create table before uploading data using pandas
-- create with perfect sizes and datatypes

create TABLE [dbo].[netflix_raw_data](
	[show_id] [varchar](10) primary key,
	[type] [varchar](10) NULL,
	[title] [nvarchar](200) NULL, -- used nvarchar to handle foreign keys
	[director] [varchar](250) NULL,
	[cast] [varchar](1000) NULL,
	[country] [varchar](150) NULL,
	[date_added] [varchar](20) NULL,
	[release_year] [int] NULL,
	[rating] [varchar](10) NULL,
	[duration] [varchar](10) NULL,
	[listed_in] [varchar](100) NULL,
	[description] [varchar](500) NULL
) 

select * from netflix_raw_data

--Check duplicates existed or not
select show_id,count(*)
from netflix_raw_data
group by show_id
having count(*)>1

-- removing duplicate titles

delete from netflix_raw_data where concat(show_id,2) in (
select concat(show_id,rank() over(partition by title order by show_id)) from netflix_raw_data
where concat(title,release_year) in(
select concat(title,release_year) from netflix_raw_data
group by title,release_year
having count(*)>1)
)

-- observed 3 null values in duration and it duration in rating
select * from netflix_raw_data
where duration is null 

--Now we gather required columns netflix_raw_data

select show_id, type, title,
cast( date_added as date) date_added, -- converting varchar to date
release_year, rating,
case when duration is null then rating else duration end duration,-- handling duration
description
into netflix_stg_data
from netflix_raw_data -- director, cast,listed_in have multiple data so we are ignoring now

select * from netflix_stg_data

--director
select show_id,trim(value) as director
into netflix_director
from netflix_raw_data
cross apply string_split(director,',')

--listed_in
select show_id,trim(value) as genre
into netflix_genre
from netflix_raw_data
cross apply string_split(listed_in,',')

--cast
select show_id,trim(value) as cast
into netflix_cast
from netflix_raw_data
cross apply string_split(cast,',')

--country
select show_id,trim(value) as country
into netflix_country
from netflix_raw_data
cross apply string_split(country,',')

-- for some directors country be null in one row and country name in another row,
-- for that directors we are copying the country name and replace with null
-- for example 
--select * from netflix_raw where director='Ahishor Solomon'

insert into netflix_country
select  show_id,m.country 
from netflix_raw_data nr
inner join (
select director,country
from  netflix_country nc
inner join netflix_director nd on nc.show_id=nd.show_id
group by director,country
) m on nr.director=m.director
where nr.country is null

-- we can add default date to date_added column ( not doing now ) 


							--------netflix data analysis----------

/*1  for each director count the no of movies and tv shows created by them in separate columns 
for directors who have created tv shows and movies both */

select * from (
select director,
count( case when lower(type)='movie'  then ns.show_id else null end) movie_count,
count( case when lower(type)='tv show'  then ns.show_id else null end) tv_show_count
from netflix_stg_data ns inner join netflix_director nd  on ns.show_id=nd.show_id
group by director
) dir
where movie_count>0 and tv_show_count>0

select nd.director 
,COUNT(distinct case when n.type='Movie' then n.show_id end) as no_of_movies
,COUNT(distinct case when n.type='TV Show' then n.show_id end) as no_of_tvshow
from netflix_stg_data n
inner join netflix_director nd on n.show_id=nd.show_id
group by nd.director
having COUNT(distinct n.type)>1

--2 which country has highest number of comedy movies 

select top 1 country,count(distinct ng.show_id) no_of_movies from 
netflix_stg_data ns 
join netflix_genre ng on ns.show_id=ng.show_id 
join netflix_country nc on  ng.show_id=nc.show_id
where ns.type='Movie' and ng.genre='comedies'
group by nc.country
order by no_of_movies desc

--3 for each year (as per date added to netflix), which director has maximum number of movies released
with year_director_movie_cnt as (
select nd.director,year(date_added) yaer,count(nd.show_id) no_of_movies from netflix_director nd left join netflix_stg_data nsd
on nd.show_id=nsd.show_id
where type='Movie'
group by year(date_added),director)

select director, yaer, no_of_movies,rn from (
select *,row_number() over(partition by yaer order by cnt desc) rn from year_director_movie_cnt ) a
where rn=1;

--4 what is average duration of movies in each genre

select genre,avg(cast(replace(duration,' min','') as int)) average_duration from netflix_genre ng join netflix_stg_data nsd
on ng.show_id=nsd.show_id
where type='Movie'
group by genre

--5  find the list of directors who have created horror and comedy movies both.
-- display director names along with number of comedy and horror movies directed by them 
with director_genre as (
select director, genre )


select director,
count(case when genre='Horror Movies' then 1 else null end) as Horror,
count(case when genre='Comedies' then 1 else null end) as Comedy
from 
netflix_stg_data nsd 
join netflix_director nd on nsd.show_id=nd.show_id
join netflix_genre ng on nsd.show_id=ng.show_id
where type='Movie' and ng.genre in ( 'Comedies','Horror Movies')
group by director
having count(distinct ng.genre)=2

