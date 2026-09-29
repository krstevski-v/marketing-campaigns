USE marketing_campaign_model;
GO
CREATE OR ALTER PROCEDURE mart.RefreshFromStage
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LANGUAGE us_english;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM stg.CampaignDailyRaw)
            THROW 51000, 'Source is empty. Existing mart has been retained.', 1;
        SELECT TRY_CONVERT(int, NULLIF(TRIM(campaign_id), '')) AS CampaignId,
            NULLIF(TRIM(company), '') AS Company,
            TRY_CONVERT(date, NULLIF(TRIM([date]), ''), 23) AS [Date],
            NULLIF(TRIM(channel), '') AS Channel,
            NULLIF(TRIM(target_audience), '') AS TargetAudience,
            NULLIF(TRIM(location), '') AS Location,
            NULLIF(TRIM(language), '') AS Language,
            TRY_CONVERT(bigint, NULLIF(TRIM(impressions), '')) AS Impressions,
            TRY_CONVERT(bigint, NULLIF(TRIM(clicks), '')) AS Clicks,
            TRY_CONVERT(bigint, NULLIF(TRIM(conversions), '')) AS Conversions,
            TRY_CONVERT(decimal(19,2), NULLIF(TRIM(spend), '')) AS Spend,
            TRY_CONVERT(decimal(19,2), NULLIF(TRIM(revenue), '')) AS Revenue
        INTO #Clean FROM stg.CampaignDailyRaw;
        IF EXISTS (SELECT 1 FROM #Clean WHERE CampaignId IS NULL OR CampaignId <= 0
            OR [Date] IS NULL OR Company IS NULL OR Channel IS NULL
            OR TargetAudience IS NULL OR Location IS NULL OR Language IS NULL
            OR Impressions IS NULL OR Clicks IS NULL OR Conversions IS NULL
            OR Spend IS NULL OR Revenue IS NULL
            OR Impressions < 0 OR Clicks < 0 OR Conversions < 0 OR Spend < 0 OR Revenue < 0
            OR LEN(Company) > 100 OR LEN(Channel) > 100 OR LEN(TargetAudience) > 100
            OR LEN(Location) > 100 OR LEN(Language) > 100)
            THROW 51001, 'Invalid, missing, negative or overlength source values. Mart unchanged.', 1;
        IF EXISTS (SELECT 1 FROM stg.CampaignDailyRaw WHERE
            TRIM([date]) <> CONVERT(char(10), TRY_CONVERT(date, TRIM([date]), 23), 23)
            OR (CHARINDEX('.', TRIM(spend)) > 0 AND LEN(TRIM(spend)) - CHARINDEX('.', TRIM(spend)) > 2)
            OR (CHARINDEX('.', TRIM(revenue)) > 0 AND LEN(TRIM(revenue)) - CHARINDEX('.', TRIM(revenue)) > 2)
            OR TRY_CONVERT(decimal(38,10), TRIM(spend)) IS NULL
            OR TRY_CONVERT(decimal(38,10), TRIM(revenue)) IS NULL
            OR TRY_CONVERT(decimal(38,10), TRIM(spend)) <> TRY_CONVERT(decimal(19,2), TRIM(spend))
            OR TRY_CONVERT(decimal(38,10), TRIM(revenue)) <> TRY_CONVERT(decimal(19,2), TRIM(revenue)))
            THROW 51002, 'Dates must be ISO yyyy-MM-dd and money must have at most two decimals.', 1;
        IF EXISTS (SELECT CampaignId, [Date] FROM #Clean GROUP BY CampaignId, [Date] HAVING COUNT(*) > 1)
            THROW 51003, 'Duplicate campaign/date grain. No arbitrary deduplication is performed.', 1;
        IF EXISTS (SELECT CampaignId FROM #Clean GROUP BY CampaignId HAVING
            COUNT(DISTINCT Company COLLATE Latin1_General_100_BIN2) > 1
            OR COUNT(DISTINCT Channel COLLATE Latin1_General_100_BIN2) > 1
            OR COUNT(DISTINCT TargetAudience COLLATE Latin1_General_100_BIN2) > 1
            OR COUNT(DISTINCT Location COLLATE Latin1_General_100_BIN2) > 1
            OR COUNT(DISTINCT Language COLLATE Latin1_General_100_BIN2) > 1)
            THROW 51004, 'Campaign attributes change within the snapshot. Revisit dimension grain before loading.', 1;
        DELETE FROM mart.FactCampaignDaily;
        DELETE FROM mart.DimCampaign;
        DELETE FROM mart.DimDate;
        INSERT mart.DimCampaign
        SELECT CampaignId, MAX(Company), MAX(Channel), MAX(TargetAudience), MAX(Location), MAX(Language),
            MIN([Date]), MAX([Date]), DATEDIFF(day, MIN([Date]), MAX([Date])) + 1, COUNT(*),
            CASE WHEN DATEDIFF(day, MIN([Date]), MAX([Date])) + 1 < 30 THEN '< 30 Days'
                 WHEN DATEDIFF(day, MIN([Date]), MAX([Date])) + 1 <= 60 THEN '30-60 Days'
                 WHEN DATEDIFF(day, MIN([Date]), MAX([Date])) + 1 <= 90 THEN '61-90 Days' ELSE '90+ Days' END,
            CASE WHEN DATEDIFF(day, MIN([Date]), MAX([Date])) + 1 < 30 THEN 1
                 WHEN DATEDIFF(day, MIN([Date]), MAX([Date])) + 1 <= 60 THEN 2
                 WHEN DATEDIFF(day, MIN([Date]), MAX([Date])) + 1 <= 90 THEN 3 ELSE 4 END
        FROM #Clean GROUP BY CampaignId;
        DECLARE @First date = (SELECT DATEFROMPARTS(YEAR(MIN([Date])), 1, 1) FROM #Clean),
                @Last date = (SELECT DATEFROMPARTS(YEAR(MAX([Date])), 12, 31) FROM #Clean);
        ;WITH Calendar AS (
            SELECT @First AS d
            UNION ALL SELECT DATEADD(day, 1, d) FROM Calendar WHERE d < @Last
        )
        INSERT mart.DimDate
        SELECT d, YEAR(d), DATEPART(quarter, d), CONCAT('Q', DATEPART(quarter, d)),
            MONTH(d), DATENAME(month, d), LEFT(DATENAME(month, d), 3),
            YEAR(d) * 100 + MONTH(d), CONCAT(LEFT(DATENAME(month, d), 3), ' ', YEAR(d)),
            DAY(d), ((DATEDIFF(day, '19000101', d) % 7 + 7) % 7) + 1,
            DATENAME(weekday, d), CASE WHEN ((DATEDIFF(day, '19000101', d) % 7 + 7) % 7) >= 5 THEN 1 ELSE 0 END
        FROM Calendar OPTION (MAXRECURSION 0);
        INSERT mart.FactCampaignDaily
        SELECT CampaignId, [Date], Impressions, Clicks, Conversions, Spend, Revenue FROM #Clean;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE mart.LoadMarketingCsv
    @CsvPath nvarchar(4000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NULLIF(TRIM(@CsvPath), '') IS NULL
        THROW 51006, 'Provide the full path to marketing_data.csv.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @LockResult int;
        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'MarketingSnapshotLoad', @LockMode = 'Exclusive',
            @LockOwner = 'Transaction', @LockTimeout = 0;
        IF @LockResult < 0
            THROW 51005, 'Another load is running. Try again when it finishes.', 1;

        -- Escape quotes in the file path before using it in BULK INSERT.
        DECLARE @SafePath nvarchar(max) = REPLACE(@CsvPath, '''', '''''');
        DECLARE @Sql nvarchar(max), @Header varchar(max);
        SET @Sql = N'SELECT @Header = LEFT(BulkColumn,
            CHARINDEX(CHAR(10), BulkColumn + CHAR(10)) - 1)
            FROM OPENROWSET(BULK ''' + @SafePath + N''', SINGLE_CLOB, CODEPAGE = ''65001'') AS csv;';
        EXEC sys.sp_executesql @Sql, N'@Header varchar(max) OUTPUT', @Header OUTPUT;
        SET @Header = REPLACE(@Header, CHAR(13), '');
        IF @Header COLLATE Latin1_General_100_BIN2 <>
            'campaign_id;company;date;channel;target_audience;location;language;impressions;clicks;conversions;spend;rev'
            THROW 51007, 'CSV header does not match the expected column names and order.', 1;

        TRUNCATE TABLE stg.CampaignDailyRaw;
        SET @Sql = N'BULK INSERT stg.CampaignDailyRaw FROM ''' + @SafePath + N'''
            WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '';'',
                  ROWTERMINATOR = ''0x0a'', CODEPAGE = ''65001'', MAXERRORS = 0);';
        EXEC sys.sp_executesql @Sql;
        -- Accommodate both LF and CRLF files when using LF as the row terminator.
        UPDATE stg.CampaignDailyRaw
        SET revenue = LEFT(revenue, LEN(revenue) - 1)
        WHERE RIGHT(revenue, 1) = CHAR(13);

        EXEC mart.RefreshFromStage;
        COMMIT;

        SELECT COUNT(*) AS DailyRows, COUNT(DISTINCT CampaignId) AS Campaigns,
            MIN([Date]) AS FirstActivityDate, MAX([Date]) AS LastActivityDate,
            SUM(Spend) AS TotalSpend, SUM(Revenue) AS TotalRevenue
        FROM mart.FactCampaignDaily;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

