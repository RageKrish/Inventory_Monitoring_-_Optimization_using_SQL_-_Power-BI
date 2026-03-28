-- PRE-REQUISITE:
-- Table `raw_inventory` must already exist in the database.
-- I have loaded it using python code in jupyter notebook. i am writing the code in comments over here , so that it can be copied .
-- import pandas as pd
-- from sqlalchemy import create_engine
-- df = pd.read_csv('inventory_forecasting.csv')
-- user = 'root'  # Use your username
-- password = 'password'  # Use your actual password
-- host = 'localhost'
-- port = '3306'
-- database = 'inventory_project'
-- engine = create_engine(f"mysql+mysqlconnector://{user}:{password}@{host}:{port}/{database}")
-- df.to_sql(name='raw_inventory', con=engine, if_exists='replace', index=False)
-- print(" CSV successfully loaded into MySQL as 'raw_inventory' table.")

 CREATE DATABASE inventory_project;
 USE inventory_project;

-- Stores Table
CREATE TABLE Stores (
    store_id VARCHAR(10) PRIMARY KEY,
	region VARCHAR(50)
);

-- Products Table
 CREATE TABLE Products (
     product_id VARCHAR(10) PRIMARY KEY,
     category VARCHAR(50)
 );

-- Inventory_Records Table
 CREATE TABLE Inventory_Records (
     record_id INT AUTO_INCREMENT PRIMARY KEY,
     date DATE,
     store_id VARCHAR(10),
     product_id VARCHAR(10),
     inventory_level INT,
     units_sold INT,
     units_ordered INT,
     demand_forecast FLOAT,
     price FLOAT,
     discount INT,
     weather_condition VARCHAR(30),
     holiday_promotion BOOLEAN,
     competitor_pricing FLOAT,
     seasonality VARCHAR(30),
     FOREIGN KEY (store_id) REFERENCES Stores(store_id),
     FOREIGN KEY (product_id) REFERENCES Products(product_id)
 );

-- Inserting unique stores into Stores table by concatenating
 INSERT INTO Stores (store_id, region)
 SELECT DISTINCT
     CONCAT(`Store ID`, '_', Region) AS store_id,
     Region
 FROM raw_inventory;

-- Inserting unique products into Products table
 INSERT INTO Products (product_id, category)
 SELECT DISTINCT
     `Product ID`,
     Category
 FROM raw_inventory;
 
-- Inserting full data into Inventory_Records table
 INSERT INTO Inventory_Records (
     date,
     store_id,
     product_id,
     inventory_level,
     units_sold,
     units_ordered,
     demand_forecast,
     price,
     discount,
     weather_condition,
     holiday_promotion,
     competitor_pricing,
     seasonality
 )
 SELECT
     STR_TO_DATE(`Date`, '%Y-%m-%d'),
     CONCAT(`Store ID`, '_', Region),
     `Product ID`,
     `Inventory Level`,
     `Units Sold`,
     `Units Ordered`,
     `Demand Forecast`,
     Price,
     Discount,
     `Weather Condition`,
     `Holiday/Promotion`,
     `Competitor Pricing`,
     Seasonality
 FROM raw_inventory;




-- Getting latest stock level of each product in each store
SELECT store_id,product_id, date AS "latest_date", inventory_level
FROM (SELECT *, ROW_NUMBER() OVER( PARTITION BY store_id, product_id ORDER BY date DESC ) AS rn
		FROM inventory_records ) t
        WHERE rn = 1;

-- Low inventory detection (average units sold vs current stock)
 WITH avg_sales_last_30_days AS (
     SELECT
         store_id,
         product_id,
         ROUND(SUM(units_sold)/30, 2) AS avg_daily_sales
     FROM Inventory_Records
     WHERE date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
     GROUP BY store_id, product_id
 ),

 latest_stock AS (
    SELECT store_id,product_id, date AS "latest_date", inventory_level
FROM (SELECT *, ROW_NUMBER() OVER( PARTITION BY store_id, product_id ORDER BY date DESC ) AS rn
		FROM inventory_records ) t
        WHERE rn = 1
 )

 SELECT
     l.store_id,
     l.product_id,
     l.inventory_level,
     a.avg_daily_sales,
     CASE 
         WHEN l.inventory_level < a.avg_daily_sales THEN ' Low Stock'
         ELSE 'OK'
     END AS inventory_status
 FROM latest_stock l
 JOIN avg_sales_last_30_days a
     ON l.store_id = a.store_id AND l.product_id = a.product_id
 ORDER BY l.store_id, l.product_id;

-- Estimating reorder point for each product in each store
-- Formula Used for calculation : Reorder Point = Avg Daily Sales × Lead Time
-- ASSUMPTIONS Used : Lead time = 7 days and 30-day moving average for demand

# Refined method
SELECT store_id, product_id, SUM(units_sold)/30 AS avg_daily_sales , SUM(units_sold)/30*7 AS Estimated_reorder_point
FROM inventory_records
WHERE date > DATE_SUB((SELECT MAX(date) FROM inventory_records), INTERVAL 30 DAY)
GROUP BY store_id,product_id;

 WITH avg_sales_last_30_days AS (
     SELECT
         store_id,
         product_id,
         ROUND(AVG(units_sold), 2) AS avg_daily_sales
     FROM Inventory_Records
     WHERE date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
     GROUP BY store_id, product_id
 )

 SELECT
     store_id,
     product_id,
     avg_daily_sales,
     ROUND(avg_daily_sales * 7, 2) AS estimated_reorder_point  -- assuming 7-day lead time
 FROM avg_sales_last_30_days
 ORDER BY store_id, product_id;

-- Inventory Turnover Ratio per store-product in last 30 days ( Also using speed label )
-- Formula Used : Inventory Turnover = Total Units Sold / Average Inventory Level

SELECT store_id, product_id, SUM(units_sold) AS Total_units_sold , AVG(inventory_level) AS avg_inventory_level , SUM(units_sold)/AVG(inventory_level) AS Inventory_turnover,
CASE WHEN SUM(units_sold)/AVG(inventory_level) > 10 THEN "Fast_moving"
	 WHEN SUM(units_sold)/AVG(inventory_level) > 5 THEN " OK moving"
     ELSE "slow moving" END AS Product_speed
FROM inventory_records
WHERE date > DATE_SUB((SELECT MAX(date) FROM inventory_records), INTERVAL 30 DAY)
GROUP BY store_id, product_id;


 WITH sales AS (
     SELECT
         store_id,
         product_id,
         SUM(units_sold) AS total_units_sold
     FROM Inventory_Records
     WHERE date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
     GROUP BY store_id, product_id
 ),

 inventory AS (
     SELECT
         store_id,
         product_id,
         ROUND(AVG(inventory_level), 2) AS avg_inventory
     FROM Inventory_Records
     WHERE date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
     GROUP BY store_id, product_id
 )

 SELECT
     s.store_id,
     s.product_id,
     s.total_units_sold,
     i.avg_inventory,
     ROUND(s.total_units_sold / NULLIF(i.avg_inventory, 0), 2) AS inventory_turnover_ratio,
     CASE
         WHEN ROUND(s.total_units_sold / NULLIF(i.avg_inventory, 0), 2) >= 10 THEN ' Fast-Moving Product'
         WHEN ROUND(s.total_units_sold / NULLIF(i.avg_inventory, 0), 2) >= 5 THEN ' OK Inventory Flow'
         ELSE ' Slow-Moving Product'
     END AS product_speed
 FROM sales s
 JOIN inventory i
   ON s.store_id = i.store_id AND s.product_id = i.product_id;

-- Best-Selling Product per Region in Last 30 Days

  
SELECT t.product_id, t.units_sold , t.region
FROM 	(SELECT  i.product_id AS product_id, SUM(i.units_sold) AS units_sold,s.region AS region , ROW_NUMBER() OVER(PARTITION BY s.region ORDER BY SUM(i.units_sold) DESC) AS rn
		 FROM inventory_records i 
		 JOIN stores s
		 ON i.store_id = s.store_id 
         WHERE date >= DATE_SUB((SELECT MAX(date) FROM inventory_records), INTERVAL 30 DAY)
		 GROUP BY product_id,region) t
WHERE rn =1 ;

 WITH recent_sales AS (
     SELECT
         s.region,
         i.product_id,
         SUM(i.units_sold) AS total_units_sold
     FROM Inventory_Records i
     JOIN Stores s ON i.store_id = s.store_id
     WHERE i.date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
     GROUP BY s.region, i.product_id
 ),

 ranked_products AS (
     SELECT *,
            RANK() OVER (PARTITION BY region ORDER BY total_units_sold DESC) AS rank_in_region
     FROM recent_sales
 )

 SELECT region, product_id, total_units_sold
 FROM ranked_products
 WHERE rank_in_region = 1;

-- Estimating Days of Inventory Left
 WITH latest_inventory AS (
     SELECT
         store_id,
         product_id,
         MAX(date) AS latest_date,
         MAX(inventory_level) AS current_inventory
     FROM Inventory_Records
     GROUP BY store_id, product_id
 ),

 avg_sales AS (
     SELECT
         store_id,
         product_id,
         ROUND(AVG(units_sold), 2) AS avg_daily_sales
     FROM Inventory_Records
     WHERE date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
     GROUP BY store_id, product_id
 )

 SELECT
     li.store_id,
     li.product_id,
     li.current_inventory,
     a.avg_daily_sales,
     ROUND(li.current_inventory / NULLIF(a.avg_daily_sales, 0), 2) AS days_of_inventory_left
 FROM latest_inventory li
 JOIN avg_sales a ON li.store_id = a.store_id AND li.product_id = a.product_id
 ORDER BY days_of_inventory_left ASC;

-- Calculating Dead Stock (No Sales in Last 30 Days)
 WITH recent_activity AS (
     SELECT
         store_id,
         product_id,
         SUM(units_sold) AS total_units_sold
     FROM Inventory_Records
     WHERE date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
     GROUP BY store_id, product_id
 )

 SELECT *
 FROM recent_activity
 WHERE total_units_sold = 0;

-- Detecting Products with Sales Drop compared to Previous Month
 WITH current_month AS (
     SELECT
         store_id,
         product_id,
         AVG(units_sold) AS avg_sales_recent
     FROM Inventory_Records
     WHERE date BETWEEN DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
                    AND (SELECT MAX(date) FROM Inventory_Records)
     GROUP BY store_id, product_id
 ),

 previous_month AS (
     SELECT
         store_id,
         product_id,
         AVG(units_sold) AS avg_sales_previous
     FROM Inventory_Records
     WHERE date BETWEEN DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 60 DAY)
                    AND DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 31 DAY)
     GROUP BY store_id, product_id
 )

 SELECT
     c.store_id,
     c.product_id,
     ROUND(p.avg_sales_previous, 2) AS avg_sales_prev_month,
     ROUND(c.avg_sales_recent, 2) AS avg_sales_this_month,
     ROUND(c.avg_sales_recent - p.avg_sales_previous, 2) AS change_in_avg_sales
 FROM current_month c
 JOIN previous_month p
   ON c.store_id = p.store_id AND c.product_id = p.product_id
 WHERE (c.avg_sales_recent - p.avg_sales_previous) < 0
 ORDER BY change_in_avg_sales ASC;

-- STOCKOUT RATE DETECTION ( Calculating the percentage of days a product had zero inventory in the last 30 days.)
 WITH zero_days AS (
   -- Counting how many days inventory was zero for each product in each store
   SELECT store_id, product_id, COUNT(*) AS zero_days
   FROM Inventory_Records
   WHERE inventory_level = 0
     AND date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
   GROUP BY store_id, product_id
 ),
 total_days AS (
   -- Counting total number of inventory records (days) for each product-store in last 30 days
   SELECT store_id, product_id, COUNT(*) AS total_days
   FROM Inventory_Records
   WHERE date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)
   GROUP BY store_id, product_id
 )

 -- Calculating stockout rate as: (zero days / total days) * 100
 SELECT
   z.store_id,
   z.product_id,
   ROUND((z.zero_days / t.total_days) * 100, 2) AS stockout_rate_percent
 FROM zero_days z
 JOIN total_days t ON z.store_id = t.store_id AND z.product_id = t.product_id
 ORDER BY stockout_rate_percent DESC
 LIMIT 20; -- Show  only top 20 most out-of-stock items

-- INVENTORY AGE ESTIMATION ( estimating how long a product typically stays in inventory(in days) )
-- Formula Used : average_inventory_level / average_daily_sales
 SELECT
   store_id,
   product_id,

   -- Average inventory level over the past 30 days
   ROUND(AVG(inventory_level), 2) AS avg_stock_level,

   -- Average daily units sold over the past 30 days
   ROUND(SUM(units_sold)/30, 2) AS avg_daily_sales,

   -- Approximate inventory age in days
   ROUND(AVG(inventory_level) / NULLIF(SUM(units_sold)/30, 0), 2) AS avg_inventory_age_days

 FROM Inventory_Records
 WHERE date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)

 GROUP BY store_id, product_id
 ORDER BY avg_inventory_age_days DESC
 LIMIT 20; -- Top 20 slowest-moving items

-- AVERAGE STOCK LEVEL per Store-Product (Calculating the average inventory level per store-product combination over the past 30 days)
 SELECT
   store_id,
   product_id,
   ROUND(AVG(inventory_level), 2) AS avg_inventory_level_30_days

 FROM Inventory_Records
 WHERE date >= DATE_SUB((SELECT MAX(date) FROM Inventory_Records), INTERVAL 30 DAY)

 GROUP BY store_id, product_id
 ORDER BY avg_inventory_level_30_days DESC
 LIMIT 20; -- Top 20 highest average stock items

-- CREATING USEFUL INDICES
-- Index on date: used frequently in WHERE clauses (last 30/60 days)
 CREATE INDEX idx_date ON Inventory_Records(date);
-- Composite index: store_id + product_id (Used heavily in GROUP BY, JOINs, and filters)
 CREATE INDEX idx_store_product ON Inventory_Records(store_id, product_id);
-- Index on inventory_level: useful for fast detection of low stock
 CREATE INDEX idx_inventory_level ON Inventory_Records(inventory_level);
-- Index on region: speeds up GROUP BY region and regional analysis
 CREATE INDEX idx_region ON Stores(region);

