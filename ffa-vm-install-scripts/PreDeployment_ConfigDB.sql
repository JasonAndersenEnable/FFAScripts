INSERT [dbo].[az_Tenant]
(
[az_Name]
,[az_Description]
,[az_DatabaseName]
,[az_SqlServerName]
,[az_UniqueName]
,[az_ODataGuid]
,[az_ConnectionString]
,[az_CorsOriginUrls]
,[az_State]
,[az_CreatedBy]
,[az_CreatedOn]
,[az_ModifiedBy]
,[az_ModifiedOn]
,[az_OwnedBy]
,[az_License]
,[az_LicenseExpiry]
,[az_Model]
,[az_ModelName]
,[az_JobServicePath]
,[az_JobServiceParameters]
)
VALUES
(
'GCG_T01'
,NULL
,'FlintfoxDataDB_TEST'
,'gcg-flintfox-sql-test'
,'GCG_TEST'
,'00000000-0000-0000-0000-000000000011'
,N'data source=gcg-flintfox-sql-test;initial catalog=FlintfoxDataDB_TEST;user id=svc-flintfoxsqladmin;password=xxx;multipleactiveresultsets=True;persist security info=true;TrustServerCertificate=True;'
,N'https://flintfox-test.gogcg.com'
,2
,NULL
,'1/1/2026'
,0
,'1/1/2026'
,0
,'AABBCCDDEEFF'
,'2099-12-31 00:00:00.000'
,0x504B0304
,'Flintfox.Azara.Data.Tenant.dll'
,'c:\windows\system32\cmd.exe'
,'/K "dir c:\temp\assembly"'
)