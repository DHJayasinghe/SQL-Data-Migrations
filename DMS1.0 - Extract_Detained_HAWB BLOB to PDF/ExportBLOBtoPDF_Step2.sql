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
IF NOT EXISTS(SELECT * FROM sysobjects WHERE name='__MigrationDetainedHawbBlob' AND xtype='U')
	CREATE TABLE __MigrationDetainedHawbBlob(
		DetainHawbId bigint NOT NULL,
		DocumentName varchar(250) NOT NULL,
		MigratedDate datetime NOT NULL CONSTRAINT DF_Status_MigratedDate DEFAULT (getdate()),
	CONSTRAINT PK_MigrationDetainedHawbBlob PRIMARY KEY CLUSTERED (DetainHawbId))

declare @recordTable table(RowNumber int,DetainHawbId bigint,DocNum varchar(100))
INSERT INTO @recordTable(RowNumber,DetainHawbId,DocNum)
SELECT ROW_NUMBER() OVER (ORDER BY DHA.DETAIN_HAWB_ID ASC) as RowNumber,DHA.DETAIN_HAWB_ID,FORMAT(DH.CREATED_DATE,'yyyy-MM') DocNum
FROM dbo.DETAINED_HAWB_ATCH DHA INNER JOIN dbo.DETAINED_HAWB DH
ON DHA.DETAIN_HAWB_ID=DH.DETAIN_HAWB_ID AND ISNULL(DHA.ATCH_IS_PRINTED,'NO')='YES' LEFT JOIN dbo.__MigrationDetainedHawbBlob MDHB
ON DHA.DETAIN_HAWB_ID=MDHB.DetainHawbId
WHERE MDHB.DetainHawbId IS NULL --Where not already migrated

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
declare @Doctable table (id int,DetainHawbId bigint,[Doc_Num] varchar(100),[FileName] varchar(100),[Doc_Content] varBinary(max),
	PRIMARY KEY(id))
DECLARE @i bigint, @init int, @data varbinary(max), @fPath varchar(max)  

WHILE(@iterationCnt < @datasetSize)
BEGIN
	INSERT INTO @Doctable([id],DetainHawbId,[Doc_Num],[FileName],[Doc_Content])
	SELECT Row_Number() OVER (Order By DHA.DETAIN_HAWB_ID ASC), DHA.DETAIN_HAWB_ID,RT.DocNum,CONCAT(DHA.ATCHMNT_NAME,'-',DHA.DETAIN_HAWB_ID,'.pdf'),DHA.ATCHMNT_DATA 
	FROM dbo.DETAINED_HAWB_ATCH DHA INNER JOIN @recordTable RT
	ON DHA.DETAIN_HAWB_ID=RT.DetainHawbId
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
	INSERT INTO __MigrationDetainedHawbBlob(DetainHawbId,DocumentName) SELECT DetainHawbId,[FileName] FROM @Doctable
	DELETE FROM @Doctable
END
