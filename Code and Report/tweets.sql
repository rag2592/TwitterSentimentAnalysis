 -- Creation of tweets raw table from the live stream

CREATE EXTERNAL TABLE Mytweets_raw (
   id BIGINT,
   created_at STRING,
   source STRING,
   favorited BOOLEAN,
   retweet_count INT,
   retweeted_status STRUCT<
      text:STRING,
      user:STRUCT<screen_name:STRING,name:STRING>>,
   entities STRUCT<
      urls:ARRAY<STRUCT<expanded_url:STRING>>,
      user_mentions:ARRAY<STRUCT<screen_name:STRING,name:STRING>>,
      hashtags:ARRAY<STRUCT<text:STRING>>>,
   text STRING,
   user STRUCT<
      screen_name:STRING,
      name:STRING,
      friends_count:INT,
      followers_count:INT,
      statuses_count:INT,
      verified:BOOLEAN,
      utc_offset:INT,
      time_zone:STRING>,
   in_reply_to_screen_name STRING
) 
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
LOCATION '/user/root/data/tweets_raw';

-- Create a tabel for the dictionary
CREATE EXTERNAL TABLE dictionary (
    type string,
    length int,
    word string,
    pos string,
    stemmed string,
    polarity string
)


ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t' 
STORED AS TEXTFILE
LOCATION '/data/dictionary';

-- loading data to the table dictionary
load data inpath 'data/dictionary/dictionary.tsv' INTO TABLE dictionary;

CREATE EXTERNAL TABLE time_zone_map (
    time_zone string,
    country string
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t' 
STORED AS TEXTFILE
LOCATION '/data/time_zone_map';

-- loading data to the table time_zone_map
load data inpath 'data/time_zone_map/time_zone_map.tsv' INTO TABLE time_zone_map;


-- Clean up tweets
CREATE VIEW tweets_simple AS
SELECT
  id,
  cast ( from_unixtime( unix_timestamp(concat( '2014 ', substring(created_at,5,15)), 'yyyy MMM dd hh:mm:ss')) as timestamp) ts,
  text,
  user.time_zone 
FROM Mytweets_raw
;

CREATE VIEW tweets_clean AS
SELECT
  id,
  ts,
  text,
  m.country 
 FROM tweets_simple t LEFT OUTER JOIN time_zone_map m ON t.time_zone = m.time_zone;

 
 -- Sentiment Computation
create view l1 as select id, words from Mytweets_raw lateral view explode(sentences(lower(text))) dummy as words;
create view l2 as select id, word from l1 lateral view explode( words ) dummy as word ;

-- calculating the polarity of the words in the tweet

create view l3 as select 
    id, 
    l2.word, 
    case d.polarity 
      when  'negative' then -1
      when 'positive' then 1 
      else 0 end as polarity 
 from l2 left outer join dictionary d on l2.word = d.word;
 
 create table tweets_sentiment as select 
  id, 
  case 
    when sum( polarity ) > 0 then 'positive' 
    when sum( polarity ) < 0 then 'negative'  
    else 'neutral' end as sentiment 
 from l3 group by id;
 
 
 -- put everything back together and re-name sentiments...
CREATE TABLE tweetsbi 
AS
SELECT 
  t.*,
  s.sentiment 
FROM tweets_clean t LEFT OUTER JOIN tweets_sentiment s on t.id = s.id;

-- data with tweet counts.....
CREATE TABLE tweetsbiaggr 
AS
SELECT 
  country,sentiment, count(sentiment) as tweet_count 
FROM tweetsbi
group by country,sentiment;

-- store data for analysis......

CREATE VIEW A as select country,tweet_count as positive_response from tweetsbiaggr where sentiment='positive';
CREATE VIEW B as select country,tweet_count as negative_response from tweetsbiaggr where sentiment='negative';
CREATE VIEW C as select country,tweet_count as neutral_response from tweetsbiaggr where sentiment='neutral';
CREATE TABLE tweetcompare as select A.*,B.negative_response as negative_response,C.neutral_response as neutral_response from A join B on A.country= B.country join C on B.country=C.country;
 
 -- permission to show data in Excel sheet for analysis ....
grant SELECT ON TABLE tweetcompare to user hue;
grant SELECT ON TABLE tweetcompare to user root;


