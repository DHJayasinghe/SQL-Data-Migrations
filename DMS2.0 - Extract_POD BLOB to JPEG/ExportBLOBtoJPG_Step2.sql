sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
sp_configure 'Ole Automation Procedures', 1;
GO
RECONFIGURE;
GO

USE [FITS_UPS_DB]

DECLARE @outPutPath varchar(500) = 'C:\Extract_BLOB' --set this value. path to export the blob files
IF NOT EXISTS(SELECT * FROM sysobjects WHERE name='__MigrationProofOfDelivery' AND xtype='U')
	CREATE TABLE __MigrationProofOfDelivery(
		CourDeliveryId bigint NOT NULL,
		DocumentName varchar(250) NOT NULL,
		MigratedDate datetime NOT NULL CONSTRAINT DF_ProofOfDeliveryBlobStatus_MigratedDate DEFAULT (getdate()),
	CONSTRAINT PK_MigrationProofOfDeliveryBlob PRIMARY KEY CLUSTERED (CourDeliveryId))

declare @recordTable table(RowNumber int,CourDeliveryId bigint,DocNum varchar(100))
INSERT INTO @recordTable(RowNumber,CourDeliveryId,DocNum)
SELECT ROW_NUMBER() OVER (ORDER BY CI.COURIER_ID ASC) as RowNumber,CI.COURIER_ID,FORMAT(CI.CREATED_DATE,'yyyy-MM') DocNum
FROM dbo.CDELIVERY_INFO CI LEFT JOIN dbo.__MigrationProofOfDelivery MDHB
ON CI.COURIER_ID=MDHB.CourDeliveryId
WHERE MDHB.CourDeliveryId IS NULL AND CI.[STATUS]='DE'  --Where not already migrated and delivered records only

--- BEGIN Folder Creation Process
declare @folderTable table(id int identity(1,1),folderName varchar(100))
declare @x int
INSERT INTO @folderTable(folderName)
SELECT DISTINCT RT.DocNum FROM @recordTable RT

SELECT @x = COUNT(1) FROM @folderTable
WHILE @x >= 1
BEGIN
	Declare @folderPath varchar(max)
	SELECT @folderPath = @outPutPath + '\'+ [folderName]
		FROM @folderTable WHERE id = @x
	 
	--Create folder first
	EXEC  [dbo].[CreateFolder] @folderPath 
	SET @x-=1
END
--- END Folder Creation Process

declare @batchSize int=500,@datasetSize int=(SELECT COUNT(*) FROM @recordTable),@iterationCnt int=0 
declare @startIndex int=1, @endingIndex int=@batchSize
declare @Doctable table (id int,CourDeliveryId bigint,[Doc_Num] varchar(100),[FileName] varchar(100),[Doc_Content] varBinary(max),
	PRIMARY KEY(id))
DECLARE @i bigint, @init int, @data varbinary(max), @fPath varchar(max)  

WHILE(@iterationCnt < @datasetSize)
BEGIN
	INSERT INTO @Doctable([id],CourDeliveryId,[Doc_Num],[FileName],[Doc_Content])
	SELECT Row_Number() OVER (Order By CI.COURIER_ID ASC), CI.COURIER_ID,RT.DocNum,CONCAT(NEWID(),'.jpg'),
	CAST(N'' AS xml).value('xs:base64Binary(sql:column("SIGNATURE"))','varbinary(max)') --convert base64 to BLOB
	FROM dbo.CDELIVERY_INFO CI INNER JOIN @recordTable RT
	ON CI.COURIER_ID=RT.CourDeliveryId
	WHERE RT.RowNumber BETWEEN @startIndex AND @endingIndex
	
	SELECT @i = COUNT(1) FROM @Doctable
	--SELECT CONCAT(@i,', ',@startIndex,', ',@endingIndex),[FileName],LEN(Doc_Content) FROM @Doctable

	WHILE @i >= 1
	BEGIN 
		SELECT 
			@data = [Doc_Content],
			@fPath = @outPutPath + '\'+ [Doc_Num] + '\' + [FileName]
		FROM @Doctable WHERE id = @i

		EXEC sp_OACreate 'ADODB.Stream', @init OUTPUT; -- An instace created
		EXEC sp_OASetProperty @init, 'Type', 1;  
		EXEC sp_OAMethod @init, 'Open'; -- Calling a method
		EXEC sp_OAMethod @init, 'Write', NULL, @data; -- Calling a method
		EXEC sp_OAMethod @init, 'SaveToFile', NULL, @fPath, 2; -- Calling a method
		EXEC sp_OAMethod @init, 'Close'; -- Calling a method
		EXEC sp_OADestroy @init; -- Closed the resources
 
		----print 'Document Generated at - '+  @fPath   

		--Reset the variables for next use
		SELECT @data = NULL, @init = NULL, @fPath = NULL
		SET @i -= 1
	END

	SET @iterationCnt=@iterationCnt+(SELECT COUNT(1) FROM @Doctable) --Iterated records count				(IMPORTANT to end the loop)
	SET @startIndex=@endingIndex+1 --Next startIndex start from Previous endingIndex + 1					 (IMPORTANT for record selection)
	SET @endingIndex+=@batchSize --Next ending index start from Previous ending index + batchSize (IMPORTANT for record selection)

	PRINT CONCAT(@iterationCnt , ' of ' , @datasetSize , ' is complete')
	INSERT INTO __MigrationProofOfDelivery(CourDeliveryId,DocumentName) SELECT CourDeliveryId,[FileName] FROM @Doctable
	DELETE FROM @Doctable
END
