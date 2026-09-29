USE marketing_campaign_model;
GO
SELECT COUNT(*) AS DailyRows, COUNT(DISTINCT CampaignId) AS Campaigns,
    MIN([Date]) AS FirstActivityDate, MAX([Date]) AS LastActivityDate,
    SUM(Spend) AS TotalSpend, SUM(Revenue) AS TotalRevenue,
    SUM(Revenue) - SUM(Spend) AS CampaignProfit
FROM mart.FactCampaignDaily;
-- Expected: 21083 rows, 280 campaigns, 2023-01-03 to 2026-01-11,
-- spend 68526059.00, revenue 153415075.00, profit 84889016.00.

SELECT Company, COUNT(*) AS Campaigns FROM mart.DimCampaign GROUP BY Company;
-- Expected: 8 companies, 35 campaigns each.

SELECT COUNT(*) AS CalendarDates,
    DATEDIFF(day, MIN([Date]), MAX([Date])) + 1 AS ExpectedContinuousDates
FROM mart.DimDate;
-- Both counts should equal 1461 for this snapshot.

SELECT c.Company, SUM(f.Spend) AS Spend, SUM(f.Revenue) AS Revenue,
    SUM(f.Revenue) - SUM(f.Spend) AS CampaignProfit,
    (SUM(f.Revenue) - SUM(f.Spend)) / NULLIF(SUM(f.Spend), 0) AS ROI,
    1.0 * SUM(f.Conversions) / NULLIF(SUM(f.Clicks), 0) AS ConversionRate,
    SUM(f.Spend) / NULLIF(SUM(f.Conversions), 0) AS CostPerConversion
FROM mart.FactCampaignDaily f
JOIN mart.DimCampaign c ON c.CampaignId = f.CampaignId
GROUP BY c.Company ORDER BY c.Company;
-- Ratios are fractions: 0.25 represents 25%.
