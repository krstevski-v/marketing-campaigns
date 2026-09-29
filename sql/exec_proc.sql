USE marketing_campaign_model;
GO

EXEC mart.LoadMarketingCsv
    -- Replace with the full CSV path accessible to SQL Server.
    @CsvPath = N'C:\path\to\marketing-report\data\marketing_data.csv';
