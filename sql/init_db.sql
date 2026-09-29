IF DB_ID(N'marketing_campaign_model') IS NULL CREATE DATABASE marketing_campaign_model;
GO
USE marketing_campaign_model;
GO
IF SCHEMA_ID(N'stg') IS NULL EXEC(N'CREATE SCHEMA stg');
IF SCHEMA_ID(N'mart') IS NULL EXEC(N'CREATE SCHEMA mart');
GO
IF OBJECT_ID(N'stg.CampaignDailyRaw', N'U') IS NULL
CREATE TABLE stg.CampaignDailyRaw (
    campaign_id nvarchar(100) NULL, company nvarchar(400) NULL,
    [date] nvarchar(100) NULL, channel nvarchar(400) NULL,
    target_audience nvarchar(400) NULL, location nvarchar(400) NULL,
    language nvarchar(400) NULL, impressions nvarchar(100) NULL,
    clicks nvarchar(100) NULL, conversions nvarchar(100) NULL,
    spend nvarchar(100) NULL, revenue nvarchar(100) NULL
);
IF OBJECT_ID(N'mart.DimCampaign', N'U') IS NULL
CREATE TABLE mart.DimCampaign (
    CampaignId int NOT NULL CONSTRAINT PK_DimCampaign PRIMARY KEY,
    Company nvarchar(100) NOT NULL, Channel nvarchar(100) NOT NULL,
    TargetAudience nvarchar(100) NOT NULL, Location nvarchar(100) NOT NULL,
    Language nvarchar(100) NOT NULL,
    StartDate date NOT NULL, EndDate date NOT NULL,
    DurationDays int NOT NULL, ObservedDays int NOT NULL,
    DurationTier nvarchar(20) NOT NULL, DurationTierSort tinyint NOT NULL,
    CONSTRAINT CK_Campaign_Dates CHECK (EndDate >= StartDate AND DurationDays > 0
        AND ObservedDays > 0 AND ObservedDays <= DurationDays)
);
IF OBJECT_ID(N'mart.DimDate', N'U') IS NULL
CREATE TABLE mart.DimDate (
    [Date] date NOT NULL CONSTRAINT PK_DimDate PRIMARY KEY,
    [Year] smallint NOT NULL, QuarterNumber tinyint NOT NULL,
    [Quarter] char(2) NOT NULL, MonthNumber tinyint NOT NULL,
    MonthName nvarchar(20) NOT NULL, MonthShort char(3) NOT NULL,
    YearMonth int NOT NULL, MonthYear nvarchar(20) NOT NULL,
    DayOfMonth tinyint NOT NULL, DayOfWeekNumber tinyint NOT NULL,
    DayName nvarchar(20) NOT NULL, IsWeekend bit NOT NULL
);
IF OBJECT_ID(N'mart.FactCampaignDaily', N'U') IS NULL
CREATE TABLE mart.FactCampaignDaily (
    CampaignId int NOT NULL, [Date] date NOT NULL,
    Impressions bigint NOT NULL, Clicks bigint NOT NULL, Conversions bigint NOT NULL,
    Spend decimal(19,2) NOT NULL, Revenue decimal(19,2) NOT NULL,
    CONSTRAINT PK_FactCampaignDaily PRIMARY KEY (CampaignId, [Date]),
    CONSTRAINT FK_Fact_Campaign FOREIGN KEY (CampaignId) REFERENCES mart.DimCampaign(CampaignId),
    CONSTRAINT FK_Fact_Date FOREIGN KEY ([Date]) REFERENCES mart.DimDate([Date]),
    CONSTRAINT CK_Fact_Nonnegative CHECK (Impressions >= 0 AND Clicks >= 0
        AND Conversions >= 0 AND Spend >= 0 AND Revenue >= 0)
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'mart.FactCampaignDaily') AND name = N'IX_Fact_Date')
CREATE INDEX IX_Fact_Date ON mart.FactCampaignDaily ([Date], CampaignId)
INCLUDE (Impressions, Clicks, Conversions, Spend, Revenue);
GO
