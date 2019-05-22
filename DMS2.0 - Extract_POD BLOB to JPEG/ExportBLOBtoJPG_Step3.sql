--Disable Ole Automation Procedures
sp_configure 'show advanced options', 0;
GO
RECONFIGURE;
GO
sp_configure 'Ole Automation Procedures', 0;
GO
RECONFIGURE;
GO
