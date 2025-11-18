USE JCAdb;
GO

-- =============================================================================
-- VIEW 1: PROCUREMENT PERFORMANCE ANALYSIS
-- Business Questions: Spend analysis, price analysis, supplier performance
-- =============================================================================

CREATE VIEW vw_ProcurementPerformance AS
SELECT 
    -- Time Dimensions
    mm.PostingDate,
    YEAR(mm.PostingDate) AS PostingYear,
    MONTH(mm.PostingDate) AS PostingMonth,
    DATENAME(MONTH, mm.PostingDate) AS PostingMonthName,
    DATEPART(QUARTER, mm.PostingDate) AS PostingQuarter,
    
    -- Material Information
    mm.Material,
    md.MaterialDescription,
    md.MaterialType,
    md.MaterialGroup,
    mm.BaseUnitOfMeasure,
    
    -- Procurement Details
    mm.Supplier,
    mm.Plant,
    mm.StorageLocationID,
    mm.MovementType,
    CASE  
        WHEN mm.MovementType = '101' THEN 'Goods Receipt for Purchase Order'
        WHEN mm.MovementType = '102' THEN 'Goods Receipt Reversal'
        WHEN mm.MovementType = '261' THEN 'Goods Issue to Production Order'-- Goods Issue to Production Order
        WHEN mm.MovementType = '262' THEN 'Goods Issue Reversal for Production'  -- Goods Issue Reversal for Production
        WHEN mm.MovementType = '301' THEN 'Transfer posting plant-to-plant transfer of stock' -- Transfer posting plant-to-plant transfer of stock
        WHEN mm.MovementType = '309' THEN 'material-to-material transfer within the same inventory' -- material-to-material transfer within the same inventory
        WHEN mm.MovementType = '311' THEN 'Transfer Posting'
        WHEN mm.MovementType = '312' THEN 'Transfer Posting Reversal'
        WHEN mm.MovementType = '321' THEN 'Quality Inspection to Unrestricted'
        WHEN mm.MovementType = '411' THEN 'Transfer from Material to Material'
        WHEN mm.MovementType = '412' THEN 'Transfer from Material to Material Reversal'
        WHEN mm.MovementType = '601' THEN 'Goods Issue (GI) to an outbound customer delivery' -- Goods Issue (GI) to an outbound customer delivery
        WHEN mm.MovementType = '641' THEN 'Goods Issue to a Stock Transport Order (STO) in transit, transferring materials between different plants or locations' -- Goods Issue to a Stock Transport Order (STO) in transit, transferring materials between different plants or locations
        ELSE 'Other Movement Type'
    END AS MovementDescription,
    
    -- Quantities and Values
    mm.Quantity,
    ABS(mm.Quantity) AS AbsQuantity,
    mm.AmtInLocCurrency AS ProcurementValue,
    ABS(mm.AmtInLocCurrency) AS AbsProcurementValue,
    
    -- Calculated Metrics
    CASE 
        WHEN mm.Quantity != 0 THEN mm.AmtInLocCurrency / mm.Quantity
        ELSE 0 
    END AS UnitPrice,
    
    -- Valuation Information
    mv.MovingPrice,
    mv.StandardPrice,
    mv.PriceUnit,
    
    -- Document References
    mm.MaterialDocument,
    mm.MaterialDocumentYear,
    mm.BatchID

FROM MaterialMovement$ mm
LEFT JOIN MaterialData$ md ON mm.Material = md.MaterialNumber
LEFT JOIN MaterialValuation$ mv ON mm.Material = mv.Material AND mm.Plant = mv.ValuationArea
WHERE mm.MovementType IN ('101', '102') -- Focus on procurement transactions
AND mm.Supplier IS NOT NULL AND mm.Supplier != ''; -- Only records with suppliers

SELECT * FROM vw_ProcurementPerformance;

-- =============================================================================
-- VIEW 2: SUPPLIER PERFORMANCE DASHBOARD
-- Business Questions: Supplier ranking, quality assessment, relationship analysis
-- =============================================================================

CREATE VIEW vw_SupplierPerformance AS
SELECT 
    -- Supplier Information
    pp.Supplier,
    
    -- Time Period (can be filtered in queries)
    pp.PostingYear,
    pp.PostingQuarter,
    
    -- Volume Metrics
    COUNT(*) AS TransactionCount,
    COUNT(DISTINCT pp.Material) AS UniqueMaterials,
    COUNT(DISTINCT pp.MaterialGroup) AS UniqueMaterialGroups,
    SUM(pp.AbsQuantity) AS TotalQuantity,
    
    -- Value Metrics
    SUM(pp.AbsProcurementValue) AS TotalProcurementValue,
    AVG(pp.AbsProcurementValue) AS AvgTransactionValue,
    
    -- Price Analysis
    AVG(pp.UnitPrice) AS AvgUnitPrice,
    MIN(pp.UnitPrice) AS MinUnitPrice,
    MAX(pp.UnitPrice) AS MaxUnitPrice,
    STDEV(pp.UnitPrice) AS UnitPriceVariability,
    
    -- Order Accuracy Indicators (previously called Quality Indicators)
    SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS OrderCorrectionCount,
    SUM(CASE WHEN pp.MovementType = '102' THEN pp.AbsProcurementValue ELSE 0 END) AS OrderCorrectionValue,
    
    -- Order Specification Complexity Rate (previously Reversal Rate)
    CASE 
        WHEN COUNT(*) > 0 THEN 
            CAST(SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100
        ELSE 0 
    END AS OrderComplexityRate,
    
    -- Specification Complexity Category
    CASE 
        WHEN (CAST(SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100) > 20 
            THEN 'High Complexity Materials'
        WHEN (CAST(SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100) > 10 
            THEN 'Medium Complexity Materials'
        WHEN (CAST(SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100) > 0 
            THEN 'Some Specification Challenges'
        ELSE 'Standard Materials'
    END AS ComplexityCategory,
    
    -- Operational Metrics
    MIN(pp.PostingDate) AS FirstTransaction,
    MAX(pp.PostingDate) AS LastTransaction,
    DATEDIFF(DAY, MIN(pp.PostingDate), MAX(pp.PostingDate)) AS RelationshipDays

FROM vw_ProcurementPerformance pp
GROUP BY 
    pp.Supplier,
    pp.PostingYear,
    pp.PostingQuarter

UNION ALL

-- Overall supplier performance (all time summary) with corrected interpretations
SELECT 
    pp.Supplier,
    NULL AS PostingYear, -- NULL indicates "All Years"
    NULL AS PostingQuarter, -- NULL indicates "All Quarters"
    
    COUNT(*) AS TransactionCount,
    COUNT(DISTINCT pp.Material) AS UniqueMaterials,
    COUNT(DISTINCT pp.MaterialGroup) AS UniqueMaterialGroups,
    SUM(pp.AbsQuantity) AS TotalQuantity,
    SUM(pp.AbsProcurementValue) AS TotalProcurementValue,
    AVG(pp.AbsProcurementValue) AS AvgTransactionValue,
    AVG(pp.UnitPrice) AS AvgUnitPrice,
    MIN(pp.UnitPrice) AS MinUnitPrice,
    MAX(pp.UnitPrice) AS MaxUnitPrice,
    STDEV(pp.UnitPrice) AS UnitPriceVariability,
    SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS OrderCorrectionCount,
    SUM(CASE WHEN pp.MovementType = '102' THEN pp.AbsProcurementValue ELSE 0 END) AS OrderCorrectionValue,
    CASE 
        WHEN COUNT(*) > 0 THEN 
            CAST(SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100
        ELSE 0 
    END AS OrderComplexityRate,
    CASE 
        WHEN (CAST(SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100) > 20 
            THEN 'High Complexity Materials'
        WHEN (CAST(SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100) > 10 
            THEN 'Medium Complexity Materials'
        WHEN (CAST(SUM(CASE WHEN pp.MovementType = '102' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100) > 0 
            THEN 'Some Specification Challenges'
        ELSE 'Standard Materials'
    END AS ComplexityCategory,
    MIN(pp.PostingDate) AS FirstTransaction,
    MAX(pp.PostingDate) AS LastTransaction,
    DATEDIFF(DAY, MIN(pp.PostingDate), MAX(pp.PostingDate)) AS RelationshipDays

FROM vw_ProcurementPerformance pp
GROUP BY pp.Supplier;

SELECT * FROM vw_SupplierPerformance;

-- =============================================================================
-- VIEW 3: MATERIAL CATEGORY ANALYSIS
-- Business Questions: Spend categorization, supplier diversity, category trends
-- =============================================================================

CREATE VIEW vw_MaterialCategoryAnalysis AS
SELECT 
    -- Category Information
    md.MaterialGroup,
    md.MaterialType,
    
    -- Time Dimensions
    YEAR(mm.PostingDate) AS PostingYear,
    MONTH(mm.PostingDate) AS PostingMonth,
    DATEPART(QUARTER, mm.PostingDate) AS PostingQuarter,
    
    -- Procurement Metrics
    COUNT(DISTINCT mm.Supplier) AS SupplierCount,
    COUNT(DISTINCT mm.Material) AS MaterialCount,
    COUNT(*) AS TransactionCount,
    
    -- Volume and Value Metrics
    SUM(ABS(mm.Quantity)) AS TotalQuantity,
    SUM(ABS(mm.AmtInLocCurrency)) AS TotalSpend,
    AVG(ABS(mm.AmtInLocCurrency)) AS AvgTransactionValue,
    
    -- Price Analysis
    AVG(CASE 
        WHEN mm.Quantity != 0 THEN ABS(mm.AmtInLocCurrency) / ABS(mm.Quantity)
        ELSE 0 
    END) AS AvgUnitCost,
    
    -- Supplier Concentration
    COUNT(DISTINCT mm.Supplier) AS ActiveSuppliers

FROM MaterialMovement$ mm
LEFT JOIN MaterialData$ md ON mm.Material = md.MaterialNumber
WHERE mm.MovementType IN ('101', '102')
    AND mm.Supplier IS NOT NULL AND mm.Supplier != ''
    AND md.MaterialGroup IS NOT NULL

GROUP BY 
    md.MaterialGroup,
    md.MaterialType,
    YEAR(mm.PostingDate),
    MONTH(mm.PostingDate),
    DATEPART(QUARTER, mm.PostingDate);

SELECT * FROM vw_MaterialCategoryAnalysis;

-- =============================================================================
-- VIEW 4: INVENTORY MOVEMENT ANALYSIS
-- Business Questions: Movement patterns, operational efficiency, stock management
-- =============================================================================

CREATE VIEW vw_InventoryMovementAnalysis AS
SELECT 
    -- Time and Location
    mm.PostingDate,
    YEAR(mm.PostingDate) AS PostingYear,
    MONTH(mm.PostingDate) AS PostingMonth,
    mm.Plant,
    mm.StorageLocationID,
    
    -- Material Information
    mm.Material,
    md.MaterialDescription,
    md.MaterialType,
    md.MaterialGroup,
    
    -- Movement Classification
    mm.MovementType,
    CASE 
        WHEN mm.MovementType = '101' THEN 'Goods Receipt for Purchase Order'
        WHEN mm.MovementType = '102' THEN 'Goods Receipt Reversal'
        WHEN mm.MovementType = '261' THEN 'Goods Issue to Production Order'-- Goods Issue to Production Order
        WHEN mm.MovementType = '262' THEN 'Goods Issue Reversal for Production'  -- Goods Issue Reversal for Production
        WHEN mm.MovementType = '301' THEN 'Transfer posting plant-to-plant transfer of stock' -- Transfer posting plant-to-plant transfer of stock
        WHEN mm.MovementType = '309' THEN 'material-to-material transfer within the same inventory' -- material-to-material transfer within the same inventory
        WHEN mm.MovementType = '311' THEN 'Transfer Posting'
        WHEN mm.MovementType = '312' THEN 'Transfer Posting Reversal'
        WHEN mm.MovementType = '321' THEN 'Quality Inspection to Unrestricted'
        WHEN mm.MovementType = '411' THEN 'Transfer from Material to Material'
        WHEN mm.MovementType = '412' THEN 'Transfer from Material to Material Reversal'
        WHEN mm.MovementType = '601' THEN 'Goods Issue (GI) to an outbound customer delivery' -- Goods Issue (GI) to an outbound customer delivery
        WHEN mm.MovementType = '641' THEN 'Goods Issue to a Stock Transport Order (STO) in transit, transferring materials between different plants or locations' -- Goods Issue to a Stock Transport Order (STO) in transit, transferring materials between different plants or locations
        ELSE 'Other Movement Type'
    END AS MovementDescription,
    
    CASE 
        WHEN mm.MovementType IN ('101', '262', '321') THEN 'Receipt'
        WHEN mm.MovementType IN ('102', '261', '601', '641') THEN 'Issue'
		WHEN mm.MovementType IN ('301','309','311', '312', '411', '412') THEN 'Transfer'
        ELSE 'Neutral'
    END AS MovementDirection,
    
    CASE 
        WHEN mm.MovementType IN ('101', '102') THEN 'Procurement'
        WHEN mm.MovementType IN ('261', '601', '641') THEN 'Consumption'
        WHEN mm.MovementType IN ('262') THEN 'Production'
        WHEN mm.MovementType IN ('301') THEN 'Plant Transfers'
		WHEN mm.MovementType IN ('309', '411', '412') THEN 'Material Conversions'
		WHEN mm.MovementType IN ('311', '312') THEN 'Location Transfers'
		WHEN mm.MovementType IN ('321') THEN 'Quality Management'
        ELSE 'Other'
    END AS MovementCategory,
    
    -- Quantities and Values
    mm.Quantity,
    ABS(mm.Quantity) AS AbsQuantity,
    mm.AmtInLocCurrency,
    ABS(mm.AmtInLocCurrency) AS AbsAmount,
    
    -- Current Stock Information
    ps.Unrestricted AS CurrentStock,
    ps.QualityInspection AS QIStock,
    ps.RestrictedUseStock,
    ps.Blocked AS BlockedStock,
    (ISNULL(ps.Unrestricted, 0) + ISNULL(ps.QualityInspection, 0) + 
     ISNULL(ps.RestrictedUseStock, 0) + ISNULL(ps.Blocked, 0)) AS TotalCurrentStock,
    
    -- Valuation Information
    mv.MovingPrice,
    mv.StandardPrice,
    
    -- Calculated Metrics
    CASE 
        WHEN mm.Quantity != 0 THEN mm.AmtInLocCurrency / mm.Quantity
        ELSE 0 
    END AS UnitValue,
    
    -- Supplier (for procurement movements)
    CASE WHEN mm.MovementType IN ('101', '102') THEN mm.Supplier ELSE NULL END AS ProcurementSupplier,
    
    -- Document References
    mm.MaterialDocument,
    mm.MaterialDocumentYear,
    mm.BatchID
    
FROM MaterialMovement$ mm
LEFT JOIN MaterialData$ md ON mm.Material = md.MaterialNumber
LEFT JOIN PlantStock$ ps ON mm.Material = ps.Material 
                        AND mm.Plant = ps.Plant 
                        AND mm.StorageLocationID = ps.StorageLocation
LEFT JOIN MaterialValuation$ mv ON mm.Material = mv.Material AND mm.Plant = mv.ValuationArea;

SELECT * FROM vw_InventoryMovementAnalysis;

--=====================================
--QUERIES ANSWERING BUSINESS QUESTIONS
--=====================================
-- 1. TOP SPENDING ANALYSIS - Biggest cost drivers
SELECT TOP 10 
    Material, 
    SUM(AbsProcurementValue) AS TotalSpend,
    COUNT(*) AS Transactions,
    COUNT(DISTINCT Supplier) AS SupplierCount,
    AVG(UnitPrice) AS AvgUnitPrice
FROM vw_ProcurementPerformance 
GROUP BY Material 
ORDER BY TotalSpend DESC;

-- 2. SUPPLIER CONCENTRATION ANALYSIS
SELECT 
    Supplier,
    TotalProcurementValue,
    (TotalProcurementValue / 995391.56) * 100 AS PercentOfTotalSpend,
    TransactionCount,
    UniqueMaterials,
    OrderComplexityRate
FROM vw_SupplierPerformance 
WHERE PostingYear IS NULL 
ORDER BY TotalProcurementValue DESC;

-- 3. SPECIFICATION COMPLEXITY ANALYSIS - Order Correction Patterns
SELECT 
    Supplier,
    TransactionCount,
    OrderCorrectionCount,
    OrderComplexityRate,
    OrderCorrectionValue,
    TotalProcurementValue,
    ComplexityCategory
FROM vw_SupplierPerformance 
WHERE PostingYear IS NULL AND OrderComplexityRate > 0
ORDER BY OrderComplexityRate DESC;

-- 4. MATERIAL CATEGORY SPENDING ANALYSIS
SELECT 
    MaterialGroup,
    SUM(TotalSpend) AS CategorySpend,
    AVG(SupplierCount) AS AvgSuppliers,
    COUNT(*) AS TimePeriodsActive
FROM vw_MaterialCategoryAnalysis 
GROUP BY MaterialGroup 
ORDER BY CategorySpend DESC;

-- 5. MONTHLY SPENDING PATTERNS
SELECT 
    PostingMonthName,
    SUM(AbsProcurementValue) AS MonthlySpend,
    COUNT(*) AS MonthlyTransactions,
    COUNT(DISTINCT Supplier) AS ActiveSuppliers
FROM vw_ProcurementPerformance 
GROUP BY PostingMonth, PostingMonthName 
ORDER BY PostingMonth;

-- Query 6: INVENTORY MOVEMENT TYPE ANALYSIS
-- Shows operational efficiency across all movement categories
SELECT 
    MovementCategory,
    MovementDescription,
    COUNT(*) AS TransactionCount,
    SUM(AbsAmount) AS TotalValue,
    AVG(AbsAmount) AS AvgTransactionValue,
    SUM(AbsQuantity) AS TotalQuantity,
    COUNT(DISTINCT Material) AS UniqueMaterials,
    COUNT(DISTINCT ProcurementSupplier) AS UniqueSuppliers
FROM vw_InventoryMovementAnalysis 
GROUP BY MovementCategory, MovementDescription
ORDER BY TotalValue DESC;